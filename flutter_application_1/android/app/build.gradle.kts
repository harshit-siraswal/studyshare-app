import java.util.Locale

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

configurations.all {
    resolutionStrategy {
        // Keep core libraries new enough for Flutter stylus handwriting and
        // UCrop's EdgeToEdge dependencies used during profile-photo editing.
        force("androidx.core:core-ktx:1.17.0")
        force("androidx.core:core:1.17.0")
    }
}

android {
    namespace = "me.studyshare.android"
    compileSdk = 36
    val disableMinify =
        project.findProperty("disableMinify")
            ?.toString()
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.toBooleanStrictOrNull() != false
    val enableLocalRelease =
        project.findProperty("enableLocalRelease")
            ?.toString()
            ?.trim()
            ?.lowercase(Locale.ROOT)
            ?.toBooleanStrictOrNull() == true
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
        ndk {
            // Keep distributed APK ABIs aligned with Flutter engine binaries.
            // This prevents packaging x86/x64-only plugin libs without matching
            // libflutter/libapp artifacts, which can cause launch-time crashes.
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
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
                    "Release signing env vars are missing. Falling back to debug signing for installable local release build."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
            // TODO(https://github.com/harshit-siraswal/studyshare-app/issues/230):
            // Remove the local minification override once local constrained builds are stable.
            // Keep release optimized by default.
            isMinifyEnabled = !disableMinify
            isShrinkResources = !disableMinify
            if (disableMinify) {
                logger.lifecycle(
                    "Minification disabled via -PdisableMinify=true for local troubleshooting."
                )
            }
        }

        if (enableLocalRelease) {
            create("localRelease") {
                initWith(getByName("release"))
                matchingFallbacks += listOf("release")
                isMinifyEnabled = false
                isShrinkResources = false
            }
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        jniLibs {
            // Drop desktop/emulator ABIs from transitive Android AARs so APK
            // does not advertise unsupported x86/x86_64 native stacks.
            excludes += setOf("**/x86/*.so", "**/x86_64/*.so")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // IMPORTANT: 1.15.0 required for setStylusHandwritingEnabled method (Flutter TextInput on API 36)
    implementation("androidx.core:core-ktx:1.17.0")
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
