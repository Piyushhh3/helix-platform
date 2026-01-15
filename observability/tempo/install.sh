#!/bin/bash

set -e

echo "============================================================================"
echo "🔍 INSTALLING GRAFANA TEMPO"
echo "============================================================================"

# Add Grafana Helm repo
echo "Adding Grafana Helm repository..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Tempo
echo ""
echo "Installing Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace monitoring \
  --values observability/tempo/values-tempo.yaml \
  --wait \
  --timeout 5m

# Deploy OTEL Collector
echo ""
echo "Deploying OpenTelemetry Collector..."
kubectl apply -f observability/tempo/otel-collector-config.yaml

echo ""
echo "✅ Tempo installed!"
echo ""
echo "🔍 Access Tempo (via Grafana):"
echo "   Grafana → Explore → Select 'Tempo' datasource"
echo ""
echo "📊 Collector endpoint for apps:"
echo "   OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.helix-dev:4317"
echo ""
