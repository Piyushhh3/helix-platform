#!/bin/bash
# Test Product Service locally without Docker first

set -e

cd ~/project/helix-platform/applications/product-service

echo "🧪 Testing Product Service Locally (Without Docker)"
echo "=================================================="

# 1. Check Python version
echo ""
echo "1️⃣ Checking Python..."
python3 --version

# 2. Create virtual environment
echo ""
echo "2️⃣ Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# 3. Install dependencies
echo ""
echo "3️⃣ Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# 4. Start PostgreSQL with Docker (just the database)
echo ""
echo "4️⃣ Starting PostgreSQL..."
docker run -d \
  --name helix-postgres-local \
  -e POSTGRES_USER=helix \
  -e POSTGRES_PASSWORD=helix \
  -e POSTGRES_DB=helix \
  -p 5432:5432 \
  postgres:15-alpine

# Wait for postgres
echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 10

# Test connection
docker exec helix-postgres-local pg_isready -U helix && echo "✅ PostgreSQL is ready!" || echo "❌ PostgreSQL not ready"

# 5. Copy common files to product-service directory
echo ""
echo "5️⃣ Setting up common modules..."
cp ../common_*.py .

# 6. Set environment variables
echo ""
echo "6️⃣ Setting environment..."
export DATABASE_URL="postgresql://helix:helix@localhost:5432/helix"
export SERVICE_NAME="product-service"
export OTEL_ENABLED="false"
export LOG_LEVEL="INFO"
export LOG_FORMAT="text"
export DEBUG="true"
export ENVIRONMENT="dev"

# 7. Run the service
echo ""
echo "7️⃣ Starting Product Service..."
echo "   Access at: http://localhost:8001"
echo "   Docs at: http://localhost:8001/docs"
echo ""
echo "Press Ctrl+C to stop"
echo ""

cd src
python -m uvicorn main:app --host 0.0.0.0 --port 8001 --reload

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    docker rm -f helix-postgres-local 2>/dev/null || true
    deactivate 2>/dev/null || true
}

trap cleanup EXIT

