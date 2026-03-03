plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

configurations.all {
    resolutionStrategy {
        // IMPORTANT: Need 1.15.0+ for setStylusHandwritingEnabled method required by Flutter
        force("androidx.core:core-ktx:1.15.0")
        force("androidx.core:core:1.15.0")
    }
}

android {
    namespace = "me.studyshare.android"
    compileSdk = 36
    val keystorePath = System.getenv("KEYSTORE_PATH")?.trim().orEmpty()
    val keystorePassword = System.getenv("KEYSTORE_PASSWORD")?.trim().orEmpty()
    val keyAlias = System.getenv("KEY_ALIAS")?.trim().orEmpty()
    val keyPassword = System.getenv("KEY_PASSWORD")?.trim().orEmpty()
    val hasReleaseSigning = keystorePath.isNotEmpty() &&
        keystorePassword.isNotEmpty() &&
        keyAlias.isNotEmpty() &&
        keyPassword.isNotEmpty()

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "me.studyshare.android"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        } else {
            logger.warn(
                "Release signing is not configured. Set KEYSTORE_PATH, " +
                    "KEYSTORE_PASSWORD, KEY_ALIAS, and KEY_PASSWORD to enable " +
                    "signed release builds."
            )
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.lifecycle(
                    "Release build will be unsigned because signing env vars are missing."
                )
            }
            // Enable ProGuard/R8 with comprehensive rules to prevent code stripping
            // This is CRITICAL for Supabase, Firebase, and JSON serialization to work in release builds
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    // IMPORTANT: 1.15.0 required for setStylusHandwritingEnabled method (Flutter TextInput on API 36)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation(platform("com.google.firebase:firebase-bom:32.7.4"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-messaging")
    // Required for OAuth/Google Sign-In on modern Android
    implementation("androidx.browser:browser:1.8.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Required for UCropActivity (Image Cropper)
    implementation("androidx.appcompat:appcompat:1.7.0")
}
