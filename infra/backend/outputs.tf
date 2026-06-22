output "ecr_repository_url" {
  description = "ECR repository URL — use this as your Docker push target"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "ecs_task_definition_family" {
  description = "ECS task definition family — used by CI/CD to render updates"
  value       = aws_ecs_task_definition.app.family
}

output "container_name" {
  description = "Container name inside the task definition"
  value       = var.project_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "API base URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "db_host" {
  description = "RDS host only (no port) — set as DB_HOST in GitHub Actions variables for migrations"
  value       = aws_db_instance.postgres.address
}

output "db_secret_arn" {
  description = "RDS-managed Secrets Manager ARN (master user/password) — set as DB_SECRET_ARN in GitHub Actions variables"
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}
