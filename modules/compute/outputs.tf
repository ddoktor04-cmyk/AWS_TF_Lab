output "alb_dns_name" {
  description = "DNS-ім'я ALB (використовується Route53 health check та alias)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID ALB (для Route53 alias record)"
  value       = aws_lb.this.zone_id
}

output "alb_arn" {
  description = "ARN Application Load Balancer"
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN Target Group"
  value       = aws_lb_target_group.this.arn
}

output "instance_ids" {
  description = "ID EC2 інстансів (для симуляції збою: stop/start)"
  value       = aws_instance.web[*].id
}

output "instance_public_ips" {
  description = "Публічні IP EC2 інстансів"
  value       = aws_instance.web[*].public_ip
}
