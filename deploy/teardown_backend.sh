#!/bin/bash
set -euo pipefail

echo "🔥 Starting full backend teardown..."

# Config
DRY_RUN=${DRY_RUN:-false}
DELETE_BUCKET=${DELETE_BUCKET:-false}

LAMBDA_NAME="dashboard-backend"
ROLE_NAME="DashboardLambdaRole"
API_NAME="dashboard-api"
BUCKET_NAME="danieldow-dashboard-assets"
DOCKER_CONTAINER="local-fastapi"
BUILD_DIR="dashboard-app/backend/lambda-build"
ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"

# 🧨 Lambda
echo "🧨 Checking Lambda function: $LAMBDA_NAME"
if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would delete Lambda function: $LAMBDA_NAME"
  else
    aws lambda delete-function --function-name "$LAMBDA_NAME"
    echo "✅ Deleted Lambda function"
  fi
else
  echo "ℹ️ Lambda function not found."
fi

# 🔐 IAM Role
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would detach and delete IAM role: $ROLE_NAME"
  else
    aws iam detach-role-policy --role-name "$ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess || true
    aws iam delete-role --role-name "$ROLE_NAME"
    echo "✅ Deleted IAM role"
  fi
else
  echo "ℹ️ IAM role not found."
fi

# 🌐 API Gateway
REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
if [ -n "$REST_API_ID" ] && [ "$REST_API_ID" != "None" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would delete API Gateway: $API_NAME ($REST_API_ID)"
  else
    aws apigateway delete-rest-api --rest-api-id "$REST_API_ID"
    echo "✅ Deleted API Gateway"
  fi
else
  echo "ℹ️ API Gateway not found."
fi

# 🪣 Optional S3 bucket
if [ "$DELETE_BUCKET" = "true" ]; then
  if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    if [ "$DRY_RUN" = "true" ]; then
      echo "🧪 DRY_RUN: Would delete S3 bucket: $BUCKET_NAME"
    else
      echo "🪣 Emptying and deleting S3 bucket..."
      aws s3 rm "s3://$BUCKET_NAME" --recursive || true
      aws s3api delete-bucket --bucket "$BUCKET_NAME"
      echo "✅ Deleted S3 bucket"
    fi
  else
    echo "ℹ️ S3 bucket not found."
  fi
fi

# 🐳 Docker cleanup
echo "🐳 Checking Docker container: $DOCKER_CONTAINER"
if docker ps -a --format '{{.Names}}' | grep -q "$DOCKER_CONTAINER"; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would stop Docker container: $DOCKER_CONTAINER"
  else
    docker rm -f "$DOCKER_CONTAINER" >/dev/null
    echo "✅ Removed Docker container: $DOCKER_CONTAINER"
  fi
else
  echo "ℹ️ Docker container not running."
fi

# 🧼 Local cleanup
echo "🧼 Cleaning local artifacts..."
if [ "$DRY_RUN" = "true" ]; then
  echo "🧪 DRY_RUN: Would remove: $BUILD_DIR and $ZIP_FILE"
else
  rm -rf "$BUILD_DIR" "$ZIP_FILE"
  echo "✅ Removed local build directory and zip"
fi

echo "✅ Full teardown complete."
