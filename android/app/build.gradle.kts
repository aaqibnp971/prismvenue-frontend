import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, kept out of the repo. `android/key.properties` and
// the keystore itself are both gitignored — see android/.gitignore. Without
// this file the release build falls back to the debug key below, which still
// lets `flutter run --release` work but produces a bundle Play will reject.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.r13.prismvenues"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.r13.prismvenues"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        //
        // 26, not Flutter's default: miniaudio drives Android through AAudio,
        // which is API 26+. The sound engine is not optional in this app, so a
        // lower floor would ship devices that install and then cannot play.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // 64-bit first (Play requires it); armeabi-v7a keeps older handsets
            // working, x86_64 keeps emulators usable.
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }

        // Cross-compiles libprism_core.so straight out of the prism-core repo's
        // own CMake tree — the same build its desktop suite verifies, no copied
        // sources and nothing vendored in here. Without this the Dart bindings
        // resolve fine and `DynamicLibrary.open('libprism_core.so')` then fails
        // at runtime, because nothing ever produced the library.
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DPRISM_BUILD_SHARED=ON",   // defaults OFF; this is what emits the .so
                    "-DPRISM_BUILD_TESTS=OFF",
                    "-DPRISM_BUILD_HARNESS=OFF",
                    "-DANDROID_PLATFORM=android-26",
                )
                targets += listOf("prism_core_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            // prismvenue-frontend/android/app → up three → the parent that holds
            // both repos, then prism-core. Nothing in prism-core is modified.
            path = file("../../../prism-core/CMakeLists.txt")
            // prism-core requires CMake >= 3.24; the SDK ships 3.22.1 by default.
            version = "3.31.6"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when key.properties is absent, so a
            // local `flutter run --release` still works. A debug-signed bundle
            // is rejected by Play — the build below prints which key was used.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Ships the native symbol table for libprism_core.so inside the
            // bundle. Without it Play accepts the upload but posts a standing
            // warning ("This App Bundle contains native code, and you've not
            // uploaded debug symbols"), and every engine crash arrives as raw
            // hex addresses instead of a stack. SYMBOL_TABLE rather than FULL:
            // it is what Play needs to symbolicate, at a fraction of the size.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
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
