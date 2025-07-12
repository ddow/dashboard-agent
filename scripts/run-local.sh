#!/usr/bin/env bash
set -euo pipefail

# 1) Repackage
bash deploy/modules/01_package_lambda.sh

# 2) Rebuild the image
docker build \
  -f dashboard-app/backend/Dockerfile \
  -t local-lambda .

# 3) Tear down old
docker rm -f lambda-local 2>/dev/null || true

# 4) Run new in DRY_RUN
docker run --rm -d \
  -e DRY_RUN=true \
  -p 9000:8080 \
  --name lambda-local \
  local-lambda \
  main.handler

echo "✅ local-lambda is up on http://localhost:9000 (DRY_RUN)"

# 5) Smoke-test /login with full event payload
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
echo "If you see a JSON with an access_token, you’re good to go!"
