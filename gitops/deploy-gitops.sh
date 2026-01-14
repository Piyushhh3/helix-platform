#!/bin/bash
set -e

echo "============================================================================"
echo "🚀 DEPLOYING GITOPS STACK"
echo "============================================================================"

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values gitops/bootstrap/argocd-values.yaml \
  --wait

# Get admin password
echo ""
echo "ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# Install Argo Rollouts
echo ""
echo "Installing Argo Rollouts..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  --values gitops/bootstrap/argo-rollouts-values.yaml \
  --wait

# Apply root app
echo ""
echo "Applying root application..."
kubectl apply -f gitops/applications/root-app.yaml

echo ""
echo "✅ GitOps stack deployed!"
echo ""
echo "Access ArgoCD:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
