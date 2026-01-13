#!/bin/bash
# Create Product Service configuration files

cd ~/project/helix-platform/applications/product-service

# Create requirements.txt
cat > requirements.txt << 'EOF'
# Product Service Dependencies

# Include base requirements
-r ../requirements-base.txt

# Additional service-specific dependencies (if any)
EOF

# Create .env.example
cat > .env.example << 'EOF'
# Product Service Environment Variables

# Application
SERVICE_NAME=product-service
ENVIRONMENT=dev
DEBUG=true

# Database
DATABASE_URL=postgresql://helix:helix@postgres:5432/helix

# OpenTelemetry
OTEL_ENABLED=true
OTEL_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=product-service

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
EOF

# Create .env for local development
cat > .env << 'EOF'
# Product Service - Local Development

SERVICE_NAME=product-service
ENVIRONMENT=dev
DEBUG=true

DATABASE_URL=postgresql://helix:helix@localhost:5432/helix

OTEL_ENABLED=false
OTEL_ENDPOINT=http://localhost:4317

LOG_LEVEL=INFO
LOG_FORMAT=text
EOF

# Create __init__.py files
touch src/__init__.py

# Create test file
cat > tests/test_product_service.py << 'EOF'
"""
Product Service Tests
"""
import pytest
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)


def test_health_check():
    """Test health endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_root():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "product-service"


# Add more tests as needed
EOF

echo "✅ Product Service files created"

