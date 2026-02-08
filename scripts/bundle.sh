#!/bin/bash
# Build MasterUI and create a proper macOS .app bundle

set -e

APP_NAME="MasterUI"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building MasterUI..."
swift build -c debug

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp ".build/debug/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Create PkgInfo
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo ""
echo "=== Build Complete ==="
echo "App bundle: ${BUNDLE_DIR}"
echo ""
echo "To run:"
echo "  open ${BUNDLE_DIR}"
echo ""
echo "To grant Accessibility permission:"
echo "  1. Open System Settings > Privacy & Security > Accessibility"
echo "  2. Click '+' and add: $(pwd)/${BUNDLE_DIR}"
echo "  3. Or drag the app from Finder into the list"
echo ""
echo "For diagnostics (run from Terminal with accessibility access):"
echo "  ${MACOS_DIR}/${APP_NAME} --diagnose com.todesktop.230313mzl4w4u92"
