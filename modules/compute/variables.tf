variable "name_prefix" {
  description = "Префікс для імен ресурсів (ALB, SG, TG, EC2)"
  type        = string
}

variable "vpc_id" {
  description = "ID VPC, де розгортається primary-стек"
  type        = string
}

variable "subnet_ids" {
  description = "Список subnet ID (мінімум 2, різні AZ) для ALB та EC2"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Потрібно щонайменше 2 subnet ID для Multi-AZ розгортання."
  }
}

variable "instance_type" {
  description = "EC2 instance type для web-вузлів"
  type        = string
  default     = "t3.micro"
}

variable "health_check_path" {
  description = "HTTP-шлях для health check ALB"
  type        = string
  default     = "/"
}

variable "page_title" {
  description = "Заголовок сторінки, яку віддає nginx (PRIMARY)"
  type        = string
  default     = "Primary site"
}

variable "tags" {
  description = "Спільні теги для всіх ресурсів"
  type        = map(string)
  default     = {}
}
