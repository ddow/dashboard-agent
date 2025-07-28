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

# Arrays to track API Gateway deletion results
declare -a deleted_api_ids
declare -a failed_api_ids

# 🧨 Lambda
echo "🧨 Checking Lambda function: $LAMBDA_NAME"
if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would delete Lambda function: $LAMBDA_NAME"
  else
    aws lambda delete-function --function-name "$LAMBDA_NAME" --region us-east-1
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
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text --region us-east-1)
    for POLICY in $POLICIES; do
      echo "Detaching policy $POLICY..."
      aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY" --region us-east-1 || {
        echo "⚠️ Failed to detach policy $POLICY, skipping..."
      }
    done
    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[*]' --output text --region us-east-1)
    for POLICY in $INLINE_POLICIES; do
      echo "Deleting inline policy $POLICY..."
      aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY" --region us-east-1 || {
        echo "⚠️ Failed to delete inline policy $POLICY, skipping..."
      }
    done
    # Delete the role with retry
    for i in {1..3}; do
      aws iam delete-role --role-name "$ROLE_NAME" --region us-east-1 && {
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
REST_API_IDS=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region us-east-1)
if [ -n "$REST_API_IDS" ] && [ "$REST_API_IDS" != "None" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY_RUN: Would delete API Gateway: $API_NAME ($REST_API_IDS)"
  else
    for REST_API_ID in $REST_API_IDS; do
      echo "Processing API Gateway with ID: $REST_API_ID..."
      # Debug: List all resources before deletion
      RESOURCES=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query "items[?path!='/'].id" --output text --region us-east-1)
      echo "Found resources for $REST_API_ID (excluding root): $RESOURCES"
      # Get all methods and integrations for each resource and delete them
      for RESOURCE in $RESOURCES; do
        METHODS=$(aws apigateway get-methods --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE" --query "items[*].httpMethod" --output text --region us-east-1 2>/dev/null || true)
        if [ -n "$METHODS" ]; then
          for METHOD in $METHODS; do
            echo "Deleting method $METHOD for resource $RESOURCE in API $REST_API_ID..."
            aws apigateway delete-method --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE" --http-method "$METHOD" --region us-east-1 || {
              echo "⚠️ Failed to delete method $METHOD for resource $RESOURCE, skipping..."
            }
            sleep 2
          done
        fi
        INTEGRATIONS=$(aws apigateway get-integrations --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE" --query "items[*].httpMethod" --output text --region us-east-1 2>/dev/null || true)
        if [ -n "$INTEGRATIONS" ]; then
          for INTEGRATION in $INTEGRATIONS; do
            echo "Deleting integration $INTEGRATION for resource $RESOURCE in API $REST_API_ID..."
            aws apigateway delete-integration --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE" --http-method "$INTEGRATION" --region us-east-1 || {
              echo "⚠️ Failed to delete integration $INTEGRATION for resource $RESOURCE, skipping..."
            }
            sleep 2
          done
        fi
      done
      # Get all stages and delete them
      STAGES=$(aws apigateway get-stages --rest-api-id "$REST_API_ID" --query "item[*].stageName" --output text --region us-east-1)
      for STAGE in $STAGES; do
        echo "Deleting stage $STAGE for API $REST_API_ID..."
        aws apigateway delete-stage --rest-api-id "$REST_API_ID" --stage-name "$STAGE" --region us-east-1 || {
          echo "⚠️ Failed to delete stage $STAGE, skipping..."
        }
        sleep 2
      done
      # Delete all non-root resources
      for RESOURCE in $RESOURCES; do
        echo "Deleting resource $RESOURCE for API $REST_API_ID..."
        aws apigateway delete-resource --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE" --region us-east-1 || {
          echo "⚠️ Failed to delete resource $RESOURCE, skipping..."
        }
        sleep 2
      done
      # Delete the REST API with Fibonacci backoff
      echo "Deleting API Gateway with ID: $REST_API_ID..."
      a=1
      b=1
      retries=10
      for (( attempt=1; attempt<=retries; attempt++ )); do
        if aws apigateway delete-rest-api --rest-api-id "$REST_API_ID" --region us-east-1; then
          deleted_api_ids+=("$REST_API_ID")
          echo "Deleted API Gateway with ID: $REST_API_ID"
          break
        else
          echo "Failed to delete $REST_API_ID on attempt $attempt. Retrying after $a seconds..."
          sleep $a
          temp=$b
          b=$((a + b))
          a=$temp
        fi
      done
      if [ $attempt -gt $retries ]; then
        failed_api_ids+=("$REST_API_ID")
        echo "⚠️ Failed to delete API Gateway $REST_API_ID after $retries attempts, skipping..."
      fi
    done
    echo "✅ Deleted API Gateway(s)"
    # Summary of deletion results
    total_failed=${#failed_api_ids[@]}
    echo "Total number of API Gateway resources that failed to delete: $total_failed"
    if [ $total_failed -gt 0 ]; then
      echo "Failed API Gateway IDs: ${failed_api_ids[*]}"
    fi
    echo "Successfully deleted API Gateway IDs: ${deleted_api_ids[*]}"
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
      a=1
      b=1
      retries=5
      for (( attempt=1; attempt<=retries; attempt++ )); do
        if aws s3 rm "s3://$BUCKET_NAME" --recursive --region us-east-1 && aws s3api delete-bucket --bucket "$BUCKET_NAME" --region us-east-1; then
          echo "✅ Deleted S3 bucket"
          break
        else
          echo "Failed to delete S3 bucket on attempt $attempt. Retrying after $a seconds..."
          sleep $a
          temp=$b
          b=$((a + b))
          a=$temp
        fi
      done
      if [ $attempt -gt $retries ]; then
        echo "⚠️ Failed to delete S3 bucket after $retries attempts."
      fi
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
  if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR" || {
      echo "⚠️ Failed to remove $BUILD_DIR, directory may be in use or permission denied. Skipping..."
    }
  fi
  if [ -f "$ZIP_FILE" ]; then
    rm -f "$ZIP_FILE" || {
      echo "⚠️ Failed to remove $ZIP_FILE, file may be in use or permission denied. Skipping..."
    }
  fi
  if [ ! -d "$BUILD_DIR" ] && [ ! -f "$ZIP_FILE" ]; then
    echo "✅ Removed local build directory and zip"
  else
    echo "⚠️ Partial cleanup: Some files/directories could not be removed."
  fi
fi

echo "✅ Full teardown complete."