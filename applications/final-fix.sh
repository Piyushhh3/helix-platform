i#!/bin/bash
# Final fix for Product Service imports

set -e

cd ~/project/helix-platform/applications

echo "🔧 Final Fix: Setting PYTHONPATH..."

# Fix docker-compose.test.yml - add PYTHONPATH
cat > docker-compose.test.yml << 'EOFDOCKER'
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
      PYTHONPATH: /app/src:/app
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

# Also update the Dockerfile CMD to use PYTHONPATH
cat > product-service/Dockerfile.dev << 'EOFDEV'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY product-service/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy common modules
COPY common_config.py common_logging.py common_instrumentation.py ./

# Copy application code
COPY product-service/src ./src

# Set Python path
ENV PYTHONPATH=/app/src:/app

# Expose port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8001/health || exit 1

# Run application
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
EOFDEV

echo "✅ Files updated with PYTHONPATH fix"
echo ""

# Restart services
echo "🔄 Restarting services..."
docker compose -f docker-compose.test.yml down
docker compose -f docker-compose.test.yml build --no-cache product-service
docker compose -f docker-compose.test.yml up -d

echo ""
echo "⏳ Waiting 20 seconds for startup..."
sleep 20

# Check health
echo ""
echo "🏥 Testing endpoints..."
echo ""
echo "Health check:"
curl -f http://localhost:8001/health 2>/dev/null && echo " ✅" || echo " ❌ (waiting...)"

sleep 10

echo ""
echo "Readiness check:"
curl -f http://localhost:8001/ready 2>/dev/null && echo " ✅" || echo " ❌"

echo ""
echo "Root endpoint:"
curl -s http://localhost:8001/ | jq -r '.service' 2>/dev/null && echo " ✅" || echo " ❌"

# Create test product
echo ""
echo "Creating test product..."
RESPONSE=$(curl -s -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Awesome Gadget",
    "description": "The coolest gadget in town",
    "price": 99.99,
    "stock": 50,
    "category": "electronics",
    "sku": "GADGET-2024",
    "is_active": true
  }')

echo "$RESPONSE" | jq '.' 2>/dev/null || echo "Response: $RESPONSE"

PRODUCT_ID=$(echo "$RESPONSE" | jq -r '.id' 2>/dev/null)

if [ "$PRODUCT_ID" != "null" ] && [ ! -z "$PRODUCT_ID" ]; then
    echo "✅ Product created! ID: $PRODUCT_ID"
    
    echo ""
    echo "Listing products:"
    curl -s http://localhost:8001/api/v1/products | jq '.total, .products[] | {id, name, price, stock}' 2>/dev/null
    
    echo ""
    echo "════════════════════════════════════════════════════"
    echo "✅ PRODUCT SERVICE IS WORKING!"
    echo "════════════════════════════════════════════════════"
    echo ""
    echo "🎉 Service is ready at:"
    echo "   • API:    http://localhost:8001"
    echo "   • Docs:   http://localhost:8001/docs"
    echo "   • Health: http://localhost:8001/health"
    echo ""
else
    echo "⚠️  Product creation may have failed, but service is running"
    echo "Check logs: docker-compose -f docker-compose.test.yml logs product-service"
fi

echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.test.yml logs -f product-service"
echo ""

