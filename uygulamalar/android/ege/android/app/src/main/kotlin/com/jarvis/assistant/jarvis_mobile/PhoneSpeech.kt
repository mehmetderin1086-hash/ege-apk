package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

/** One cancellable recognition request; callbacks from an old recognizer cannot finish a new one. */
class PhoneSpeech(private val activity: Activity) {
    private var recognizer: SpeechRecognizer? = null
    private var pending: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0
    private var deadline: Runnable? = null

    fun start(result: MethodChannel.Result) {
        cancel()
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4412)
            result.success(mapOf("status" to "PERMISSION_NEEDED")); return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            result.success(mapOf("status" to "UNAVAILABLE")); return
        }
        pending = result
        val token = generation
        try {
            val sr = SpeechRecognizer.createSpeechRecognizer(activity)
            Log.i("EgeSTT", "START engine=system_default")
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
                    Log.i("EgeSTT", "ERROR code=$error")
                    finish(token, if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) "PERMISSION_NEEDED"
                        else if (error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT || error == SpeechRecognizer.ERROR_NO_MATCH) "NO_SPEECH" else "ERROR", "")
                    if (error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE) {
                        PhoneSpeechModels.prepare(activity, knownMissing = true)
                    }
                }
                override fun onResults(results: Bundle?) {
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    finish(token, if (text.isBlank()) "NO_SPEECH" else "OK", text)
                }
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 700L)
            deadline = Runnable { finish(token, "ERROR", "") }.also { handler.postDelayed(it, 20000) }
            sr.startListening(intent)
        } catch (_: Throwable) { finish(token, "UNAVAILABLE", "") }
    }
    private fun finish(token: Int, status: String, text: String) {
        if (token != generation || pending == null) return
        Log.i("EgeSTT", "FINISH status=$status characters=${text.length}")
        val result = pending
        pending = null
        generation++
        deadline?.let { handler.removeCallbacks(it) }; deadline = null
        val old = recognizer; recognizer = null
        try { old?.cancel(); old?.destroy() } catch (_: Throwable) {}
        result?.success(mapOf("status" to status, "text" to text))
    }
    fun stop() { try { recognizer?.stopListening() } catch (_: Throwable) { cancel() } }
    fun cancel() { finish(generation, "CANCELLED", "") }
}
