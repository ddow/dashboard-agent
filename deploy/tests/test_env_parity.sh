#!/bin/bash
set -euo pipefail

# Ensure tests never hit AWS
export DRY_RUN=true

echo "🔍 Testing local Docker build environment against AWS Lambda baseline..."
echo "---------------------------------------------------------------"

EXPECTED_IMAGE="public.ecr.aws/sam/build-python3.12"
EXPECTED_ARCH="aarch64"
EXPECTED_SO_LIB="_pydantic_core"
BUILD_DIR="dashboard-app/backend/lambda-build"

# Step 1: Confirm Docker image is aarch64
echo "🐳 Verifying Docker base image architecture..."
IMAGE_ARCH=$(docker run --rm "$EXPECTED_IMAGE" uname -m)
if [[ "$IMAGE_ARCH" == "$EXPECTED_ARCH" ]]; then
  echo "✅ Docker architecture matches Lambda ($EXPECTED_ARCH)"
else
  echo "❌ Docker architecture mismatch. Found: $IMAGE_ARCH, expected: $EXPECTED_ARCH"
  exit 1
fi

# Step 2: Fresh build in Docker
echo "🛠 Building Lambda layer using Docker..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

docker run --rm -v "$PWD/$BUILD_DIR":/var/task "$EXPECTED_IMAGE" /bin/bash -c "
  set -eux
  cd /var/task
  rm -rf $EXPECTED_SO_LIB* __pycache__
  /var/lang/bin/python3.12 -m pip install --upgrade pip
  /var/lang/bin/python3.12 -m pip install --no-cache-dir -r requirements-lambda.txt -t .
"

# Step 3: Confirm shared object exists
echo "🔍 Verifying compiled shared object: ${EXPECTED_SO_LIB}.so"
SO_PATH=$(find "$BUILD_DIR" -name "*${EXPECTED_SO_LIB}*.so" | head -n 1)

if [[ -z "$SO_PATH" ]]; then
  echo "❌ Expected binary ${EXPECTED_SO_LIB}.so not found"
  exit 1
else
  echo "✅ Found binary: $SO_PATH"
fi

# Step 4: Confirm .so file is built for aarch64
echo "🧠 Verifying binary architecture..."
BIN_DESC=$(file "$SO_PATH")

if echo "$BIN_DESC" | grep -q "$EXPECTED_ARCH"; then
  echo "✅ Binary architecture matches ($EXPECTED_ARCH)"
else
  echo "❌ Binary architecture mismatch:"
  echo "$BIN_DESC"
  exit 1
fi

# Step 5: Confirm Python version matches Lambda
echo "🐍 Verifying Python version inside Docker..."
PYTHON_VERSION=$(docker run --rm "$EXPECTED_IMAGE" /var/lang/bin/python3.12 --version)
echo "🧪 Detected version: $PYTHON_VERSION"

if [[ "$PYTHON_VERSION" =~ Python\ 3\.12\.[0-9]+ ]]; then
  echo "✅ Python version is valid for AWS Lambda (3.12.x)"
else
  echo "❌ Python version mismatch: $PYTHON_VERSION"
  exit 1
fi

echo ""
echo "✅ Local Docker environment matches AWS Lambda runtime ✅"
