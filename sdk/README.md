# TestPilot SDK

This is a Kotlin Multiplatform implementation of TestPilotKit. 

## Building

The shared KMM module can be built with the following Gradle command:

```sh
./gradlew testpilot:assembleTestPilotSharedXCFramework
```

The above command will build all configurations, including Debug and Release. This might take a while, so in order to speed up development, you can build specifically the Debug framework:

```sh
./gradlew testpilot:assembleTestPilotSharedDebugXCFramework
```

## Swift API

Because KMM doesn't currently support Swift modules and outputs an Objective-C framework, a standalone Swift-friendly API is provided under the `swift-wrapper` directory. 

You need to have successfully built the KMM module at least once before you can build the Swift API project, as the `Package.swift` file requires the XCFramework to exist in the build output directory.

Building the Swift API triggers a pre-build script to build the KMM module, so once you have built the KMM module, you don't have to manually rebuild it if you update Swift code.
