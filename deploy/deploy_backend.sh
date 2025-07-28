#!/usr/bin/env bash
# Ensure this script runs in Bash
if [ -z "$BASH_VERSION" ]; then
  echo "Error: This script must be run with Bash. Use: bash $0"
  exit 1
fi

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

LOCAL_ONLY=false
# Default architecture for Lambda (fixed to x86_64 for Lambda compatibility)
PACKAGE_ARCH="x86_64"  # Hardcoded to match Lambda's supported architecture

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
  # Use fixed platform for Lambda compatibility
  DOCKER_PLATFORM="--platform linux/amd64"
  docker build \
    $DOCKER_PLATFORM \
    -f dashboard-app/backend/Dockerfile \
    -t local-lambda \
    dashboard-app/backend

  echo ""
  echo "🚀 Starting local Lambda container…"
  # Remove old container and run new one, keeping it alive
  docker rm -f lambda-local 2>/dev/null || true
  docker run -d -p 9000:8080 \
    -e DRY_RUN=true \
    -e SECRET_KEY=abc123def456ghi789jkl012mno345 \
    -e DASHBOARD_USERS_TABLE=dashboard-users \
    -e AWS_REGION=us-east-1 \
    --name lambda-local \
    local-lambda
  echo "✅ local-lambda is up on http://localhost:9000 (DRY_RUN)"

  echo ""
  echo "🔍 Testing POST /login with dry-run credentials…"
  curl -s -XPOST http://localhost:9000/2015-03-31/functions/function/invocations \
    -H "Content-Type: application/json" \
    -d '{
      "version":"2.0",
      "routeKey":"POST /login",
      "rawPath":"/login",
      "rawQueryString":"",
      "headers":{"content-type":"application/x-www-form-urlencoded"},
      "requestContext":{"http":{"method":"POST","path":"/login","sourceIp":"127.0.0.1"}},
      "body":"username=testuser@example.com&password=Passw0rd%21",
      "isBase64Encoded":false
    }' | jq .

  echo ""
  echo "✅ Local-only deployment complete. Container is running. Test manually with:"
  echo "   curl -v -X POST http://localhost:9000/login -H \"Content-Type: application/x-www-form-urlencoded\" -d 'username=strngr12@gmail.com&password=Passw0rd!'"
  echo "   (Use token from response for /dashboard)"
  exit 0  # Explicitly exit to skip AWS steps
fi

# —————————————————————————————————————————————————————————
# No --local-only: do the full AWS deploy with teardown first
# —————————————————————————————————————————————————————————

echo "🚀 Starting full deployment with teardown…"

# Perform complete teardown before deployment
echo "🔥 Initiating teardown of existing resources…"
"$(dirname "$0")/teardown_backend.sh"

echo "🚀 Proceeding with deployment…"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

export LAMBDA_NAME="dashboard-backend"
export ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"
export ROLE_NAME="DashboardLambdaRole"
export POLICY_ARN="arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
export BUILD_DIR="dashboard-app/backend/lambda-build"
export API_NAME="dashboard-api"
export PACKAGE_ARCH  # Export the fixed value

# Version management
TEMPLATE_FILE="template.yml"
VERSION_KEY="Description"  # Using Description as the version holder
VERSION_DEFAULT="0.01"     # Starting version

# Extract current version or set default
if [ -f "$TEMPLATE_FILE" ]; then
  CURRENT_VERSION=$(awk -F': ' '/^Description:/ {print $2}' "$TEMPLATE_FILE" | grep -oE '[0-9]+\.[0-9]+' || echo "$VERSION_DEFAULT")
  if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="$VERSION_DEFAULT"
  fi
else
  CURRENT_VERSION="$VERSION_DEFAULT"
fi

# Increment version
VERSION_NUM=$(echo "$CURRENT_VERSION" | awk -F'.' '{print $1*100 + $2}' | bc)
NEW_VERSION_NUM=$((VERSION_NUM + 1))
NEW_VERSION=$(printf "%.2f" "$(echo "$NEW_VERSION_NUM/100" | bc -l)")

# Generate a new SECRET_KEY securely and update template.yml
{
  SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null)
  sed -i.bak "s/^${VERSION_KEY}: .*/${VERSION_KEY}: Dashboard API Stack - v${NEW_VERSION} (SECRET_KEY updated)/" "$TEMPLATE_FILE" && rm -f "${TEMPLATE_FILE}.bak"
  sed -i.bak "s/SECRET_KEY: .*/SECRET_KEY: $SECRET_KEY/" "$TEMPLATE_FILE" && rm -f "${TEMPLATE_FILE}.bak"
} > /dev/null 2>&1  # Suppress output
unset SECRET_KEY  # Clear the variable after use
echo "📝 Updated version in $TEMPLATE_FILE to v${NEW_VERSION} with new SECRET_KEY"

# Run deployment modules
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
  . "$MODULES/$step"
done

# Update CloudFormation stack with the new version and force Lambda update
if [ "$DRY_RUN" = "false" ]; then
  echo "🔄 Updating CloudFormation stack with new version..."
  # Use --no-fail-on-empty-changeset to allow updates with no changes
  aws cloudformation update-stack \
    --stack-name dashboard-prod \
    --template-body file://template.yml \
    --region us-east-1 \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --no-fail-on-empty-changeset || {
      echo "⚠️ Stack update failed, checking if stack exists..."
      if aws cloudformation describe-stacks --stack-name dashboard-prod --region us-east-1 >/dev/null 2>&1; then
        echo "ℹ️ Stack exists, attempting update again with full capabilities..."
        aws cloudformation update-stack \
          --stack-name dashboard-prod \
          --template-body file://template.yml \
          --region us-east-1 \
          --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
          --no-fail-on-empty-changeset
      else
        echo "⚠️ Stack does not exist, creating new stack..."
        aws cloudformation create-stack \
          --stack-name dashboard-prod \
          --template-body file://template.yml \
          --region us-east-1 \
          --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
      fi
    }
  echo "✅ CloudFormation stack updated or created."
else
  echo "⚠️ Skipping stack update (DRY_RUN set)."
fi

echo ""
echo "✅ Full deployment completed."