#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/../frontend"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

S3_BUCKET=$(terraform output -raw frontend_bucket_name)
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url)

echo "📦 Deploying frontend..."
echo "  S3 bucket: $S3_BUCKET"
echo "  CloudFront: $CLOUDFRONT_URL"

echo ""
echo "☁️ Uploading frontend to S3..."

aws s3 sync "$FRONTEND_DIR/" \
    "s3://$S3_BUCKET/" \
    --exclude "*.sh" \
    --delete

echo ""
echo "🔄 Finding CloudFront distribution..."

CLOUDFRONT_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?DomainName=='${CLOUDFRONT_URL#https://}'].Id | [0]" \
    --output text)

if [ "$CLOUDFRONT_ID" = "None" ] || [ -z "$CLOUDFRONT_ID" ]; then
    echo "❌ Could not find CloudFront distribution."
    exit 1
fi

echo "  Distribution ID: $CLOUDFRONT_ID"

echo ""
echo "🔄 Invalidating CloudFront cache..."

INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_ID" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)

echo "  Invalidation: $INVALIDATION_ID"

echo ""
echo "✅ Frontend deployed!"
echo "🌐 Dashboard: $CLOUDFRONT_URL"
