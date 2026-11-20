package com.jarvis.assistant.jarvis_mobile

import android.os.Build
import android.os.SystemClock
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min

/** JNI surface of libjarvis_whisper.so (whisper.cpp). */
object WhisperNative {
    @Volatile
    private var state = 0 // 0 = not tried, 1 = loaded, -1 = unavailable
    var loadError = ""
        private set

    /** arm64 build uses ARMv8.2 dot-product + fp16 instructions. */
    fun cpuSupported(): Boolean {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: ""
        return when (abi) {
            "arm64-v8a" -> try {
                val info = File("/proc/cpuinfo").readText()
                info.contains("asimddp") && (info.contains("asimdhp") || info.contains("fphp"))
            } catch (_: Throwable) {
                false
            }
            "x86_64" -> true
            else -> false
        }
    }

    @Synchronized
    fun ensureLoaded(): Boolean {
        if (state == 1) return true
        if (state == -1) return false
        if (!cpuSupported()) {
            state = -1
            loadError = "Bu işlemci yerel Whisper için gereken ARMv8.2 (dotprod) desteğine sahip değil."
            return false
        }
        return try {
            System.loadLibrary("jarvis_whisper")
            state = 1
            true
        } catch (t: Throwable) {
            state = -1
            loadError = "Whisper kütüphanesi yüklenemedi: ${t.message}"
            false
        }
    }

    @JvmStatic external fun initContext(modelPath: String): Long
    @JvmStatic external fun freeContext(ctx: Long)
    @JvmStatic external fun transcribe(
        ctx: Long,
        audio: FloatArray,
        language: String,
        threads: Int,
        audioCtx: Int,
        prompt: String,
    ): ByteArray?
    @JvmStatic external fun systemInfo(): String
}

/** Keeps the model loaded between requests and converts WAV to 16 kHz mono floats. */
object JarvisWhisper {
    // Explicit product choice: Android local STT only, including legacy callers.
    private var enabled = false
    private var ctx = 0L
    private var ctxPath = ""

    private fun fail(msg: String) = mapOf("ok" to false, "error" to msg)

    /**
     * realme 10 (Helio G99, 2 büyük + 6 küçük çekirdek) ölçümü, base modeli,
     * 4,75 sn Türkçe: 2 çekirdek 6,0 sn · 4 → 5,0 · 6 → 4,3 · 8 → 4,2 sn.
     * ggml işleri parça parça dağıttığı için küçük çekirdekler de katkı veriyor.
     * Ama uygulama içinde arayüz/ses/uyandırma iş parçacıkları da çalıştığından
     * 8 iş parçacığı çekirdekleri aşırı yükleyip çözümü 2-3 kat yavaşlattı
     * (telefon kaydı: Tiny 3 sn ses → 4 sn). 2 çekirdek arayüze bırakılır.
     */
    fun defaultThreads(): Int = min(6, max(1, Runtime.getRuntime().availableProcessors() - 2))

    @Synchronized
    fun transcribe(
        modelPath: String,
        wav: ByteArray,
        language: String,
        fast: Boolean,
        prompt: String,
        threads: Int = 0,
    ): Map<String, Any> {
        if (!enabled) return fail("Whisper devre dışı. Android yerel STT kullanılır.")
        if (!WhisperNative.ensureLoaded()) return fail(WhisperNative.loadError)
        if (!File(modelPath).exists()) return fail("Whisper modeli bulunamadı; Ayarlar → Konuşma Tanıma'dan indirin.")
        val t0 = SystemClock.elapsedRealtime()
        if (ctx == 0L || ctxPath != modelPath) {
            if (ctx != 0L) WhisperNative.freeContext(ctx)
            ctx = WhisperNative.initContext(modelPath)
            ctxPath = modelPath
            if (ctx == 0L) {
                ctxPath = ""
                return fail("Whisper modeli yüklenemedi (dosya bozuk olabilir, yeniden indirin).")
            }
        }
        val t1 = SystemClock.elapsedRealtime()
        val pcm = wavToFloat16k(wav) ?: return fail("Ses biçimi okunamadı.")
        val seconds = pcm.size / 16000.0
        if (pcm.size < 3200) return mapOf("ok" to true, "text" to "", "seconds" to seconds, "loadMs" to (t1 - t0), "ms" to 0L)
        // Whisper works on >=1 s windows; pad very short clips with silence.
        val audio = if (pcm.size < 16000) pcm.copyOf(16000) else pcm
        // Kısa komutlarda küçük kodlayıcı penceresi = telefonda çok daha hızlı.
        // Ölçüm (base, 8 çekirdek): 1500 → 4,2 sn · 768 → 2,6 sn · 512 → 2,1 sn.
        // 384'te kod çözücü takılıp 9-10 sn'ye çıktı; alt sınır 512.
        val audioCtx = if (fast && seconds < 28) min(1500, max(512, (seconds * 50).toInt() + 96)) else 0
        val useThreads = if (threads in 1..16) threads else defaultThreads()
        val bytes = WhisperNative.transcribe(ctx, audio, language, useThreads, audioCtx, prompt)
            ?: return fail("Whisper çözümleme başarısız.")
        val t2 = SystemClock.elapsedRealtime()
        return mapOf(
            "ok" to true,
            "text" to String(bytes, Charsets.UTF_8).trim(),
            "seconds" to seconds,
            "loadMs" to (t1 - t0),
            "ms" to (t2 - t1),
            "threads" to useThreads,
            "audioCtx" to audioCtx,
        ).also {
            android.util.Log.i(
                "JarvisWhisper",
                "cozuldu: ses=${"%.1f".format(seconds)}sn yukleme=${t1 - t0}ms cozme=${t2 - t1}ms " +
                    "cekirdek=$useThreads ctx=$audioCtx",
            )
        }
    }

    @Synchronized
    fun release() {
        if (ctx != 0L) WhisperNative.freeContext(ctx)
        ctx = 0L
        ctxPath = ""
    }

    fun info(): Map<String, Any> {
        val supported = WhisperNative.cpuSupported()
        val loaded = supported && WhisperNative.ensureLoaded()
        return mapOf(
            "supported" to supported,
            "loaded" to loaded,
            "error" to WhisperNative.loadError,
            "system" to (if (loaded) WhisperNative.systemInfo() else ""),
            "threads" to defaultThreads(),
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
        )
    }

    /** RIFF/WAV (PCM16 / PCM8 / float32, any channels / rate) -> 16 kHz mono floats. */
    fun wavToFloat16k(wav: ByteArray): FloatArray? {
        val buf = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        var channels = 1
        var rate = 16000
        var bits = 16
        var format = 1
        var dataOff = -1
        var dataLen = 0
        if (wav.size >= 12 && String(wav, 0, 4, Charsets.US_ASCII) == "RIFF" &&
            String(wav, 8, 4, Charsets.US_ASCII) == "WAVE"
        ) {
            var pos = 12
            while (pos + 8 <= wav.size) {
                val id = String(wav, pos, 4, Charsets.US_ASCII)
                val size = buf.getInt(pos + 4)
                val body = pos + 8
                if (id == "fmt " && body + 16 <= wav.size) {
                    format = buf.getShort(body).toInt() and 0xFFFF
                    channels = max(1, buf.getShort(body + 2).toInt())
                    rate = buf.getInt(body + 4)
                    bits = buf.getShort(body + 14).toInt()
                    if (format == 0xFFFE && size >= 40 && body + 26 <= wav.size) {
                        format = buf.getShort(body + 24).toInt() and 0xFFFF
                    }
                } else if (id == "data") {
                    dataOff = body
                    dataLen = if (size <= 0 || body + size > wav.size) wav.size - body else size
                    break
                }
                pos = body + size + (size and 1)
                if (size < 0) break
            }
            if (dataOff < 0) return null
        } else {
            dataOff = 0 // raw PCM16 mono 16 kHz
            dataLen = wav.size
        }
        val bytesPerSample = max(1, bits / 8)
        val frames = dataLen / (bytesPerSample * channels)
        if (frames <= 0) return FloatArray(0)
        val mono = FloatArray(frames)
        for (f in 0 until frames) {
            var acc = 0f
            for (c in 0 until channels) {
                val o = dataOff + (f * channels + c) * bytesPerSample
                acc += when {
                    format == 3 && bits == 32 -> buf.getFloat(o)
                    bits == 16 -> buf.getShort(o) / 32768f
                    bits == 8 -> ((wav[o].toInt() and 0xFF) - 128) / 128f
                    bits == 24 -> {
                        val v = (wav[o].toInt() and 0xFF) or ((wav[o + 1].toInt() and 0xFF) shl 8) or (wav[o + 2].toInt() shl 16)
                        v / 8388608f
                    }
                    bits == 32 -> buf.getInt(o) / 2147483648f
                    else -> 0f
                }
            }
            mono[f] = acc / channels
        }
        if (rate == 16000 || rate <= 0) return mono
        // Linear resampling to 16 kHz.
        val outLen = (frames.toLong() * 16000 / rate).toInt()
        val out = FloatArray(outLen)
        val step = rate / 16000.0
        for (i in 0 until outLen) {
            val src = i * step
            val i0 = src.toInt()
            val frac = (src - i0).toFloat()
            val a = mono[min(i0, frames - 1)]
            val b = mono[min(i0 + 1, frames - 1)]
            out[i] = a + (b - a) * frac
        }
        return out
    }
}
