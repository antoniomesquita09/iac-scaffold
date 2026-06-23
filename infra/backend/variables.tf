variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used as a prefix for resource names"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (must have an existing Route53 hosted zone)"
  type        = string
}

variable "api_subdomain" {
  description = "Subdomain for the API (e.g. 'api' produces api.domain.com)"
  type        = string
  default     = "api"
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "app_count" {
  description = "Number of ECS task instances to run"
  type        = number
  default     = 1
}

variable "fargate_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 512
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}
