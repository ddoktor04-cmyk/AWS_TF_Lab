# =============================================================================
# DNS Failover module: hosted zone + health check + FAILOVER A-записи
# PRIMARY = web-1 (EIP), SECONDARY = web-2 (EIP) — звичайні non-alias A-записи
# (alias-записи експериментально не перемикалися, див. README)
# =============================================================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# --- Public hosted zone ---
resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = "Public zone managed by Terraform (DNS failover lab)"

  tags = merge(var.tags, { Name = var.zone_name })
}

# --- HTTP health check за PRIMARY endpoint (IP web-1) ---
resource "aws_route53_health_check" "primary" {
  ip_address         = var.primary_ip
  port               = var.health_check_port
  type               = var.health_check_type
  resource_path      = var.health_check_path
  failure_threshold  = var.failure_threshold
  request_interval   = var.request_interval
  measure_latency    = false
  enable_sni         = false

  tags = merge(var.tags, {
    Name = "${var.zone_name}-primary-health-check"
  })
}

# --- PRIMARY A-запис → EIP web-1 (+ health check) ---
resource "aws_route53_record" "primary" {
  zone_id         = aws_route53_zone.this.zone_id
  name            = var.zone_name
  type            = "A"
  ttl             = 60
  records         = [var.primary_ip]
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

# --- SECONDARY A-запис → EIP web-2 (без health check = завжди healthy) ---
resource "aws_route53_record" "secondary" {
  zone_id        = aws_route53_zone.this.zone_id
  name           = var.zone_name
  type           = "A"
  ttl            = 60
  records        = [var.secondary_ip]
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }
}
