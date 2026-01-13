import os
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
