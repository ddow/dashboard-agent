#!/usr/bin/env bash
set -euo pipefail

# Override in env if you like
BUILD_DIR=${BUILD_DIR:-dashboard-app/backend/lambda-build}
# Set ZIP_FILE to be inside backend dir
ZIP_FILE=${ZIP_FILE:-dashboard-app/backend/dashboard-backend.zip}
DRY_RUN=${DRY_RUN:-false}
PACKAGE_ARCH=${PACKAGE_ARCH:-x86_64}  # Default to x86_64

: "${BUILD_DIR:?Need BUILD_DIR defined}"
: "${ZIP_FILE:?Need ZIP_FILE defined}"

echo "📦 Packaging Lambda function…"
echo "🧹 Cleaning old build directory & ZIP…"
rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

# Copy code & manifest to a staging directory first (outside Docker for initial setup)
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

if [ "$DRY_RUN" = "false" ]; then
  echo "🐳 Installing Python dependencies and creating ZIP inside Docker…"
  if [ "$PACKAGE_ARCH" = "arm64" ]; then
    DOCKER_FLAGS="--platform linux/arm64/v8"
  else
    DOCKER_FLAGS="--platform linux/amd64"
  fi
  # Use amazonlinux:2023 for Python and yum compatibility
  docker run --rm $DOCKER_FLAGS \
    --entrypoint /bin/bash \
    -v "$PWD/$BUILD_DIR":/var/task \
    "amazonlinux:2023" \
    -c "
      set -eux
      yum install -y zip
      curl -sSL https://bootstrap.pypa.io/get-pip.py | python3
      pip install --upgrade pip
      pip install --platform manylinux2014_x86_64 --only-binary=:all: --no-binary=:none: -r /var/task/requirements-lambda.txt -t /var/task
      cd /var/task
      zip -r /var/task/dashboard-backend.zip .
    "
  # Copy the ZIP back to the host
  cp "$BUILD_DIR/dashboard-backend.zip" "$ZIP_FILE"
else
  echo "⚠️ DRY_RUN: skipping dependency install and ZIP creation"
fi

echo "✅ Lambda package ready at $ZIP_FILE"
echo