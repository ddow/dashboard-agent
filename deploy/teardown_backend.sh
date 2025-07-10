#!/bin/bash
set -euo pipefail

DRY_RUN=${DRY_RUN:-false}

LAMBDA_NAME="dashboard-backend"
API_NAME="dashboard-api"
ROLE_NAME="DashboardLambdaRole"
BUCKET_NAME="danieldow-dashboard-assets"
BUILD_DIR="$(pwd)/dashboard-app/backend/lambda-build"

echo "🔥 Starting teardown..."

if [ "$DRY_RUN" = "true" ]; then
  echo "🧪 DRY_RUN enabled — no AWS resources will be deleted."
fi

# --------------------------------------------
# Stop local Docker container if running
echo "🧼 Cleaning up local Docker container..."
docker rm -f local-fastapi >/dev/null 2>&1 || echo "(no container to stop)"

# --------------------------------------------
# Delete local build dir
if [ -d "$BUILD_DIR" ]; then
  echo "🗑 Removing local Lambda build directory: $BUILD_DIR"
  rm -rf "$BUILD_DIR"
else
  echo "(no local build dir to remove)"
fi

if [ "$DRY_RUN" = "true" ]; then
  echo "✅ Local cleanup complete (DRY_RUN). Skipping AWS teardown."
  exit 0
fi

# --------------------------------------------
# Delete Lambda function
if aws lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  echo "🗑 Deleting Lambda function: $LAMBDA_NAME"
  aws lambda delete-function --function-name "$LAMBDA_NAME"
else
  echo "ℹ️ Lambda function not found: $LAMBDA_NAME"
fi

# --------------------------------------------
# Delete API Gateway
REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
if [ -n "$REST_API_ID" ]; then
  echo "🗑 Deleting API Gateway: $API_NAME ($REST_API_ID)"
  aws apigateway delete-rest-api --rest-api-id "$REST_API_ID"
else
  echo "ℹ️ API Gateway not found: $API_NAME"
fi

# --------------------------------------------
# Detach policy and delete IAM role
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "🔓 Detaching policy from IAM role..."
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" || true

  echo "🗑 Deleting IAM role: $ROLE_NAME"
  aws iam delete-role --role-name "$ROLE_NAME"
else
  echo "ℹ️ IAM role not found: $ROLE_NAME"
fi

# --------------------------------------------
# Delete S3 bucket and contents
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "🗑 Deleting all contents from S3 bucket: $BUCKET_NAME"
  aws s3 rm "s3://$BUCKET_NAME" --recursive || true

  echo "🪣 Deleting S3 bucket: $BUCKET_NAME"
  aws s3api delete-bucket --bucket "$BUCKET_NAME"
else
  echo "ℹ️ S3 bucket not found: $BUCKET_NAME"
fi

echo "✅ Teardown complete."
