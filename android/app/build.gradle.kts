plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.godeli.go_deli"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.godeli.go_deli"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // CI: variables de entorno (GitHub Actions)
            var keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (keystorePath != null && keystorePath.isNotEmpty()) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            } else {
                // Local: buscar el keystore en la ruta por defecto
                val localKeystore = file("C:/Proyectos/_godeli_keys/release.jks")
                if (localKeystore.exists()) {
                    keystorePath = localKeystore.absolutePath
                    storeFile = localKeystore
                    storePassword = "GoDeliReleaseKey2026"
                    keyAlias = "godeli"
                    keyPassword = "GoDeliReleaseKey2026"
                }
            }
        }
    }

    buildTypes {
        release {
            // Firma con release si el keystore está disponible (CI o local);
            // de lo contrario usa debug para `flutter run`.
            val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            val localKeystore = file("C:/Proyectos/_godeli_keys/release.jks")
            signingConfig = if ((keystorePath != null && keystorePath.isNotEmpty()) || localKeystore.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // R8: reduce y optimiza el APK/AAB para producción
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
