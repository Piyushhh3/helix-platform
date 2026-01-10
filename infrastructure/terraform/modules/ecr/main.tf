# infrastructure/terraform/modules/ecr/main.tf
# ECR Module - Container Registry for application images

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(
    var.tags,
    {
      "ManagedBy"   = "Terraform"
      "Project"     = var.project_name
      "Environment" = var.environment
    }
  )
}

# ============================================================================
# ECR Repositories
# ============================================================================

resource "aws_ecr_repository" "main" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256" # Use KMS for production
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${each.value}"
    }
  )
}

# ============================================================================
# Lifecycle Policy (Keep last N images, delete old ones)
# ============================================================================

resource "aws_ecr_lifecycle_policy" "main" {
  for_each = aws_ecr_repository.main

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# Repository Policy (Allow EKS nodes to pull images)
# ============================================================================

data "aws_iam_policy_document" "ecr_pull_policy" {
  for_each = aws_ecr_repository.main

  statement {
    sid    = "AllowEKSNodesPull"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }

  # Allow GitHub Actions to push (if CI/CD enabled)
  dynamic "statement" {
    for_each = var.enable_github_actions_push ? [1] : []

    content {
      sid    = "AllowGitHubActionsPush"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.github_actions_role_arns
      }

      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
      ]
    }
  }
}

resource "aws_ecr_repository_policy" "main" {
  for_each = aws_ecr_repository.main

  repository = each.value.name
  policy     = data.aws_iam_policy_document.ecr_pull_policy[each.key].json
}
