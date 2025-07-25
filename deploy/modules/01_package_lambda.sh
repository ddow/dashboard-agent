#!/usr/bin/env bash
set -euo pipefail

# Override in env if you like
BUILD_DIR=${BUILD_DIR:-dashboard-app/backend/lambda-build}
# <-- changed default to one level up
ZIP_FILE=${ZIP_FILE:-dashboard-app/dashboard-backend.zip}
DRY_RUN=${DRY_RUN:-false}

: "${BUILD_DIR:?Need BUILD_DIR defined}"
: "${ZIP_FILE:?Need ZIP_FILE defined}"

echo "📦 Packaging Lambda function…"
echo "🧹 Cleaning old build directory & ZIP…"
rm -rf "$BUILD_DIR" "$ZIP_FILE" || true
mkdir -p "$BUILD_DIR"

# Copy code & manifest
cp dashboard-app/backend/*.py               "$BUILD_DIR/"
cp dashboard-app/backend/requirements-lambda.txt "$BUILD_DIR/"
cp -r dashboard-app/backend/public          "$BUILD_DIR/"

if [ "$DRY_RUN" = "false" ]; then
  echo "🐳 Installing Python dependencies…"
  docker run --rm \
    -v "$PWD/$BUILD_DIR":/var/task \
    public.ecr.aws/sam/build-python3.12 \
    /bin/bash -c "
      set -eux
      /var/lang/bin/python3.12 -m pip install --upgrade pip
      /var/lang/bin/python3.12 -m pip install -r requirements-lambda.txt -t .
    "
else
  echo "⚠️ DRY_RUN: skipping dependency install"
fi

echo "📦 Creating deployment package…"
# ensure the parent directory exists
mkdir -p "$(dirname "$ZIP_FILE")"

# zip from inside BUILD_DIR but write to the corrected path
pushd "$BUILD_DIR" >/dev/null
zip -r "$OLDPWD/$ZIP_FILE" . >/dev/null
popd >/dev/null

echo "✅ Lambda package ready at $ZIP_FILE"
echo
