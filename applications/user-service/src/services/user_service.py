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
