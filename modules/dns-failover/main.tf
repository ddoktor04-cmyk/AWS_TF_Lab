# =============================================================================
# DNS Failover module: hosted zone + health check + FAILOVER A-alias records
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

# --- HTTP health check за PRIMARY endpoint (ALB) ---
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_fqdn
  port              = var.health_check_port
  type              = var.health_check_type
  resource_path     = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval
  measure_latency   = false
  enable_sni        = false

  tags = merge(var.tags, {
    Name = "${var.zone_name}-primary-health-check"
  })
}

# --- PRIMARY alias record → ALB ---
resource "aws_route53_record" "primary" {
  zone_id         = aws_route53_zone.this.zone_id
  name            = var.zone_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_dns_name
    zone_id                = var.primary_zone_id
    evaluate_target_health = true # ALB: оцінюємо здоров'я target'ів для швидкого failover
  }
}

# --- SECONDARY alias record → S3 website endpoint ---
resource "aws_route53_record" "secondary" {
  zone_id        = aws_route53_zone.this.zone_id
  name           = var.zone_name
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_dns_name
    zone_id                = var.secondary_zone_id
    evaluate_target_health = false
  }
}
