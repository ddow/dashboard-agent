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
    # Detach all managed policies
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text)
    for POLICY in $POLICIES; do
      echo "Detaching policy $POLICY..."
      aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY" || {
        echo "⚠️ Failed to detach policy $POLICY, skipping..."
      }
    done
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[*]' --output text)
    for POLICY in $INLINE_POLICIES; do
      echo "Deleting inline policy $POLICY..."
      aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY" || {
        echo "⚠️ Failed to delete inline policy $POLICY, skipping..."
      }
    done
    # Delete the role with retry
    for i in {1..3}; do
      aws iam delete-role --role-name "$ROLE_NAME" && {
        echo "✅ Deleted IAM role"
        break
      } || {
        echo "⚠️ Attempt $i failed to delete role, retrying..."
        sleep 5
      }
    done
    if [ $i -eq 3 ]; then
      echo "❌ Failed to delete IAM role after 3 attempts."
      exit 1
    fi
  fi
else
  echo "ℹ️ IAM role not found."
fi

# 🌐 API Gateway
REST_API_IDS=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
if [ -n "$REST_API_IDS" ] && [ "$REST_API_IDS" != "None" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would delete API Gateway: $API_NAME ($REST_API_IDS)"
  else
    for REST_API_ID in $REST_API_IDS; do
      echo "Deleting API Gateway with ID: $REST_API_ID..."
      aws apigateway delete-rest-api --rest-api-id "$REST_API_ID" || {
        echo "⚠️ Failed to delete API Gateway $REST_API_ID, skipping..."
      }
      sleep 5  # Add sleep to avoid rate limits
    done
    echo "✅ Deleted API Gateway(s)"
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
if docker ps -a --format "{{.Names}}" | grep -q "$DOCKER_CONTAINER"; then
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