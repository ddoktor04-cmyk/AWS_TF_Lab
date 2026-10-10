output "bucket_name" {
  description = "Ім'я S3-бакета"
  value       = aws_s3_bucket.this.id
}

output "website_endpoint" {
  description = "S3 website endpoint (target для Route53 secondary alias)"
  value       = aws_s3_bucket_website_configuration.this.website_endpoint
}

output "website_domain" {
  description = "Домен S3 website endpoint"
  value       = aws_s3_bucket_website_configuration.this.website_domain
}

output "bucket_arn" {
  description = "ARN бакета"
  value       = aws_s3_bucket.this.arn
}
