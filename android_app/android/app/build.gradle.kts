plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.feyzaras.onepiece_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.feyzaras.onepiece_scanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signiert mit dem Debug-Schluessel: ausreichend zum Selbstinstallieren,
            // fuer den Play Store waere ein eigener Signaturschluessel noetig.
            signingConfig = signingConfigs.getByName("debug")

            // Code-Verkleinerung (R8) ist bewusst AUS.
            // Mit R8 schlug die Bilduebergabe an ML Kit zur Laufzeit fehl:
            //   PlatformException(InputImageConverterError, java.lang.NullPointerException:
            //   Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'
            //   on a null object reference)
            // Ursache: R8 entfernt Teile, die ML Kit erst zur Laufzeit ueber Reflection laedt.
            // Die App wird dadurch groesser, funktioniert aber zuverlaessig.
            isMinifyEnabled = false
            isShrinkResources = false
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
