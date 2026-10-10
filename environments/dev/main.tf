# =============================================================================
# DNS Failover lab (dev):
#   PRIMARY   = EC2 web-1 (EIP) у eu-north-1
#   SECONDARY = EC2 web-2 (EIP) у eu-north-1
#   Моніторинг = Route53 HTTP health check за IP web-1
# =============================================================================

# --- Primary provider (eu-north-1) — дефолтний для цього модуля ---
provider "aws" {
  region     = var.aws_region_primary
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = local.common_tags
  }
}

# --- Secondary provider (eu-west-1) — для S3 website ---
provider "aws" {
  alias      = "secondary"
  region     = var.aws_region_secondary
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = local.common_tags
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }

  # Обираємо 2 перші AZ регіону primary
  azs = slice(sort(data.aws_availability_zones.available.names), 0, 2)
}

# =============================================================================
# Default VPC + subnets (щоб зосередитись на самому DNS failover)
# =============================================================================

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Один default subnet в кожному AZ (у default VPC їх по одному на AZ)
data "aws_subnet" "by_az" {
  for_each = toset(local.azs)

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = [each.value]
  }
}

# =============================================================================
# Modules
# =============================================================================

# PRIMARY: 2 EC2 у різних AZ + Elastic IP
module "primary" {
  source = "../../modules/compute"

  name_prefix   = "dns-failover"
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = [for az in local.azs : data.aws_subnet.by_az[az].id]
  instance_type = var.instance_type
  page_title    = "Primary site"
  tags          = local.common_tags
}

# DNS: hosted zone + health check + failover records
module "dns_failover" {
  source = "../../modules/dns-failover"

  zone_name         = var.domain_name
  primary_ip        = module.primary.eip_public_ips[0]
  secondary_ip      = module.primary.eip_public_ips[1]
  health_check_type = "HTTP"
  health_check_port = 80
  health_check_path = "/"
  failure_threshold = 3
  request_interval  = 30
  tags              = local.common_tags
}
