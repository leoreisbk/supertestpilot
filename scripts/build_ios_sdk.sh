#! /bin/bash

set +o xtrace

TASK=$1

# Replace Xcode path and create .def files
export XCODE_PATH="$(xcode-select -p)"
export IPHONEOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONESIMULATOR_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
export XCTEST_STUB_HEADER="$(pwd)/sdk/testpilot/src/iosMain/xctest_stub.h"

declare -a FILES=("xctest_iosArm64" "xctest_iosSimulatorArm64" "xctest_iosX64")

IFS=
for FILE in ${FILES[@]}; do
  full_path="sdk/testpilot/src/iosMain/$FILE"

  temp=$(cat $full_path.templ | envsubst)
  echo "$temp" > $full_path.def
done

# Build iOS SDK
cd sdk
./gradlew ${TASK:-testpilot:assembleTestPilotSharedDebugXCFramework}

# Deploy built artifacts to ~/.testpilot/ so harness can find them
CACHE_DIR="$HOME/.testpilot"
mkdir -p "$CACHE_DIR/ios" "$CACHE_DIR/harness"

FRAMEWORK_SRC="$(pwd)/testpilot/build/XCFrameworks/debug/TestPilotShared.xcframework"
rm -rf "$CACHE_DIR/ios/TestPilotShared.xcframework"
cp -R "$FRAMEWORK_SRC" "$CACHE_DIR/ios/TestPilotShared.xcframework"

rsync -a --exclude="AnalystTests/AnalystTests.swift" \
    "$(cd .. && pwd)/harness/" "$CACHE_DIR/harness/"

echo "Artifacts deployed to $CACHE_DIR"
