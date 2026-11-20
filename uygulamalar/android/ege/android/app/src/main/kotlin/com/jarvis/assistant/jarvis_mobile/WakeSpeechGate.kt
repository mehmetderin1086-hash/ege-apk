package com.jarvis.assistant.jarvis_mobile

import java.io.ByteArrayOutputStream
import java.util.Locale

/** Small utterances only; no continuous audio storage or network calls. */
class WakeSpeechGate {
    private var noise = 0.0002
    private val pre = java.util.ArrayDeque<ByteArray>()
    private var audio: ByteArrayOutputStream? = null
    private var speech = 0
    private var quiet = 0
    private var chunks = 0
    private val tail = java.util.ArrayDeque<ByteArray>()
    private val levels = java.util.ArrayDeque<Double>()
    private var levelTicks = 0
    fun accept(pcm: ByteArray, rms: Double): ByteArray? {
        levels.add(rms)
        if (levels.size > 50) levels.removeFirst()
        // A constant fan/room noise must not keep STT decoding continuously.
        // Lower-percentile calibration leaves short louder phrases detectable.
        if (++levelTicks % 5 == 0 && levels.size >= 20) {
            noise = levels.sorted()[levels.size / 5].coerceIn(0.00005, 0.003)
        }
        val voiced = rms > maxOf(0.0006, noise * 2.5)
        if (!voiced) noise = (noise * 0.98 + rms * 0.02).coerceIn(0.00005, 0.003)
        if (audio == null) {
            if (!voiced) {
                pre.add(pcm)
                if (pre.size > 3) pre.removeFirst()
                return null
            }
            audio = ByteArrayOutputStream()
            pre.forEach { audio!!.write(it) }
            pre.clear()
            tail.clear()
            speech = 0; quiet = 0; chunks = 0
        }
        audio!!.write(pcm)
        tail.add(pcm)
        if (tail.size > 8) tail.removeFirst()
        chunks++
        if (voiced) { speech++; quiet = 0 } else quiet++
        if (quiet < 5 && chunks < 35) return null
        val clip = if (speech >= 4) audio!!.toByteArray() else null
        audio = null
        // A hard window boundary can split "Hey" from "Jarvis". Retain an
        // 800 ms overlap only for continuous speech; never stop listening.
        if (quiet < 5) pre.addAll(tail)
        tail.clear()
        return clip
    }
}

object WakePhrasePolicy {
    fun matchesEnglishFallback(text: String): Boolean =
        matches(text) || text.trim().equals("assistant", ignoreCase = true)

    fun needsEnglishFallback(turkishMatched: Boolean, pcmBytes: Int): Boolean =
        !turkishMatched && pcmBytes in 16000..144000 // 0.5–4.5 s, PCM16/16 kHz

    fun matches(text: String): Boolean {
        val t = text.lowercase(Locale.forLanguageTag("tr"))
            .replace('ı','i').replace('ü','u').replace('ö','o').replace('ş','s').replace('ç','c').replace('ğ','g')
            .replace(Regex("[^a-z ]"), " ").trim().replace(Regex(" +"), " ")
        return t == "asistan" || t.startsWith("asistan ")
    }
}

/** One pending speech clip, rather than dropping every clip while ASR is busy. */
internal class WakeClipQueue {
    data class Clip(val pcm: ByteArray, val generation: Int, val model: String, val at: Long)
    private var pending: Clip? = null
    @Synchronized fun offer(clip: Clip) { pending = clip }
    @Synchronized fun clear() { pending = null }
    @Synchronized fun hasPending() = pending != null
    @Synchronized fun take(generation: Int, now: Long): Clip? {
        val clip = pending
        pending = null
        return clip?.takeIf { it.generation == generation && now - it.at <= 8000 }
    }
}

internal object WakeHealth {
    fun stalled(now: Long, started: Long, pcm: Long, decoded: Long, silenced: Boolean): Boolean =
        !silenced && now - started >= 12000 && (now - pcm > 3000 || now - decoded > 7000)
}

/** Missing language packs must not cause a recognizer restart on every sound. */
internal class WakePhoneRetry {
    private var nextAt = 0L
    fun ready(now: Long) = now >= nextAt
    fun reset() { nextAt = 0L }
    fun complete(status: String, now: Long) {
        val delay = when (status) {
            "OK", "NO_SPEECH", "ERROR_6", "ERROR_7", "CANCELLED" -> 0L
            "ERROR_12", "ERROR_13", "SOURCE_UNSUPPORTED", "UNAVAILABLE" -> 60000L
            else -> 5000L
        }
        nextAt = now + delay
    }
}
