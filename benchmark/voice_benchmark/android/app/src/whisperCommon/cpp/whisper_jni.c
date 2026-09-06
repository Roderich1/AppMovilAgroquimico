// Puente JNI mínimo hacia whisper.cpp para el banco de pruebas de EVOLUTION-3.
//
// Derivado de `examples/whisper.android/lib/src/main/jni/whisper/jni.c` de
// whisper.cpp (MIT, © 2023-2026 The ggml authors). Se conservan los términos de
// esa licencia; ver `benchmark/voice_benchmark/THIRD_PARTY.md`.
//
// ## Por qué existe una versión propia
//
// El wrapper original **fija `params.language = "en"`**. Medir español con la
// pista de idioma en inglés falsearía todo el benchmark: el modelo multilingüe
// se comporta de otra manera según ese parámetro. Aquí el idioma es un argumento
// y se registra en el resultado.
//
// Este archivo no conoce Agrocuentas: sólo recibe audio en memoria y devuelve
// texto. No escribe archivos y no guarda el audio.

#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysinfo.h>
#include "whisper.h"

#define UNUSED(x) (void)(x)
#define TAG "WhisperBench"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

static struct whisper_context *ctx_of(jlong ptr) {
    return (struct whisper_context *) ptr;
}

JNIEXPORT jlong JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_initContext(
        JNIEnv *env, jobject thiz, jstring model_path) {
    UNUSED(thiz);
    const char *path = (*env)->GetStringUTFChars(env, model_path, NULL);
    struct whisper_context_params params = whisper_context_default_params();
    // El benchmark mide CPU a propósito: el objetivo es saber qué rinde en un
    // teléfono cualquiera, no en uno con GPU utilizable.
    params.use_gpu = false;
    struct whisper_context *context = whisper_init_from_file_with_params(path, params);
    if (context == NULL) {
        LOGW("whisper_init_from_file_with_params devolvio NULL");
    }
    (*env)->ReleaseStringUTFChars(env, model_path, path);
    return (jlong) context;
}

JNIEXPORT void JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_freeContext(
        JNIEnv *env, jobject thiz, jlong context_ptr) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = ctx_of(context_ptr);
    if (context != NULL) whisper_free(context);
}

/// Transcribe `audio_data` (PCM float mono a 16 kHz) con la pista de idioma
/// `language`. Devuelve 0 si whisper terminó bien.
JNIEXPORT jint JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_fullTranscribe(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint num_threads,
        jstring language, jfloatArray audio_data) {
    UNUSED(thiz);
    struct whisper_context *context = ctx_of(context_ptr);
    if (context == NULL) return -1;

    jfloat *samples = (*env)->GetFloatArrayElements(env, audio_data, NULL);
    const jsize length = (*env)->GetArrayLength(env, audio_data);
    const char *lang = (*env)->GetStringUTFChars(env, language, NULL);

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.translate = false;      // transcribir, nunca traducir al ingles
    params.language = lang;        // <- la diferencia con el wrapper original
    params.detect_language = false;
    params.n_threads = num_threads;
    params.offset_ms = 0;
    params.no_context = true;
    params.single_segment = false;

    whisper_reset_timings(context);
    const int rc = whisper_full(context, params, samples, length);

    (*env)->ReleaseFloatArrayElements(env, audio_data, samples, JNI_ABORT);
    (*env)->ReleaseStringUTFChars(env, language, lang);
    return rc;
}

JNIEXPORT jint JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_getTextSegmentCount(
        JNIEnv *env, jobject thiz, jlong context_ptr) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = ctx_of(context_ptr);
    return context == NULL ? 0 : whisper_full_n_segments(context);
}

JNIEXPORT jstring JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_getTextSegment(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint index) {
    UNUSED(thiz);
    struct whisper_context *context = ctx_of(context_ptr);
    if (context == NULL) return (*env)->NewStringUTF(env, "");
    const char *text = whisper_full_get_segment_text(context, index);
    return (*env)->NewStringUTF(env, text == NULL ? "" : text);
}

JNIEXPORT jstring JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_getSystemInfo(
        JNIEnv *env, jobject thiz) {
    UNUSED(thiz);
    return (*env)->NewStringUTF(env, whisper_print_system_info());
}

/// Versión de whisper.cpp con la que se compiló esta librería.
JNIEXPORT jstring JNICALL
Java_com_comunidad_agro_voicebench_whisper_WhisperLib_00024Companion_getVersion(
        JNIEnv *env, jobject thiz) {
    UNUSED(thiz);
#ifdef WHISPER_BENCH_VERSION
    return (*env)->NewStringUTF(env, WHISPER_BENCH_VERSION);
#else
    return (*env)->NewStringUTF(env, "desconocida");
#endif
}
