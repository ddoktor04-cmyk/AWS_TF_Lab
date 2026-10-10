output "app_url" {
  description = "URL застосунку через DNS failover (відкривати в браузері)"
  value       = "http://${var.domain_name}"
}

output "primary_url" {
  description = "URL напряму до PRIMARY (ALB)"
  value       = "http://${module.primary.alb_dns_name}"
}

output "secondary_url" {
  description = "URL напряму до SECONDARY (S3 website)"
  value       = "http://${module.secondary_site.website_endpoint}"
}

output "hosted_zone_id" {
  description = "ID Route53 hosted zone"
  value       = module.dns_failover.zone_id
}

output "name_servers" {
  description = "NS-записи hosted zone (для делегації реального домену)"
  value       = module.dns_failover.name_servers
}

output "health_check_id" {
  description = "ID Route53 health check"
  value       = module.dns_failover.health_check_id
}

output "instance_ids" {
  description = "ID EC2 інстансів (для симуляції збою: aws ec2 stop-instances)"
  value       = module.primary.instance_ids
}

output "s3_bucket_name" {
  description = "Ім'я S3-бакета резервного сайту"
  value       = module.secondary_site.bucket_name
}
