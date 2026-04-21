#!/bin/bash
set -euo pipefail

# Build CLiteRTLM.xcframework from Google's LiteRT-LM source.
#
# Prerequisites:
#   - Bazel 7.6.1+ (https://bazel.build)
#   - Xcode 16+ with command line tools
#   - ~10 GB disk space for build artifacts
#
# Usage:
#   ./scripts/build-xcframework.sh [--repo-path /path/to/LiteRT-LM]
#
# If --repo-path is not specified, clones the official repo to a temp directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"
FRAMEWORK_NAME="LiteRTLM"

REPO_URL="https://github.com/google-ai-edge/LiteRT-LM.git"
REPO_PATH=""

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo-path) REPO_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=== LiteRTLM XCFramework Builder ==="
echo ""

# Check prerequisites
command -v bazel >/dev/null 2>&1 || { echo "Error: Bazel not found. Install from https://bazel.build"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: Xcode not found."; exit 1; }

BAZEL_VERSION=$(bazel version 2>/dev/null | head -1 | awk '{print $NF}')
echo "Bazel version: $BAZEL_VERSION"
echo "Xcode: $(xcodebuild -version | head -1)"
echo ""

# Clone or use existing repo
if [ -z "$REPO_PATH" ]; then
    REPO_PATH=$(mktemp -d)/LiteRT-LM
    echo "Cloning LiteRT-LM to $REPO_PATH ..."
    git clone --depth 1 "$REPO_URL" "$REPO_PATH"
fi

echo "Using LiteRT-LM source at: $REPO_PATH"
cd "$REPO_PATH"

# Build for iOS device (arm64)
echo ""
echo "=== Building for iOS device (arm64) ==="
bazel build //litert_lm/c_api:litert_lm_engine \
    --config=ios_arm64 \
    --compilation_mode=opt \
    --copt=-O3

# Build for iOS simulator (arm64)
echo ""
echo "=== Building for iOS simulator (arm64) ==="
bazel build //litert_lm/c_api:litert_lm_engine \
    --config=ios_sim_arm64 \
    --compilation_mode=opt \
    --copt=-O3

# Build for macOS (arm64)
echo ""
echo "=== Building for macOS (arm64) ==="
bazel build //litert_lm/c_api:litert_lm_engine \
    --config=macos_arm64 \
    --compilation_mode=opt \
    --copt=-O3

echo ""
echo "=== Packaging XCFramework ==="

# Create staging directories
STAGING=$(mktemp -d)
IOS_FW="$STAGING/ios-arm64/CLiteRTLM.framework"
SIM_FW="$STAGING/ios-arm64-simulator/CLiteRTLM.framework"
MAC_FW="$STAGING/macos-arm64/CLiteRTLM.framework"

for FW in "$IOS_FW" "$SIM_FW" "$MAC_FW"; do
    mkdir -p "$FW/Headers" "$FW/Modules"
done

# Copy headers
HEADER_SRC="$REPO_PATH/litert_lm/c_api"
for FW in "$IOS_FW" "$SIM_FW" "$MAC_FW"; do
    cp "$HEADER_SRC/engine.h" "$FW/Headers/"
    cp "$HEADER_SRC/litert_lm_logging.h" "$FW/Headers/" 2>/dev/null || true

    # Create module map
    cat > "$FW/Modules/module.modulemap" << 'MODULEMAP'
framework module CLiteRTLM {
    header "engine.h"
    export *
}
MODULEMAP

    # Create Info.plist
    cat > "$FW/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CLiteRTLM</string>
    <key>CFBundleIdentifier</key>
    <string>com.google.litert-lm</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
</dict>
</plist>
PLIST
done

# Copy binaries from Bazel output
# NOTE: Actual paths depend on Bazel output structure — adjust as needed
BAZEL_OUT="$REPO_PATH/bazel-out"

echo "Copying binaries..."
# These paths are approximate — adjust based on actual Bazel output
find "$BAZEL_OUT" -name "*.dylib" -path "*ios_arm64*" -exec cp {} "$IOS_FW/CLiteRTLM" \; 2>/dev/null || true
find "$BAZEL_OUT" -name "*.dylib" -path "*ios_sim*" -exec cp {} "$SIM_FW/CLiteRTLM" \; 2>/dev/null || true
find "$BAZEL_OUT" -name "*.dylib" -path "*macos*" -exec cp {} "$MAC_FW/CLiteRTLM" \; 2>/dev/null || true

# Create XCFramework
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

xcodebuild -create-xcframework \
    -framework "$IOS_FW" \
    -framework "$SIM_FW" \
    -framework "$MAC_FW" \
    -output "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

echo ""
echo "=== Done ==="
echo "XCFramework created at: $OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
echo ""
echo "Slices:"
ls -d "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"/*/
