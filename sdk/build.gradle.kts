plugins {
    //trick: for the same plugin versions in all sub-modules
    id("com.android.library").version("8.3.2").apply(false)
    kotlin("multiplatform").version("2.1.20").apply(false)
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
