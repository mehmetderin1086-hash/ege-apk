// JNI bridge between JARVIS (Kotlin: WhisperNative) and whisper.cpp.
#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>

#include "whisper.h"

#define TAG "JarvisWhisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

JNIEXPORT jlong JNICALL
Java_com_jarvis_assistant_jarvis_1mobile_WhisperNative_initContext(
        JNIEnv *env, jclass clazz, jstring model_path) {
    (void) clazz;
    const char *path = (*env)->GetStringUTFChars(env, model_path, NULL);
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;
    struct whisper_context *ctx = whisper_init_from_file_with_params(path, cparams);
    LOGI("model loaded: %s -> %p", path, (void *) ctx);
    (*env)->ReleaseStringUTFChars(env, model_path, path);
    return (jlong) ctx;
}

JNIEXPORT void JNICALL
Java_com_jarvis_assistant_jarvis_1mobile_WhisperNative_freeContext(
        JNIEnv *env, jclass clazz, jlong ctx_ptr) {
    (void) env;
    (void) clazz;
    if (ctx_ptr != 0) whisper_free((struct whisper_context *) ctx_ptr);
}

// Returns the transcript as UTF-8 bytes (NewStringUTF only accepts modified
// UTF-8, which breaks on emoji / supplementary characters), or NULL on error.
JNIEXPORT jbyteArray JNICALL
Java_com_jarvis_assistant_jarvis_1mobile_WhisperNative_transcribe(
        JNIEnv *env, jclass clazz, jlong ctx_ptr, jfloatArray audio, jstring language,
        jint threads, jint audio_ctx, jstring prompt) {
    (void) clazz;
    struct whisper_context *ctx = (struct whisper_context *) ctx_ptr;
    if (ctx == NULL) return NULL;

    const jsize n = (*env)->GetArrayLength(env, audio);
    jfloat *samples = (*env)->GetFloatArrayElements(env, audio, NULL);
    const char *lang = (*env)->GetStringUTFChars(env, language, NULL);
    const char *init_prompt = (*env)->GetStringUTFChars(env, prompt, NULL);

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.translate = false;
    params.language = lang;
    params.detect_language = false;
    params.n_threads = threads > 0 ? threads : 4;
    params.no_context = true;
    params.single_segment = false;
    params.no_timestamps = true;
    params.suppress_blank = true;
    // No "[Müzik]" / "(alkış)" style tokens for voice commands.
    params.suppress_nst = true;
    // Temperature fallback only kicks in on unclear audio; 2 candidates keep
    // it robust without the 5x cost of the default on a phone CPU.
    params.greedy.best_of = 2;
    params.audio_ctx = audio_ctx;
    if (init_prompt != NULL && init_prompt[0] != '\0') params.initial_prompt = init_prompt;

    const int rc = whisper_full(ctx, params, samples, n);
    (*env)->ReleaseFloatArrayElements(env, audio, samples, JNI_ABORT);

    size_t cap = 512;
    size_t len = 0;
    char *out = (char *) malloc(cap);
    if (out != NULL) out[0] = '\0';
    if (rc == 0 && out != NULL) {
        const int segments = whisper_full_n_segments(ctx);
        for (int i = 0; i < segments; i++) {
            const char *text = whisper_full_get_segment_text(ctx, i);
            const size_t tl = strlen(text);
            if (len + tl + 1 > cap) {
                while (len + tl + 1 > cap) cap *= 2;
                char *grown = (char *) realloc(out, cap);
                if (grown == NULL) break;
                out = grown;
            }
            memcpy(out + len, text, tl);
            len += tl;
            out[len] = '\0';
        }
    }

    (*env)->ReleaseStringUTFChars(env, language, lang);
    (*env)->ReleaseStringUTFChars(env, prompt, init_prompt);

    if (rc != 0 || out == NULL) {
        LOGI("whisper_full failed: %d", rc);
        free(out);
        return NULL;
    }
    jbyteArray result = (*env)->NewByteArray(env, (jsize) len);
    (*env)->SetByteArrayRegion(env, result, 0, (jsize) len, (const jbyte *) out);
    free(out);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_jarvis_assistant_jarvis_1mobile_WhisperNative_systemInfo(JNIEnv *env, jclass clazz) {
    (void) clazz;
    return (*env)->NewStringUTF(env, whisper_print_system_info());
}
