variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "aws_region_primary" {
  description = "AWS регіон PRIMARY endpoint (ALB + EC2)"
  type        = string
  default     = "eu-central-1"
}

variable "aws_region_secondary" {
  description = "AWS регіон SECONDARY endpoint (S3 website)"
  type        = string
  default     = "eu-west-1"
}

variable "domain_name" {
  description = "Домен для public hosted zone (збігається з іменем S3-бакета)"
  type        = string
  default     = "failover-lab.test"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.domain_name))
    error_message = "domain_name має бути валідним іменем бакета: малі літери, цифри, крапки та дефіси."
  }
}

variable "environment" {
  description = "Середовище розгортання"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment має бути dev, staging або prod."
  }
}

variable "project_name" {
  description = "Назва проєкту (використовується в тегах)"
  type        = string
  default     = "route53-dns-failover"
}

variable "instance_type" {
  description = "EC2 instance type для web-вузлів"
  type        = string
  default     = "t3.micro"
}
