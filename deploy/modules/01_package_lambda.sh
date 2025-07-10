#!/bin/bash
set -euo pipefail

echo "📦 Step 1: Packaging Lambda function..."
echo "🧹 Cleaning old build directory..."

rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

echo "🐳 Installing Python dependencies using Docker..."
docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
  set -eux
  /var/lang/bin/python3.12 -m pip install --upgrade pip
  /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
"

echo "📦 Creating deployment package..."
cd "$BUILD_DIR"
zip -r ../../backend/dashboard-backend.zip . > /dev/null
cd -
echo "✅ Lambda package ready: $ZIP_FILE"
