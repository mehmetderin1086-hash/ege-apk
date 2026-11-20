package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

// ===========================================================================
// Varsayılan dijital asistan: ana tuşa / güç tuşuna uzun basınca JARVIS açılır
// ve hemen dinler. Kullanıcı "ekran içeriğini kullan" iznini açık bıraktıysa
// ekran görüntüsü de gelir ("ekranda ne var?" soruları için).
// ===========================================================================
class JarvisVoiceInteractionService : VoiceInteractionService() {
    companion object {
        @Volatile var instance: JarvisVoiceInteractionService? = null

        /** "Hey Jarvis" arka planda algılanınca asistan penceresini aç. */
        fun show(): Boolean = try {
            val s = instance ?: return false
            s.showSession(Bundle().apply { putString("jarvis_source", "wake") }, 0)
            true
        } catch (_: Throwable) { false }
    }

    override fun onReady() {
        super.onReady()
        instance = this
    }

    override fun onShutdown() {
        if (instance === this) instance = null
        super.onShutdown()
    }
}

class JarvisVoiceSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = JarvisVoiceSession(this)
}

class JarvisVoiceSession(context: Context) : VoiceInteractionSession(context) {
    private val handler = Handler(Looper.getMainLooper())
    private var launched = false
    private var screenshotPath: String? = null
    private var source = "assist"

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        launched = false
        source = args?.getString("jarvis_source") ?: "assist"
        Log.i("JarvisWake", "SESSION_SHOW source=$source")
        screenshotPath = null
        val wantsShot = (showFlags and SHOW_WITH_SCREENSHOT) != 0
        // Ekran görüntüsü onShow'dan sonra gelir; en çok 900 ms bekle.
        handler.postDelayed({ launch() }, if (wantsShot) 900L else 0L)
    }

    override fun onHandleScreenshot(screenshot: Bitmap?) {
        if (screenshot != null) {
            try {
                val maxSide = 1280
                val scale = minOf(1f, maxSide.toFloat() / max(screenshot.width, screenshot.height))
                val bmp = if (scale < 1f) {
                    Bitmap.createScaledBitmap(screenshot, (screenshot.width * scale).toInt(), (screenshot.height * scale).toInt(), true)
                } else screenshot
                val f = File(context.cacheDir, "assist_screen.jpg")
                FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                screenshotPath = f.absolutePath
            } catch (t: Throwable) {
                Log.w("JarvisAssist", "ekran goruntusu kaydedilemedi: ${t.message}")
            }
        }
        launch()
    }

    private fun launch() {
        if (launched) return
        launched = true
        handler.removeCallbacksAndMessages(null)
        val i = Intent(context, MainActivity::class.java)
            .setAction(MainActivity.ACTION_LISTEN)
            .putExtra("jarvis_source", source)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        screenshotPath?.let { i.putExtra("jarvis_screenshot", it) }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startAssistantActivity(i) else context.startActivity(i)
            Log.i("JarvisWake", "ACTIVITY_LAUNCH source=$source")
        } catch (_: Throwable) {
            try { context.startActivity(i) } catch (_: Throwable) {
                // Etkinlik açılamadı: devir olmayacak, uyandırmayı hemen sürdür.
                JarvisWakeWord.resumeIfEnabled(context)
            }
        }
        hide()
    }

    override fun onHide() {
        handler.removeCallbacksAndMessages(null)
        super.onHide()
    }
}

object JarvisAssistantRole {
    fun isDefault(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val rm = ctx.getSystemService(RoleManager::class.java)
                if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) return rm.isRoleHeld(RoleManager.ROLE_ASSISTANT)
            } catch (_: Throwable) {}
        }
        val cur = try { Settings.Secure.getString(ctx.contentResolver, "assistant") ?: "" } catch (_: Throwable) { "" }
        return cur.contains(ctx.packageName)
    }

    /**
     * ROLE_ASSISTANT uygulamalar tarafından pencereyle istenemez; doğrudan
     * "Varsayılan uygulamalar → Dijital asistan" ekranı açılır.
     */
    fun openSettings(ctx: Context): String {
        val intents = listOf(
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (i in intents) {
            try {
                ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return "SETTINGS"
            } catch (_: Throwable) {}
        }
        return "UNAVAILABLE"
    }
}

// ===========================================================================
// Sistem konuşma tanıma servisi: diğer uygulamaların mikrofon düğmeleri
// (asistan "ses girişi" olarak JARVIS seçilirse) cihazdaki Whisper'ı kullanır;
// internet gerekmez, ses telefondan çıkmaz.
// ===========================================================================
class JarvisRecognitionService : RecognitionService() {
    @Volatile private var running = false
    @Volatile private var stopRequested = false
    private var worker: Thread? = null

    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        val cb = listener ?: return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            cb.error(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS)
            return
        }
        val model = findModel(this)
        if (model == null) {
            Log.w("JarvisRecognition", "Whisper modeli yok")
            cb.error(SpeechRecognizer.ERROR_SERVER)
            return
        }
        if (running) {
            cb.error(SpeechRecognizer.ERROR_RECOGNIZER_BUSY)
            return
        }
        running = true
        stopRequested = false
        val lang = recognizerIntent?.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE)?.substringBefore('-')?.lowercase() ?: "tr"
        worker = Thread {
            try {
                recognize(cb, model, if (lang.length == 2) lang else "tr")
            } catch (t: Throwable) {
                Log.w("JarvisRecognition", "hata: ${t.message}")
                try { cb.error(SpeechRecognizer.ERROR_CLIENT) } catch (_: Throwable) {}
            } finally {
                running = false
            }
        }.apply { name = "jarvis-recognition"; start() }
    }

    private fun recognize(cb: Callback, model: File, lang: String) {
        val rate = 16000
        val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(4096)
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, minBuf * 2)
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            cb.error(SpeechRecognizer.ERROR_AUDIO)
            return
        }
        val vad = AdaptiveVad(rate, 900, 6000, 30000)
        val out = ByteArrayOutputStream()
        val buf = ShortArray(800)
        val bytes = ByteArray(buf.size * 2)
        rec.startRecording()
        cb.readyForSpeech(Bundle())
        var began = false
        try {
            while (!stopRequested) {
                val n = rec.read(buf, 0, buf.size)
                if (n <= 0) continue
                for (i in 0 until n) {
                    val v = buf[i].toInt()
                    bytes[i * 2] = (v and 0xFF).toByte()
                    bytes[i * 2 + 1] = ((v ushr 8) and 0xFF).toByte()
                }
                out.write(bytes, 0, n * 2)
                val rms = AdaptiveVad.rms(buf, n)
                val end = vad.process(rms, n)
                cb.rmsChanged((vad.level(rms) * 10).toFloat())
                if (!began && vad.heardSpeech) {
                    began = true
                    cb.beginningOfSpeech()
                }
                if (end != AdaptiveVad.End.NONE) break
            }
        } finally {
            try { rec.stop() } catch (_: Throwable) {}
            rec.release()
        }
        cb.endOfSpeech()
        if (!vad.heardSpeech) {
            cb.error(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
            return
        }
        val pcm = AdaptiveVad.trimAndNormalize(out.toByteArray(), rate, vad.speechStartSample, vad.lastSpeechSample)
        val wav = wavOf(pcm, rate)
        val r = JarvisWhisper.transcribe(model.absolutePath, wav, lang, true, "", 0)
        val text = (r["text"] as? String)?.trim().orEmpty()
        if (r["ok"] != true || text.isEmpty()) {
            cb.error(SpeechRecognizer.ERROR_NO_MATCH)
            return
        }
        val results = Bundle()
        results.putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text))
        results.putFloatArray(SpeechRecognizer.CONFIDENCE_SCORES, floatArrayOf(0.9f))
        cb.results(results)
    }

    override fun onStopListening(listener: Callback?) {
        stopRequested = true
    }

    override fun onCancel(listener: Callback?) {
        stopRequested = true
    }

    companion object {
        /** Uygulamanın indirdiği Whisper modeli (hızlıdan yavaşa). */
        fun findModel(ctx: Context): File? {
            val dir = File(ctx.filesDir, "whisper")
            for (name in listOf("ggml-base-q5_1.bin", "ggml-small-q5_1.bin", "ggml-tiny-q5_1.bin", "ggml-large-v3-turbo-q5_0.bin")) {
                val f = File(dir, name)
                if (f.isFile && f.length() > 1_000_000) return f
            }
            return null
        }

        fun wavOf(pcm: ByteArray, rate: Int): ByteArray {
            val out = ByteArray(44 + pcm.size)
            fun le32(o: Int, v: Int) { out[o] = v.toByte(); out[o + 1] = (v shr 8).toByte(); out[o + 2] = (v shr 16).toByte(); out[o + 3] = (v shr 24).toByte() }
            fun le16(o: Int, v: Int) { out[o] = v.toByte(); out[o + 1] = (v shr 8).toByte() }
            "RIFF".toByteArray().copyInto(out, 0); le32(4, 36 + pcm.size); "WAVE".toByteArray().copyInto(out, 8)
            "fmt ".toByteArray().copyInto(out, 12); le32(16, 16); le16(20, 1); le16(22, 1); le32(24, rate); le32(28, rate * 2); le16(32, 2); le16(34, 16)
            "data".toByteArray().copyInto(out, 36); le32(40, pcm.size)
            pcm.copyInto(out, 44)
            return out
        }
    }
}
