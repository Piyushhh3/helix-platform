#!/bin/bash
# Day 3 - Microservices Project Setup

set -e

echo "🐍 Day 3: Microservices Development Setup"
echo "=========================================="

cd ~/project/helix-platform

# Create directory structure for all services
echo "📁 Creating directory structure..."

for service in product-service order-service user-service; do
    mkdir -p applications/${service}/{src/{api,models,services,db},tests}
    
    # Create __init__.py files for Python packages
    touch applications/${service}/src/__init__.py
    touch applications/${service}/src/api/__init__.py
    touch applications/${service}/src/models/__init__.py
    touch applications/${service}/src/services/__init__.py
    touch applications/${service}/src/db/__init__.py
    touch applications/${service}/tests/__init__.py
done

echo "✅ Directory structure created"

# Create shared requirements for all services
cat > applications/requirements-base.txt << 'EOF'
# Base requirements for all microservices

# Web Framework
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0

# Database
sqlalchemy==2.0.25
psycopg2-binary==2.9.9
alembic==1.13.1

# HTTP Client (for inter-service communication)
httpx==0.26.0

# OpenTelemetry - Distributed Tracing
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
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
EOF

echo "✅ Base requirements created"

# Create .dockerignore for all services
cat > applications/.dockerignore << 'EOF'
**/__pycache__
**/*.pyc
**/*.pyo
**/*.pyd
**/.Python
**/env
**/venv
**/.venv
**/*.egg-info
**/.pytest_cache
**/.coverage
**/htmlcov
**/.git
**/.gitignore
**/README.md
**/docker-compose*.yml
**/*.md
EOF

echo "✅ .dockerignore created"

# Create common configuration module
cat > applications/common_config.py << 'EOF'
"""
Common configuration for all microservices
"""
from pydantic_settings import BaseSettings
from typing import Optional


class CommonSettings(BaseSettings):
    """Base settings that all services inherit from"""
    
    # Application
    service_name: str = "helix-service"
    environment: str = "dev"
    debug: bool = True
    
    # Database
    database_url: str = "postgresql://helix:helix@localhost:5432/helix"
    
    # OpenTelemetry
    otel_enabled: bool = True
    otel_endpoint: str = "http://localhost:4317"
    otel_service_name: Optional[str] = None
    
    # Logging
    log_level: str = "INFO"
    log_format: str = "json"
    
    class Config:
        env_file = ".env"
        case_sensitive = False


def get_service_name_from_env(default: str) -> str:
    """Helper to get service name"""
    import os
    return os.getenv("SERVICE_NAME", default)
EOF

echo "✅ Common configuration created"

# Create common instrumentation module
cat > applications/common_instrumentation.py << 'EOF'
"""
Common OpenTelemetry instrumentation for all microservices
"""
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
import logging

logger = logging.getLogger(__name__)


def setup_opentelemetry(
    service_name: str,
    otlp_endpoint: str = "http://localhost:4317",
    enabled: bool = True
):
    """
    Setup OpenTelemetry instrumentation for the service
    
    Args:
        service_name: Name of the service (e.g., "product-service")
        otlp_endpoint: OTLP collector endpoint
        enabled: Whether to enable tracing
    """
    if not enabled:
        logger.info("OpenTelemetry disabled")
        return None
    
    # Create resource with service name
    resource = Resource(attributes={
        SERVICE_NAME: service_name
    })
    
    # Create tracer provider
    provider = TracerProvider(resource=resource)
    
    # Create OTLP exporter
    otlp_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True  # Use TLS in production
    )
    
    # Add span processor
    provider.add_span_processor(
        BatchSpanProcessor(otlp_exporter)
    )
    
    # Set as global tracer provider
    trace.set_tracer_provider(provider)
    
    # Auto-instrument libraries
    HTTPXClientInstrumentor().instrument()
    
    logger.info(f"OpenTelemetry initialized for {service_name}")
    logger.info(f"Sending traces to {otlp_endpoint}")
    
    return provider


def instrument_fastapi(app):
    """Instrument FastAPI application"""
    FastAPIInstrumentor.instrument_app(app)
    logger.info("FastAPI instrumented with OpenTelemetry")


def instrument_sqlalchemy(engine):
    """Instrument SQLAlchemy engine"""
    SQLAlchemyInstrumentor().instrument(engine=engine)
    logger.info("SQLAlchemy instrumented with OpenTelemetry")
EOF

echo "✅ Common instrumentation created"

# Create common logging setup
cat > applications/common_logging.py << 'EOF'
"""
Common logging configuration for all microservices
"""
import logging
import sys
from pythonjsonlogger import jsonlogger


def setup_logging(service_name: str, log_level: str = "INFO", log_format: str = "json"):
    """
    Setup structured logging for the service
    
    Args:
        service_name: Name of the service
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        log_format: Format (json or text)
    """
    # Create logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # Remove existing handlers
    logger.handlers.clear()
    
    # Create handler
    handler = logging.StreamHandler(sys.stdout)
    
    if log_format.lower() == "json":
        # JSON formatter for production
        formatter = jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
            rename_fields={
                "asctime": "timestamp",
                "name": "logger",
                "levelname": "level"
            }
        )
        formatter.default_time_format = "%Y-%m-%dT%H:%M:%S"
        formatter.default_msec_format = "%s.%03dZ"
    else:
        # Simple formatter for development
        formatter = logging.Formatter(
            fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
    
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    # Add service name to all logs
    logger = logging.LoggerAdapter(logger, {"service": service_name})
    
    logging.info(f"Logging initialized for {service_name} at level {log_level}")
    
    return logger
EOF

echo "✅ Common logging setup created"

# Create pytest configuration
cat > applications/pytest.ini << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v --tb=short
EOF

echo "✅ pytest configuration created"

# Create README
cat > applications/README.md << 'EOF'
# Helix Platform - Microservices

This directory contains the three microservices that make up the Helix platform:

1. **Product Service**: Manages product catalog
2. **Order Service**: Handles order processing
3. **User Service**: User authentication and management

## Architecture

```
User Service → Order Service → Product Service → Database
                    ↓
            OpenTelemetry Collector → Tempo/Prometheus
```

## Tech Stack

- **Framework**: FastAPI (async Python web framework)
- **Database**: PostgreSQL with SQLAlchemy ORM
- **Observability**: OpenTelemetry (distributed tracing)
- **Logging**: Structured JSON logging
- **Containerization**: Docker with multi-stage builds

## Local Development

### Prerequisites

```bash
# Install Python 3.11+
python --version

# Install Docker
docker --version
```

### Running Locally

```bash
# Start all services with Docker Compose
docker-compose up --build

# Or run individual service
cd product-service
pip install -r requirements.txt
uvicorn src.main:app --reload --port 8001
```

### Testing

```bash
# Run tests for a service
cd product-service
pytest

# Run with coverage
pytest --cov=src tests/
```

## OpenTelemetry Instrumentation

All services are automatically instrumented with:
- HTTP request/response tracing
- Database query tracing
- Inter-service call tracing
- Custom spans for business logic

Traces are exported to OTLP collector (Grafana Tempo).

## Health Checks

Each service exposes:
- `GET /health` - Liveness probe
- `GET /ready` - Readiness probe

## API Documentation

FastAPI auto-generates interactive docs:
- Swagger UI: `http://localhost:800X/docs`
- ReDoc: `http://localhost:800X/redoc`

## Environment Variables

See `.env.example` in each service directory.
EOF

echo "✅ README created"

echo ""
echo "════════════════════════════════════════"
echo "✅ Project Setup Complete!"
echo "════════════════════════════════════════"
echo ""
echo "Created:"
echo "  ✅ Directory structure for 3 services"
echo "  ✅ Common configuration module"
echo "  ✅ OpenTelemetry instrumentation"
echo "  ✅ Structured logging setup"
echo "  ✅ Base requirements file"
echo "  ✅ Docker ignore file"
echo "  ✅ Testing configuration"
echo ""
echo "Next: Build the Product Service!"
echo ""

