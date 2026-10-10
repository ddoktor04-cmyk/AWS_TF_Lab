# =============================================================================
# S3 Website module — SECONDARY (fallback) endpoint для DNS failover
# =============================================================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# --- Бакет для статичного сайту ---
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = merge(var.tags, { Name = var.bucket_name })
}

# --- Website hosting configuration (index + error documents) ---
resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}

# --- Дозволяємо публічний доступ (потрібен для website endpoint) ---
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# --- Bucket policy: публічне читання об'єктів лише для website ---
data "aws_iam_policy_document" "public_read" {
  statement {
    sid    = "PublicReadForWebsite"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.public_read.json

  # Policy має створюватись після зняття Public Access Block
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# --- Завантаження HTML-файлів статичного сайту ---
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.this.id
  key          = var.index_document
  source       = "${path.module}/files/index.html"
  etag         = filemd5("${path.module}/files/index.html")
  content_type = "text/html"

  tags = var.tags
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.this.id
  key          = var.error_document
  source       = "${path.module}/files/error.html"
  etag         = filemd5("${path.module}/files/error.html")
  content_type = "text/html"

  tags = var.tags
}
