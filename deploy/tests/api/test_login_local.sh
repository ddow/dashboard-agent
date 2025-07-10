#!/bin/bash
set -euo pipefail

echo "🧪 Starting local FastAPI container to test /login..."

BUILD_DIR="dashboard-app/backend/lambda-build"

# Rebuild in Docker
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

echo "🐳 Building dependencies..."
docker run --rm -v "$PWD/$BUILD_DIR":/var/task public.ecr.aws/sam/build-python3.12 /bin/bash -c "
  set -eux
  cd /var/task
  pip install -r requirements-lambda.txt -t .
"

# Kill any leftover container from a previous test
docker rm -f local-fastapi >/dev/null 2>&1 || true

echo "🚀 Starting uvicorn locally on port 8000..."
docker run --rm -d -v "$PWD/$BUILD_DIR":/app -p 8000:8000 --name local-fastapi \
  public.ecr.aws/sam/build-python3.12 \
  /bin/bash -c "
    cd /app
    pip install 'uvicorn[standard]'
    uvicorn main:app --host 0.0.0.0 --port 8000
"

echo "⏳ Waiting for server to start..."
sleep 3

echo "📡 Sending /login request to local Docker server..."
curl -X POST http://localhost:8000/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=strngr12@gmail.com&password=Passw0rd\!"

echo ""
echo "🧼 Cleaning up..."
docker stop local-fastapi >/dev/null
