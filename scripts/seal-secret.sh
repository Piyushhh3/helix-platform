#!/bin/bash
# Helper script to seal a Kubernetes secret

set -e

if [ -z "$1" ]; then
    echo "Usage: ./seal-secret.sh <input-secret.yaml>"
    echo ""
    echo "Example:"
    echo "  ./seal-secret.sh infrastructure/kubernetes/secrets/templates/database-secret.yaml"
    echo ""
    echo "This will create a sealed secret in infrastructure/kubernetes/secrets/sealed/"
    exit 1
fi

INPUT_FILE="$1"
BASENAME=$(basename "$INPUT_FILE" .yaml.template)
BASENAME=$(basename "$BASENAME" .yaml)
OUTPUT_FILE="infrastructure/kubernetes/secrets/sealed/${BASENAME}-sealed.yaml"

echo "🔐 Sealing secret..."
echo "Input:  $INPUT_FILE"
echo "Output: $OUTPUT_FILE"

kubeseal --format yaml < "$INPUT_FILE" > "$OUTPUT_FILE"

echo "✅ Secret sealed successfully!"
echo ""
echo "You can now safely commit: $OUTPUT_FILE"
echo ""
echo "To apply to cluster:"
echo "  kubectl apply -f $OUTPUT_FILE"
