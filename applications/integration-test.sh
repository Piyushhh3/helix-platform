#!/bin/bash
# Integration test for all Helix microservices

set -e

cd ~/project/helix-platform/applications

echo "🧪 Helix Platform - Integration Test"
echo "====================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counter
PASSED=0
FAILED=0

test_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    
    echo -n "Testing $name... "
    
    response=$(curl -s -w "%{http_code}" -o /tmp/response.json "$url" 2>/dev/null || echo "000")
    
    if [ "$response" = "$expected_code" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (Expected $expected_code, got $response)"
        FAILED=$((FAILED + 1))
        return 1
    fi
}
: '
echo "📦 Step 1: Stop existing containers"
docker compose down -v 2>/dev/null || true
echo ""

echo "🔨 Step 2: Build all services"
docker compose build --no-cache
echo ""

echo "🚀 Step 3: Start all services"
docker compose up -d
echo ""

echo "⏳ Step 4: Wait for services to be healthy (60 seconds)"
for i in {1..60}; do
    if docker compose ps | grep -q "healthy"; then
        break
    fi
    echo -n "."
    sleep 1
done
echo ""
echo ""
 
echo "🏥 Step 5: Health Checks"
echo "========================"
test_endpoint "Product Service Health" "http://localhost:8001/health"
test_endpoint "Order Service Health" "http://localhost:8002/health"
test_endpoint "User Service Health" "http://localhost:8003/health"
echo ""
'
echo "📊 Step 6: Service Status"
echo "========================"
docker compose ps
echo ""

echo "🧪 Step 7: Functional Tests"
echo "==========================="

# Test 1: Create a user
echo ""
echo "Test 1: Create User"
USER_RESPONSE=$(curl -s -X POST http://localhost:8003/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuserr",
    "email": "testt@example.com",
    "full_name": "Test Userr",
    "password": "password123"
  }')

USER_ID=$(echo $USER_RESPONSE | jq -r '.id' 2>/dev/null)

if [ "$USER_ID" != "null" ] && [ ! -z "$USER_ID" ]; then
    echo -e "${GREEN}✓ User created: ID=$USER_ID${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Failed to create user${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 2: Login
echo ""
echo "Test 2: User Login"
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8003/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuserr",
    "password": "password123"
  }')

TOKEN=$(echo $LOGIN_RESPONSE | jq -r '.access_token' 2>/dev/null)

if [ "$TOKEN" != "null" ] && [ ! -z "$TOKEN" ]; then
    echo -e "${GREEN}✓ Login successful${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Login failed${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 3: Create products
echo ""
echo "Test 3: Create Products"

PRODUCT1=$(curl -s -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Laptop",
    "description": "High-performance laptop",
    "price": 999.99,
    "stock": 10,
    "category": "electronics",
    "sku": "LAPTOP-001",
    "is_active": true
  }')

PRODUCT1_ID=$(echo $PRODUCT1 | jq -r '.id' 2>/dev/null)

PRODUCT2=$(curl -s -X POST http://localhost:8001/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mouse",
    "description": "Wireless mouse",
    "price": 29.99,
    "stock": 50,
    "category": "electronics",
    "sku": "MOUSE-001",
    "is_active": true
  }')

PRODUCT2_ID=$(echo $PRODUCT2 | jq -r '.id' 2>/dev/null)

if [ "$PRODUCT1_ID" != "null" ] && [ "$PRODUCT2_ID" != "null" ]; then
    echo -e "${GREEN}✓ Products created: IDs=$PRODUCT1_ID, $PRODUCT2_ID${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Failed to create products${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 4: List products
echo ""
echo "Test 4: List Products"
PRODUCTS=$(curl -s http://localhost:8001/api/v1/products)
PRODUCT_COUNT=$(echo $PRODUCTS | jq -r '.total' 2>/dev/null)

if [ "$PRODUCT_COUNT" -ge "2" ]; then
    echo -e "${GREEN}✓ Products listed: Count=$PRODUCT_COUNT${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Failed to list products${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 5: Create order (Inter-service communication test!)
echo ""
echo "Test 5: Create Order (Inter-service Call)"

ORDER_RESPONSE=$(curl -s -X POST http://localhost:8002/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": $USER_ID,
    \"customer_name\": \"Test User\",
    \"customer_email\": \"test@example.com\",
    \"shipping_address\": \"123 Test St, Test City, TC 12345\",
    \"items\": [
      {
        \"product_id\": $PRODUCT1_ID,
        \"quantity\": 1
      },
      {
        \"product_id\": $PRODUCT2_ID,
        \"quantity\": 2
      }
    ]
  }")

ORDER_ID=$(echo $ORDER_RESPONSE | jq -r '.id' 2>/dev/null)

if [ "$ORDER_ID" != "null" ] && [ ! -z "$ORDER_ID" ]; then
    TOTAL=$(echo $ORDER_RESPONSE | jq -r '.total_amount' 2>/dev/null)
    echo -e "${GREEN}✓ Order created: ID=$ORDER_ID, Total=\$$TOTAL${NC}"
    echo -e "  ${BLUE}→ Order Service called Product Service successfully!${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Failed to create order${NC}"
    echo "Response: $ORDER_RESPONSE"
    FAILED=$((FAILED + 1))
fi
: '
if [ -z "$USER_ID" ] || [ -z "$PRODUCT1_ID" ] || [ -z "$PRODUCT2_ID" ]; then
    echo -e "${RED}✗ Missing required IDs: USER_ID=$USER_ID, PRODUCT1_ID=$PRODUCT1_ID, PRODUCT2_ID=$PRODUCT2_ID${NC}"
    FAILED=$((FAILED + 1))
    exit 1
fi

ORDER_RESPONSE=$(curl -s -X POST http://localhost:8002/api/v1/orders \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": $USER_ID,
    \"customer_name\": \"Test User\",
    \"customer_email\": \"testuser@example.com\",
    \"shipping_address\": \"123 Test St, Test City, TC 12345\",
    \"items\": [
      {
        \"product_id\": $PRODUCT1_ID,
        \"quantity\": 1
      },
      {
        \"product_id\": $PRODUCT2_ID,
        \"quantity\": 2
      }
    ]
  }")

# Extract order ID from response
ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.id' 2>/dev/null)

if [ "$ORDER_ID" != "null" ] && [ -n "$ORDER_ID" ]; then
    TOTAL=$(echo "$ORDER_RESPONSE" | jq -r '.total_amount' 2>/dev/null)
    echo -e "${GREEN}✓ Order created: ID=$ORDER_ID, Total=\$$TOTAL${NC}"
    echo -e "  ${BLUE}→ Order Service called Product Service successfully!${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Failed to create order${NC}"
    echo "Response: $ORDER_RESPONSE"
    FAILED=$((FAILED + 1))
fi
'
# Test 6: Verify stock was reduced
echo ""
echo "Test 6: Verify Stock Reduction"
UPDATED_PRODUCT=$(curl -s http://localhost:8001/api/v1/products/$PRODUCT1_ID)
NEW_STOCK=$(echo $UPDATED_PRODUCT | jq -r '.stock' 2>/dev/null)

if [ "$NEW_STOCK" = "9" ]; then
    echo -e "${GREEN}✓ Stock reduced correctly: 10 → 9${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Stock not reduced correctly: Expected 9, got $NEW_STOCK${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 7: Get order details
echo ""
echo "Test 7: Get Order Details"
ORDER_DETAILS=$(curl -s http://localhost:8002/api/v1/orders/$ORDER_ID)
ORDER_STATUS=$(echo $ORDER_DETAILS | jq -r '.status' 2>/dev/null)
ITEM_COUNT=$(echo $ORDER_DETAILS | jq -r '.items | length' 2>/dev/null)

if [ "$ORDER_STATUS" = "pending" ] && [ "$ITEM_COUNT" = "2" ]; then
    echo -e "${GREEN}✓ Order details correct: Status=$ORDER_STATUS, Items=$ITEM_COUNT${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ Order details incorrect${NC}"
    FAILED=$((FAILED + 1))
fi

# Final Summary
echo ""
echo "═══════════════════════════════════════════"
echo "📊 Test Results"
echo "═══════════════════════════════════════════"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo ""
    echo "🎉 Helix Platform is fully operational!"
    echo ""
    echo "Services running:"
    echo "  • Product Service: http://localhost:8001/docs"
    echo "  • Order Service:   http://localhost:8002/docs"
    echo "  • User Service:    http://localhost:8003/docs"
    echo ""
    echo "Try it yourself:"
    echo "  1. Open http://localhost:8001/docs"
    echo "  2. Create products"
    echo "  3. Open http://localhost:8002/docs"
    echo "  4. Create an order (watch it call Product Service!)"
    echo ""
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo ""
    echo "Check logs:"
    echo "  docker-compose logs product-service"
    echo "  docker-compose logs order-service"
    echo "  docker-compose logs user-service"
    echo ""
    exit 1
fi

