#!/bin/bash

set -e

VERSION=${1:-latest}
REGISTRY="725537514357.dkr.ecr.us-east-1.amazonaws.com"
IMAGE_NAME="helix-healing-agent"

echo "============================================================================"
echo "🏗️  BUILDING HEALING AGENT"
echo "============================================================================"
echo "Version: $VERSION"
echo "Registry: $REGISTRY"
echo ""

# Build Docker image
echo "Building Docker image..."
docker build -t ${IMAGE_NAME}:${VERSION} .

# Tag for ECR
echo "Tagging for ECR..."
docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:${VERSION}
docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:latest

echo ""
echo "✅ Build complete!"
echo ""
echo "To push to ECR:"
echo "  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${REGISTRY}"
echo "  docker push ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo "  docker push ${REGISTRY}/${IMAGE_NAME}:latest"
