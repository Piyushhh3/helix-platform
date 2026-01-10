#!/bin/bash
# Day 2 - Security Verification & Health Check

set -e

echo "🔍 Day 2: Security Verification"
echo "================================"
echo ""

cd ~/project/helix-platform

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS=0
FAILED=0

check_item() {
    local name=$1
    local command=$2
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅${NC} $name"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${RED}❌${NC} $name"
        FAILED=$((FAILED + 1))
    fi
}

echo "1️⃣  Sealed Secrets"
echo "─────────────────"
check_item "Sealed Secrets controller running" \
    "kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.status.availableReplicas}' | grep -q 1"
check_item "kubeseal CLI installed" "command -v kubeseal"
check_item "Secret templates exist" "test -d infrastructure/kubernetes/secrets/templates"
echo ""

echo "2️⃣  RBAC Configuration"
echo "─────────────────────"
check_item "helix-app namespace exists" "kubectl get namespace helix-app"
check_item "monitoring namespace exists" "kubectl get namespace monitoring"
check_item "aiops namespace exists" "kubectl get namespace aiops"
check_item "helix-app-sa service account exists" "kubectl get sa helix-app-sa -n helix-app"
check_item "ai-healing-agent service account exists" "kubectl get sa ai-healing-agent -n aiops"
check_item "AI agent has cluster read permissions" \
    "kubectl auth can-i get pods --as=system:serviceaccount:aiops:ai-healing-agent -A | grep -q yes"
check_item "AI agent can delete pods in helix-app" \
    "kubectl auth can-i delete pods --as=system:serviceaccount:aiops:ai-healing-agent -n helix-app | grep -q yes"
check_item "AI agent CANNOT delete pods in kube-system" \
    "kubectl auth can-i delete pods --as=system:serviceaccount:aiops:ai-healing-agent -n kube-system | grep -q no"
echo ""

echo "3️⃣  Network Policies"
echo "────────────────────"
check_item "Default deny-all policy exists" "kubectl get networkpolicy default-deny-all -n helix-app"
check_item "DNS policy exists" "kubectl get networkpolicy allow-dns -n helix-app"
check_item "Product service ingress policy exists" "kubectl get networkpolicy product-service-ingress -n helix-app"
check_item "AI agent network policy exists" "kubectl get networkpolicy ai-healing-agent-policy -n aiops"
check_item "Monitoring network policy exists" "kubectl get networkpolicy monitoring-policy -n monitoring"
echo ""

echo "4️⃣  Pod Security Standards"
echo "──────────────────────────"
check_item "helix-app namespace has restricted policy" \
    "kubectl get namespace helix-app -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -q restricted"
check_item "monitoring namespace has baseline policy" \
    "kubectl get namespace monitoring -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -q baseline"
check_item "aiops namespace has baseline policy" \
    "kubectl get namespace aiops -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -q baseline"
echo ""

echo "5️⃣  EKS Security Features"
echo "─────────────────────────"
check_item "KMS encryption enabled" \
    "aws eks describe-cluster --name helix-dev-eks --query 'cluster.encryptionConfig' --output text | grep -q secrets"
check_item "IRSA configured (OIDC provider exists)" \
    "aws eks describe-cluster --name helix-dev-eks --query 'cluster.identity.oidc.issuer' --output text | grep -q oidc"
check_item "Control plane logging enabled" \
    "aws eks describe-cluster --name helix-dev-eks --query 'cluster.logging.clusterLogging[0].enabled' --output text | grep -q True"
echo ""

echo "════════════════════════════════════════"
echo "Summary"
echo "════════════════════════════════════════"
echo -e "${GREEN}Passed:${NC} $SUCCESS checks"
echo -e "${RED}Failed:${NC} $FAILED checks"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All security checks passed!${NC}"
    echo ""
    echo "Your cluster is now production-ready with:"
    echo "  ✅ Encrypted secrets in Git (Sealed Secrets)"
    echo "  ✅ Least-privilege access control (RBAC)"
    echo "  ✅ Network isolation (Network Policies)"
    echo "  ✅ Pod security enforcement (PSS)"
    echo "  ✅ Encryption at rest (KMS)"
    echo "  ✅ Secure pod authentication (IRSA)"
    echo ""
    exit 0
else
    echo -e "${RED}⚠️  Some checks failed. Please review and fix.${NC}"
    exit 1
fi

