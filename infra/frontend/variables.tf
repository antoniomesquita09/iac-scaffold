variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used as a prefix for resource names"
  type        = string
}

variable "domain_name" {
  description = "Root domain name (e.g. example.com) — both apex and www will be configured"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain — find it in the AWS console under Route53 > Hosted Zones"
  type        = string
}
