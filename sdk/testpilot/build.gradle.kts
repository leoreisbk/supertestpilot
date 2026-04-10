import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    kotlin("plugin.serialization") version "2.1.20"
    id("com.android.library")
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

kotlin {
    androidTarget {
        compilations.all {
            kotlinOptions {
                jvmTarget = "1.8"
            }
        }
    }

    jvm()

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
        val jvmMain by getting {
            dependencies {
                implementation("com.microsoft.playwright:playwright:1.44.0")
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

// ── Web runner tasks ──────────────────────────────────────────────────────────

fun jvmClasspath() = kotlin.jvm().compilations["main"].let { c ->
    c.output.allOutputs + c.runtimeDependencyFiles
}

tasks.register<JavaExec>("runWebRunner") {
    group = "application"
    description = "Run the web runner with env vars set by the testpilot CLI"
    dependsOn("jvmMainClasses")
    mainClass.set("co.work.testpilot.MainKt")
    classpath = jvmClasspath()
}

tasks.register<JavaExec>("installPlaywrightBrowsers") {
    group = "application"
    description = "Download Playwright Chromium browser (one-time setup)"
    dependsOn("jvmMainClasses")
    mainClass.set("com.microsoft.playwright.CLI")
    classpath = jvmClasspath()
    args = listOf("install", "chromium")
}

// ── Web fat-jar ───────────────────────────────────────────────────────────────

tasks.register<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    group = "build"
    description = "Produces a self-contained fat-jar for the web runner"
    archiveBaseName.set("testpilot-web")
    archiveClassifier.set("")
    archiveVersion.set("")
    isZip64 = true
    from(kotlin.jvm().compilations["main"].output.allOutputs)
    from(kotlin.jvm().compilations["main"].runtimeDependencyFiles)
    manifest {
        attributes["Main-Class"] = "co.work.testpilot.MainKt"
    }
    dependsOn("jvmMainClasses")
    mergeServiceFiles()
    // Playwright bundles its own driver — exclude duplicate signatures
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
}
