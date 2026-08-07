resource "aws_kms_key" "app" {
  description             = "${var.name_prefix} application encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable root account full access"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-app-key"
    }
  )
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.name_prefix}-app"
  target_key_id = aws_kms_key.app.key_id
}

