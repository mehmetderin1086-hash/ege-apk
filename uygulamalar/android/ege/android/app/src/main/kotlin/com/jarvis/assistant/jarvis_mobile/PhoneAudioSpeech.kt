package com.jarvis.assistant.jarvis_mobile

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/** Transcribe the supplied PCM with Android's on-device engine.
 * Only segmented callbacks are accepted: an engine ignoring AUDIO_SOURCE must
 * not substitute fresh, unverified microphone speech for the supplied audio.
 */
class PhoneAudioSpeech(private val activity: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0
    private var pending: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private var pipe: Array<ParcelFileDescriptor>? = null
    private var deadline: Runnable? = null

    fun start(pcm: ByteArray?, result: MethodChannel.Result) {
        cancel()
        if (pcm == null || pcm.size < 3200 || pcm.size > 32000 * 120 || pcm.size % 2 != 0) {
            result.success(mapOf("status" to "INVALID_AUDIO")); return
        }
        if (Build.VERSION.SDK_INT < 33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) {
            result.success(mapOf("status" to "UNAVAILABLE")); return
        }
        pending = result
        val token = ++generation
        val segments = mutableListOf<String>()
        try {
            val sr = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            recognizer = sr
            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onError(error: Int) {
                    if (token != generation) return
                    finish(token, "ERROR_$error", "")
                    if (error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE) {
                        PhoneSpeechModels.prepare(activity, knownMissing = true)
                    }
                }
                override fun onResults(results: Bundle?) { finish(token, "SOURCE_UNSUPPORTED", "") }
                override fun onSegmentResults(segmentResults: Bundle) {
                    if (token != generation) return
                    segmentResults.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.let(segments::add)
                }
                override fun onEndOfSegmentedSession() {
                    val text = segments.joinToString(" ")
                    finish(token, if (text.isBlank()) "NO_SPEECH" else "OK", text)
                }
            })
            val audioPipe = ParcelFileDescriptor.createPipe()
            pipe = audioPipe
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, audioPipe[0])
                .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
                .putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            deadline = Runnable { finish(token, "TIMEOUT", "") }.also { handler.postDelayed(it, 6000) }
            Log.i("EgeSTT", "START engine=phone_local source=provided_pcm bytes=${pcm.size}")
            sr.startListening(intent)
            Thread {
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(audioPipe[1]).use { it.write(pcm) }
                } catch (_: Throwable) {
                    handler.post { finish(token, "SOURCE_ERROR", "") }
                }
            }.apply { name = "ege-phone-stt-audio"; start() }
        } catch (_: Throwable) { finish(token, "UNAVAILABLE", "") }
    }

    private fun finish(token: Int, status: String, text: String) {
        if (token != generation || pending == null) return
        val result = pending
        pending = null
        generation++
        deadline?.let(handler::removeCallbacks); deadline = null
        val old = recognizer; recognizer = null
        try { old?.cancel(); old?.destroy() } catch (_: Throwable) {}
        pipe?.forEach { try { it.close() } catch (_: Throwable) {} }; pipe = null
        Log.i("EgeSTT", "FINISH source=provided_pcm status=$status characters=${text.length}")
        result?.success(mapOf("status" to status, "text" to text))
    }

    fun cancel() { finish(generation, "CANCELLED", "") }
}
