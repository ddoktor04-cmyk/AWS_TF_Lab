output "eip_public_ips" {
  description = "Elastic IP інстансів (PRIMARY = [0], SECONDARY = [1]) — для Route53 A-записів"
  value       = aws_eip.web[*].public_ip
}

output "instance_ids" {
  description = "ID EC2 інстансів (для симуляції збою: stop/start)"
  value       = aws_instance.web[*].id
}
