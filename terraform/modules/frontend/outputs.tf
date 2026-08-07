output "cloudfront_url" { value = "https://${aws_cloudfront_distribution.frontend.domain_name}" }
output "cloudfront_domain_name" { value = aws_cloudfront_distribution.frontend.domain_name }
output "cloudfront_id" { value = aws_cloudfront_distribution.frontend.id }
output "s3_bucket_name" { value = aws_s3_bucket.frontend.id }
output "s3_bucket_arn" { value = aws_s3_bucket.frontend.arn }
