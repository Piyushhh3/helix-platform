#!/bin/bash

set -e

echo "============================================================================"
echo "🧪 TESTING HELM CHARTS LOCALLY"
echo "============================================================================"

# Start Minikube if not running
if ! minikube status > /dev/null 2>&1; then
    echo "Starting Minikube..."
    minikube start --cpus=4 --memory=8192
fi

# Point to Minikube Docker
eval $(minikube docker-env)

# Build images
echo "Building images..."
cd ../applications
docker build -q -t helix-user-service:latest -f user-service/Dockerfile . &
docker build -q -t helix-product-service:latest -f product-service/Dockerfile . &
docker build -q -t helix-order-service:latest -f order-service/Dockerfile . &
wait

cd ../helm-charts

# Lint
echo "Linting chart..."
helm lint helix-app -f /home/ubuntu/project/helix-platform/helm-charts/helix-app/values-local.yaml

# Deploy
echo "Deploying to Minikube..."
helm upgrade --install helix-platform helix-app \
  --namespace helix-local \
  --values helix-app/values-local.yaml \
  --wait \
  --timeout 5m

# Wait for pods
echo "Waiting for pods..."
kubectl wait --for=condition=ready pod -l app=user-service -n helix-local --timeout=120s
kubectl wait --for=condition=ready pod -l app=product-service -n helix-local --timeout=120s
kubectl wait --for=condition=ready pod -l app=order-service -n helix-local --timeout=120s

echo ""
echo "✅ VALIDATION COMPLETE"
echo ""
echo "Check status: kubectl get all -n helix-local"
echo "View logs: kubectl logs -n helix-local deployment/user-service"
echo "Cleanup: helm uninstall helix-platform -n helix-local"
