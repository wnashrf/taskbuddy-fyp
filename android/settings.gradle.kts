pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        // Ensure local.properties exists and is readable.
        // Adding a check for file existence before trying to read it.
        val localPropertiesFile = file("local.properties")
        if (!localPropertiesFile.exists()) {
            throw GradleException("local.properties file not found. Ensure it exists and flutter.sdk is set.")
        }
        localPropertiesFile.inputStream().use { properties.load(it) }
        val flutterSdkPathValue = properties.getProperty("flutter.sdk")
        require(flutterSdkPathValue != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPathValue
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // TODO: Ensure this Android Gradle Plugin version "8.7.3" is what you intend to use.
    // It's a very new version. If you encounter issues, you might need to align it
    // with versions known to be stable with your Flutter version (e.g., 8.2.0, 7.4.2).
    id("com.android.application") version "8.7.3" apply false

    // START: FlutterFire Configuration
    // MODIFIED: Aligning this version with your project-level build.gradle.kts target.
    // Ensure "4.4.2" is the version you have in android/build.gradle.kts
    id("com.google.gms.google-services") version "4.4.2" apply false
    // END: FlutterFire Configuration

    // TODO: Ensure this Kotlin version "2.1.0" is compatible with your AGP and other dependencies.
    // It's also very new. Common stable versions are often in the 1.8.x or 1.9.x range.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

// This is correct and crucial. It tells Gradle that the 'app' directory
// is a module in this build.
include(":app")

// It's good practice to define the root project name, though not strictly required
// if it defaults correctly.
// rootProject.name = "YourAndroidProjectName" // e.g., "TaskBuddyAndroid"
