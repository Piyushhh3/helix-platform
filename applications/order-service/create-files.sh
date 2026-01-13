#!/bin/bash
# Create all Order Service files

set -e

cd ~/project/helix-platform/applications/order-service

echo "📦 Creating Order Service files..."

# Create __init__.py files
touch src/__init__.py
touch src/models/__init__.py
touch src/api/__init__.py
touch src/services/__init__.py
touch src/db/__init__.py

# Database connection (same as Product Service)
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
    engine = create_engine(database_url, pool_pre_ping=True, pool_size=5, max_overflow=10)
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

# Configuration
cat > src/config.py << 'EOFCONFIG'
"""Order Service Configuration"""
import sys
import os

current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)

from common_config import CommonSettings

class Settings(CommonSettings):
    """Order Service specific settings"""
    service_name: str = "order-service"
    database_url: str = "postgresql://helix:helix@postgres:5432/helix"
    otel_service_name: str = "order-service"
    
    # Product Service URL for inter-service communication
    product_service_url: str = "http://product-service:8001"
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False

settings = Settings()
EOFCONFIG

# Requirements
cat > requirements.txt << 'EOF'
# Order Service Dependencies

# Web Framework
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0
pydantic[email]==2.5.3

# Database
sqlalchemy==2.0.25
psycopg2-binary==2.9.9
alembic==1.13.1

# HTTP Client for inter-service calls
httpx==0.26.0

# OpenTelemetry
opentelemetry-api==1.22.0
opentelemetry-sdk==1.22.0
opentelemetry-instrumentation-fastapi==0.43b0
opentelemetry-instrumentation-sqlalchemy==0.43b0
opentelemetry-instrumentation-httpx==0.43b0
opentelemetry-exporter-otlp==1.22.0

# Logging
python-json-logger==2.0.7

# Utilities
python-multipart==0.0.6
EOF

# .env for local development
cat > .env << 'EOF'
# Order Service - Local Development

SERVICE_NAME=order-service
ENVIRONMENT=dev
DEBUG=true

DATABASE_URL=postgresql://helix:helix@localhost:5432/helix
PRODUCT_SERVICE_URL=http://localhost:8001

OTEL_ENABLED=false
OTEL_ENDPOINT=http://localhost:4317

LOG_LEVEL=INFO
LOG_FORMAT=text
EOF

# .env.example
cat > .env.example << 'EOF'
# Order Service Environment Variables

SERVICE_NAME=order-service
ENVIRONMENT=dev
DEBUG=true

DATABASE_URL=postgresql://helix:helix@postgres:5432/helix
PRODUCT_SERVICE_URL=http://product-service:8001

OTEL_ENABLED=true
OTEL_ENDPOINT=http://otel-collector:4317

LOG_LEVEL=INFO
LOG_FORMAT=json
EOF

# Dockerfile for development
cat > Dockerfile.dev << 'EOFDEV'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc postgresql-client curl && rm -rf /var/lib/apt/lists/*

COPY order-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common_config.py common_logging.py common_instrumentation.py ./
COPY order-service/src ./src

ENV PYTHONPATH=/app/src:/app

EXPOSE 8002

HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8002/health || exit 1

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
EOFDEV

echo "✅ Order Service files created!"
echo ""
echo "Files created:"
echo "  ✅ src/db/database.py"
echo "  ✅ src/config.py"
echo "  ✅ requirements.txt"
echo "  ✅ .env"
echo "  ✅ Dockerfile.dev"
echo ""

