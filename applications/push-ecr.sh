#!/bin/bash
set -e

VERSION="${1:-v1.0.0}"
AWS_REGION="us-east-1"
ECR_REGISTRY="725537514357.dkr.ecr.us-east-1.amazonaws.com"

echo "============================================================================"
echo "🚀 PUSHING TO ECR - VERSION: $VERSION"
echo "============================================================================"

# Authenticate
echo "🔐 Authenticating..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_REGISTRY

echo "✅ Authenticated"

push_service() {
    SERVICE=$1
    
    echo ""
    echo "📤 Pushing: $SERVICE"
    docker push "${ECR_REGISTRY}/helix-${SERVICE}:${VERSION}"
    docker push "${ECR_REGISTRY}/helix-${SERVICE}:latest"
    echo "✅ Pushed: $SERVICE"
}

START=$(date +%s)

push_service "user-service"
push_service "product-service"
push_service "order-service"

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "============================================================================"
echo "✅ ALL IMAGES PUSHED - Time: ${DURATION}s"
echo "============================================================================"
echo ""
echo "Image URIs:"
echo "  ${ECR_REGISTRY}/helix-user-service:${VERSION}"
echo "  ${ECR_REGISTRY}/helix-product-service:${VERSION}"
echo "  ${ECR_REGISTRY}/helix-order-service:${VERSION}"
echo ""
echo "Verify: aws ecr list-images --repository-name helix-user-service --region us-east-1"
