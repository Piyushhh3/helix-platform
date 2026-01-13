# applications/order-service/src/main.py
"""
Order Service - Main FastAPI Application
"""
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import sys
import os
from datetime import datetime
import logging

# Add parent directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

# Import common modules
from common_logging import setup_logging
from common_instrumentation import setup_opentelemetry, instrument_fastapi, instrument_sqlalchemy

# Import local modules
from api import routes
from db.database import init_database, create_tables
from services.product_client import ProductServiceClient
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
    logger.info(f"Product Service URL: {settings.product_service_url}")
    
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
    
    # Initialize Product Service client
    product_client = ProductServiceClient(base_url=settings.product_service_url)
    routes.product_client = product_client
    logger.info("Product Service client initialized")
    
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
    await product_client.close()


# Create FastAPI app
app = FastAPI(
    title="Order Service",
    description="Microservice for managing orders and order processing",
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
app.include_router(routes.router)


@app.get("/health")
async def health_check():
    """Health check endpoint (liveness probe)"""
    # Check Product Service connection
    product_service_status = "unknown"
    try:
        if routes.product_client:
            is_healthy = await routes.product_client.health_check()
            product_service_status = "healthy" if is_healthy else "unhealthy"
    except Exception as e:
        logger.error(f"Product Service health check error: {e}")
        product_service_status = "error"
    
    return {
        "status": "healthy",
        "service": settings.service_name,
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "product_service": product_service_status
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
        
        # Test Product Service connection
        product_service_ready = False
        if routes.product_client:
            product_service_ready = await routes.product_client.health_check()
        
        if not product_service_ready:
            logger.warning("Product Service is not ready")
        
        return {
            "status": "ready",
            "service": settings.service_name,
            "database": "connected",
            "product_service": "connected" if product_service_ready else "disconnected",
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
        port=8002,
        reload=settings.debug,
        log_level=settings.log_level.lower()
    )
