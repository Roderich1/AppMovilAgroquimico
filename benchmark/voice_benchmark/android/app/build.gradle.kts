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

// Banco de pruebas de motores de voz (EVOLUTION-3, Fase 0).
//
// Tres sabores, tres APK, tres `applicationId` distintos: el propietario puede
// tener los tres instalados a la vez, junto a Agrocuentas, sin que ninguno pise
// al otro. Se eligieron sabores en lugar de tres proyectos separados porque la
// interfaz, el corpus y el puerto son idénticos: duplicarlos habría permitido
// que las mediciones se hicieran contra código distinto sin darse cuenta.
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
        // que los tres APK se distingan en el lanzador del teléfono.
        resValues = true
    }

    flavorDimensions += "engine"

    productFlavors {
        create("androidSpeech") {
            dimension = "engine"
            applicationIdSuffix = ".android"
            versionNameSuffix = "-android"
            resValue("string", "app_name", "Voz · Android")
            buildConfigField("String", "ENGINE_ID", "\"android-speech\"")
            buildConfigField("String", "WHISPER_MODEL", "\"\"")
            // Sin librerías nativas: este APK no lleva una línea de Whisper.
        }
        create("whisperTiny") {
            dimension = "engine"
            applicationIdSuffix = ".whispertiny"
            versionNameSuffix = "-whisper-tiny"
            resValue("string", "app_name", "Voz · Whisper tiny")
            buildConfigField("String", "ENGINE_ID", "\"whisper-tiny-q5_1\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-tiny-q5_1.bin\"")
        }
        create("whisperBase") {
            dimension = "engine"
            applicationIdSuffix = ".whisperbase"
            versionNameSuffix = "-whisper-base"
            resValue("string", "app_name", "Voz · Whisper base")
            buildConfigField("String", "ENGINE_ID", "\"whisper-base-q5_1\"")
            buildConfigField("String", "WHISPER_MODEL", "\"ggml-base-q5_1.bin\"")
        }
    }

    sourceSets {
        // Los dos sabores de Whisper comparten motor, JNI y librerías: sólo
        // cambia el modelo. El código vive una sola vez en `whisperCommon`.
        getByName("whisperTiny") {
            kotlin.srcDir("src/whisperCommon/kotlin")
            jniLibs.srcDir("src/whisperCommon/jniLibs")
        }
        getByName("whisperBase") {
            kotlin.srcDir("src/whisperCommon/kotlin")
            jniLibs.srcDir("src/whisperCommon/jniLibs")
        }
    }

    androidResources {
        // Los modelos ggml ya vienen cuantizados: recomprimirlos sólo alarga la
        // build y complica la lectura desde assets.
        noCompress += "bin"
    }

    buildTypes {
        release {
            // El banco se distribuye en DEBUG: no se firma con clave de release
            // y no se publica. Es una herramienta de medición, no un producto.
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
}

flutter {
    source = "../.."
}
