package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque

/** One microphone from playback through the following user turn; no system STT tones. */
class LiveDuplexCapture(private val activity: MainActivity) {
    private class Session(val token: Int, val recorder: AudioRecord) {
        @Volatile var active = true
        @Volatile var playback = true
        @Volatile var playbackEndedAt = 0L
        @Volatile var speakerDecision: Boolean? = null
        var worker: Thread? = null
    }
    private var current: Session? = null

    fun start(token: Int, allowBarge: Boolean, requireSpeaker: Boolean): Map<String, Any> {
        stop()
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return mapOf("status" to "PERMISSION_NEEDED", "bargeIn" to false)
        }
        var recorder: AudioRecord? = null
        var echo: AcousticEchoCanceler? = null
        try {
            val size = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(4096)
            recorder = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, 16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size * 2)
            if (recorder.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("microphone")
            if (AcousticEchoCanceler.isAvailable()) {
                echo = AcousticEchoCanceler.create(recorder.audioSessionId)
                echo?.enabled = true
            }
            val canBarge = allowBarge && echo?.enabled == true
            val session = Session(token, recorder)
            current = session
            recorder.startRecording()
            val effect = echo
            session.worker = Thread({ capture(session, effect, canBarge, requireSpeaker) }, "ege-live-duplex").also { it.start() }
            android.util.Log.i("EgeLive", "duplex started token=$token aec=${echo?.enabled} barge=$canBarge")
            return mapOf("status" to "OK", "bargeIn" to canBarge)
        } catch (_: Throwable) {
            current = null
            try { echo?.release() } catch (_: Throwable) {}
            try { recorder?.release() } catch (_: Throwable) {}
            return mapOf("status" to "UNAVAILABLE", "bargeIn" to false)
        }
    }

    fun speakerDecision(token: Int, accepted: Boolean) {
        current?.takeIf { it.token == token }?.speakerDecision = accepted
    }

    fun playbackEnded(token: Int) {
        current?.takeIf { it.token == token }?.let {
            it.playbackEndedAt = SystemClock.elapsedRealtime()
            it.playback = false
        }
    }

    fun stop() {
        val session = current ?: return
        current = null
        session.active = false
        try { session.recorder.stop() } catch (_: Throwable) {}
        // The worker owns release; never release a recorder underneath a read.
    }

    private fun event(session: Session, name: String, extra: Map<String, Any> = emptyMap()) {
        activity.runOnUiThread {
            if (current === session && session.active) {
                activity.notifyFlutter("onDuplexCapture", mapOf("token" to session.token, "event" to name) + extra)
            }
        }
    }

    private fun capture(s: Session, echo: AcousticEchoCanceler?, canBarge: Boolean, requireSpeaker: Boolean) {
        val samples = ShortArray(320)
        val preRoll = ArrayDeque<ByteArray>() // 400 ms, retains the beginning of an interruption.
        val output = ByteArrayOutputStream()
        var gate = BargeGate()
        var candidateSent = false
        var speakerAccepted = !requireSpeaker
        var started = false
        var interrupted = false
        var silenceMs = 0
        var speechMs = 0
        var candidateMs = 0
        var listeningMs = 0
        var totalMs = 0
        var lastLevelMs = 0
        var noise = 0.003
        try {
            while (s.active && totalMs < 240000) {
                val count = s.recorder.read(samples, 0, samples.size)
                if (count < 0) throw IllegalStateException("microphone read $count")
                if (count == 0) continue
                val ms = count * 1000 / 16000
                totalMs += ms
                val rms = AdaptiveVad.rms(samples, count)
                val bytes = ByteArray(count * 2)
                for (i in 0 until count) {
                    bytes[i * 2] = samples[i].toByte()
                    bytes[i * 2 + 1] = (samples[i].toInt() shr 8).toByte()
                }
                if (!started && s.playback) {
                    preRoll.addLast(bytes)
                    while (preRoll.size > 20) preRoll.removeFirst()
                    if (canBarge && gate.process(rms, ms)) {
                        started = true
                        interrupted = true
                        speechMs = 180
                        preRoll.forEach { output.write(it) }
                        preRoll.clear()
                        if (!requireSpeaker) event(s, "speech")
                        android.util.Log.i("EgeLive", "barge detected token=${s.token}")
                    }
                    continue
                }
                // Let the speaker tail settle only after natural playback completion.
                if (!started && SystemClock.elapsedRealtime() - s.playbackEndedAt < 160) {
                    preRoll.clear()
                    continue
                }
                if (interrupted && requireSpeaker && !speakerAccepted) {
                    val decision = s.speakerDecision
                    if (decision == true) {
                        speakerAccepted = true
                        event(s, "speech")
                    } else if (decision == false || (candidateSent && output.size() > 32000 * 6)) {
                        s.speakerDecision = null
                        candidateSent = false
                        started = false
                        interrupted = false
                        silenceMs = 0
                        speechMs = 0
                        candidateMs = 0
                        listeningMs = 0
                        output.reset()
                        preRoll.clear()
                        gate = BargeGate()
                        continue
                    }
                }
                listeningMs += ms
                val voiced = rms > maxOf(0.008, noise * 2.5)
                if (!started) {
                    preRoll.addLast(bytes)
                    while (preRoll.size > 20) preRoll.removeFirst()
                    if (voiced) candidateMs += ms else {
                        candidateMs = 0
                        noise = noise * 0.98 + rms * 0.02
                    }
                    if (candidateMs >= 100) {
                        started = true
                        speechMs = candidateMs
                        preRoll.forEach { output.write(it) }
                        preRoll.clear()
                    }
                } else {
                    output.write(bytes)
                    if (voiced) { silenceMs = 0; speechMs += ms } else silenceMs += ms
                }
                if (totalMs - lastLevelMs >= 100) {
                    lastLevelMs = totalMs
                    event(s, "level", mapOf("level" to (rms * 12).coerceIn(0.0, 1.0)))
                }
                if (interrupted && requireSpeaker && !speakerAccepted) {
                    if (!candidateSent && output.size() >= 32000 * 1.4) {
                        candidateSent = true
                        event(s, "candidate", mapOf("wav" to wav(output.toByteArray())))
                    }
                    continue
                }
                if ((started && silenceMs >= 560) || listeningMs >= 30000 || (!started && listeningMs >= 12000)) {
                    val pcm = if (speechMs >= 180) AdaptiveVad.trimAndNormalize(output.toByteArray(), 16000, -1, -1) else ByteArray(0)
                    event(s, "audio", mapOf("wav" to if (pcm.isEmpty()) pcm else wav(pcm)))
                    android.util.Log.i("EgeLive", "capture complete token=${s.token} speechMs=$speechMs interrupted=$interrupted")
                    return
                }
            }
            if (s.active) event(s, "error")
        } catch (_: Throwable) {
            if (s.active) event(s, "error")
        } finally {
            try { s.recorder.stop() } catch (_: Throwable) {}
            try { echo?.release() } catch (_: Throwable) {}
            try { s.recorder.release() } catch (_: Throwable) {}
        }
    }

    private fun wav(pcm: ByteArray): ByteArray {
        val out = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
        out.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVEfmt ".toByteArray())
        out.putInt(16).putShort(1).putShort(1).putInt(16000).putInt(32000).putShort(2).putShort(16)
        out.put("data".toByteArray()).putInt(pcm.size).put(pcm)
        return out.array()
    }
}
