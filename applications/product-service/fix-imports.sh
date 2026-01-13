#!/bin/bash
# Fix module structure and imports

set -e

cd ~/project/helix-platform/applications/product-service

echo "🔧 Fixing module imports..."

# Create all __init__.py files
touch src/__init__.py
touch src/models/__init__.py
touch src/api/__init__.py
touch src/services/__init__.py
touch src/db/__init__.py

# Fix the main.py with corrected imports
cat > src/main.py << 'EOFMAIN'
"""
Product Service - Main FastAPI Application
"""
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import sys
import os
from datetime import datetime
import logging

# Add parent directory to path for common modules
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

# Import common modules
from common_logging import setup_logging
from common_instrumentation import setup_opentelemetry, instrument_fastapi, instrument_sqlalchemy

# Import local modules
from api.routes import router
from db.database import init_database, create_tables
from config import settings

# Setup logging
setup_logging(
    service_name=settings.service_name,
    log_level=settings.log_level,
    log_format=settings.log_format
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup and shutdown events"""
    # Startup
    logger.info(f"Starting {settings.service_name}")
    logger.info(f"Environment: {settings.environment}")
    
    # Initialize database
    try:
        engine = init_database(settings.database_url)
        create_tables()
        logger.info("Database initialized successfully")
        
        # Instrument SQLAlchemy
        if settings.otel_enabled:
            instrument_sqlalchemy(engine)
        
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        raise
    
    # Initialize OpenTelemetry
    if settings.otel_enabled:
        setup_opentelemetry(
            service_name=settings.service_name,
            otlp_endpoint=settings.otel_endpoint,
            enabled=settings.otel_enabled
        )
        logger.info("OpenTelemetry initialized")
    
    logger.info(f"{settings.service_name} started successfully")
    
    yield
    
    # Shutdown
    logger.info(f"Shutting down {settings.service_name}")


# Create FastAPI app
app = FastAPI(
    title="Product Service",
    description="Microservice for managing product catalog",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instrument FastAPI with OpenTelemetry
if settings.otel_enabled:
    instrument_fastapi(app)

# Include API routes
app.include_router(router)


@app.get("/health")
async def health_check():
    """Health check endpoint (liveness probe)"""
    return {
        "status": "healthy",
        "service": settings.service_name,
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint (readiness probe)"""
    from db.database import SessionLocal
    
    try:
        # Test database connection
        db = SessionLocal()
        db.execute("SELECT 1")
        db.close()
        
        return {
            "status": "ready",
            "service": settings.service_name,
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "service": settings.service_name,
                "database": "disconnected",
                "error": str(e),
                "timestamp": datetime.utcnow().isoformat()
            }
        )


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": settings.service_name,
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
        "ready": "/ready"
    }


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "type": exc.__class__.__name__
        }
    )


if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8001,
        reload=settings.debug,
        log_level=settings.log_level.lower()
    )
EOFMAIN

# Fix config.py
cat > src/config.py << 'EOFCONFIG'
"""Product Service Configuration"""
import sys
import os

# Add parent directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from common_config import CommonSettings


class Settings(CommonSettings):
    """Product Service specific settings"""
    
    service_name: str = "product-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"
    otel_service_name: str = "product-service"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


settings = Settings()
EOFCONFIG

# Fix routes.py
cat > src/api/routes.py << 'EOFROUTES'
"""FastAPI routes for Product Service"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from db.database import get_db
from services.product_service import ProductService
from models.schemas import (
    ProductCreate,
    ProductUpdate,
    ProductResponse,
    ProductListResponse
)
from typing import Optional
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["products"])


@router.get("/products", response_model=ProductListResponse)
def list_products(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    category: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db)
):
    """List all products with pagination"""
    logger.info(f"Listing products: skip={skip}, limit={limit}")
    
    products, total = ProductService.get_products(
        db=db, skip=skip, limit=limit, category=category, is_active=is_active
    )
    
    return ProductListResponse(
        total=total,
        products=products,
        page=skip // limit + 1,
        page_size=limit
    )


@router.get("/products/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: Session = Depends(get_db)):
    """Get a specific product by ID"""
    product = ProductService.get_product(db, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("/products", response_model=ProductResponse, status_code=201)
def create_product(product: ProductCreate, db: Session = Depends(get_db)):
    """Create a new product"""
    try:
        return ProductService.create_product(db, product)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put("/products/{product_id}", response_model=ProductResponse)
def update_product(product_id: int, product: ProductUpdate, db: Session = Depends(get_db)):
    """Update an existing product"""
    updated = ProductService.update_product(db, product_id, product)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found")
    return updated


@router.delete("/products/{product_id}", status_code=204)
def delete_product(product_id: int, db: Session = Depends(get_db)):
    """Delete a product (soft delete)"""
    if not ProductService.delete_product(db, product_id):
        raise HTTPException(status_code=404, detail="Product not found")


@router.post("/products/{product_id}/check-stock")
def check_stock(
    product_id: int,
    quantity: int = Query(..., gt=0),
    db: Session = Depends(get_db)
):
    """Check if product has enough stock"""
    has_stock = ProductService.check_stock(db, product_id, quantity)
    product = ProductService.get_product(db, product_id)
    
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    
    return {
        "product_id": product_id,
        "requested_quantity": quantity,
        "available_stock": product.stock,
        "has_sufficient_stock": has_stock
    }


@router.post("/products/{product_id}/reduce-stock")
def reduce_stock(
    product_id: int,
    quantity: int = Query(..., gt=0),
    db: Session = Depends(get_db)
):
    """Reduce product stock"""
    if not ProductService.reduce_stock(db, product_id, quantity):
        raise HTTPException(status_code=400, detail="Insufficient stock")
    
    product = ProductService.get_product(db, product_id)
    return {
        "product_id": product_id,
        "reduced_by": quantity,
        "remaining_stock": product.stock,
        "success": True
    }
EOFROUTES

# Fix product_service.py
cat > src/services/product_service.py << 'EOFSERVICE'
"""Product business logic"""
from sqlalchemy.orm import Session
from models.product import Product
from models.schemas import ProductCreate, ProductUpdate
from typing import List, Optional, Tuple
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class ProductService:
    """Product service for business logic"""
    
    @staticmethod
    def get_product(db: Session, product_id: int) -> Optional[Product]:
        """Get product by ID"""
        with tracer.start_as_current_span("get_product") as span:
            span.set_attribute("product.id", product_id)
            product = db.query(Product).filter(Product.id == product_id).first()
            return product
    
    @staticmethod
    def get_product_by_sku(db: Session, sku: str) -> Optional[Product]:
        """Get product by SKU"""
        return db.query(Product).filter(Product.sku == sku).first()
    
    @staticmethod
    def get_products(
        db: Session,
        skip: int = 0,
        limit: int = 100,
        category: Optional[str] = None,
        is_active: Optional[bool] = None
    ) -> Tuple[List[Product], int]:
        """Get list of products with pagination"""
        query = db.query(Product)
        
        if category:
            query = query.filter(Product.category == category)
        if is_active is not None:
            query = query.filter(Product.is_active == is_active)
        
        total = query.count()
        products = query.offset(skip).limit(limit).all()
        
        return products, total
    
    @staticmethod
    def create_product(db: Session, product_data: ProductCreate) -> Product:
        """Create new product"""
        existing = ProductService.get_product_by_sku(db, product_data.sku)
        if existing:
            raise ValueError(f"Product with SKU {product_data.sku} already exists")
        
        product = Product(**product_data.model_dump())
        db.add(product)
        db.commit()
        db.refresh(product)
        return product
    
    @staticmethod
    def update_product(db: Session, product_id: int, product_data: ProductUpdate) -> Optional[Product]:
        """Update existing product"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return None
        
        update_data = product_data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(product, field, value)
        
        db.commit()
        db.refresh(product)
        return product
    
    @staticmethod
    def delete_product(db: Session, product_id: int) -> bool:
        """Delete product (soft delete)"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return False
        
        product.is_active = False
        db.commit()
        return True
    
    @staticmethod
    def check_stock(db: Session, product_id: int, quantity: int) -> bool:
        """Check if product has enough stock"""
        product = ProductService.get_product(db, product_id)
        if not product:
            return False
        return product.stock >= quantity
    
    @staticmethod
    def reduce_stock(db: Session, product_id: int, quantity: int) -> bool:
        """Reduce product stock"""
        product = ProductService.get_product(db, product_id)
        if not product or product.stock < quantity:
            return False
        
        product.stock -= quantity
        db.commit()
        return True
EOFSERVICE

# Fix database.py
cat > src/db/database.py << 'EOFDB'
"""Database connection and session management"""
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
    """Initialize database connection"""
    global engine, SessionLocal
    
    logger.info("Initializing database connection")
    
    engine = create_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
        echo=False
    )
    
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    logger.info("Database connection initialized")
    
    return engine


def create_tables():
    """Create all tables"""
    logger.info("Creating database tables")
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created")


def get_db() -> Generator[Session, None, None]:
    """Dependency for getting database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOFDB

# Fix product.py model
cat > src/models/product.py << 'EOFMODEL'
"""Product database models"""
from sqlalchemy import Column, Integer, String, Float, DateTime, Boolean, Text
from sqlalchemy.sql import func
from db.database import Base


class Product(Base):
    """Product model"""
    __tablename__ = "products"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False, index=True)
    description = Column(Text, nullable=True)
    price = Column(Float, nullable=False)
    stock = Column(Integer, nullable=False, default=0)
    category = Column(String(100), nullable=True, index=True)
    sku = Column(String(100), unique=True, nullable=False, index=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    def __repr__(self):
        return f"<Product(id={self.id}, name={self.name})>"
EOFMODEL

echo "✅ All files fixed with correct imports!"

