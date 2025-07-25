#!/usr/bin/env bash
set -euo pipefail

# Tear down old container if running
docker rm -f lambda-local 2>/dev/null || true

# Run new container in detached mode
docker run --rm -d \
  -e DRY_RUN=true \
  -e SECRET_KEY=abc123def456ghi789jkl012mno345 \
  -e DASHBOARD_USERS_TABLE=dashboard-users \
  -e AWS_REGION=us-east-1 \
  -p 9000:8080 \
  --name lambda-local \
  local-lambda

echo "✅ local-lambda is up on http://localhost:9000 (DRY_RUN)"

# Smoke-test /login with full event payload
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