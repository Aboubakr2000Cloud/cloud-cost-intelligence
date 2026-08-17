#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Cloud Cost Intelligence
# Lambda Packaging
#
# Builds deployment ZIPs for all Lambda functions.
#
# Output:
#   build/*.zip
#
# Guarantees:
#   - Clean package builds
#   - No __pycache__
#   - No *.pyc / *.pyo
#   - Dependencies included where required
#   - Fails if a required handler is missing
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LAMBDA_DIR="${PROJECT_ROOT}/lambdas"
BUILD_DIR="${PROJECT_ROOT}/build"

PYTHON_BIN="${PYTHON_BIN:-python3}"

###############################################################################
# Configuration
###############################################################################

# Lambda functions that require third-party dependencies.
#
# Format:
#   "lambda_directory:requirements_file"
#
# Functions without requirements.txt are packaged without pip dependencies.
DEPENDENCY_FUNCTIONS=(
  "collector"
  "anomaly_detector"
  "data_seeder"
  "db_verifier"
)

# Functions that only contain application code / migrations.
NO_DEPENDENCY_FUNCTIONS=(
  "db_migrator"
)

###############################################################################
# Helpers
###############################################################################

log() {
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

die() {
  echo
  echo "❌ ERROR: $1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

cleanup_package_artifacts() {
  local package_dir="$1"

  find "$package_dir" \
    -type d \
    -name "__pycache__" \
    -prune \
    -exec rm -rf {} +

  find "$package_dir" \
    -type f \
    \( -name "*.pyc" -o -name "*.pyo" \) \
    -delete
}

###############################################################################
# Prerequisites
###############################################################################

require_command "$PYTHON_BIN"
require_command zip

[[ -d "$LAMBDA_DIR" ]] || die "Lambda directory not found: $LAMBDA_DIR"

###############################################################################
# Prepare build directory
###############################################################################

log "Cleaning previous Lambda builds"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

###############################################################################
# Build dependency-based Lambda functions
###############################################################################

build_with_dependencies() {
  local function_name="$1"
  local function_dir="${LAMBDA_DIR}/${function_name}"
  local requirements_file="${function_dir}/requirements.txt"
  local package_dir="${function_dir}/package"
  local zip_file="${BUILD_DIR}/${function_name}.zip"

  [[ -d "$function_dir" ]] \
    || die "Lambda directory not found: $function_dir"

  [[ -f "${function_dir}/app.py" ]] \
    || die "Lambda handler not found: ${function_dir}/app.py"

  [[ -f "$requirements_file" ]] \
    || die "Requirements file not found: $requirements_file"

  log "Building ${function_name}"

  rm -rf "$package_dir"
  mkdir -p "$package_dir"

  echo "Installing dependencies..."

  "$PYTHON_BIN" -m pip install \
    --upgrade \
    --target "$package_dir" \
    -r "$requirements_file"

  echo "Copying Lambda handler..."

  cp "${function_dir}/app.py" "$package_dir/"

  cleanup_package_artifacts "$package_dir"

  (
    cd "$package_dir"

    zip -qr \
      "$zip_file" \
      . \
      -x "__pycache__/*" \
      -x "*.pyc" \
      -x "*.pyo"
  )

  cleanup_package_artifacts "$package_dir"

  [[ -f "$zip_file" ]] \
    || die "Failed to create package: $zip_file"

  echo "✅ Created ${zip_file}"
}

###############################################################################
# Build dependency-free Lambda functions
###############################################################################

build_without_dependencies() {
  local function_name="$1"
  local function_dir="${LAMBDA_DIR}/${function_name}"
  local zip_file="${BUILD_DIR}/${function_name}.zip"

  [[ -d "$function_dir" ]] \
    || die "Lambda directory not found: $function_dir"

  [[ -f "${function_dir}/app.py" ]] \
    || die "Lambda handler not found: ${function_dir}/app.py"

  log "Building ${function_name}"

  rm -f "$zip_file"

  (
    cd "$function_dir"

    zip -qr \
      "$zip_file" \
      app.py \
      migrations \
      -x "__pycache__/*" \
      -x "*.pyc" \
      -x "*.pyo"
  )

  [[ -f "$zip_file" ]] \
    || die "Failed to create package: $zip_file"

  echo "✅ Created ${zip_file}"
}

###############################################################################
# Build all Lambdas
###############################################################################

for function_name in "${DEPENDENCY_FUNCTIONS[@]}"; do
  build_with_dependencies "$function_name"
done

for function_name in "${NO_DEPENDENCY_FUNCTIONS[@]}"; do
  build_without_dependencies "$function_name"
done

###############################################################################
# Verify packages
###############################################################################

###############################################################################
# Verify packages
###############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "▶ Verifying Lambda packages"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

expected_packages=(
  "collector"
  "anomaly_detector"
  "data_seeder"
  "db_migrator"
  "db_verifier"
)

for function_name in "${expected_packages[@]}"; do
  zip_file="${BUILD_DIR}/${function_name}.zip"

  [[ -f "$zip_file" ]] \
    || die "Expected package missing: $zip_file"

  # Lambda handler must exist at the ZIP root.
  if ! unzip -Z1 "$zip_file" | grep -Fx 'app.py' >/dev/null; then
    die "Handler app.py missing from ZIP root: $zip_file"
  fi

  # No Python cache artifacts are allowed.
  if unzip -Z1 "$zip_file" | grep -Eq '(^|/)__pycache__/|\.py[co]$'; then
    die "Python cache artifacts found in $zip_file"
  fi

  echo "✅ Verified ${function_name}.zip"
done

###############################################################################
# Summary
###############################################################################

echo
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         Lambda Build Complete                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo

ls -lh "$BUILD_DIR"/*.zip

echo
echo "✅ All Lambda packages built successfully."

