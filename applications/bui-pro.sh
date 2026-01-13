#!/bin/bash
set -e

VERSION="${1:-v1.0.0}"
ECR_REGISTRY="725537514357.dkr.ecr.us-east-1.amazonaws.com"

echo "============================================================================"
echo "🏗️  BUILDING PRODUCTION IMAGES - VERSION: $VERSION"
echo "============================================================================"

# Must run from applications directory
if [ ! -d "user-service" ]; then
    echo "❌ Run from applications/ directory"
    exit 1
fi

build_service() {
    SERVICE=$1
    PORT=$2
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building: $SERVICE (port $PORT)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    docker build \
        -t "helix-${SERVICE}:${VERSION}" \
        -t "helix-${SERVICE}:latest" \
        -t "${ECR_REGISTRY}/helix-${SERVICE}:${VERSION}" \
        -t "${ECR_REGISTRY}/helix-${SERVICE}:latest" \
        -f ${SERVICE}/Dockerfile \
        .
    
    SIZE=$(docker images "helix-${SERVICE}:${VERSION}" --format "{{.Size}}")
    echo "✅ Built successfully - Size: $SIZE"
}

START=$(date +%s)

build_service "user-service" "8003"
build_service "product-service" "8001"
build_service "order-service" "8002"

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "============================================================================"
echo "✅ ALL BUILDS COMPLETE - Time: ${DURATION}s"
echo "============================================================================"
echo ""
docker images | grep -E "helix-(user|product|order)" | grep "$VERSION"
echo ""
echo "Next: ./push-to-ecr.sh $VERSION"
