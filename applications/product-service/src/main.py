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
