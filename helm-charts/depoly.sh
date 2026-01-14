#!/bin/bash

set -e

ENVIRONMENT="${1:-dev}"
NAMESPACE="helix-${ENVIRONMENT}"
CHART_PATH="./helix-app"

echo "============================================================================"
echo "🚀 DEPLOYING HELIX PLATFORM TO EKS"
echo "============================================================================"
echo "Environment: $ENVIRONMENT"
echo "Namespace: $NAMESPACE"
echo ""

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy with Helm
if [ "$ENVIRONMENT" == "prod" ]; then
    helm upgrade --install helix-platform $CHART_PATH \
        --namespace $NAMESPACE \
        --values $CHART_PATH/values.yaml \
        --values $CHART_PATH/values-prod.yaml \
        --wait \
        --timeout 10m
else
    helm upgrade --install helix-platform $CHART_PATH \
        --namespace $NAMESPACE \
        --values $CHART_PATH/values.yaml \
        --values $CHART_PATH/values-dev.yaml \
        --wait \
        --timeout 10m
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Check status:"
echo "kubectl get all -n $NAMESPACE"
echo ""
echo "🔍 View pods:"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "📝 View logs:"
echo "kubectl logs -f -n $NAMESPACE deployment/user-service"
