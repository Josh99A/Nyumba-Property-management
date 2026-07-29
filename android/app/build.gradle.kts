import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material is supplied by an untracked android/key.properties.
// Absent it, release builds fall back to the debug key so `flutter run
// --release` still works locally; such builds are not publishable.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseSigning) FileInputStream(keystorePropertiesFile).use { load(it) }
}

// The Android Maps SDK reads its key from the manifest, so it cannot come from
// a --dart-define. Supplied by an untracked android/maps.properties containing
// `mapsApiKey=...`, restricted in Google Cloud to this package name and the
// signing SHA-1. Absent it the placeholder resolves empty: the app still builds
// and every map surface falls back through NyumbaMaps.isConfigured rather than
// rendering a grey tile.
val mapsPropertiesFile = rootProject.file("maps.properties")
val mapsProperties = Properties().apply {
    if (mapsPropertiesFile.exists()) FileInputStream(mapsPropertiesFile).use { load(it) }
}

android {
    namespace = "com.nyumba.nyumba_property_management"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nyumba.nyumba_property_management"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] =
            mapsProperties.getProperty("mapsApiKey") ?: ""
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
