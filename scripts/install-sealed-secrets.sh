#!/bin/bash
# Day 2 - Install Sealed Secrets Controller

set -e

echo "🔐 Day 2: Installing Sealed Secrets"
echo "===================================="

cd ~/project/helix-platform

# Verify cluster access
echo "✓ Checking cluster access..."
kubectl get nodes > /dev/null 2>&1 || {
    echo "❌ Cannot connect to cluster. Run: aws eks update-kubeconfig --name helix-dev-eks"
    exit 1
}

echo "✅ Cluster access verified"
echo ""

# Install Sealed Secrets controller
echo "📦 Installing Sealed Secrets controller..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

echo "⏳ Waiting for Sealed Secrets controller to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/sealed-secrets-controller -n kube-system

echo "✅ Sealed Secrets controller installed"
echo ""

# Install kubeseal CLI (client-side tool)
echo "📦 Installing kubeseal CLI..."

OS="$(uname -s)"
if [[ "$OS" == "Linux" ]]; then
    KUBESEAL_VERSION='0.24.0'
    wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
    tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
    sudo install -m 755 kubeseal /usr/local/bin/kubeseal
    rm kubeseal kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz
elif [[ "$OS" == "Darwin" ]]; then
    brew install kubeseal
else
    echo "❌ Unsupported OS: $OS"
    exit 1
fi

# Verify installation
KUBESEAL_VERSION=$(kubeseal --version 2>&1 | grep -oP 'v\K[0-9.]+' || echo "installed")
echo "✅ kubeseal CLI installed (version: ${KUBESEAL_VERSION})"
echo ""

# Test kubeseal
echo "🧪 Testing kubeseal..."
echo -n "test-secret" | kubeseal --raw --scope cluster-wide --name test --namespace default > /dev/null 2>&1
echo "✅ kubeseal is working"
echo ""

# Create directory structure for secrets
echo "📁 Creating secrets directory structure..."
mkdir -p infrastructure/kubernetes/secrets/{sealed,templates}

# Create a template for regular secrets (never commit!)
cat > infrastructure/kubernetes/secrets/templates/database-secret.yaml.template << 'EOF'
# Template for database secret
# Replace PLACEHOLDER values and seal with: kubeseal --format yaml < secret.yaml > sealed/database-sealed.yaml

apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: helix-app
type: Opaque
stringData:
  username: REPLACE_WITH_DB_USERNAME
  password: REPLACE_WITH_DB_PASSWORD
  database: helix_db
  host: REPLACE_WITH_RDS_ENDPOINT
  port: "5432"
EOF

cat > infrastructure/kubernetes/secrets/templates/slack-webhook.yaml.template << 'EOF'
# Template for Slack webhook secret

apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
  namespace: helix-app
type: Opaque
stringData:
  webhook-url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
EOF

cat > infrastructure/kubernetes/secrets/templates/groq-api.yaml.template << 'EOF'
# Template for Groq API secret (for AI healing agent)

apiVersion: v1
kind: Secret
metadata:
  name: groq-api-key
  namespace: helix-app
type: Opaque
stringData:
  api-key: REPLACE_WITH_GROQ_API_KEY
EOF

echo "✅ Secret templates created in infrastructure/kubernetes/secrets/templates/"
echo ""

# Create helper script for sealing secrets
cat > scripts/seal-secret.sh << 'EOFSCRIPT'
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
EOFSCRIPT

chmod +x scripts/seal-secret.sh

echo "✅ Helper script created: scripts/seal-secret.sh"
echo ""

# Create README for secrets directory
cat > infrastructure/kubernetes/secrets/README.md << 'EOF'
# Secrets Management with Sealed Secrets

## Overview

This directory contains encrypted secrets that are safe to commit to Git.

## Directory Structure

```
secrets/
├── sealed/           # Encrypted secrets (SAFE to commit)
│   └── *.yaml       # SealedSecret resources
├── templates/        # Secret templates (NEVER commit actual values!)
│   └── *.yaml.template
└── README.md
```

## How to Create a Sealed Secret

### Step 1: Create a regular Kubernetes secret

```bash
# Copy a template
cp templates/database-secret.yaml.template my-secret.yaml

# Edit and replace PLACEHOLDER values
nano my-secret.yaml
```

### Step 2: Seal the secret

```bash
# Use the helper script
./scripts/seal-secret.sh my-secret.yaml

# Or manually:
kubeseal --format yaml < my-secret.yaml > sealed/my-secret-sealed.yaml
```

### Step 3: Delete the plaintext secret

```bash
# IMPORTANT: Never commit the plaintext secret!
rm my-secret.yaml
```

### Step 4: Commit the sealed secret

```bash
git add infrastructure/kubernetes/secrets/sealed/my-secret-sealed.yaml
git commit -m "Add sealed secret for database"
git push
```

## How It Works

1. **Sealed Secrets Controller** runs in your cluster with a private key
2. **kubeseal CLI** encrypts secrets using the cluster's public key
3. Only the controller can decrypt sealed secrets
4. Encrypted secrets are safe to store in Git

## Security Benefits

- ✅ Secrets encrypted at rest in Git
- ✅ GitOps workflow enabled
- ✅ Full audit trail of secret changes
- ✅ No secrets in CI/CD variables
- ✅ Cluster-scoped encryption (can only decrypt in target cluster)

## Important Notes

- **NEVER** commit files in `templates/` with real values
- Always add `secrets/*.yaml` (not sealed) to `.gitignore`
- Sealed secrets are cluster-specific (can't be moved between clusters)
- Lost private key = lost secrets (backup your cluster!)

## Common Commands

```bash
# Get the public key
kubeseal --fetch-cert > pub-cert.pem

# Seal a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Seal a secret for a specific namespace
kubeseal --format yaml --namespace helix-app < secret.yaml > sealed-secret.yaml

# Apply a sealed secret
kubectl apply -f sealed/my-secret-sealed.yaml

# Verify the secret was created
kubectl get secret my-secret -n helix-app
```

## Interview Talking Point

"I implemented Sealed Secrets for GitOps-native secret management. Secrets are encrypted client-side using the cluster's public key and can be safely stored in Git. This enables full GitOps workflow with complete audit trail while maintaining security. The controller running in the cluster is the only entity that can decrypt the secrets using its private key."
EOF

echo "✅ Documentation created: infrastructure/kubernetes/secrets/README.md"
echo ""

# Update .gitignore to ensure we never commit plaintext secrets
cat >> .gitignore << 'EOF'

# Secrets (plaintext - NEVER commit!)
infrastructure/kubernetes/secrets/*.yaml
infrastructure/kubernetes/secrets/templates/*.yaml
!infrastructure/kubernetes/secrets/templates/*.yaml.template
!infrastructure/kubernetes/secrets/sealed/*.yaml

# Temporary files
*.tmp
*.temp
EOF

echo "✅ Updated .gitignore to protect plaintext secrets"
echo ""

echo "════════════════════════════════════════"
echo "✅ Sealed Secrets Installation Complete!"
echo "════════════════════════════════════════"
echo ""
echo "What we installed:"
echo "  ✅ Sealed Secrets controller (in kube-system namespace)"
echo "  ✅ kubeseal CLI tool"
echo "  ✅ Secret templates"
echo "  ✅ Helper scripts"
echo "  ✅ Documentation"
echo ""
echo "Next steps:"
echo "  1. Create application secrets using templates"
echo "  2. Seal them with: ./scripts/seal-secret.sh <file>"
echo "  3. Commit sealed secrets to Git"
echo ""
echo "Commands to remember:"
echo "  • Check controller: kubectl get pods -n kube-system | grep sealed-secrets"
echo "  • Create secret: ./scripts/seal-secret.sh <input.yaml>"
echo "  • List secrets: kubectl get secrets -n helix-app"
echo ""

