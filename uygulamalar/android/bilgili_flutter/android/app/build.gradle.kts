plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mehmetderin.bilgiarena"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mehmetderin.bilgiarena"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // BILGILI_IMZA_DOSYASI verilirse sürüm APK'sı bu sabit anahtarla imzalanır
    // (CI önbellekte saklar); böylece sürümler birbirinin üzerine kurulur.
    val imzaDosyasi = System.getenv("BILGILI_IMZA_DOSYASI")
    signingConfigs {
        if (imzaDosyasi != null) {
            create("bilgili") {
                storeFile = file(imzaDosyasi)
                storePassword = System.getenv("BILGILI_IMZA_PAROLA") ?: "android"
                keyAlias = System.getenv("BILGILI_IMZA_TAKMA_AD") ?: "androiddebugkey"
                keyPassword = System.getenv("BILGILI_IMZA_PAROLA") ?: "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (imzaDosyasi != null) "bilgili" else "debug",
            )
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
