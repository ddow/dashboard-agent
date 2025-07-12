#!/bin/bash
set -euo pipefail

echo "🧪 Starting local Lambda container to test /login via RIE…"

# 1) Package your lambda into dashboard-backend.zip
BUILD_DIR="dashboard-app/backend/lambda-build"
ZIP_FILE="dashboard-app/backend/dashboard-backend.zip"

echo "📦 Step 1: Packaging Lambda function..."
rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

echo "🐳 Installing Python dependencies using Docker..."
docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
  set -eux
  cd /var/task
  /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
"

echo "📦 Creating deployment package..."
cd "$BUILD_DIR"
zip -r ../../dashboard-backend.zip . > /dev/null
cd -

# 2) Build the RIE‐based image using the correct Dockerfile path
echo "🐳 Building local Docker image for Lambda…"
docker build \
  -t local-lambda \
  -f dashboard-app/backend/Dockerfile \
  dashboard-app/backend

# 3) Tear down any old container
docker rm -f lambda-local >/dev/null 2>&1 || true

# 4) Start your RIE container pointing at the handler
echo "🚀 Starting local Lambda container under RIE (DRY_RUN=$DRY_RUN)…"
docker run --rm -d -p 9000:8080 --name lambda-local \
  -e DRY_RUN=true \
  local-lambda main.handler

echo "⏳ Waiting a couple seconds for RIE to spin up…"
sleep 2

# 5) Invoke /login
echo "📡 Invoking POST /login via RIE…"
curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
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
  }'

echo ""
echo "🧼 Cleaning up..."
docker stop lambda-local >/dev/null 2>&1 || true
