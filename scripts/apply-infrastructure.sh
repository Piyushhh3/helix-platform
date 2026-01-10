#!/bin/bash
# Apply Helix Infrastructure
# Run: chmod +x apply-infrastructure.sh && ./apply-infrastructure.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Helix Platform Infrastructure Setup     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check AWS credentials
echo -e "${YELLOW}🔐 Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured!${NC}"
    echo "Run: aws configure"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
echo -e "${GREEN}✅ Connected to AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✅ Region: $AWS_REGION${NC}"
echo ""

# Navigate to terraform directory
cd infrastructure/terraform/environments/dev

# Initialize Terraform
echo -e "${YELLOW}📦 Initializing Terraform...${NC}"
terraform init

echo ""
echo -e "${YELLOW}🔍 Validating configuration...${NC}"
terraform validate

echo ""
echo -e "${YELLOW}📋 Planning infrastructure...${NC}"
terraform plan -out=tfplan

echo ""
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⚠️  COST WARNING ⚠️${NC}"
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo ""
echo "This will create:"
echo "  • EKS Cluster: \$0.10/hour (~\$19 for 8 days)"
echo "  • NAT Gateway: \$0.045/hour (~\$9 for 8 days)"
echo "  • ALB (later): \$0.0225/hour (~\$4 for 8 days)"
echo ""
echo "  Total: ~\$32 for 8 days"
echo ""
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo ""
read -p "Do you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${RED}❌ Deployment cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}🚀 Applying infrastructure...${NC}"
echo -e "${YELLOW}⏱️  This will take about 20 minutes (EKS cluster creation)${NC}"
echo ""
echo "☕ Perfect time to:"
echo "  • Get coffee"
echo "  • Read the README"
echo "  • Prepare for Day 2 tasks"
echo ""

terraform apply tfplan

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Infrastructure Created Successfully! ✅   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Get outputs
echo -e "${BLUE}📊 Infrastructure Details:${NC}"
echo ""
terraform output

echo ""
echo -e "${YELLOW}🔧 Configuring kubectl...${NC}"
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

echo ""
echo -e "${GREEN}✅ kubectl configured!${NC}"
echo ""

# Verify cluster
echo -e "${YELLOW}🔍 Verifying cluster access...${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Day 1 Complete! 🎉                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "What we've created:"
echo "  ✅ Production VPC with public/private subnets"
echo "  ✅ EKS 1.29 cluster with 2 worker nodes"
echo "  ✅ IRSA configured for secure pod access"
echo "  ✅ ECR repositories for container images"
echo "  ✅ Security groups and network policies"
echo "  ✅ KMS encryption for Kubernetes secrets"
echo ""
echo "Next steps (Day 2):"
echo "  1. Install Sealed Secrets"
echo "  2. Configure RBAC"
echo "  3. Setup Network Policies"
echo ""
echo "Commands to remember:"
echo "  • View cluster: kubectl get nodes"
echo "  • View pods: kubectl get pods -A"
echo "  • Describe cluster: kubectl cluster-info"
echo "  • ECR login: \$(terraform output -raw ecr_login_command)"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
