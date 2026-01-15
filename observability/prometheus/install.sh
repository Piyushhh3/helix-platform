#!/bin/bash

set -e

echo "============================================================================"
echo "📊 INSTALLING PROMETHEUS STACK"
echo "============================================================================"

# Add Prometheus community Helm repo
echo "Adding Prometheus Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace
echo "Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install kube-prometheus-stack
echo ""
echo "Installing kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values observability/prometheus/values-prometheus-stack.yaml \
  --wait \
  --timeout 10m

echo ""
echo "✅ Prometheus Stack installed!"
echo ""
echo "📊 Access Grafana:"
echo "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo ""
echo "🔍 Access Prometheus:"
echo "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo ""
echo "Default Grafana credentials:"
echo "Username: admin"
echo "Password: admin123"
echo ""
