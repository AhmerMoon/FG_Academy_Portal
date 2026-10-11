
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.academy_portal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.academy_portal"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = file("fgacademy-release.jks")

            storePassword =
                System.getenv("ANDROID_KEYSTORE_PASSWORD")

            keyAlias = "fgacademy"

            // IMPORTANT:
            // GitHub may supply an empty ANDROID_KEY_PASSWORD.
            // If empty, use the keystore password instead.
            keyPassword =
                System.getenv("ANDROID_KEY_PASSWORD")
                    ?.takeIf { it.isNotBlank() }
                    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
