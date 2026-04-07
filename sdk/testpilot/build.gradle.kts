import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    kotlin("plugin.serialization") version "2.1.20"
    id("com.android.library")
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "1.8"
            }
        }
    }
    
    val xcf = XCFramework("TestPilotShared")
    listOf(
        iosX64(),
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach {
        val main by it.compilations.getting
        main.cinterops.create("xctest") {
            defFile("src/iosMain/xctest_${it.name}.def")
        }
        it.compilations.all {
            kotlinOptions {
                freeCompilerArgs += listOf(
                    "-opt-in=kotlinx.cinterop.ExperimentalForeignApi",
                    "-opt-in=kotlin.experimental.ExperimentalNativeApi",
                )
            }
        }

        it.binaries.framework {
            baseName = "TestPilotShared"
            xcf.add(this)
        }
    }

    sourceSets {
        val ktorVersion = "2.2.4"
        val napierVersion = "2.6.1"

        val commonMain by getting {
            dependencies {
                implementation("com.aallam.openai:openai-client:3.1.1")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
                implementation("io.ktor:ktor-client-core:$ktorVersion")
                implementation("io.ktor:ktor-client-websockets:$ktorVersion")
                implementation("io.ktor:ktor-client-cio:$ktorVersion")
                implementation("io.github.aakira:napier:$napierVersion")
                implementation(kotlin("test"))
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("io.ktor:ktor-client-okhttp:$ktorVersion")
                implementation("androidx.test.uiautomator:uiautomator:2.2.0")
                implementation("androidx.test:core-ktx:1.5.0")
            }
        }
        val iosX64Main by getting
        val iosArm64Main by getting
        val iosSimulatorArm64Main by getting
        val iosMain by creating {
            dependsOn(commonMain)
            iosX64Main.dependsOn(this)
            iosArm64Main.dependsOn(this)
            iosSimulatorArm64Main.dependsOn(this)
            dependencies {
                implementation("io.ktor:ktor-client-darwin:$ktorVersion")
            }
        }
    }
}

android {
    namespace = "co.work.testpilot"
    compileSdk = 33
    defaultConfig {
        minSdk = 29
        targetSdk = 33
    }
}