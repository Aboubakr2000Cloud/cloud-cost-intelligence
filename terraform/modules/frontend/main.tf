resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.name_prefix}-frontend"
  force_destroy = true
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-frontend-bucket"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} dashboard"

  # ==========================================================
  # S3 FRONTEND ORIGIN
  # ==========================================================

  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # ==========================================================
  # ALB API ORIGIN
  # ==========================================================

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALB-API"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"

      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  # ==========================================================
  # DEFAULT BEHAVIOR — FRONTEND → S3
  # ==========================================================

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    cached_methods = [
      "GET",
      "HEAD"
    ]

    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # ==========================================================
  # API BEHAVIOR — /api/* → ALB
  # ==========================================================

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    target_origin_id = "ALB-API"

    allowed_methods = [
      "GET",
      "HEAD",
      "OPTIONS",
      "PUT",
      "POST",
      "PATCH",
      "DELETE"
    ]

    cached_methods = [
      "GET",
      "HEAD",
      "OPTIONS"
    ]

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true

      headers = [
        "Origin",
        "Authorization",
        "Content-Type"
      ]

      cookies {
        forward = "all"
      }
    }

    # API responses should not be cached.
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ==========================================================
  # SPA ROUTING
  # ==========================================================

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  # ==========================================================
  # RESTRICTIONS
  # ==========================================================

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ==========================================================
  # HTTPS
  # ==========================================================

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # ==========================================================
  # TAGS
  # ==========================================================

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-cloudfront-distribution"
    }
  )
}

# S3 bucket policy — only CloudFront can read
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontServicePrincipal"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
}
