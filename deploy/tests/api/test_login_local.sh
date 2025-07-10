#!/bin/bash
set -euo pipefail

echo "🧪 Starting local FastAPI container to test /login..."

BUILD_DIR="dashboard-app/backend/lambda-build"

# Rebuild local test environment
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

echo "🐳 Building dependencies..."
docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
  set -eux
  pip install -r requirements-lambda.txt -t .
"

# Kill any leftover container
docker rm -f local-fastapi >/dev/null 2>&1 || true

echo "🚀 Starting uvicorn locally on port 8000..."
docker run --rm -d \
  -v "$PWD/$BUILD_DIR":/app \
  -p 8000:8000 \
  --name local-fastapi \
  -e DRY_RUN=true \
  public.ecr.aws/sam/build-python3.12 \
  /bin/bash -c '
    set -eux
    cd /app
    pip install "uvicorn[standard]"
    export PYTHONPATH=/app
    uvicorn main:app --host 0.0.0.0 --port 8000 --log-level debug
  '

echo "⏳ Waiting 3s for FastAPI to initialize..."
sleep 3

echo "📡 Sending /login request with fake user..."
RESPONSE=$(curl -s -w "\nHTTP %{http_code}" -X POST http://localhost:8000/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=testuser@example.com&password=Passw0rd!")

echo ""
echo "🔎 Raw response:"
echo "$RESPONSE"

TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d':' -f2- | tr -d '"')
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP" | awk '{print $2}')

if [[ -n "$TOKEN" && "$HTTP_CODE" == "200" ]]; then
  echo -e "\n✅ Login test succeeded. Token:"
  echo "$TOKEN"
else
  echo -e "\n❌ Login failed or token not returned"
fi

echo ""
echo "🪵 Container logs:"
docker logs local-fastapi || echo "(no logs found)"

echo ""
echo "🧼 Cleaning up..."
docker stop local-fastapi >/dev/null
