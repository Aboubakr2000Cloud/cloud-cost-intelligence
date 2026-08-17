id="d81k42"
#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Cloud Cost Intelligence
# Post-Deployment Smoke Tests
#
# Usage:
#   ./scripts/smoke-test.sh <ALB_URL> <CLOUDFRONT_URL>
#
# Example:
#   ./scripts/smoke-test.sh \
#     "http://cloud-cost-intelligence-prod-alb-123.eu-west-1.elb.amazonaws.com" \
#     "https://d123456789.cloudfront.net"
#
# The script intentionally performs lightweight HTTP checks only.
# It does not modify infrastructure or application data.
###############################################################################

ALB_URL="${1:-}"
CLOUDFRONT_URL="${2:-}"

###############################################################################
# Helpers
###############################################################################

die() {
  echo
  echo "❌ SMOKE TEST FAILED: $1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

normalize_url() {
  local url="$1"
  echo "${url%/}"
}

###############################################################################
# Validate arguments
###############################################################################

[[ -n "$ALB_URL" ]] \
  || die "ALB URL is required."

[[ -n "$CLOUDFRONT_URL" ]] \
  || die "CloudFront URL is required."

require_command curl

ALB_URL="$(normalize_url "$ALB_URL")"
CLOUDFRONT_URL="$(normalize_url "$CLOUDFRONT_URL")"

echo
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                       CloudCost Smoke Tests                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo
echo "ALB API:     $ALB_URL"
echo "CloudFront:  $CLOUDFRONT_URL"
echo

###############################################################################
# ALB / API health check
###############################################################################

echo "🔎 Checking API health..."

HTTP_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /tmp/cloud-cost-api-health.json \
    --write-out "%{http_code}" \
    --max-time 15 \
    "${ALB_URL}/health"
)"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Response:"
  cat /tmp/cloud-cost-api-health.json 2>/dev/null || true
  die "API health endpoint returned HTTP $HTTP_STATUS."
fi

echo "  ✅ API health: HTTP $HTTP_STATUS"

###############################################################################
# Alerts endpoint
###############################################################################

echo
echo "🔎 Checking alerts endpoint..."

HTTP_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /tmp/cloud-cost-api-alerts.json \
    --write-out "%{http_code}" \
    --max-time 15 \
    "${ALB_URL}/api/alerts?limit=1"
)"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Response:"
  cat /tmp/cloud-cost-api-alerts.json 2>/dev/null || true
  die "Alerts endpoint returned HTTP $HTTP_STATUS."
fi

echo "  ✅ Alerts endpoint: HTTP $HTTP_STATUS"

###############################################################################
# CloudFront frontend
###############################################################################

echo
echo "🔎 Checking CloudFront frontend..."

HTTP_STATUS="$(
  curl \
    --silent \
    --show-error \
    --output /tmp/cloud-cost-frontend.html \
    --write-out "%{http_code}" \
    --max-time 20 \
    "${CLOUDFRONT_URL}/"
)"

if [[ "$HTTP_STATUS" != "200" ]]; then
  die "CloudFront returned HTTP $HTTP_STATUS."
fi

echo "  ✅ CloudFront: HTTP $HTTP_STATUS"

###############################################################################
# Basic frontend content verification
###############################################################################

echo
echo "🔎 Checking frontend content..."

if ! grep -qi "CloudCost Intelligence" /tmp/cloud-cost-frontend.html; then
  die "Expected CloudCost Intelligence frontend content was not found."
fi

echo "  ✅ Frontend content verified"

###############################################################################
# Summary
###############################################################################

echo
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         Smoke Tests Passed                                   ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo
echo "✅ API health check passed"
echo "✅ Alerts endpoint passed"
echo "✅ CloudFront availability passed"
echo "✅ Frontend content verified"
echo
echo "🚀 Deployment is responding successfully."

