// Puente JNI mínimo hacia whisper.cpp para la segunda pasada local de voz.
//
// Derivado de `benchmark/voice_benchmark/.../whisper_jni.c` (rama del banco
// híbrido), que a su vez deriva de `examples/whisper.android/lib/src/main/jni/`
// de whisper.cpp (MIT, © 2023-2026 The ggml authors). Ver
// `docs/evidence/F09_VOZ_LOCAL_2026-11-05.md` y `tool/voice_local/THIRD_PARTY.md`.
//
// Sólo recibe audio en memoria y devuelve texto. No escribe archivos, no guarda
// el audio y no registra lo transcrito: el log sólo lleva códigos.

#include <jni.h>
#include <android/log.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "whisper.h"

#define TAG "AgroVozWhisper"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

// Una sola inferencia a la vez en todo el proceso: la revisa un único hilo.
static atomic_bool g_abort = false;

static bool should_abort(void *user_data) {
    (void) user_data;
    return atomic_load(&g_abort);
}

JNIEXPORT jlong JNICALL
Java_com_comunidad_agro_agroquimicos_WhisperNative_init(
        JNIEnv *env, jobject thiz, jstring model_path) {
    (void) thiz;
    const char *path = (*env)->GetStringUTFChars(env, model_path, NULL);
    struct whisper_context_params params = whisper_context_default_params();
    params.use_gpu = false;
    struct whisper_context *ctx = whisper_init_from_file_with_params(path, params);
    (*env)->ReleaseStringUTFChars(env, model_path, path);
    if (ctx == NULL) LOGW("init: el modelo no cargo");
    return (jlong) ctx;
}

JNIEXPORT void JNICALL
Java_com_comunidad_agro_agroquimicos_WhisperNative_free(
        JNIEnv *env, jobject thiz, jlong ptr) {
    (void) env;
    (void) thiz;
    if (ptr != 0) whisper_free((struct whisper_context *) ptr);
}

JNIEXPORT void JNICALL
Java_com_comunidad_agro_agroquimicos_WhisperNative_abort(JNIEnv *env, jobject thiz) {
    (void) env;
    (void) thiz;
    atomic_store(&g_abort, true);
}

/// Transcribe PCM float mono a 16 kHz, en español y sin traducir.
///
/// `prompt` es la pista de vocabulario (nombres del catálogo); puede ser
/// nula. Devuelve el texto, o NULL si falló o se abortó. `out_no_speech[0]`
/// recibe la mayor probabilidad de «sin habla» de los segmentos.
JNIEXPORT jstring JNICALL
Java_com_comunidad_agro_agroquimicos_WhisperNative_transcribe(
        JNIEnv *env, jobject thiz, jlong ptr, jfloatArray audio, jstring prompt,
        jint threads, jfloatArray out_no_speech) {
    (void) thiz;
    struct whisper_context *ctx = (struct whisper_context *) ptr;
    if (ctx == NULL) return NULL;
    atomic_store(&g_abort, false);

    jfloat *samples = (*env)->GetFloatArrayElements(env, audio, NULL);
    const jsize length = (*env)->GetArrayLength(env, audio);
    const char *hint = prompt == NULL ? NULL : (*env)->GetStringUTFChars(env, prompt, NULL);

    struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.print_realtime = false;
    p.print_progress = false;
    p.print_timestamps = false;
    p.print_special = false;
    p.translate = false;          // transcribir, nunca traducir
    p.language = "es";
    p.detect_language = false;
    p.n_threads = threads;
    p.no_context = true;          // nada de una frase anterior condiciona ésta
    p.no_timestamps = true;
    p.single_segment = true;
    p.suppress_blank = true;
    p.suppress_nst = true;        // sin [MÚSICA], (risas) ni símbolos
    p.temperature = 0.0f;
    p.temperature_inc = 0.0f;     // sin reintentos a mayor temperatura
    p.initial_prompt = hint;
    p.abort_callback = should_abort;
    p.abort_callback_user_data = NULL;

    const int rc = whisper_full(ctx, p, samples, length);

    (*env)->ReleaseFloatArrayElements(env, audio, samples, JNI_ABORT);
    if (hint != NULL) (*env)->ReleaseStringUTFChars(env, prompt, hint);
    if (rc != 0 || atomic_load(&g_abort)) return NULL;

    const int n = whisper_full_n_segments(ctx);
    size_t size = 1;
    for (int i = 0; i < n; i++) size += strlen(whisper_full_get_segment_text(ctx, i)) + 1;
    char *text = calloc(size, 1);
    if (text == NULL) return NULL;
    float no_speech = 0.0f;
    for (int i = 0; i < n; i++) {
        strcat(text, whisper_full_get_segment_text(ctx, i));
        const float prob = whisper_full_get_segment_no_speech_prob(ctx, i);
        if (prob > no_speech) no_speech = prob;
    }
    (*env)->SetFloatArrayRegion(env, out_no_speech, 0, 1, &no_speech);
    jstring result = (*env)->NewStringUTF(env, text);
    free(text);
    return result;
}
