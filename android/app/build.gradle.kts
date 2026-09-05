import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Configuración de firma de release.
//
// Las credenciales NUNCA se versionan: se leen de `android/key.properties`,
// que está en .gitignore. Si el archivo no existe (por ejemplo en la máquina de
// un desarrollador nuevo o en CI sin secretos), la build de release NO se firma
// con la clave de depuración: falla de forma explícita, para que nadie publique
// por error un binario firmado con una clave pública.
//
// Para habilitar la firma, ver docs/20_BUILD_AND_CONFIGURATION.md.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null

if (!hasReleaseSigning) {
    logger.warn(
        "\n[agrocuentas] android/key.properties no existe: la build de RELEASE " +
            "quedará SIN FIRMAR.\n" +
            "[agrocuentas] Un APK sin firmar no se puede instalar ni publicar. " +
            "Esto es deliberado: firmar con la clave de depuración es inseguro " +
            "y Google Play lo rechaza.\n" +
            "[agrocuentas] Para habilitar la firma copie android/key.properties.example " +
            "a android/key.properties y complete los valores.\n" +
            "[agrocuentas] Detalle: docs/20_BUILD_AND_CONFIGURATION.md\n"
    )
}

android {
    namespace = "com.comunidad.agro.agroquimicos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.comunidad.agro.agroquimicos"
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
        if (hasReleaseSigning) {
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
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Sin `key.properties` la build queda deliberadamente SIN firmar.
            // Es preferible a firmarla con la clave de depuración, que es
            // pública, impide publicar en Google Play y permitiría a cualquiera
            // suplantar una actualización de la aplicación.
            isMinifyEnabled = false
            isShrinkResources = false
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
