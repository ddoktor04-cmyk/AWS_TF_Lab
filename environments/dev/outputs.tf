output "app_url" {
  description = "URL застосунку через DNS failover (відкривати в браузері)"
  value       = "http://${var.domain_name}"
}

output "primary_url" {
  description = "URL напряму до PRIMARY (EIP web-1)"
  value       = "http://${module.primary.eip_public_ips[0]}"
}

output "secondary_url" {
  description = "URL напряму до SECONDARY (EIP web-2)"
  value       = "http://${module.primary.eip_public_ips[1]}"
}

output "eip_public_ips" {
  description = "Elastic IP інстансів: [0] = web-1 (PRIMARY), [1] = web-2 (SECONDARY)"
  value       = module.primary.eip_public_ips
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
