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
  echo "✅ Local-only build complete. You can now run your Lambda container:"
  echo "   bash scripts/run-local.sh"
  exit 0  # Explicitly exit to skip AWS steps
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

# Update template.yml with new version
sed -i.bak "s/^${VERSION_KEY}: .*/${VERSION_KEY}: Dashboard API Stack - v${NEW_VERSION} (SECRET_KEY updated)/" "$TEMPLATE_FILE" && rm -f "${TEMPLATE_FILE}.bak"
echo "📝 Updated version in $TEMPLATE_FILE to v${NEW_VERSION}"

# Check and manage resources
echo "🔍 Checking existing resources..."
LAMBDA_EXISTS=$(aws lambda get-function --function-name "$LAMBDA_NAME" --region us-east-1 2>/dev/null && echo "true" || echo "false")
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --region us-east-1 2>/dev/null && echo "true" || echo "false")
API_EXISTS=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region us-east-1 | grep -q . && echo "true" || echo "false")

# Run deployment modules based on existence and version
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
  if [ "$step" = "01_package_lambda.sh" ] || [ "$step" = "02_create_iam_role.sh" ] || [ "$step" = "03_deploy_lambda.sh" ]; then
    if [ "$LAMBDA_EXISTS" = "true" ] || [ "$ROLE_EXISTS" = "true" ]; then
      echo "ℹ️ $step skipped: Lambda or IAM role already exists"
    else
      . "$MODULES/$step"
    fi
  elif [ "$step" = "04_setup_api_gateway.sh" ] || [ "$step" = "05_wire_proxy_route.sh" ] || [ "$step" = "06_wire_public_proxy.sh" ] || [ "$step" = "07_deploy_api_gateway.sh" ]; then
    if [ "$API_EXISTS" = "true" ]; then
      # Check if API version or configuration needs update
      CURRENT_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME']|[0].id" --output text --region us-east-1)
      # Simplified update check (compare with template version or resource state)
      if [ -n "$CURRENT_API_ID" ]; then
        echo "ℹ️ API Gateway $CURRENT_API_ID exists, checking for updates..."
        . "$MODULES/$step"  # Run to potentially update if changes detected
      else
        . "$MODULES/$step"
      fi
    else
      . "$MODULES/$step"
    fi
  fi
done

# Update CloudFormation stack output with the new API ID if set
if [ -n "${REST_API_ID:-}" ] && [ "$DRY_RUN" = "false" ]; then
  echo "🔄 Updating CloudFormation stack output with new API ID: $REST_API_ID"
  # Generate outputs.json dynamically
  cat <<EOF > outputs.json
  [
    {
      "OutputKey": "ApiEndpoint",
      "OutputValue": "https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/Prod",
      "Description": "Default execute-api endpoint"
    }
  ]
  EOF
  aws cloudformation update-stack \
    --stack-name dashboard-prod \
    --use-previous-template \
    --region us-east-1 \
    --capabilities CAPABILITY_NAMED_IAM \
    --outputs file://outputs.json || {
      echo "⚠️ Failed to update stack output, creating stack if it doesn't exist..."
      aws cloudformation create-stack \
        --stack-name dashboard-prod \
        --template-body file://template.yml \
        --region us-east-1 \
        --capabilities CAPABILITY_NAMED_IAM \
        --outputs file://outputs.json
    }
  rm -f outputs.json
  echo "✅ CloudFormation stack output updated or created."
else
  echo "⚠️ Skipping stack output update (DRY_RUN or REST_API_ID not set)."
fi

echo ""
echo "✅ Full deployment completed."