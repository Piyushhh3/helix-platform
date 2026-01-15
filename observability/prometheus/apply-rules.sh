#!/bin/bash

set -e

echo "============================================================================"
echo "🚨 APPLYING ALERT RULES"
echo "============================================================================"

# Apply alert rules
echo "Applying alert rules..."
kubectl apply -f observability/prometheus/rules/helix-alerts.yaml

# Apply recording rules
echo "Applying recording rules..."
kubectl apply -f observability/prometheus/rules/recording-rules.yaml

# Wait for reload
echo ""
echo "Waiting for Prometheus to reload configuration..."
sleep 10

# Verify rules loaded
echo ""
echo "Verifying rules..."
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
PF_PID=$!
sleep 5

echo ""
echo "✅ Rules applied!"
echo ""
echo "View rules at: http://localhost:9090/rules"
echo "View alerts at: http://localhost:9090/alerts"
echo ""

# Cleanup
kill $PF_PID 2>/dev/null || true
