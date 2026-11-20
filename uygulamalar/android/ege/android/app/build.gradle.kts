plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures { resValues = true }
    namespace = "com.jarvis.assistant.jarvis_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jarvis.assistant.jarvis_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "ege_microsoft_client_id", providers.gradleProperty("egeMicrosoftClientId").orElse("").get())

        // JARVIS yalnız realme 10 (arm64) için derleniyor: whisper.cpp'yi tek
        // ABI için derle (derleme süresi ~3 kat kısalır).
        externalNativeBuild {
            cmake {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    // sherpa-onnx ve diğer eklentiler her ABI için .so getiriyor; telefon
    // arm64 olduğu için diğerlerini APK'ya koyma (~60 MB tasarruf).
    packaging {
        resources {
            merges += setOf("META-INF/LICENSE.md", "META-INF/NOTICE.md")
        }
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    // On-device Whisper (whisper.cpp). Built for every ABI Flutter packages;
    // the Kotlin side only enables it on arm64 (ARMv8.2 dotprod) and x86_64.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    implementation("com.microsoft.identity.client:msal:8.7.0")
    // Nimbus (via MSAL) references these optional crypto implementations.
    // Package the implementations so release R8 and runtime agree; do not
    // silence missing-class errors for authentication code.
    implementation("com.google.crypto.tink:tink-android:1.24.0")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.86")
}
