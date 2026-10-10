# =============================================================================
# Compute module: ALB + 2 EC2 (Multi-AZ) — PRIMARY endpoint для DNS failover
# =============================================================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# --- AMI Amazon Linux 2023 (динамічний пошук через SSM Parameter Store) ---
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- Security Group для ALB: HTTP з інтернету ---
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB ingress HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

# --- Security Group для EC2: HTTP лише від ALB ---
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "EC2 ingress HTTP from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

# --- Target Group з HTTP health check (той самий шлях, що й у Route53) ---
resource "aws_lb_target_group" "this" {
  name     = "${var.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg" })
}

# --- Internet-facing Application Load Balancer ---
resource "aws_lb" "this" {
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  idle_timeout               = 60

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

# --- Listener HTTP:80 → forward на Target Group ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# --- EC2 інстанси (по одному в кожному AZ) з nginx ---
resource "aws_instance" "web" {
  count = length(var.subnet_ids)

  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    instance_label = "web-${count.index + 1}"
    page_title     = var.page_title
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 обов'язковий
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-web-${count.index + 1}"
  })
}
