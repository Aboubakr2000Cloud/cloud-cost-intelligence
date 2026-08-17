#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Cloud Cost Intelligence
# Demo Data Seeding
#
# Invokes the data_seeder Lambda to populate the application with demo data.
#
# Usage:
#   ./scripts/seed-data.sh
#
# Optional:
#   ENVIRONMENT=prod ./scripts/seed-data.sh
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

###############################################################################
# Helpers
###############################################################################

die() {
  echo
  echo "❌ ERROR: $1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

###############################################################################
# Prerequisites
###############################################################################

require_command aws
require_command terraform
require_command jq

[[ -d "$TERRAFORM_DIR" ]] \
  || die "Terraform directory not found: $TERRAFORM_DIR"

###############################################################################
# Load Lambda name from Terraform
###############################################################################

echo "📦 Loading infrastructure outputs..."

cd "$TERRAFORM_DIR"

SEEDER_LAMBDA="$(terraform output -raw data_seeder_lambda_name 2>/dev/null || true)"

[[ -n "$SEEDER_LAMBDA" ]] \
  || die "Terraform output 'data_seeder_lambda_name' is unavailable."

echo "  Lambda: $SEEDER_LAMBDA"
echo "  Region: $AWS_REGION"

###############################################################################
# Invoke data seeder
###############################################################################

echo
echo "🌱 Invoking data seeder Lambda..."

RESPONSE_FILE="/tmp/cloud-cost-intelligence-seed-response.json"

rm -f "$RESPONSE_FILE"

aws lambda invoke \
  --region "$AWS_REGION" \
  --function-name "$SEEDER_LAMBDA" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  "$RESPONSE_FILE" \
  --query 'StatusCode' \
  --output text

[[ -s "$RESPONSE_FILE" ]] \
  || die "Lambda returned an empty response."

echo
echo "📋 Seeder response:"
jq . "$RESPONSE_FILE" 2>/dev/null || cat "$RESPONSE_FILE"

###############################################################################
# Check Lambda-level errors
###############################################################################

if jq -e '.FunctionError' "$RESPONSE_FILE" >/dev/null 2>&1; then
  FUNCTION_ERROR="$(jq -r '.FunctionError' "$RESPONSE_FILE")"

  [[ "$FUNCTION_ERROR" == "null" ]] \
    || die "Data seeder Lambda reported an error: $FUNCTION_ERROR"
fi

###############################################################################
# Complete
###############################################################################

echo
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         Data Seeding Complete                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo
echo "✅ Demo data seeding completed."

