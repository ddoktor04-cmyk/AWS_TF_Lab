# =============================================================================
# DNS Failover lab (dev):
#   PRIMARY   = ALB + 2 EC2 (nginx) у eu-central-1
#   SECONDARY = S3 static website у eu-west-1
#   Моніторинг = Route53 HTTP health check за ALB
# =============================================================================

# --- Primary provider (eu-central-1) — дефолтний для цього модуля ---
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

  # Hosted zone ID для S3 WEBSITE endpoints (див. AWS General Reference:
  # "Amazon S3 website endpoints" → колонка Hosted zone ID)
  s3_website_hosted_zone_ids = {
    "eu-central-1" = "Z21DNDUVLTQW6Q"
    "eu-west-1"    = "Z1BKCTXD74EZPE"
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

# PRIMARY: ALB + 2 EC2 у різних AZ
module "primary" {
  source = "../../modules/compute"

  name_prefix       = "dns-failover"
  vpc_id            = data.aws_vpc.default.id
  subnet_ids        = [for az in local.azs : data.aws_subnet.by_az[az].id]
  instance_type     = var.instance_type
  health_check_path = "/"
  page_title        = "Primary site"
  tags              = local.common_tags
}

# SECONDARY: S3 static website (fallback)
module "secondary_site" {
  source = "../../modules/s3-website"

  providers = {
    aws = aws.secondary
  }

  bucket_name    = var.domain_name
  index_document = "index.html"
  error_document = "error.html"
  tags           = local.common_tags
}

# DNS: hosted zone + health check + failover records
module "dns_failover" {
  source = "../../modules/dns-failover"

  zone_name          = var.domain_name
  primary_fqdn       = module.primary.alb_dns_name
  primary_dns_name   = module.primary.alb_dns_name
  primary_zone_id    = module.primary.alb_zone_id
  secondary_dns_name = module.secondary_site.website_endpoint
  secondary_zone_id  = local.s3_website_hosted_zone_ids[var.aws_region_secondary]
  health_check_type  = "HTTP"
  health_check_port  = 80
  health_check_path  = "/"
  failure_threshold  = 3
  request_interval   = 30
  tags               = local.common_tags
}
