# infrastructure/terraform/modules/ecr/variables.tf

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["product-service", "order-service", "user-service"]
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository. Must be MUTABLE or IMMUTABLE"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Indicates whether images are scanned after being pushed to the repository"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep in repository"
  type        = number
  default     = 10
}

variable "enable_github_actions_push" {
  description = "Allow GitHub Actions to push images"
  type        = bool
  default     = false
}

variable "github_actions_role_arns" {
  description = "List of GitHub Actions IAM role ARNs allowed to push images"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
