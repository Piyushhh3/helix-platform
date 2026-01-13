#!/bin/bash

echo "================================================================================"
echo "🔍 HELIX PLATFORM - COMPLETE PROJECT AUDIT"
echo "================================================================================"
echo ""

# Check if project exists
if [ ! -d ~/project/helix-platform ]; then
    echo "❌ ERROR: Project directory not found at ~/project/helix-platform"
    echo "Please specify the correct location of your project."
    exit 1
fi

cd ~/project/helix-platform

echo "📁 PROJECT LOCATION"
echo "--------------------------------------------------------------------------------"
pwd
echo ""

echo "📊 PROJECT STRUCTURE (Full Tree)"
echo "--------------------------------------------------------------------------------"
tree -L 4 -I '__pycache__|*.pyc|node_modules|.git' || find . -type f -not -path '*/\.*' -not -path '*/__pycache__/*' | head -100
echo ""

echo "📦 DIRECTORY SIZES"
echo "--------------------------------------------------------------------------------"
du -sh */ 2>/dev/null | sort -h
echo ""

echo "🐳 DOCKER STATUS"
echo "--------------------------------------------------------------------------------"
echo "Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "All Containers (including stopped):"
docker ps -a --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "Docker Images:"
docker images | grep -E "helix|user-service|product-service|order-service|postgres|redis"
echo ""

echo "📝 KEY FILES INVENTORY"
echo "--------------------------------------------------------------------------------"
echo "Infrastructure Files:"
find . -name "*.tf" -o -name "terraform.tfvars" -o -name "backend.tf" | head -20
echo ""
echo "Application Files:"
find ./applications -name "*.py" -o -name "requirements.txt" -o -name "Dockerfile" | head -30
echo ""
echo "Docker Compose:"
find . -name "docker-compose*.yml"
echo ""
echo "Test Files:"
find . -name "*test*.py" -o -name "*test*.sh"
echo ""

echo "🔧 CONFIGURATION FILES"
echo "--------------------------------------------------------------------------------"
echo "Docker Compose (if exists):"
[ -f applications/docker-compose.yml ] && echo "✅ applications/docker-compose.yml" || echo "❌ NOT FOUND"
[ -f applications/integration-test.sh ] && echo "✅ applications/integration-test.sh" || echo "❌ NOT FOUND"
echo ""

echo "📋 GIT STATUS"
echo "--------------------------------------------------------------------------------"
if [ -d .git ]; then
    echo "Repository: $(git remote get-url origin 2>/dev/null || echo 'No remote configured')"
    echo "Branch: $(git branch --show-current)"
    echo "Last Commit: $(git log -1 --oneline 2>/dev/null)"
    echo ""
    echo "Uncommitted Changes:"
    git status --short | head -20
else
    echo "⚠️  NOT A GIT REPOSITORY"
fi
echo ""

echo "🔐 SECRETS & CONFIG"
echo "--------------------------------------------------------------------------------"
echo "AWS Credentials:"
[ -f ~/.aws/credentials ] && echo "✅ AWS credentials configured" || echo "❌ No AWS credentials"
echo ""
echo "Environment Files:"
find . -name ".env*" -o -name "*.env"
echo ""

echo "📊 SERVICE HEALTH (if running)"
echo "--------------------------------------------------------------------------------"
echo "Testing service endpoints..."
curl -s http://localhost:8001/health 2>/dev/null && echo "✅ User Service (8001): UP" || echo "❌ User Service (8001): DOWN"
curl -s http://localhost:8002/health 2>/dev/null && echo "✅ Product Service (8002): UP" || echo "❌ Product Service (8002): DOWN"
curl -s http://localhost:8003/health 2>/dev/null && echo "✅ Order Service (8003): UP" || echo "❌ Order Service (8003): DOWN"
echo ""

echo "💾 DATABASE STATUS"
echo "--------------------------------------------------------------------------------"
echo "PostgreSQL containers:"
docker ps --filter "name=postgres" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "📈 SYSTEM RESOURCES"
echo "--------------------------------------------------------------------------------"
echo "Disk Usage:"
df -h ~ | tail -1
echo ""
echo "Docker Disk Usage:"
docker system df
echo ""

echo "================================================================================"
echo "✅ AUDIT COMPLETE"
echo "================================================================================"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Review the output above"
echo "2. Confirm all services are running"
echo "3. Check for any missing files"
echo "4. Ready to proceed to Day 4"
echo ""
