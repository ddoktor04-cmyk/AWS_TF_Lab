output "zone_id" {
  description = "ID створеної public hosted zone"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "NS-записи hosted zone (потрібні для делегації, якщо домен реальний)"
  value       = aws_route53_zone.this.name_servers
}

output "health_check_id" {
  description = "ID Route53 health check (для моніторингу статусу)"
  value       = aws_route53_health_check.primary.id
}

output "primary_record_fqdn" {
  description = "FQDN первинного запису"
  value       = aws_route53_record.primary.fqdn
}

output "secondary_record_fqdn" {
  description = "FQDN резервного запису"
  value       = aws_route53_record.secondary.fqdn
}
