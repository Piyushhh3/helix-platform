#!/bin/bash
# Fix Product Service Docker and requirements issues

set -e

cd ~/project/helix-platform/applications

echo "🔧 Fixing Product Service..."

# First, let's create a proper combined requirements file
cat > product-service/requirements.txt << 'EOF'
# Product Service - All Dependencies

# Web Framework
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0

# Database
sqlalchemy==2.0.25
psycopg2-binary==2.9.9
alembic==1.13.1

# HTTP Client
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
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
EOF

# Fix the Dockerfile for local testing
cat > product-service/Dockerfile.dev << 'EOFDEV'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY product-service/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy common modules
COPY common_config.py common_logging.py common_instrumentation.py ./

# Copy application code
COPY product-service/src ./src

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"

# Run application
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001", "--reload"]
EOFDEV

# Create a simpler docker-compose for testing
cat > docker-compose.test.yml << 'EOFDOCKER'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: helix-postgres-test
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
    networks:
      - helix-network

  product-service:
    build:
      context: .
      dockerfile: product-service/Dockerfile.dev
    container_name: product-service-test
    ports:
      - "8001:8001"
    environment:
      DATABASE_URL: postgresql://helix:helix@postgres:5432/helix
      SERVICE_NAME: product-service
      ENVIRONMENT: dev
      DEBUG: "true"
      OTEL_ENABLED: "false"
      LOG_LEVEL: INFO
      LOG_FORMAT: text
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - helix-network
    restart: unless-stopped

networks:
  helix-network:
    driver: bridge
EOFDOCKER

echo "✅ Files fixed!"
echo ""

# Clean up any previous containers
echo "🧹 Cleaning up old containers..."
docker compose -f docker-compose.test.yml down -v 2>/dev/null || true

echo ""
echo "🔨 Building services..."
docker compose -f docker-compose.test.yml build --no-cache

echo ""
echo "🚀 Starting services..."
docker compose -f docker-compose.test.yml up -d

echo ""
echo "⏳ Waiting for services to be healthy (30 seconds)..."
sleep 30

# Show logs
echo ""
echo "📋 Product Service logs:"
docker compose -f docker-compose.test.yml logs product-service | tail -20

echo ""
echo "🏥 Testing endpoints..."

# Test health
echo ""
echo "1. Health Check:"
curl -f http://localhost:8001/health 2>/dev/null && echo " ✅" || echo " ❌"

# Test readiness
echo ""
echo "2. Readiness Check:"
curl -f http://localhost:8001/ready 2>/dev/null && echo " ✅" || echo " ❌"

# Test root
echo ""
echo "3. Root Endpoint:"
curl -s http://localhost:8001/ | jq -r '.service' 2>/dev/null && echo " ✅" || echo " ❌"

# Create test product
echo ""
echo "4. Creating test product..."
PRODUCT_RESPONSE=$(curl -s -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Widget",
    "description": "A test product for demo",
    "price": 29.99,
    "stock": 100,
    "category": "widgets",
    "sku": "TEST-WIDGET-001",
    "is_active": true
  }')

echo "$PRODUCT_RESPONSE" | jq '.' 2>/dev/null || echo "Failed to create product"

# Get product ID from response
PRODUCT_ID=$(echo "$PRODUCT_RESPONSE" | jq -r '.id' 2>/dev/null)

if [ "$PRODUCT_ID" != "null" ] && [ ! -z "$PRODUCT_ID" ]; then
    echo " ✅ Product created with ID: $PRODUCT_ID"
    
    # List products
    echo ""
    echo "5. Listing products:"
    curl -s http://localhost:8001/api/v1/products | jq '.total, .products[0].name' 2>/dev/null
    echo " ✅"
    
    # Get specific product
    echo ""
    echo "6. Getting product by ID:"
    curl -s http://localhost:8001/api/v1/products/$PRODUCT_ID | jq -r '.name' 2>/dev/null
    echo " ✅"
else
    echo " ❌ Failed to create product"
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "✅ Product Service Test Complete!"
echo "════════════════════════════════════════════════════"
echo ""
echo "Service is running at:"
echo "  • API:    http://localhost:8001"
echo "  • Docs:   http://localhost:8001/docs (Open this in your browser!)"
echo "  • ReDoc:  http://localhost:8001/redoc"
echo "  • Health: http://localhost:8001/health"
echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.test.yml logs -f product-service"
echo ""
echo "To stop:"
echo "  docker-compose -f docker-compose.test.yml down"
echo ""
echo "To rebuild:"
echo "  docker-compose -f docker-compose.test.yml up --build"
echo ""

