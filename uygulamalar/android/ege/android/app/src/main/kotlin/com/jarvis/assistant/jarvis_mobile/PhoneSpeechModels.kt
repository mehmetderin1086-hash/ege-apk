package com.jarvis.assistant.jarvis_mobile

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/** Ask Android to provision Turkish locally. Android shows its own download
 * dialog for every request, so automatic requests are limited to one per week
 * (persisted); only the explicit Settings/Diagnostics button may ask again.
 * While the model is missing the Dart side transcribes recordings in the cloud. */
object PhoneSpeechModels {
    private val handler = Handler(Looper.getMainLooper())
    private var active: SpeechRecognizer? = null
    private var lastAttempt = -60_000L
    private var lastDownload = -60_000L
    private var timeout: Runnable? = null

    private const val PREFS = "ege_stt_model"
    private const val KEY_LAST_PROMPT = "last_download_prompt_ms"
    private const val AUTO_PROMPT_INTERVAL_MS = 7L * 24 * 60 * 60 * 1000
    @Volatile private var forced = false

    fun prepare(context: Context, knownMissing: Boolean = false, force: Boolean = false) {
        if (force) forced = true
        if (Build.VERSION.SDK_INT < 33 || active != null ||
            SystemClock.elapsedRealtime() - (if (knownMissing) lastDownload else lastAttempt) < 60_000L) return
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) return
        lastAttempt = SystemClock.elapsedRealtime()
        try {
            val sr = SpeechRecognizer.createOnDeviceSpeechRecognizer(context.applicationContext)
            active = sr
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "tr-TR")
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            timeout = Runnable { complete(sr, "WAIT_TIMEOUT") }.also { handler.postDelayed(it, 120_000) }
            if (knownMissing) { download(sr, context, intent); return }
            sr.checkRecognitionSupport(intent, context.mainExecutor, object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (active !== sr) return
                    fun List<String>.hasTurkish() = any { it.equals("tr", true) || it.startsWith("tr-", true) || it.startsWith("tr_", true) }
                    when {
                        support.installedOnDeviceLanguages.hasTurkish() -> complete(sr, "READY")
                        support.pendingOnDeviceLanguages.hasTurkish() -> complete(sr, "SCHEDULED")
                        support.supportedOnDeviceLanguages.hasTurkish() -> download(sr, context, intent)
                        else -> complete(sr, "NOT_SUPPORTED")
                    }
                }
                override fun onError(error: Int) { complete(sr, "CHECK_ERROR_$error") }
            })
        } catch (_: Throwable) { active?.let { complete(it, "UNAVAILABLE") } }
    }

    private fun download(sr: SpeechRecognizer, context: Context, intent: Intent) {
        if (active !== sr || Build.VERSION.SDK_INT < 33) return
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val nowWall = System.currentTimeMillis()
        val sinceLast = nowWall - prefs.getLong(KEY_LAST_PROMPT, 0L)
        val userAsked = forced
        forced = false
        if (!userAsked && sinceLast in 0 until AUTO_PROMPT_INTERVAL_MS) {
            complete(sr, "PROMPT_SUPPRESSED")
            return
        }
        prefs.edit().putLong(KEY_LAST_PROMPT, nowWall).apply()
        lastDownload = SystemClock.elapsedRealtime()
        Log.i("EgeSTT", "MODEL language=tr-TR status=REQUESTED")
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                sr.triggerModelDownload(intent, context.mainExecutor, object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {}
                    override fun onSuccess() { complete(sr, "READY") }
                    override fun onScheduled() { complete(sr, "SCHEDULED") }
                    override fun onError(error: Int) {
                        if (active !== sr) return
                        if (error == SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS) {
                            try { sr.triggerModelDownload(intent) } catch (_: Throwable) {}
                        }
                        complete(sr, "DOWNLOAD_ERROR_$error")
                    }
                })
            } else {
                sr.triggerModelDownload(intent)
            }
        } catch (_: Throwable) { complete(sr, "DOWNLOAD_UNAVAILABLE") }
    }

    private fun complete(sr: SpeechRecognizer, status: String) {
        if (active !== sr) return
        active = null
        timeout?.let(handler::removeCallbacks); timeout = null
        Log.i("EgeSTT", "MODEL language=tr-TR status=$status")
        try { sr.destroy() } catch (_: Throwable) {}
    }
}
