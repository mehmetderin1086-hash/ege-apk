package com.jarvis.assistant.jarvis_mobile

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Uyarlanabilir, enerji tabanlı konuşma algılayıcı (VAD).
 *
 * Eski sürüm sabit bir RMS eşiği (0.032) kullanıyordu; realme'nin
 * VOICE_RECOGNITION mikrofonunda normal konuşma bu eşiği hiç geçmediği için
 * uygulama konuşmayı fark etmiyor, 7 sn "sessizlik" bekleyip tüm kaydı
 * Whisper'a veriyordu (yavaş ve çoğu zaman boş sonuç).
 *
 * Burada gürültü tabanı "minimum istatistikleri" ile izlenir: son ~2 sn'deki
 * en sessiz karelerin seviyesi. Kullanıcı kayda başlar başlamaz konuşsa bile
 * kelime aralarındaki boşluklar tabanı doğru yere çeker. Konuşma başlangıcı
 * için yüksek, devam için daha düşük eşik (histerezis) kullanılır.
 */
class AdaptiveVad(
    private val sampleRate: Int = 16000,
    private val endSilenceMs: Int = 900,
    private val noSpeechTimeoutMs: Int = 7000,
    private val maxCaptureMs: Int = 45000,
) {
    enum class End { NONE, SPEECH_ENDED, NO_SPEECH, MAX_LENGTH }

    var noiseFloor = 0.0
        private set
    var peakRms = 0.0
        private set
    var speechMs = 0
        private set
    var heardSpeech = false
        private set
    /** Konuşmanın başladığı örnek (yaklaşık), -1 = yok. */
    var speechStartSample = -1L
        private set
    /** Son konuşma karesinin bittiği örnek, -1 = yok. */
    var lastSpeechSample = -1L
        private set
    var endReason = End.NONE
        private set
    var processedSamples = 0L
        private set

    private val history = DoubleArray(40) // ~2 sn (50 ms kareler)
    private var historyCount = 0
    private var historyPos = 0
    private var silenceMs = 0
    private var aboveRunMs = 0
    private var runStartSample = 0L

    private fun floorEstimate(): Double {
        if (historyCount == 0) return 0.002
        var m = Double.MAX_VALUE
        for (i in 0 until historyCount) m = min(m, history[i])
        return m.coerceIn(0.0008, 0.03)
    }

    /** Konuşma başlangıcı eşiği. */
    fun startThreshold(): Double = max(noiseFloor * 3.0, 0.0045)

    /** Konuşma devamı eşiği (daha düşük; yumuşak heceler kesilmesin). */
    fun keepThreshold(): Double = max(noiseFloor * 2.0, 0.0030)

    /** Arayüzdeki ses halkası için 0..1 seviye (gürültüye göre). */
    fun level(rms: Double): Double =
        ((rms - noiseFloor) / max(noiseFloor * 14.0, 0.035)).coerceIn(0.0, 1.0)

    /**
     * Bir kareyi işler. Dönüş değeri [End.NONE] dışında bir şeyse kayıt
     * durdurulmalıdır.
     */
    fun process(rms: Double, frameSamples: Int): End {
        if (endReason != End.NONE) return endReason
        val frameMs = max(1, frameSamples * 1000 / sampleRate)
        val frameStart = processedSamples
        processedSamples += frameSamples
        if (rms > peakRms) peakRms = rms

        history[historyPos] = rms
        historyPos = (historyPos + 1) % history.size
        if (historyCount < history.size) historyCount++
        noiseFloor = floorEstimate()

        // İlk 150 ms yalnızca tabanı öğrenir.
        if (processedSamples < sampleRate * 15 / 100) return End.NONE

        val threshold = if (heardSpeech) keepThreshold() else startThreshold()
        if (rms >= threshold) {
            if (aboveRunMs == 0) runStartSample = frameStart
            aboveRunMs += frameMs
            silenceMs = 0
            if (!heardSpeech && aboveRunMs >= 100) {
                heardSpeech = true
                speechStartSample = runStartSample
            }
            if (heardSpeech) {
                speechMs += frameMs
                lastSpeechSample = processedSamples
            }
        } else {
            aboveRunMs = 0
            silenceMs += frameMs
        }

        val elapsedMs = (processedSamples * 1000 / sampleRate).toInt()
        endReason = when {
            heardSpeech && silenceMs >= endSilenceMs -> End.SPEECH_ENDED
            !heardSpeech && elapsedMs >= noSpeechTimeoutMs -> End.NO_SPEECH
            elapsedMs >= maxCaptureMs -> End.MAX_LENGTH
            else -> End.NONE
        }
        return endReason
    }

    companion object {
        fun rms(buf: ShortArray, count: Int): Double {
            if (count <= 0) return 0.0
            var sumSq = 0.0
            for (i in 0 until count) {
                val s = buf[i].toDouble()
                sumSq += s * s
            }
            return sqrt(sumSq / count) / 32768.0
        }

        /**
         * Kaydı konuşma bölgesine kırpar (başta 350 ms, sonda 450 ms pay) ve
         * kısık sesi tepe ~0.6 olacak şekilde yükseltir (en çok 6 kat).
         * [pcm] 16 bit little-endian mono.
         */
        fun trimAndNormalize(
            pcm: ByteArray,
            sampleRate: Int,
            speechStartSample: Long,
            lastSpeechSample: Long,
        ): ByteArray {
            val totalSamples = pcm.size / 2
            if (totalSamples == 0) return pcm
            var start = 0
            var end = totalSamples
            if (speechStartSample >= 0 && lastSpeechSample > speechStartSample) {
                // Konuşma ilk 1.5 sn içinde başladıysa baştan kırpma (taban
                // tahmini erken konuşmada geç kalabilir).
                val startCut = speechStartSample - sampleRate * 35 / 100
                start = if (speechStartSample < sampleRate * 3 / 2) 0 else max(0L, startCut).toInt()
                end = min(totalSamples.toLong(), lastSpeechSample + sampleRate * 45 / 100).toInt()
                if (end - start < sampleRate / 2) {
                    start = 0
                    end = totalSamples
                }
            }
            var peak = 1
            for (i in start until end) {
                val v = abs(readSample(pcm, i))
                if (v > peak) peak = v
            }
            val gain = (0.6 * 32767.0 / peak).coerceIn(1.0, 6.0)
            val out = ByteArray((end - start) * 2)
            for (i in start until end) {
                var v = readSample(pcm, i)
                if (gain > 1.01) v = (v * gain).toInt().coerceIn(-32768, 32767)
                val o = (i - start) * 2
                out[o] = (v and 0xFF).toByte()
                out[o + 1] = ((v shr 8) and 0xFF).toByte()
            }
            return out
        }

        private fun readSample(pcm: ByteArray, i: Int): Int {
            val lo = pcm[i * 2].toInt() and 0xFF
            val hi = pcm[i * 2 + 1].toInt()
            return (hi shl 8) or lo
        }
    }
}
