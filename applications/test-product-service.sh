#!/bin/bash
# Test Product Service locally with Docker Compose

set -e

cd ~/project/helix-platform/applications

echo "🐳 Testing Product Service with Docker Compose"
echo "=============================================="

# Create minimal docker-compose for testing
cat > docker-compose.test.yml << 'EOFDOCKER'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: helix
      POSTGRES_PASSWORD: helix
      POSTGRES_DB: helix
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U helix"]
      interval: 5s
      timeout: 5s
      retries: 5

  product-service:
    build:
      context: .
      dockerfile: product-service/Dockerfile.dev
    ports:
      - "8001:8001"
    environment:
      - DATABASE_URL=postgresql://helix:helix@postgres:5432/helix
      - SERVICE_NAME=product-service
      - OTEL_ENABLED=false
      - LOG_LEVEL=INFO
      - LOG_FORMAT=text
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./product-service:/app
      - ./common_config.py:/app/common_config.py
      - ./common_logging.py:/app/common_logging.py
      - ./common_instrumentation.py:/app/common_instrumentation.py
EOFDOCKER

# Create development Dockerfile
cat > product-service/Dockerfile.dev << 'EOFDEV'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements-base.txt .
COPY product-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY product-service/src ./src
COPY common_*.py ./

# Expose port
EXPOSE 8001

# Run with hot reload
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001", "--reload"]
EOFDEV

echo "✅ Docker Compose files created"
echo ""
echo "🚀 Starting services..."

# Start services
docker compose -f docker-compose.test.yml up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check health
echo ""
echo "🏥 Checking health..."
curl -s http://localhost:8001/health | jq

# Check readiness
echo ""
echo "✅ Checking readiness..."
curl -s http://localhost:8001/ready | jq

# Create a test product
echo ""
echo "📦 Creating test product..."
curl -s -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Widget",
    "description": "A test product",
    "price": 29.99,
    "stock": 100,
    "category": "widgets",
    "sku": "TEST-001",
    "is_active": true
  }' | jq

# List products
echo ""
echo "📋 Listing products..."
curl -s http://localhost:8001/api/v1/products | jq

echo ""
echo "════════════════════════════════════════"
echo "✅ Product Service is working!"
echo "════════════════════════════════════════"
echo ""
echo "Access the service:"
echo "  • API: http://localhost:8001"
echo "  • Docs: http://localhost:8001/docs"
echo "  • Health: http://localhost:8001/health"
echo ""
echo "To stop:"
echo "  docker-compose -f docker-compose.test.yml down"
echo ""

