import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

/** Traduce el `--target-platform` de Flutter a nombres de ABI de Android. */
fun abisFromFlutterTarget(targetPlatform: String?): Set<String> {
    if (targetPlatform.isNullOrBlank()) return setOf("arm64-v8a")
    return targetPlatform.split(",").mapNotNull {
        when (it.trim()) {
            "android-arm64" -> "arm64-v8a"
            "android-arm" -> "armeabi-v7a"
            "android-x64" -> "x86_64"
            "android-x86" -> "x86"
            else -> null
        }
    }.toSet().ifEmpty { setOf("arm64-v8a") }
}

// Banco de pruebas de motores de voz (EVOLUTION-3, Fases 0 y 0-bis).
//
// Un sabor por candidato, un APK por sabor, un `applicationId` por sabor: el
// propietario puede tenerlos todos instalados a la vez, junto a Agrocuentas, sin
// que ninguno pise a otro. Se eligieron sabores en lugar de proyectos separados
// porque la interfaz, el corpus y el puerto son idénticos: duplicarlos habría
// permitido que las mediciones se hicieran contra código distinto sin darse
// cuenta.
//
// Este módulo NO forma parte de la aplicación Agrocuentas ni de su CI.

android {
    namespace = "com.comunidad.agro.voicebench"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.comunidad.agro.voicebench"
        // `createOnDeviceSpeechRecognizer` existe desde API 31; sólo
        // `checkRecognitionSupport` pide API 33. Bajar a 31 permite medir en
        // Android 12, que es gama media todavía muy presente en campo, a cambio
        // de no poder consultar los idiomas instalados: allí la capacidad
        // offline se verifica en modo avión, no preguntándole a la API.
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Las ABIs empaquetadas deben coincidir con las que compila Flutter.
        //
        // Si el APK lleva libs nativas de Whisper para x86_64 pero el motor de
        // Flutter se compilo solo para arm64, Android elige x86_64 por las libs
        // de Whisper y despues no encuentra `libflutter.so`: la app se cae al
        // arrancar con "is for EM_AARCH64 instead of EM_X86_64". Derivar el
        // filtro de `target-platform` hace imposible esa combinacion.
        ndk {
            abiFilters += abisFromFlutterTarget(
                project.findProperty("target-platform") as String?,
            )
        }
    }

    buildFeatures {
        buildConfig = true
        // AGP 9 exige habilitarlo: cada sabor define su propio `app_name` para
        // que los APK se distingan en el lanzador del teléfono.
        resValues = true
    }

    flavorDimensions += "engine"

    productFlavors {
        // ---------------------------------------------------------------- C0
        create("androidSpeech") {
            dimension = "engine"
            applicationIdSuffix = ".android"
            versionNameSuffix = "-android"
            resValue("string", "app_name", "Voz · Android")
            buildConfigField("String", "ENGINE_ID", "\"android-speech\"")
            buildConfigField("String", "WHISPER_MODEL", "\"\"")
            buildConfigField("String", "VOSK_MODEL", "\"\"")
            // Sin librerías nativas: este APK no lleva una línea de Whisper.
        }
        // ------------------------------------------------- Fase 0, histórico
        create("whisperTiny") {
            dimension = "engine"
            applicationIdSuffix = ".whispertiny"
            versionNameSuffix = "-whisper-tiny"
            resValue("string", "app_name", "Voz · Whisper tiny")
            buildConfigField("String", "ENGINE_ID", "\"whisper-tiny-q5_1\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-tiny-q5_1.bin\"")
            buildConfigField("String", "VOSK_MODEL", "\"\"")
        }
        // ---------------------------------------------------------------- C2
        create("whisperBase") {
            dimension = "engine"
            applicationIdSuffix = ".whisperbase"
            versionNameSuffix = "-whisper-base"
            resValue("string", "app_name", "Voz · Whisper base")
            buildConfigField("String", "ENGINE_ID", "\"whisper-base-q5_1\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-base-q5_1.bin\"")
            buildConfigField("String", "VOSK_MODEL", "\"\"")
        }
        // ---------------------------------------------------------------- C3
        create("whisperSmall") {
            dimension = "engine"
            applicationIdSuffix = ".whispersmall"
            versionNameSuffix = "-whisper-small"
            resValue("string", "app_name", "Voz · Whisper small")
            buildConfigField("String", "ENGINE_ID", "\"whisper-small-q5_1\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-small-q5_1.bin\"")
            buildConfigField("String", "VOSK_MODEL", "\"\"")
        }
        // ---------------------------------------------------------------- C1
        create("vosk") {
            dimension = "engine"
            applicationIdSuffix = ".vosk"
            versionNameSuffix = "-vosk"
            resValue("string", "app_name", "Voz · Vosk")
            buildConfigField("String", "ENGINE_ID", "\"vosk-small-es-0.42\"")
            buildConfigField("String", "WHISPER_MODEL", "\"\"")
            buildConfigField("String", "VOSK_MODEL", "\"vosk-model-small-es-0.42\"")
        }
        // ---------------------------------------------------------------- C4
        create("hybrid") {
            dimension = "engine"
            applicationIdSuffix = ".hybrid"
            versionNameSuffix = "-hybrid"
            resValue("string", "app_name", "Voz · Híbrido")
            buildConfigField("String", "ENGINE_ID", "\"hybrid-vosk-whisper-small\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-small-q5_1.bin\"")
            buildConfigField("String", "VOSK_MODEL", "\"vosk-model-small-es-0.42\"")
        }
    }

    sourceSets {
        // Los sabores de Whisper comparten motor, JNI y librerías: sólo cambia
        // el modelo. El código vive una vez en `whisperCommon`, y la fábrica
        // —que debe existir exactamente una por sabor— en `whisperOnly`.
        //
        // `captureCommon` lo comparten todos los que abren el micrófono: la
        // captura de audio existe **una sola vez** en el banco. Si cada motor
        // tuviera la suya, el híbrido mediría dos grabaciones distintas y la
        // comparación con los motores aislados no significaría nada.
        for (flavor in listOf("whisperTiny", "whisperBase", "whisperSmall")) {
            getByName(flavor) {
                kotlin.srcDir("src/captureCommon/kotlin")
                kotlin.srcDir("src/whisperCommon/kotlin")
                kotlin.srcDir("src/whisperOnly/kotlin")
                jniLibs.srcDir("src/whisperCommon/jniLibs")
            }
        }
        getByName("vosk") {
            kotlin.srcDir("src/captureCommon/kotlin")
            kotlin.srcDir("src/voskCommon/kotlin")
            kotlin.srcDir("src/voskOnly/kotlin")
        }
        // El híbrido es el único que compila los dos motores a la vez, porque
        // es el único que los usa sobre la misma captura.
        getByName("hybrid") {
            kotlin.srcDir("src/captureCommon/kotlin")
            kotlin.srcDir("src/voskCommon/kotlin")
            kotlin.srcDir("src/whisperCommon/kotlin")
            jniLibs.srcDir("src/whisperCommon/jniLibs")
        }
    }

    androidResources {
        // Los modelos ggml ya vienen cuantizados y los de Vosk son FST
        // comprimidos: recomprimirlos sólo alarga la build y complica leerlos
        // desde assets.
        noCompress += listOf("bin", "fst", "mdl", "ie", "dubm", "mat", "stats")
    }

    packaging {
        jniLibs {
            // Necesario para páginas de 16 KB: las librerías se mapean desde el
            // APK sin descomprimir. `zipalign -P 16` lo comprueba después.
            useLegacyPackaging = false
        }
    }

    buildTypes {
        release {
            // El banco se distribuye firmado con la clave de DEPURACIÓN: no se
            // publica. Es una herramienta de medición, no un producto. Se
            // construye `--release` porque medir latencias sobre Dart
            // interpretado no mediría el motor.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")

    // Vosk sólo entra en los sabores que lo miden. El APK de Android y los de
    // Whisper no llevan una línea suya.
    //
    // Versión exacta y contenido fijado: ver `verifyPinnedVoiceArtifacts`. Sin
    // rangos, sin `latest`, sin `+`, y sólo desde Maven Central por el
    // `exclusiveContent` del proyecto raíz.
    add("voskImplementation", "com.alphacephei:vosk-android:0.3.75")
    add("hybridImplementation", "com.alphacephei:vosk-android:0.3.75")
}

// --------------------------------------------------------- cadena de suministro

/**
 * Binarios de voz cuyo contenido exacto está fijado.
 *
 * Verificados en fuente primaria el 2026-09-07 y registrados en
 * `benchmark/voice_benchmark/THIRD_PARTY.md`. `RISK-033` documenta lo que estos
 * hashes **no** garantizan: que el binario corresponda al código publicado.
 */
val pinnedVoiceArtifacts: Map<String, Triple<String, Long, String>> = mapOf(
    "vosk-android-0.3.75.aar" to Triple(
        "ab2f8b91ac8051561aa325546b35fed9a68b36b8121bac5c6fb927525c4adfad",
        13_472_638L,
        "Apache-2.0",
    ),
    // Única transitiva de Vosk, y con exclusiones `*:*`: no arrastra nada más.
    // Dual LGPL-2.1-or-later / Apache-2.0; se elige Apache-2.0 para no arrastrar
    // las obligaciones de relinkeo de la LGPL.
    "jna-5.18.1.aar" to Triple(
        "7f053e3ec99e14dd71259c82c1c8a02738d64a13c31226b2acc170f3060951e0",
        522_677L,
        "Apache-2.0 (elegida sobre LGPL-2.1-or-later)",
    ),
)

fun sha256Of(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { stream ->
        val buffer = ByteArray(1 shl 16)
        while (true) {
            val read = stream.read(buffer)
            if (read <= 0) break
            digest.update(buffer, 0, read)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

/**
 * Falla la build si un binario de voz no es exactamente el medido.
 *
 * ## Por qué esto y no `verification-metadata.xml`
 *
 * La verificación que trae Gradle es todo o nada: activarla obliga a enumerar
 * el hash de **todos** los artefactos, incluidos los cientos del propio AGP y
 * del compilador de Kotlin, y ese archivo se acaba regenerando a ciegas con
 * cada subida de herramientas —con lo que deja de verificar nada.
 *
 * Aquí interesa algo más estricto y más pequeño: que **estos dos** binarios,
 * los que ejecutan el audio del usuario y para los que `RISK-033` no pudo
 * cerrar la cadena PGP, sean los registrados. Se comprueba en cada build de un
 * sabor con Vosk y no depende de que nadie se acuerde de regenerar nada.
 */
val verifyPinnedVoiceArtifacts by tasks.registering {
    group = "verification"
    description = "Comprueba el SHA-256 de los binarios de voz fijados."

    doLast {
        // Los sabores con Vosk resuelven en `voskDebugRuntimeClasspath`,
        // `hybridReleaseRuntimeClasspath`, etc. Se miran todos: verificar sólo
        // uno dejaría el otro sabor sin comprobar.
        val toVerify = configurations.filter {
            it.isCanBeResolved &&
                it.name.endsWith("RuntimeClasspath") &&
                (it.name.startsWith("vosk") || it.name.startsWith("hybrid"))
        }
        if (toVerify.isEmpty()) {
            throw GradleException(
                "No hay configuración con Vosk que verificar. Un sabor que " +
                    "debería llevarlo y no lo lleva está mal configurado.",
            )
        }

        val found = mutableSetOf<String>()
        toVerify.flatMap {
            it.incoming.artifactView { lenient(true) }.artifacts.artifacts
        }.forEach { artifact ->
                val file = artifact.file
                val pinned = pinnedVoiceArtifacts[file.name] ?: return@forEach
                found += file.name

                val (expectedSha, expectedSize, license) = pinned
                val actualSize = file.length()
                val actualSha = sha256Of(file)
                if (actualSize != expectedSize || actualSha != expectedSha) {
                    throw GradleException(
                        buildString {
                            appendLine("CADENA DE SUMINISTRO: ${file.name} NO coincide.")
                            appendLine("  archivo:  ${file.absolutePath}")
                            appendLine("  esperado: $expectedSize B  sha256=$expectedSha")
                            appendLine("  obtenido: $actualSize B  sha256=$actualSha")
                            appendLine()
                            append(
                                "No se construye un APK de medición sobre un binario " +
                                    "que no es el registrado. Si la subida de versión " +
                                    "es intencionada hay que repetir el gate completo " +
                                    "de RISK-033: hashes, licencias, transitivas, ABIs, " +
                                    "16 KB, corpus y rendimiento en los dos teléfonos.",
                            )
                        },
                    )
                }
                logger.lifecycle("cadena de suministro OK: ${file.name}  ($license)")
            }

        val missing = pinnedVoiceArtifacts.keys - found
        if (missing.isNotEmpty()) {
            throw GradleException(
                "CADENA DE SUMINISTRO: no se resolvieron ${missing.joinToString()}. " +
                    "Un sabor con Vosk que no los traiga está mal configurado.",
            )
        }
    }
}

// Cada compilación de un sabor con Vosk pasa por la verificación. No es un paso
// opcional que alguien pueda olvidar antes de medir.
afterEvaluate {
    // Se engancha por prefijo y no por una lista de nombres exactos: los
    // nombres de tarea de AGP cambian entre versiones, y una lista que dejara
    // de coincidir haría que la verificación se saltara en silencio, que es
    // justo el fallo que no puede ocurrir aquí.
    tasks.matching { task ->
        val name = task.name
        (name.startsWith("compileVosk") || name.startsWith("compileHybrid")) &&
            (name.endsWith("Kotlin") || name.endsWith("JavaWithJavac"))
    }.configureEach { dependsOn(verifyPinnedVoiceArtifacts) }
}

flutter {
    source = "../.."
}
