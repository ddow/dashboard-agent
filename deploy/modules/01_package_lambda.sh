#!/usr/bin/env bash
set -euo pipefail

# Override in env if you like
BUILD_DIR=${BUILD_DIR:-dashboard-app/backend/lambda-build}
# Set ZIP_FILE to be inside backend dir
ZIP_FILE=${ZIP_FILE:-dashboard-app/backend/dashboard-backend.zip}
DRY_RUN=${DRY_RUN:-false}
PACKAGE_ARCH=${PACKAGE_ARCH:-x86_64}  # Default to x86_64 for compatibility

: "${BUILD_DIR:?Need BUILD_DIR defined}"
: "${ZIP_FILE:?Need ZIP_FILE defined}"

echo "📦 Packaging Lambda function…"
echo "🧹 Cleaning old build directory & ZIP…"
rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

# Copy code & manifest
cp dashboard-app/backend/*.py "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public "$BUILD_DIR/"

if [ "$DRY_RUN" = "false" ]; then
  echo "🐳 Installing Python dependencies…"
  SAM_IMAGE="public.ecr.aws/sam/build-python3.12"
  if [ "$PACKAGE_ARCH" = "arm64" ]; then
    DOCKER_FLAGS="--platform linux/arm64/v8"
  else
    DOCKER_FLAGS="--platform linux/amd64"  # Added for x86_64 compatibility
  fi
  docker run --rm $DOCKER_FLAGS \
    -v "$PWD/$BUILD_DIR":/var/task \
    "$SAM_IMAGE" \
    /bin/bash -c "
      set -eux
      /var/lang/bin/python3.12 -m pip install --upgrade pip
      /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
    "
else
  echo "⚠️ DRY_RUN: skipping dependency install"
fi

echo "📦 Creating deployment package…"
# Ensure the parent directory exists (handled by mkdir -p above)
pushd "$BUILD_DIR" >/dev/null
zip -r "$OLDPWD/$ZIP_FILE" . >/dev/null
popd >/dev/null

echo "✅ Lambda package ready at $ZIP_FILE"
echo