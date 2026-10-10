variable "bucket_name" {
  description = "Ім'я S3-бакета (рекомендовано = domain_name, щоб задовольнити вимогу Route53 alias)"
  type        = string
}

variable "index_document" {
  description = "Ім'я index-файлу статичного сайту"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Ім'я error-файлу статичного сайту"
  type        = string
  default     = "error.html"
}

variable "tags" {
  description = "Спільні теги для всіх ресурсів"
  type        = map(string)
  default     = {}
}
