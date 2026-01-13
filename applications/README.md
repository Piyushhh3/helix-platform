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
