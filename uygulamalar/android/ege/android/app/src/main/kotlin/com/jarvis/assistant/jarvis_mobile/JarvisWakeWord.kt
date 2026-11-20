package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean
import android.os.Build
import android.util.Log
import kotlin.math.sqrt
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** The foreground service owns both the detector engine and microphone.
 * No Activity, UI lifecycle, or Activity method channel is needed to listen. */
object JarvisWakeWord {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var micGeneration = 0
    @Volatile private var generation = 0
    private var requested = false
    private var active = false
    private var sensitivity = 0.5f
    private var lastError: String? = null
    @Volatile private var pcmFrames = 0L
    @Volatile private var rmsLevel = 0.0
    @Volatile private var silenced = false
    private var decodedSamples = 0L
    private var hits = 0
    private val fallbackBusy = AtomicBoolean(false)
    private val fallbackQueue = WakeClipQueue()
    private var phoneWake: PhoneAudioSpeech? = null
    private val phoneRetry = WakePhoneRetry()
    @Volatile private var fallbackChecks = 0L
    @Volatile private var fallbackLastMs = 0L
    @Volatile private var lastPcmAt = 0L
    private var lastDecodeAt = 0L
    private var listeningSince = 0L
    private var recoveryWindow = 0L
    private var recoveries = 0
    @Volatile private var diagnosticSince = 0L
    @Volatile private var diagnosticUntil = 0L
    @Volatile private var diagnosticPeak = 0.0
    private var diagnosticHits = 0
    private var speakerStatus = "Henüz ses doğrulanmadı"
    private val diagnosticTexts = mutableListOf<String>()

    fun beginDiagnostic(): Boolean {
        if (!active) return false
        diagnosticTexts.clear()
        diagnosticHits = 0
        diagnosticPeak = 0.0
        diagnosticSince = android.os.SystemClock.elapsedRealtime()
        diagnosticUntil = diagnosticSince + 30000
        fallbackQueue.clear()
        return true
    }

    fun endDiagnostic() {
        diagnosticUntil = 0
        diagnosticSince = 0
        diagnosticTexts.clear()
        diagnosticPeak = 0.0
        diagnosticHits = 0
    }
    private var fallbackAvailable = false
    private val pending = mutableListOf<MethodChannel.Result>()

    private const val PREFS = "jarvis_wake_native"
    private const val RESUME_MS = 45000L
    private var resumeRunnable: Runnable? = null
    private var recoverRunnable: Runnable? = null
    private var recoverStep = 0
    private var lastRecoverAt = 0L
    private val recoverDelays = longArrayOf(5000L, 30000L, 120000L, 300000L)

    private fun savePrefs(ctx: Context, enabled: Boolean, value: Float?) {
        try {
            val e = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", enabled)
            if (value != null) e.putFloat("sens", value)
            e.apply()
        } catch (_: Throwable) {}
    }

    fun enabled(ctx: Context): Boolean = try {
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", false)
    } catch (_: Throwable) { false }

    fun savedSensitivity(ctx: Context): Float = try {
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getFloat("sens", 0.5f)
    } catch (_: Throwable) { 0.5f }

    private fun cancelTimers() {
        resumeRunnable?.let { handler.removeCallbacks(it) }
        resumeRunnable = null
        recoverRunnable?.let { handler.removeCallbacks(it) }
        recoverRunnable = null
    }

    private val noopResult = object : MethodChannel.Result {
        override fun success(result: Any?) {}
        override fun error(code: String, message: String?, details: Any?) {}
        override fun notImplemented() {}
    }

    /** Dart olmadan yerel başlatma (servis yeniden başlatma, devir sonrası dönüş). */
    fun start(ctx: Context, value: Float) = start(ctx.applicationContext, value, noopResult)

    /** Kayıtlı ayara göre, açıksa hemen yeniden başlat. */
    fun resumeIfEnabled(ctx: Context) {
        val app = ctx.applicationContext
        cancelTimers()
        if (!enabled(app) || active || requested) return
        start(app, savedSensitivity(app))
    }

    private fun scheduleResume(ctx: Context) {
        val app = ctx.applicationContext
        resumeRunnable?.let { handler.removeCallbacks(it) }
        val r = object : Runnable {
            override fun run() {
                resumeRunnable = null
                if (!enabled(app) || active || requested) return
                if (JarvisKeepAlive.active().contains("live")) {
                    resumeRunnable = this
                    handler.postDelayed(this, RESUME_MS)
                    return
                }
                Log.i("JarvisWake", "NATIVE_RESUME")
                start(app, savedSensitivity(app))
            }
        }
        resumeRunnable = r
        handler.postDelayed(r, RESUME_MS)
    }

    fun start(ctx: Context, value: Float, result: MethodChannel.Result) {
        if (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.success("Mikrofon izni gerekli."); return
        }
        if (!JarvisAssistantRole.isDefault(ctx)) {
            result.success("Diğer uygulamalardan açılmak için Ege'yi varsayılan dijital asistan seçin."); return
        }
        cancelTimers()
        savePrefs(ctx, true, value)
        if (active) { result.success("OK"); return }
        pending.add(result)
        if (requested) return
        requested = true
        listeningSince = android.os.SystemClock.elapsedRealtime()
        lastDecodeAt = listeningSince
        lastPcmAt = listeningSince
        lastError = null
        pcmFrames = 0
        decodedSamples = 0
        sensitivity = value
        val token = ++generation
        JarvisKeepAlive.acquire(ctx, "wake", "Asistan dinlemesi hazırlanıyor")
        handler.postDelayed({
            if (generation == token && !active && requested) fail(ctx, "Uyandırma servisi başlatılamadı veya zaman aşımına uğradı.")
        }, 30000)
    }

    /** Called only after startForeground(MICROPHONE) has succeeded. */
    fun serviceReady(ctx: Context) {
        if (!requested || engine != null) return
        val token = generation
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(ctx.applicationContext)
            loader.ensureInitializationComplete(ctx.applicationContext, null)
            val e = FlutterEngine(ctx.applicationContext)
            engine = e
            val ch = MethodChannel(e.dartExecutor.binaryMessenger, "com.jarvis.assistant/device")
            channel = ch
            ch.setMethodCallHandler { call, result ->
                if (token != generation) { result.success(null); return@setMethodCallHandler }
                when (call.method) {
                    "speakerProfileRead" -> result.success(SpeakerProfileStore.read(ctx))
                    "wakeSpeakerDecision" -> {
                        speakerStatus = call.argument<String>("reason") ?: "Ses doğrulama sonucu alınamadı"
                        Log.i("JarvisWake", "KWS_SPEAKER accepted=${call.argument<Boolean>("accepted")} status=$speakerStatus")
                        result.success(null)
                    }
                    "wakeConfig" -> result.success(sensitivity.toDouble())
                    "startWakeMic" -> result.success(startMic(ctx))
                    "stopWakeMic" -> { stopMic(); result.success(true) }
                    "wakeReady" -> {
                        val error = call.arguments as? String
                        result.success(null)
                        if (error != null) handler.post { fail(ctx, error) }
                        else {
                            active = true
                            JarvisForegroundService.wakePaused = false
                            JarvisWakeNotices.cancel(ctx, JarvisWakeNotices.ID_STOPPED)
                            complete("OK")
                            JarvisKeepAlive.acquire(ctx, "wake", "Asistan de, dinlemeye başlayayım")
                            watchHealth(ctx, token)
                        }
                    }
                    "wakeProgress" -> {
                        decodedSamples = call.argument<Number>("decodedSamples")?.toLong() ?: 0L
                        lastDecodeAt = android.os.SystemClock.elapsedRealtime()
                        result.success(null)
                    }
                    "wakeEngineError" -> {
                        result.success(null)
                        handler.post { if (token == generation) recover(ctx, "Algılayıcı durdu") }
                    }
                    "wakeDetected" -> {
                        result.success(null)
                        handler.post {
                            trigger(ctx, token, "kws")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
            e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "jarvisWakeMain"))
        } catch (t: Throwable) { fail(ctx, "Uyandırma motoru: ${t.message}") }
    }

    private fun startMic(ctx: Context): String {
        stopMic()
        return try {
            val size = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(4096)
            val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size * 2)
            if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return "UNAVAILABLE" }
            recorder = rec
            rec.startRecording()
            val token = micGeneration
            fallbackAvailable = Build.VERSION.SDK_INT >= 33 &&
                android.speech.SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)
            phoneWake = if (fallbackAvailable) PhoneAudioSpeech(ctx.applicationContext) else null
            phoneRetry.reset()
            val speechGate = WakeSpeechGate()
            val session = generation
            Log.i("JarvisWake", "WAKE_ENGINE keyword_spotter=true android_local=$fallbackAvailable whisper=false")
            worker = Thread {
                val samples = ShortArray(1600)
                while (token == micGeneration) {
                    val n = try { rec.read(samples, 0, samples.size) } catch (_: Throwable) { -1 }
                    if (n <= 0) break
                    pcmFrames++
                    lastPcmAt = android.os.SystemClock.elapsedRealtime()
                    var energy = 0.0
                    for (i in 0 until n) { val v = samples[i] / 32768.0; energy += v * v }
                    rmsLevel = sqrt(energy / n)
                    if (android.os.SystemClock.elapsedRealtime() < diagnosticUntil) diagnosticPeak = maxOf(diagnosticPeak, rmsLevel)
                    if (pcmFrames % 50L == 1L) {
                        val muted = if (Build.VERSION.SDK_INT >= 29) rec.activeRecordingConfiguration?.isClientSilenced == true else false
                        handler.post {
                            if (token == micGeneration) {
                                if (silenced != muted) {
                                    silenced = muted
                                    JarvisKeepAlive.acquire(ctx, "wake", if (muted)
                                        "Mikrofon başka uygulama nedeniyle sessize alındı" else "Asistan dinleniyor")
                                }
                                Log.i("JarvisWake", "PCM frames=$pcmFrames decoded=$decodedSamples rms=$rmsLevel silenced=$silenced")
                            }
                        }
                    }
                    val bytes = ByteArray(n * 2)
                    for (i in 0 until n) {
                        bytes[2 * i] = samples[i].toByte()
                        bytes[2 * i + 1] = (samples[i].toInt() shr 8).toByte()
                    }
                    val clip = if (fallbackAvailable) speechGate.accept(bytes, rmsLevel) else null
                    handler.post {
                        if (token == micGeneration) {
                            channel?.invokeMethod("onWakePcm", bytes)
                            if (clip != null && phoneRetry.ready(android.os.SystemClock.elapsedRealtime())) {
                                fallbackQueue.offer(WakeClipQueue.Clip(clip, session, "android_local", android.os.SystemClock.elapsedRealtime()))
                                drainWakeChecks(ctx)
                            }
                        }
                    }
                }
                if (token == micGeneration) handler.post {
                    recover(ctx, "Uyandırma mikrofonu kesildi")
                }
            }.apply { name = "jarvis-service-wake-mic"; start() }
            "OK"
        } catch (t: Throwable) { stopMic(); "Mikrofon: ${t.message}" }
    }

    private fun watchHealth(ctx: Context, token: Int) {
        handler.postDelayed({
            if (token != generation || !active) return@postDelayed
            val now = android.os.SystemClock.elapsedRealtime()
            if (WakeHealth.stalled(now, listeningSince, lastPcmAt, lastDecodeAt, silenced)) {
                recover(ctx, "Ses veya algılayıcı akışı durdu")
            } else watchHealth(ctx, token)
        }, 4000)
    }

    private fun recover(ctx: Context, reason: String) {
        if (!requested && !active) return
        val app = ctx.applicationContext
        val now = android.os.SystemClock.elapsedRealtime()
        // 10 dk sorunsuz çalıştıysa geri çekilme basamağı sıfırlanır.
        if (lastRecoverAt != 0L && now - lastRecoverAt > 600000L) recoverStep = 0
        lastRecoverAt = now
        if (recoverStep >= 8) { giveUp(app, reason); return }
        val delay = recoverDelays[minOf(recoverStep, recoverDelays.size - 1)]
        recoverStep++
        Log.w("JarvisWake", "RECOVER attempt=$recoverStep delayMs=$delay reason=$reason")
        val value = sensitivity
        pause()
        JarvisKeepAlive.acquire(app, "wake", "Asistan yeniden başlatılıyor")
        recoverRunnable?.let { handler.removeCallbacks(it) }
        val r = Runnable {
            recoverRunnable = null
            if (enabled(app) && !active && !requested) start(app, value)
        }
        recoverRunnable = r
        handler.postDelayed(r, delay)
    }

    private fun giveUp(ctx: Context, reason: String) {
        lastError = "$reason. Yeniden başlatma denemeleri başarısız."
        MainActivity.instance?.notifyFlutter("onWakeError", lastError)
        halt(ctx)
        JarvisWakeNotices.post(ctx, JarvisWakeNotices.ID_STOPPED, "Asistan dinlemesi durdu, yeniden başlatmak için dokun", true)
    }

    /** Android consumes bounded PCM clips, never a second microphone or Whisper. */
    private fun drainWakeChecks(ctx: Context) {
        if (!active || !phoneRetry.ready(android.os.SystemClock.elapsedRealtime())) return
        val decoder = phoneWake ?: return
        if (!fallbackBusy.compareAndSet(false, true)) return
        val clip = fallbackQueue.take(generation, android.os.SystemClock.elapsedRealtime())
        if (clip == null) { fallbackBusy.set(false); return }
        val started = android.os.SystemClock.elapsedRealtime()
        fun done() {
            if (clip.generation != generation) return
            fallbackBusy.set(false)
            if (fallbackQueue.hasPending()) {
                handler.post { drainWakeChecks(ctx) }
            }
        }
        decoder.start(clip.pcm, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (clip.generation != generation) { done(); return }
                val data = result as? Map<*, *>
                val status = data?.get("status")?.toString() ?: "UNAVAILABLE"
                val text = data?.get("text")?.toString().orEmpty()
                val match = status == "OK" && WakePhrasePolicy.matches(text)
                fallbackChecks++
                fallbackLastMs = android.os.SystemClock.elapsedRealtime() - started
                phoneRetry.complete(status, android.os.SystemClock.elapsedRealtime())
                if (diagnosticSince != 0L && clip.at >= diagnosticSince && clip.at <= diagnosticUntil) {
                    diagnosticTexts.add("Android TR: " + if (status == "OK") text.take(160).ifBlank { "(konuşma yok)" } else status)
                    while (diagnosticTexts.size > 4) diagnosticTexts.removeAt(0)
                }
                Log.i("JarvisWake", "ANDROID_CHECK status=$status wake=$match ms=$fallbackLastMs")
                if (!match) { done(); return }
                if (!SpeakerProfileStore.enabled(ctx)) {
                    trigger(ctx, clip.generation, "android_local")
                    done(); return
                }
                val ch = channel
                if (ch == null) { done(); return }
                // Verify exactly the clip recognized as the wake phrase, not
                // the current ring buffer which may now contain another voice.
                ch.invokeMethod("verifyWakeVoice", mapOf("wav" to JarvisRecognitionService.wavOf(clip.pcm, 16000)), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (clip.generation == generation) {
                            val voice = result as? Map<*, *>
                            val accepted = voice?.get("accepted") == true
                            speakerStatus = voice?.get("reason")?.toString() ?: "Ses doğrulama sonucu alınamadı"
                            Log.i("JarvisWake", "ANDROID_SPEAKER accepted=$accepted status=$speakerStatus")
                            if (accepted) trigger(ctx, clip.generation, "android_local_verified")
                        }
                        done()
                    }
                    override fun error(code: String, message: String?, details: Any?) { done() }
                    override fun notImplemented() { done() }
                })
            }
            override fun error(code: String, message: String?, details: Any?) {
                if (clip.generation == generation) phoneRetry.complete("UNAVAILABLE", android.os.SystemClock.elapsedRealtime())
                done()
            }
            override fun notImplemented() { error("UNAVAILABLE", null, null) }
        })
    }

    private fun trigger(ctx: Context, token: Int, origin: String) {
        if (token != generation || !active) return
        if (android.os.SystemClock.elapsedRealtime() < diagnosticUntil) {
            diagnosticHits++
            Log.i("JarvisWake", "DIAGNOSTIC_HIT source=$origin")
            return
        }
        hits++
        Log.i("JarvisWake", "HIT source=$origin count=$hits frames=$pcmFrames decoded=$decodedSamples")
        pause()
        val shown = JarvisVoiceInteractionService.show()
        Log.i("JarvisWake", "SHOW_ASSISTANT accepted=$shown")
        if (!shown) {
            lastError = "Asistan penceresi açılamadı. Ege'yi varsayılan asistan olarak kontrol edin."
            MainActivity.instance?.notifyFlutter("onWakeError", lastError)
            JarvisKeepAlive.release(ctx, "wake")
        } else {
            // Devir sırasında mikrofon bırakıldı; Dart dönmezse yerel olarak sürdür.
            JarvisForegroundService.wakePaused = true
            JarvisKeepAlive.acquire(ctx, "wake", "Asistan duraklatıldı")
            scheduleResume(ctx)
        }
    }

    private fun stopMic() {
        micGeneration++
        val decoder = phoneWake
        phoneWake = null
        decoder?.cancel()
        fallbackBusy.set(false)
        fallbackQueue.clear()
        val rec = recorder
        recorder = null
        try { rec?.stop() } catch (_: Throwable) {}
        try { worker?.join(500) } catch (_: Throwable) {}
        worker = null
        try { rec?.release() } catch (_: Throwable) {}
    }

    private fun complete(message: String) {
        val callbacks = pending.toList()
        pending.clear()
        callbacks.forEach { it.success(message) }
    }

    /** Release the microphone for STT/TTS but keep the foreground service alive. */
    fun pause() {
        generation++
        fallbackQueue.clear()
        requested = false
        active = false
        complete("Dinleme durduruldu.")
        stopMic()
        channel?.setMethodCallHandler(null)
        channel = null
        val old = engine
        engine = null
        old?.destroy()
    }

    /** Kullanıcı/Dart kapattı: kalıcı olarak devre dışı. */
    fun stop(ctx: Context) {
        savePrefs(ctx, false, null)
        JarvisWakeNotices.cancel(ctx, JarvisWakeNotices.ID_STOPPED)
        halt(ctx)
    }

    private fun halt(ctx: Context) {
        cancelTimers()
        pause()
        JarvisKeepAlive.release(ctx, "wake")
    }

    fun fail(ctx: Context, error: String) {
        lastError = error
        complete(error)
        MainActivity.instance?.notifyFlutter("onWakeError", error)
        // Ayar açık kalır (geçici hata olabilir); yerel yeniden başlatmada tekrar denenir.
        halt(ctx)
    }

    fun info(ctx: Context): Map<String, Any> = mapOf(
        "active" to active, "starting" to requested, "error" to (lastError ?: ""),
        "serviceOwned" to true, "pcmFrames" to pcmFrames, "decodedSamples" to decodedSamples,
        "rms" to rmsLevel, "silenced" to silenced, "hits" to hits, "localFallback" to fallbackAvailable,
        "localChecks" to fallbackChecks, "localLastMs" to fallbackLastMs,
        "diagnosticActive" to (android.os.SystemClock.elapsedRealtime() < diagnosticUntil),
        "diagnosticPeak" to diagnosticPeak, "diagnosticHits" to diagnosticHits,
        "diagnosticTexts" to diagnosticTexts.toList(),
        "speakerFilter" to SpeakerProfileStore.enabled(ctx), "speakerStatus" to speakerStatus,
        "pcmAgeMs" to if (lastPcmAt == 0L) -1 else android.os.SystemClock.elapsedRealtime() - lastPcmAt)
}
