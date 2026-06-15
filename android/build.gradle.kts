allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker v11+ and similar plugins detect AGP 9 and skip applying the
// Kotlin Android plugin, expecting android.builtInKotlin=true. We keep
// builtInKotlin=false to avoid a Windows cross-drive path-relativization
// bug (pub cache on C:, project on D:). This hook applies the plugin for
// any library module that missed it.
subprojects {
    plugins.withId("com.android.library") {
        if (!plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            apply(plugin = "org.jetbrains.kotlin.android")
            // Match the Kotlin JVM target to the Java target (17) used by these plugins.
            the<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>()
                .compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
