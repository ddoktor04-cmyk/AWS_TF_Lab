variable "zone_name" {
  description = "Ім'я public hosted zone (домен), напр. failover-lab.test"
  type        = string
}

variable "primary_ip" {
  description = "IP PRIMARY endpoint (EIP web-1) — значення A-запису та ціль health check"
  type        = string
}

variable "secondary_ip" {
  description = "IP SECONDARY endpoint (EIP web-2) — значення A-запису"
  type        = string
}

variable "health_check_type" {
  description = "Тип health check (HTTP або HTTPS)"
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.health_check_type)
    error_message = "health_check_type має бути HTTP, HTTPS або TCP."
  }
}

variable "health_check_port" {
  description = "Порт health check"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP-шлях health check"
  type        = string
  default     = "/"
}

variable "failure_threshold" {
  description = "Скільки послідовних невдач до зміни статусу (3-5-10-15-20-25-30)"
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5, 10, 15, 20, 25, 30], var.failure_threshold)
    error_message = "failure_threshold має бути одним із: 3, 5, 10, 15, 20, 25, 30."
  }
}

variable "request_interval" {
  description = "Інтервал запитів health check (10 або 30 секунд)"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.request_interval)
    error_message = "request_interval має бути 10 або 30."
  }
}

variable "tags" {
  description = "Спільні теги для всіх ресурсів"
  type        = map(string)
  default     = {}
}
