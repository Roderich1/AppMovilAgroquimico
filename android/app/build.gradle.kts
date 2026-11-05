import java.security.MessageDigest
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
        // Sólo para `src/androidTest`: inferencia real del motor de voz local
        // con audio de referencia (tool/voice_local/run_reference_check.sh).
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // Voz local (F09, #165/#166): los modelos viajan como assets, pero NO se
    // versionan. Los deja aquí `tool/voice_local/fetch_voice_models.sh` tras
    // verificar su SHA-256. Sin esa carpeta la app compila igual y la pantalla
    // de voz dice que el modelo no está instalado.
    sourceSets {
        getByName("main") {
            assets.srcDir("voice-models")
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

dependencies {
    // Reconocimiento local de voz. Versión exacta y contenido fijado abajo; sin
    // rangos ni `+`. Trae JNA 5.18.1 como única transitiva.
    implementation("com.alphacephei:vosk-android:0.3.75")

    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.2")
}

// --------------------------------------------------------- cadena de suministro

/**
 * Binarios de voz cuyo contenido exacto está fijado, los mismos que midió el
 * banco híbrido el 2026-09-07 (`benchmark/voice_benchmark/THIRD_PARTY.md` de la
 * rama `evolution/evolution-3-hybrid-voice-benchmark`). La firma PGP de Vosk no
 * se pudo verificar entonces (`RISK-033`); el hash fija los bytes aceptados.
 */
val pinnedVoiceArtifacts: Map<String, Pair<String, Long>> = mapOf(
    "vosk-android-0.3.75.aar" to
        ("ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad" to 13_472_638L),
    // Dual LGPL-2.1-or-later / Apache-2.0: se usa bajo Apache-2.0.
    "jna-5.18.1.aar" to
        ("7f053e3ec99e14dd71259c82c1c8a02738d64a13c31226b2acc170f3060951e0" to 522_677L),
)

val verifyPinnedVoiceArtifacts by tasks.registering {
    group = "verification"
    description = "Comprueba el SHA-256 de los binarios de voz fijados."
    doLast {
        val found = mutableSetOf<String>()
        configurations.filter { it.isCanBeResolved && it.name.endsWith("RuntimeClasspath") }
            .flatMap { it.incoming.artifactView { lenient(true) }.artifacts.artifacts }
            .forEach { artifact ->
                val file = artifact.file
                val (sha, size) = pinnedVoiceArtifacts[file.name] ?: return@forEach
                val digest = MessageDigest.getInstance("SHA-256")
                file.inputStream().use { input ->
                    val buffer = ByteArray(1 shl 16)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        digest.update(buffer, 0, read)
                    }
                }
                val actual = digest.digest().joinToString("") { "%02x".format(it) }
                if (actual != sha || file.length() != size) {
                    throw GradleException(
                        "CADENA DE SUMINISTRO: ${file.name} no coincide " +
                            "(esperado $size B sha256=$sha; obtenido ${file.length()} B sha256=$actual).",
                    )
                }
                found += file.name
            }
        val missing = pinnedVoiceArtifacts.keys - found
        if (missing.isNotEmpty()) throw GradleException("No se resolvieron: $missing")
        logger.lifecycle("cadena de suministro de voz OK: ${found.sorted()}")
    }
}

tasks.named("preBuild") { dependsOn(verifyPinnedVoiceArtifacts) }
