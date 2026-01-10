# Terraform Backend Configuration
# S3 for state storage, DynamoDB for state locking

terraform {
  backend "s3" {
    bucket         = "helix-terraform-state-725537514357"
    key            = "helix/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helix-terraform-locks"

    # Optional: Use this if you have multiple AWS profiles
    # profile = "default"
  }
}
