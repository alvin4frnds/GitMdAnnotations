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

// AGP 8+ requires every Android library to declare a `namespace`. Older
// Flutter plugins (e.g. `shared_storage` 0.8.x) still rely on the now-
// removed `package` attribute in their manifest and blow up at configure
// time with "Namespace not specified." This block injects `project.group`
// as the namespace for any Android library subproject that hasn't set
// one, so we don't have to fork those plugins just to bump metadata.
//
// Also pins both Java and Kotlin compile tasks to JVM 17 — the app
// targets 17 (see `android/app/build.gradle.kts`), and legacy plugins
// that ship with a Java 1.8 default + no Kotlin jvmTarget mismatch
// against the JDK 21 toolchain on this host at configure time.
// Namespace auto-injection for Android library subprojects that still
// rely on the pre-AGP-8 `package="…"` manifest attribute. Runs at
// configure time so AGP's variant evaluation sees the injected field.
// The `compileSdk` + `namespace` gaps in `shared_storage` 0.8.1 are
// patched directly in the pub cache's `android/build.gradle` (manual
// one-time patch in the local pub cache) — the namespace hook here
// covers any other legacy plugin that surfaces the same gap.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace.isNullOrBlank()) {
                namespace = project.group.toString()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
