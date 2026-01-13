#!/bin/bash
# Create complete User Service in one script

set -e

cd ~/project/helix-platform/applications/user-service

echo "👤 Creating User Service (complete)..."

# Create __init__.py files
touch src/__init__.py
touch src/models/__init__.py
touch src/api/__init__.py
touch src/services/__init__.py
touch src/db/__init__.py

# 1. Database Models
cat > src/models/user.py << 'EOFMODEL'
"""User database models"""
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from db.database import Base

class User(Base):
    """User model"""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    full_name = Column(String(255), nullable=False)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    is_admin = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    def __repr__(self):
        return f"<User(id={self.id}, username={self.username})>"
EOFMODEL

# 2. Pydantic Schemas
cat > src/models/schemas.py << 'EOFSCHEMA'
"""Pydantic schemas for User Service"""
from pydantic import BaseModel, EmailStr, Field, ConfigDict
from typing import Optional
from datetime import datetime

class UserBase(BaseModel):
    """Base user schema"""
    username: str = Field(..., min_length=3, max_length=100)
    email: EmailStr
    full_name: str = Field(..., min_length=1, max_length=255)

class UserCreate(UserBase):
    """Schema for creating a user"""
    password: str = Field(..., min_length=6, max_length=100)

class UserUpdate(BaseModel):
    """Schema for updating a user"""
    email: Optional[EmailStr] = None
    full_name: Optional[str] = Field(None, min_length=1, max_length=255)
    password: Optional[str] = Field(None, min_length=6, max_length=100)
    is_active: Optional[bool] = None

class UserResponse(UserBase):
    """Schema for user response"""
    id: int
    is_active: bool
    is_admin: bool
    created_at: datetime
    updated_at: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)

class UserListResponse(BaseModel):
    """Schema for list of users"""
    total: int
    users: list[UserResponse]
    page: int
    page_size: int

class LoginRequest(BaseModel):
    """Schema for login request"""
    username: str
    password: str

class LoginResponse(BaseModel):
    """Schema for login response"""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    service: str
    version: str
    timestamp: datetime
EOFSCHEMA

# 3. User Service Logic
cat > src/services/user_service.py << 'EOFSERVICE'
"""User business logic"""
from sqlalchemy.orm import Session
from models.user import User
from models.schemas import UserCreate, UserUpdate
from typing import List, Optional, Tuple
from passlib.context import CryptContext
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class UserService:
    """User service for business logic"""
    
    @staticmethod
    def hash_password(password: str) -> str:
        """Hash a password"""
        return pwd_context.hash(password)
    
    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        """Verify a password"""
        return pwd_context.verify(plain_password, hashed_password)
    
    @staticmethod
    def get_user(db: Session, user_id: int) -> Optional[User]:
        """Get user by ID"""
        with tracer.start_as_current_span("user_service.get_user") as span:
            span.set_attribute("user.id", user_id)
            return db.query(User).filter(User.id == user_id).first()
    
    @staticmethod
    def get_user_by_username(db: Session, username: str) -> Optional[User]:
        """Get user by username"""
        return db.query(User).filter(User.username == username).first()
    
    @staticmethod
    def get_user_by_email(db: Session, email: str) -> Optional[User]:
        """Get user by email"""
        return db.query(User).filter(User.email == email).first()
    
    @staticmethod
    def get_users(
        db: Session,
        skip: int = 0,
        limit: int = 100,
        is_active: Optional[bool] = None
    ) -> Tuple[List[User], int]:
        """Get list of users"""
        query = db.query(User)
        
        if is_active is not None:
            query = query.filter(User.is_active == is_active)
        
        total = query.count()
        users = query.offset(skip).limit(limit).all()
        
        return users, total
    
    @staticmethod
    def create_user(db: Session, user_data: UserCreate) -> User:
        """Create new user"""
        with tracer.start_as_current_span("user_service.create_user") as span:
            # Check if username exists
            if UserService.get_user_by_username(db, user_data.username):
                raise ValueError(f"Username {user_data.username} already exists")
            
            # Check if email exists
            if UserService.get_user_by_email(db, user_data.email):
                raise ValueError(f"Email {user_data.email} already exists")
            
            # Hash password
            hashed_password = UserService.hash_password(user_data.password)
            
            # Create user
            user = User(
                username=user_data.username,
                email=user_data.email,
                full_name=user_data.full_name,
                hashed_password=hashed_password
            )
            
            db.add(user)
            db.commit()
            db.refresh(user)
            
            span.set_attribute("user.id", user.id)
            logger.info(f"Created user {user.id}: {user.username}")
            
            return user
    
    @staticmethod
    def update_user(db: Session, user_id: int, user_data: UserUpdate) -> Optional[User]:
        """Update user"""
        user = UserService.get_user(db, user_id)
        if not user:
            return None
        
        update_data = user_data.model_dump(exclude_unset=True)
        
        # Hash password if provided
        if "password" in update_data:
            update_data["hashed_password"] = UserService.hash_password(update_data.pop("password"))
        
        for field, value in update_data.items():
            setattr(user, field, value)
        
        db.commit()
        db.refresh(user)
        
        return user
    
    @staticmethod
    def authenticate_user(db: Session, username: str, password: str) -> Optional[User]:
        """Authenticate user"""
        with tracer.start_as_current_span("user_service.authenticate") as span:
            span.set_attribute("username", username)
            
            user = UserService.get_user_by_username(db, username)
            if not user:
                logger.warning(f"User {username} not found")
                return None
            
            if not user.is_active:
                logger.warning(f"User {username} is inactive")
                return None
            
            if not UserService.verify_password(password, user.hashed_password):
                logger.warning(f"Invalid password for user {username}")
                return None
            
            logger.info(f"User {username} authenticated successfully")
            return user
EOFSERVICE

# 4. Auth utilities (JWT mock)
cat > src/services/auth.py << 'EOFAUTH'
"""Authentication utilities (JWT mock)"""
from jose import jwt
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

# Mock secret key (use environment variable in production)
SECRET_KEY = "helix-secret-key-change-in-production"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

def create_access_token(data: dict, expires_delta: timedelta = None) -> str:
    """Create JWT access token (mock implementation)"""
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    
    return encoded_jwt
EOFAUTH

# 5. API Routes
cat > src/api/routes.py << 'EOFROUTES'
"""FastAPI routes for User Service"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from db.database import get_db
from services.user_service import UserService
from services.auth import create_access_token
from models.schemas import (
    UserCreate, UserUpdate, UserResponse, UserListResponse,
    LoginRequest, LoginResponse
)
from typing import Optional
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["users"])

@router.post("/register", response_model=UserResponse, status_code=201)
def register_user(user: UserCreate, db: Session = Depends(get_db)):
    """Register a new user"""
    try:
        return UserService.create_user(db, user)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/login", response_model=LoginResponse)
def login(credentials: LoginRequest, db: Session = Depends(get_db)):
    """Login user and return JWT token"""
    user = UserService.authenticate_user(db, credentials.username, credentials.password)
    
    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid username or password"
        )
    
    # Create access token
    access_token = create_access_token(
        data={"sub": user.username, "user_id": user.id},
        expires_delta=timedelta(minutes=30)
    )
    
    return LoginResponse(
        access_token=access_token,
        user=user
    )

@router.get("/users", response_model=UserListResponse)
def list_users(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db)
):
    """List all users"""
    users, total = UserService.get_users(db, skip, limit, is_active)
    return UserListResponse(total=total, users=users, page=skip//limit+1, page_size=limit)

@router.get("/users/{user_id}", response_model=UserResponse)
def get_user(user_id: int, db: Session = Depends(get_db)):
    """Get user by ID"""
    user = UserService.get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.put("/users/{user_id}", response_model=UserResponse)
def update_user(user_id: int, user_data: UserUpdate, db: Session = Depends(get_db)):
    """Update user"""
    user = UserService.update_user(db, user_id, user_data)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user
EOFROUTES

# 6. Main Application
cat > src/main.py << 'EOFMAIN'
"""User Service - Main FastAPI Application"""
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import sys, os
from datetime import datetime
import logging

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from common_logging import setup_logging
from common_instrumentation import setup_opentelemetry, instrument_fastapi, instrument_sqlalchemy
from api.routes import router
from db.database import init_database, create_tables
from config import settings

setup_logging(settings.service_name, settings.log_level, settings.log_format)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"Starting {settings.service_name}")
    try:
        engine = init_database(settings.database_url)
        create_tables()
        if settings.otel_enabled:
            instrument_sqlalchemy(engine)
            setup_opentelemetry(settings.service_name, settings.otel_endpoint, settings.otel_enabled)
        logger.info(f"{settings.service_name} started successfully")
    except Exception as e:
        logger.error(f"Startup failed: {e}")
        raise
    yield
    logger.info(f"Shutting down {settings.service_name}")

app = FastAPI(title="User Service", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

if settings.otel_enabled:
    instrument_fastapi(app)

app.include_router(router)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": settings.service_name, "version": "1.0.0", "timestamp": datetime.utcnow().isoformat()}

@app.get("/ready")
async def ready():
    from db.database import SessionLocal
    try:
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        return {"status": "ready", "service": settings.service_name, "database": "connected"}
    except Exception as e:
        return JSONResponse(status_code=503, content={"status": "not_ready", "error": str(e)})

@app.get("/")
async def root():
    return {"service": settings.service_name, "version": "1.0.0", "docs": "/docs"}
EOFMAIN

# 7. Config, DB, and other files
cat > src/db/database.py << 'EOFDB'
"""Database connection"""
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
import logging

logger = logging.getLogger(__name__)
Base = declarative_base()
engine = None
SessionLocal = None

def init_database(database_url: str):
    global engine, SessionLocal
    logger.info("Initializing database")
    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    return engine

def create_tables():
    Base.metadata.create_all(bind=engine)

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOFDB

cat > src/config.py << 'EOFCONFIG'
"""User Service Configuration"""
import sys, os
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(current_dir))
from common_config import CommonSettings

class Settings(CommonSettings):
    service_name: str = "user-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"

settings = Settings()
EOFCONFIG

cat > requirements.txt << 'EOFREQ'
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0
pydantic[email]==2.5.3
sqlalchemy==2.0.25
psycopg2-binary==2.9.9
httpx==0.26.0
opentelemetry-api==1.22.0
opentelemetry-sdk==1.22.0
opentelemetry-instrumentation-fastapi==0.43b0
opentelemetry-instrumentation-sqlalchemy==0.43b0
opentelemetry-exporter-otlp==1.22.0
python-json-logger==2.0.7
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
EOFREQ

cat > .env << 'EOFENV'
SERVICE_NAME=user-service
DATABASE_URL=postgresql://helix:helix@localhost:5432/helix
OTEL_ENABLED=false
LOG_LEVEL=INFO
LOG_FORMAT=text
EOFENV

cat > Dockerfile.dev << 'EOFDOCKER'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y gcc postgresql-client curl && rm -rf /var/lib/apt/lists/*
COPY user-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY common_*.py ./
COPY user-service/src ./src
ENV PYTHONPATH=/app/src:/app
EXPOSE 8003
HEALTHCHECK CMD curl -f http://localhost:8003/health || exit 1
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8003"]
EOFDOCKER

echo "✅ User Service created completely!"

