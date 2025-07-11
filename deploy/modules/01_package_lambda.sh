#!/bin/bash
# Default environment variables
BUILD_DIR=${BUILD_DIR:-dashboard-app/backend/lambda-build}
ZIP_FILE=${ZIP_FILE:-dashboard-app/backend/dashboard-backend.zip}
LAMBDA_NAME=${LAMBDA_NAME:-dashboard-backend}
ROLE_NAME=${ROLE_NAME:-DashboardLambdaRole}
POLICY_ARN=${POLICY_ARN:-arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess}
API_NAME=${API_NAME:-dashboard-api}

set -euo pipefail

# Allow skipping AWS calls when DRY_RUN=true
DRY_RUN=${DRY_RUN:-false}

# Fail if we don’t know where to build or where to write the ZIP
: "${BUILD_DIR:?Need BUILD_DIR defined}"
: "${ZIP_FILE:?Need ZIP_FILE defined}"

echo "📦 Step 1: Packaging Lambda function..."
echo "🧹 Cleaning old build directory…"

rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

if [ "$DRY_RUN" = "false" ]; then
  echo "🐳 Installing Python dependencies using Docker…"
  docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
    set -eux
    /var/lang/bin/python3.12 -m pip install --upgrade pip
    /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
  "

  echo "📦 Creating deployment package…"
  cd "$BUILD_DIR"
  zip -r ../../backend/dashboard-backend.zip . > /dev/null
  cd -
  echo "✅ Lambda package ready: $ZIP_FILE"
else
  echo "⚠️ DRY_RUN: Skipping dependency install & ZIP creation"
fi
