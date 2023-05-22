Building for Development
===

TestPilot is a Kotlin Multiplatform project available for iOS and Android. The bulk of the framework is identical for both platforms, however there are some helper files that provide some syntax sugar and remove some of the KMM quirks for a more native feel.

To build TestPilot, either for development and modifications or for using on your own tests, you will need the following.

## Requirements

To build the TestPilot framework for Android and iOS, you'll need:

- Android Studio (JDK 11+)

### Building for Apple platforms

If you want to build TestPilot for using on Apple platforms, you'll also need:

- Xcode 14+

# Building the frameworks

iOS and Android have different requirements and instructions for installing the framework as a dependency to be used for your tests.

In either case, since TestPilot is being installed as a compiled framework, any changes applied to TestPilot need to be recompiled in order for you tests to access and use those tests

## Building for Android

First build the TestPilot framework: navigate to the `sdk/` folder and run the gradle tasks directly:
```bash
$ ./gradlew testpilot:assemble{Debug|Release}
```

### Installing TestPilot as a local dependency on Android Studio

Include the following on your `app/build.gradle` dependencies block:

```
dependencies {
    def ktorVersion = "2.2.4"
    def napierVersion = "2.6.1"
    implementation files("${path_to_testpilot}/sdk/testPilot/build/outputs/aar/testPilot-debug.aar")
    implementation "com.aallam.openai:openai-client:3.1.1"
    implementation "org.jetbrains.kotlinx:kotlinx-serialization-json:1.4.1"
    implementation "io.ktor:ktor-client-core:$ktorVersion"
    implementation "io.ktor:ktor-client-websockets:$ktorVersion"
    implementation "io.ktor:ktor-client-cio:$ktorVersion"
    implementation "io.github.aakira:napier:$napierVersion"
    androidTestImplementation "androidx.test.uiautomator:uiautomator:2.2.0"
    androidTestImplementation "org.jetbrains.kotlin:kotlin-test"
```

> Note that `${path_to_testpilot}` must be the absolute path to the TestPilot repository's root folder on your development machine

This should allow you to import the `co.work.testpilot` package on your test files.

## Building for iOS

The preferred way of building for iOS is by running the script on `scripts/build_ios_sdk.sh`. This script populates some .def files required by KMM with the path for your primary Xcode install, reading that by running `xcode-select --print-path`

```
$ scripts/build_ios_sdk.sh
```

> xcode-select may require you to provide elevated privileges and request your macOS user password

### Installing TestPilot as a local dependency on Xcode

1. From Finder, drag the TestPilot repository folder (the one containing the Package.swift file) to your project inside Xcode, as if you were adding a file. Xcode should display the Swift Package instead of a folder.
2. Next, on Xcode, tap on your project from the Explore panel.
3. Then select the test target(s) where you want to import TestPilot.
4. Navigate to the Build Phases tab for that Target.
5. Expand the Link Binary With Libraries section and tap the + button.
6. Select TestPilotKit from the Workspaces -> TestPilot section.

You should now be able to import TestPilotKit and TestPilotShared frameworks on your test files.