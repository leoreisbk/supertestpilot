#! /bin/bash

set +o xtrace

TASK=$1

# Replace Xcode path and create .def files
export XCODE_PATH="$(xcode-select -p)"
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