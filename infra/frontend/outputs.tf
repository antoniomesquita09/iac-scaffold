output "s3_bucket_name" {
  description = "S3 bucket name — set as S3_BUCKET in GitHub Actions variables"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — set as CF_DISTRIBUTION_ID in GitHub Actions variables"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain (useful for debugging DNS)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_url" {
  description = "Frontend URL"
  value       = "https://${var.domain_name}"
}
