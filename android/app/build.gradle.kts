plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // This correctly applies the plugin
}

android {
    namespace = "com.wan.taskbuddy.taskbuddy_testing01"
    compileSdk = flutter.compileSdkVersion // Usually an Int, e.g., 34
    ndkVersion = "27.0.12077973" // Ensure this NDK version is installed via SDK Manager

    compileOptions {
        // MODIFIED: Upgrading to Java 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // MODIFIED: Aligning Kotlin's JVM target with Java 17
        jvmTarget = JavaVersion.VERSION_17.toString() // "17"

        // ADDED: Explicitly set the JVM toolchain for Kotlin tasks
        // This helps ensure Kotlin compilation uses the specified JDK version.
        // Make sure you have a JDK 17 installed and accessible to Android Studio/Gradle.
        // If you are using the embedded JDK from Android Studio and it's JDK 17+, this should work fine.
        // You might need to install JDK 17 via SDK Manager (Tools > SDK Manager > SDK Tools > NDK (Side by side) - JDK is often listed there or managed by AS)
        // or ensure your AS embedded JBR is JDK 17.
        // toolchainVersion.set(JavaLanguageVersion.of(17)) // Alternative if jvmToolchain not available directly
    }

    defaultConfig {
        applicationId = "com.wan.taskbuddy.taskbuddy_testing01"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion // Usually an Int, e.g., 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner" // Good practice to have for tests
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // isMinifyEnabled = false // Keep false for debug, true for release with ProGuard/R8
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        // It's good practice to also have a debug buildType defined, even if it's mostly default
        debug {
            // Debug specific settings if any
        }
    }

    // ADDED: Packaging options, can sometimes help with duplicate file issues from dependencies.
    // Not directly related to Java 8 warnings but good to have.
    packagingOptions {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/gradle/incremental.annotation.processors"
        }
    }

    // ADDED: Lint options to provide more details on warnings if needed,
    // and potentially to turn off specific checks if they are too noisy and accepted.
    // lint {
    //    checkReleaseBuilds = true
    //    abortOnError = false // Set to true for CI builds
    //    // To get more details on deprecation from lint (different from JavaC -Xlint:deprecation)
    //    enable += "Deprecated"
    // }
}

// Ensure flutter block is correctly configured
flutter {
    source = "../.." // This path should point to the root of your Flutter project
}

dependencies {
    // Flutter adds its own dependencies.
    // You would add any app-specific native Android dependencies here, for example:
    // implementation("androidx.core:core-ktx:1.12.0")
    // implementation("androidx.appcompat:appcompat:1.6.1")
    // implementation(platform("com.google.firebase:firebase-bom:33.0.0")) // Example for Firebase
    // implementation("com.google.firebase:firebase-auth")
}

