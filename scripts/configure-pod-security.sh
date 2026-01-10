#!/bin/bash
# Day 2 - Configure Pod Security Standards

set -e

echo "🛡️  Configuring Pod Security Standards"
echo "====================================="

cd ~/project/helix-platform

# Pod Security Standards (PSS) enforce security policies at the namespace level
# Three levels: privileged, baseline, restricted

# Apply labels to namespaces to enforce Pod Security Standards
echo "📝 Applying Pod Security labels to namespaces..."

# helix-app: Restricted (most secure)
kubectl label namespace helix-app \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite

echo "✅ helix-app namespace: restricted"

# monitoring: Baseline (needs some privileges for scraping)
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite

echo "✅ monitoring namespace: baseline"

# aiops: Baseline (needs API access)
kubectl label namespace aiops \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite

echo "✅ aiops namespace: baseline"

# kube-system: Privileged (system components need it)
kubectl label namespace kube-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

echo "✅ kube-system namespace: privileged"

echo ""
echo "📊 Verifying Pod Security labels..."
kubectl get namespaces --show-labels | grep pod-security

echo ""
echo "════════════════════════════════════════"
echo "✅ Pod Security Standards Configured!"
echo "════════════════════════════════════════"
echo ""
echo "Security Levels Applied:"
echo "  • helix-app:    RESTRICTED (highest security)"
echo "  • monitoring:   BASELINE"
echo "  • aiops:        BASELINE"
echo "  • kube-system:  PRIVILEGED (system components)"
echo ""
echo "What this prevents:"
echo "  ❌ Running as root"
echo "  ❌ Privileged containers"
echo "  ❌ Host network/PID/IPC access"
echo "  ❌ Dangerous capabilities"
echo "  ❌ Unsafe volume types"
echo ""

