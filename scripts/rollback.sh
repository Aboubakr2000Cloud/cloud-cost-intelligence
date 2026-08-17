#!/usr/bin/env bash

###############################################################################
# CloudCost Intelligence — Manual ECS Rollback
#
# Purpose:
#   Restore the ECS service to the previous task definition revision.
#
# Usage:
#   ./scripts/rollback.sh
#   ./scripts/rollback.sh <task-definition-family>
#   ./scripts/rollback.sh <task-definition-family> <revision>
#
# Examples:
#   ./scripts/rollback.sh cloud-cost-intelligence-prod-api
#   ./scripts/rollback.sh cloud-cost-intelligence-prod-api 12
#
# Requirements:
#   - AWS CLI
#   - Valid AWS credentials
#   - ECS cluster/service already deployed
###############################################################################

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

AWS_REGION="${AWS_REGION:-eu-west-1}"

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"

###############################################################################
# Helpers
###############################################################################

error() {
    echo "❌ $*" >&2
    exit 1
}

info() {
    echo "ℹ️  $*"
}

success() {
    echo "✅ $*"
}

###############################################################################
# Load infrastructure context from Terraform
###############################################################################

cd "$TERRAFORM_DIR"

info "Loading ECS configuration from Terraform..."

ECS_CLUSTER="$(terraform output -raw ecs_cluster_name 2>/dev/null)" \
    || error "Unable to read ecs_cluster_name from Terraform."

ECS_SERVICE="$(terraform output -raw ecs_service_name 2>/dev/null)" \
    || error "Unable to read ecs_service_name from Terraform."

TASK_DEFINITION_FAMILY="${1:-}"

if [[ -z "$TASK_DEFINITION_FAMILY" ]]; then
    TASK_DEFINITION_FAMILY="$(
        aws ecs describe-services \
            --region "$AWS_REGION" \
            --cluster "$ECS_CLUSTER" \
            --services "$ECS_SERVICE" \
            --query 'services[0].taskDefinition' \
            --output text
    )"

    TASK_DEFINITION_FAMILY="${TASK_DEFINITION_FAMILY%:*}"
fi

###############################################################################
# Validate ECS service
###############################################################################

info "Cluster: $ECS_CLUSTER"
info "Service: $ECS_SERVICE"
info "Task definition family: $TASK_DEFINITION_FAMILY"

CURRENT_TASK_DEFINITION="$(
    aws ecs describe-services \
        --region "$AWS_REGION" \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --query 'services[0].taskDefinition' \
        --output text
)"

CURRENT_REVISION="${CURRENT_TASK_DEFINITION##*:}"

info "Current task definition: $CURRENT_TASK_DEFINITION"

###############################################################################
# Determine rollback revision
###############################################################################

REQUESTED_REVISION="${2:-}"

if [[ -n "$REQUESTED_REVISION" ]]; then

    ROLLBACK_REVISION="$REQUESTED_REVISION"

else

    ROLLBACK_REVISION="$(
        aws ecs list-task-definitions \
            --region "$AWS_REGION" \
            --family-prefix "$TASK_DEFINITION_FAMILY" \
            --status ACTIVE \
            --sort DESC \
            --query 'taskDefinitionArns[1]' \
            --output text
    )"

    if [[ "$ROLLBACK_REVISION" == "None" || -z "$ROLLBACK_REVISION" ]]; then
        error "No previous task definition revision was found."
    fi

    ROLLBACK_REVISION="${ROLLBACK_REVISION##*:}"

fi

###############################################################################
# Prevent accidental rollback to the current revision
###############################################################################

if [[ "$ROLLBACK_REVISION" == "$CURRENT_REVISION" ]]; then
    error "Rollback revision $ROLLBACK_REVISION is already running."
fi

ROLLBACK_TASK_DEFINITION="${TASK_DEFINITION_FAMILY}:${ROLLBACK_REVISION}"

###############################################################################
# Verify requested task definition exists
###############################################################################

info "Validating rollback target..."

aws ecs describe-task-definition \
    --region "$AWS_REGION" \
    --task-definition "$ROLLBACK_TASK_DEFINITION" \
    >/dev/null \
    || error "Task definition $ROLLBACK_TASK_DEFINITION does not exist."

###############################################################################
# Display rollback target
###############################################################################

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    MANUAL ROLLBACK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "AWS Region:          $AWS_REGION"
echo "ECS Cluster:         $ECS_CLUSTER"
echo "ECS Service:         $ECS_SERVICE"
echo "Current Revision:    $CURRENT_REVISION"
echo "Rollback Revision:   $ROLLBACK_REVISION"
echo
echo "Rollback target:"
echo "  $ROLLBACK_TASK_DEFINITION"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

###############################################################################
# Explicit confirmation
###############################################################################

read -r -p "⚠️  Roll back the ECS service to revision $ROLLBACK_REVISION? [y/N] " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled."
    exit 0
fi

###############################################################################
# Perform rollback
###############################################################################

echo
info "Updating ECS service..."

aws ecs update-service \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --service "$ECS_SERVICE" \
    --task-definition "$ROLLBACK_TASK_DEFINITION" \
    >/dev/null

success "ECS service updated."

###############################################################################
# Wait for service stability
###############################################################################

info "Waiting for ECS service to become stable..."

aws ecs wait services-stable \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE"

success "ECS service is stable."

###############################################################################
# Verify deployed revision
###############################################################################

DEPLOYED_TASK_DEFINITION="$(
    aws ecs describe-services \
        --region "$AWS_REGION" \
        --cluster "$ECS_CLUSTER" \
        --services "$ECS_SERVICE" \
        --query 'services[0].taskDefinition' \
        --output text
)"

DEPLOYED_REVISION="${DEPLOYED_TASK_DEFINITION##*:}"

echo
info "Verifying deployed revision..."

if [[ "$DEPLOYED_REVISION" != "$ROLLBACK_REVISION" ]]; then
    error "Rollback verification failed."
fi

success "Rollback verified."

###############################################################################
# Optional smoke test
###############################################################################

if [[ -x "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/smoke-test.sh" ]]; then

    CF_URL="$(
        terraform output -raw cloudfront_url 2>/dev/null || true
    )"

    if [[ -n "$CF_URL" ]]; then
        echo
        info "Running smoke test against CloudFront..."

        "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/smoke-test.sh" "$CF_URL"

        success "Smoke test passed."
    else
        info "CloudFront URL unavailable; skipping smoke test."
    fi

else
    info "smoke-test.sh not found/executable; skipping smoke test."
fi

###############################################################################
# Final summary
###############################################################################

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                 ROLLBACK COMPLETED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Previous revision:  $CURRENT_REVISION"
echo "Restored revision:  $ROLLBACK_REVISION"
echo "ECS service:        $ECS_SERVICE"
echo "Status:             Stable"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
