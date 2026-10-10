# =============================================================================
# Compute module: 2 EC2 (Multi-AZ) + Elastic IP — PRIMARY/SECONDARY для DNS failover
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

# --- Security Group для EC2: HTTP напряму з інтернету
# (Route53 health check та користувачі звертаються до інстансів без ALB).
# УВАГА: description НЕ змінювати — AWS/TF форсує заміну SG, а заміна SG з
# підключеними ENI інстансів входить у deadlock (старий SG не видаляється) ---
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "EC2 ingress HTTP from ALB only"
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

  tags = merge(var.tags, { Name = "${var.name_prefix}-app-sg" })
}

# --- EC2 інстанси (по одному в кожному AZ) з nginx ---
resource "aws_instance" "web" {
  count = length(var.subnet_ids)

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[count.index]
  vpc_security_group_ids = [aws_security_group.app.id]

  # cloud-init виконує user_data лише при першому запуску — зміна тексту
  # сторінки вимагає заміни інстансу (stop/start не оновлює контент)
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    instance_label = "web-${count.index + 1}"
    page_title     = count.index == 0 ? var.page_title : "Secondary site"
    role           = count.index == 0 ? "Primary" : "Secondary"
    role_desc      = count.index == 0 ? "основний (PRIMARY)" : "резервний (SECONDARY)"
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

# --- Elastic IP: публічна IP-адреса не звільняється при stop (на відміну від
# dynamic public IP) — Route53 A-записи посилаються саме на EIP ---
resource "aws_eip" "web" {
  count = length(aws_instance.web)

  instance = aws_instance.web[count.index].id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-web-${count.index + 1}-eip"
  })
}
