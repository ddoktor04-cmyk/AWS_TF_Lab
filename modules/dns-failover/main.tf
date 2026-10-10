# =============================================================================
# DNS Failover module: hosted zone + health check + FAILOVER A-alias records
# =============================================================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    dns = {
      source = "hashicorp/dns"
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

# --- IP ALB (alias A-запис не перемикається failover на практиці, тому
# резолвимо IP напряму і робимо звичайний A-запис з health check) ---
data "dns_a_record_set" "primary" {
  host = var.primary_dns_name
}

# --- PRIMARY A-запис → IP ALB + health check ---
resource "aws_route53_record" "primary" {
  zone_id         = aws_route53_zone.this.zone_id
  name            = var.zone_name
  type            = "A"
  ttl             = 60
  records         = data.dns_a_record_set.primary.addrs
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

# --- IP S3 website endpoint (alias-SECONDARY блокував failover на практиці) ---
data "dns_a_record_set" "secondary" {
  host = var.secondary_dns_name
}

# --- SECONDARY A-запис → IP S3 website (без health check = завжди healthy) ---
resource "aws_route53_record" "secondary" {
  zone_id        = aws_route53_zone.this.zone_id
  name           = var.zone_name
  type           = "A"
  ttl            = 60
  records        = data.dns_a_record_set.secondary.addrs
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  # Публічний DNS S3 website endpoint повертає різний підмножину IP-пула щозапиту,
  # тому фіксуємо адреси, отримані при apply (інакше — perpetual diff)
  lifecycle {
    ignore_changes = [records]
  }
}
