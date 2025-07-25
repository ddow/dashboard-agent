#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# deploy/deploy_backend.sh
#
# Usage:
#   ./deploy/deploy_backend.sh [--local-only]
#
# Flags:
#   --local-only    only build and run locally (in Docker),
#                   skip all AWS deploy steps
# ---------------------------------------------------------

# Set default PACKAGE_ARCH (can be overridden by env)
PACKAGE_ARCH=${PACKAGE_ARCH:-x86_64}

LOCAL_ONLY=false
# parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    *)
      echo "❌ Unknown flag: $1"
      exit 1
      ;;
  esac
done

if $LOCAL_ONLY; then
  echo "🚀 Starting full deployment (local-only)…"

  echo ""
  echo "🧩 Running module: 01_package_lambda.sh"
  bash "$(dirname "$0")/modules/01_package_lambda.sh"

  echo ""
  echo "📦 Building local Docker image for Lambda…"
  # point at the backend folder where your Dockerfile lives
  if [ "$PACKAGE_ARCH" = "arm64" ]; then
    DOCKER_PLATFORM="--platform linux/arm64/v8"
  else
    DOCKER_PLATFORM="--platform linux/amd64"
  fi
  docker build \
    $DOCKER_PLATFORM \
    -f dashboard-app/backend/Dockerfile \
    -t local-lambda \
    dashboard-app/backend

  echo ""
  echo "✅ Local-only build complete. You can now run your Lambda container:"
  echo "   bash scripts/run-local.sh"
  exit 0
fi

# —————————————————————————————————————————————————————————
# No --local-only: do the full AWS deploy
# —————————————————————————————————————————————————————————

echo "🚀 Starting full deployment…"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

export LAMBDA_NAME="dashboard-backend"
export ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
export ROLE_NAME="DashboardLambdaRole"
export POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
export BUILD_DIR="dashboard-app/backend/lambda-build"
export API_NAME="dashboard-api"
export PACKAGE_ARCH

for step in \
  01_package_lambda.sh \
  02_create_iam_role.sh \
  03_deploy_lambda.sh \
  04_setup_api_gateway.sh \
  05_wire_proxy_route.sh \
  06_wire_public_proxy.sh \
  07_deploy_api_gateway.sh
do
  echo ""
  echo "🧩 Running module: $step"
  bash "$MODULES/$step"
done

echo ""
echo "✅ Full deployment completed."