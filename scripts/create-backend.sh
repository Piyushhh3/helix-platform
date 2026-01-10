#!/bin/bash
# Create Terraform Backend (S3 + DynamoDB)
# This must be created BEFORE running terraform init

set -e

# Configuration
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="helix-terraform-state-${AWS_ACCOUNT_ID}"
DYNAMODB_TABLE="helix-terraform-locks"

echo "🗄️  Setting up Terraform Backend"
echo "================================"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo ""

# Create S3 bucket for state
echo "📦 Creating S3 bucket..."
if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION"
    
    # Enable versioning (important for state recovery)
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    echo "✅ S3 bucket created and configured"
else
    echo "✅ S3 bucket already exists"
fi

# Create DynamoDB table for state locking
echo ""
echo "🔒 Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" 2>&1 | grep -q 'ResourceNotFoundException'; then
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"
    
    echo "⏳ Waiting for table to be active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION"
    
    echo "✅ DynamoDB table created"
else
    echo "✅ DynamoDB table already exists"
fi

# Create backend configuration file
echo ""
echo "📝 Creating backend configuration..."
cat > infrastructure/terraform/backend.tf << EOF
# Terraform Backend Configuration
# S3 for state storage, DynamoDB for state locking

terraform {
  backend "s3" {
    bucket         = "${BUCKET_NAME}"
    key            = "helix/dev/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${DYNAMODB_TABLE}"
    
    # Optional: Use this if you have multiple AWS profiles
    # profile = "default"
  }
}
EOF

echo "✅ backend.tf created"

echo ""
echo "================================"
echo "✅ Backend Setup Complete!"
echo "================================"
echo ""
echo "Resources created:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""
echo "Security features enabled:"
echo "  ✅ Bucket versioning"
echo "  ✅ Server-side encryption (AES256)"
echo "  ✅ Public access blocked"
echo "  ✅ State locking enabled"
echo ""
echo "Cost: $0 (within Free Tier)"
echo "  - S3: First 5GB free"
echo "  - DynamoDB: First 25GB free"
echo ""
