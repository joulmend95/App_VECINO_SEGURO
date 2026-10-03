import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lee las claves de firma desde android/key.properties.
// Ese archivo está en .gitignore y nunca debe subirse al repositorio.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "com.vecinoseguro.app"
    // flutter_secure_storage exige API 37 o superior. Se fija a mano en lugar
    // de heredarlo de Flutter, que aún apunta a 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications usa APIs de java.time que no existen en
        // versiones antiguas de Android; el desugaring las hace disponibles.
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        create("release") {
            // Si key.properties no existe la build de release falla de forma
            // explícita en lugar de firmar silenciosamente con claves de debug.
            storeFile = file(keyProperties.getProperty("storeFile")!!)
            storePassword = keyProperties.getProperty("storePassword")!!
            keyAlias = keyProperties.getProperty("keyAlias")!!
            keyPassword = keyProperties.getProperty("keyPassword")!!
        }
    }

    defaultConfig {
        applicationId = "com.vecinoseguro.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

            // El trafico sin cifrar SOLO existe en depuracion.
            //
            // En desarrollo hace falta: el emulador habla con el backend local
            // por HTTP contra 10.0.2.2. Dejarlo activo en release permitiria
            // que el token de sesion viajara en claro, y cualquiera en la misma
            // wifi podria leerlo y suplantar al vecino.
            manifestPlaceholders["permitirTraficoSinCifrar"] = "false"
        }
        debug {
            manifestPlaceholders["permitirTraficoSinCifrar"] = "true"
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // MediaSessionCompat y VolumeProviderCompat: es lo que permite al servicio
    // de pánico recibir las pulsaciones de volumen con la pantalla apagada.
    implementation("androidx.media:media:1.6.0")
}
