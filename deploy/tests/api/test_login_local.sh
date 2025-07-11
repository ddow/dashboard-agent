#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Starting local Lambda container to test /login via RIE…"

#–– Config ––
BUILD_DIR="dashboard-app/backend/lambda-build"
IMAGE_NAME="local-lambda"
CONTAINER_NAME="lambda-local"

#–– 1) Rebuild local test environment ––
if [ -d "$BUILD_DIR" ]; then
  echo "🧹 Removing old build directory: $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi
echo "📁 Creating fresh build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "📄 Copying source files into build dir…"
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

#–– 2) Vendor dependencies ––
echo "🐳 Installing Python dependencies into $BUILD_DIR…"
docker run --rm \
  -v "$PWD/$BUILD_DIR":/var/task \
  public.ecr.aws/sam/build-python3.12 \
  /bin/bash -c "
    set -eux
    cd /var/task
    pip install -r requirements-lambda.txt -t .
  "

#–– 3) (Re)build your RIE image ––
echo "🖼️  (Re)building Docker image: $IMAGE_NAME"
docker build -f dashboard-app/backend/Dockerfile -t "$IMAGE_NAME" .

#–– 4) Tear down any previous container ––
echo "🗑️  Cleaning up old container (if any): $CONTAINER_NAME"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

#–– 5) Launch under RIE with DRY_RUN ––
echo "🚀 Starting RIE container ($CONTAINER_NAME)…"
docker run --rm -d \
  --name "$CONTAINER_NAME" \
  -p 9000:8080 \
  -e DRY_RUN=true \
  "$IMAGE_NAME" main.handler

echo "⏳ Waiting 3s for RIE to come up…"
sleep 3

#–– 6) Invoke it just like API Gateway ––
echo "📡 POST /login → expecting fake-DB token"
RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
  -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" \
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
  }')

echo ""
echo "🔎 Raw response:"
echo "$RESPONSE"

#–– 7) Tear down RIE container ––
echo ""
echo "🧼 Stopping RIE container…"
docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true

#–– 8) Assert we got a token ––
TOKEN=$(printf '%s' "$RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d':' -f2- | tr -d '"')
HTTP_CODE=$(printf '%s' "$RESPONSE" | awk '/HTTP /{print $2}')

if [[ "$HTTP_CODE" == "200" && -n "$TOKEN" ]]; then
  echo -e "\n✅ Success! Got token:\n$TOKEN"
  exit 0
else
  echo -e "\n❌ Failed (HTTP $HTTP_CODE)."
  exit 1
fi
