import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signaturschluessel - der wichtigste Punkt im ganzen Projekt.
//
// Android laesst ein Update nur zu, wenn es mit DEMSELBEN Schluessel signiert ist wie die
// installierte App. Passt er nicht, bleibt nur Deinstallieren - und damit waere die
// Sammlung des Nutzers weg.
//
// Frueher stand hier signingConfigs.getByName("debug"). Das war gefaehrlich: Fehlt
// ~/.android/debug.keystore, erzeugt das Android-Werkzeug stillschweigend einen NEUEN
// Schluessel. Der Build laeuft durch, die APK ist signiert - nur mit fremder Identitaet.
// Auffallen wuerde das erst auf dem Handy mit "App nicht installiert", und dann waere es
// nicht mehr zu reparieren.
//
// Deshalb jetzt: fester Pfad ueber key.properties, und wenn die Datei fehlt, bricht der
// Build ab. Lieber kein Release als ein Release mit falschem Schluessel.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
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

    signingConfigs {
        create("release") {
            val pfad = keystoreProperties.getProperty("storeFile")
            if (pfad == null) {
                // Nur melden, nicht sofort abbrechen: 'flutter test' und Analysen sollen
                // weiterhin ohne Schluessel laufen. Der Abbruch kommt beim Release-Build.
                logger.warn("WARNUNG: android/key.properties fehlt - ein Release-Build wird abbrechen.")
            } else {
                val datei = file(pfad)
                if (!datei.exists()) {
                    throw GradleException(
                        "Keystore nicht gefunden: $pfad\n" +
                        "NICHT neu erzeugen - die Datei aus der Sicherung wiederherstellen.\n" +
                        "Ohne genau diesen Schluessel laesst sich die installierte App nie wieder aktualisieren."
                    )
                }
                storeFile = datei
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Auch Testlaeufe per 'flutter run' mit demselben Schluessel signieren.
            // Sonst liesse sich eine Entwicklungsfassung nicht ueber die installierte
            // App legen und man waere versucht, sie zu deinstallieren.
            if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }

        release {
            // Derselbe Schluessel wie seit v0.1.0 - nachgewiesen ueber den Fingerabdruck
            // der veroeffentlichten v0.7.0-APK (SHA-256 ccbd78f9...83cb04bb).
            // Fuer den Play Store waere ein eigener Schluessel noetig; der ist nicht geplant.
            signingConfig = signingConfigs.getByName("release")

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
