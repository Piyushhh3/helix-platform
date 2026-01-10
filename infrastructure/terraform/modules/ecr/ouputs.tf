# infrastructure/terraform/modules/ecr/outputs.tf

output "repository_urls" {
  description = "Map of repository names to URLs"
  value = {
    for repo in aws_ecr_repository.main :
    repo.name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of repository names to ARNs"
  value = {
    for repo in aws_ecr_repository.main :
    repo.name => repo.arn
  }
}

output "registry_id" {
  description = "The registry ID where the repositories are created"
  value       = [for repo in aws_ecr_repository.main : repo.registry_id][0]
}
