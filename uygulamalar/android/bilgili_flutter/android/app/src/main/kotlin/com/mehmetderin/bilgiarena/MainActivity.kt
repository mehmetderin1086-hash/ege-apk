package com.mehmetderin.bilgiarena

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.mehmetderin.bilgiarena/native"
        private const val REQ_RECORD_AUDIO = 4101
        private const val REQ_PICK_FILES = 4102
        private const val REQ_SAVE_FILE = 4103
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioExecutor = Executors.newFixedThreadPool(2)

    // TTS state (Edge Neural TTS default: tr-TR-AhmetNeural + System TTS fallback)
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsPlayer: MediaPlayer? = null
    private var currentTtsVoice: String = EdgeTtsClient.DEFAULT_VOICE
    private var activeSpeakToken: Int = 0
    private var pendingSpeakResult: MethodChannel.Result? = null
    private var activeUtteranceId: String? = null

    // SpeechRecognizer state
    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingMicPermResult: MethodChannel.Result? = null

    // Background Music state
    private var mediaPlayer: MediaPlayer? = null
    private var currentMusicTrack: String? = null
    private var currentMusicVolume: Float = 0.35f
    private var musicPausedByLifecycle = false

    // SAF state
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initTts()
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    private fun initTts() {
        if (tts != null) return
        tts = TextToSpeech(applicationContext) { status ->
            ttsReady = (status == TextToSpeech.SUCCESS)
            if (ttsReady) {
                tts?.language = Locale.forLanguageTag("tr-TR")
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        mainHandler.post {
                            if (utteranceId != null && utteranceId == activeUtteranceId) {
                                val res = pendingSpeakResult
                                pendingSpeakResult = null
                                activeUtteranceId = null
                                res?.success(true)
                            }
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        mainHandler.post {
                            if (utteranceId != null && utteranceId == activeUtteranceId) {
                                val res = pendingSpeakResult
                                pendingSpeakResult = null
                                activeUtteranceId = null
                                res?.success(false)
                            }
                        }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        onError(utteranceId)
                    }
                })
            }
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openAtlas" -> {
                startActivity(Intent(this, AtlasActivity::class.java))
                result.success(null)
            }
            "speak" -> {
                val text = call.argument<String>("text")?.trim() ?: ""
                val language = call.argument<String>("language") ?: "tr-TR"
                val voice = call.argument<String>("voice") ?: currentTtsVoice
                val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                val awaitCompletion = call.argument<Boolean>("awaitCompletion") ?: true
                speakText(text, language, voice, rate, awaitCompletion, result)
            }
            "setTtsVoice" -> {
                val voice = call.argument<String>("voice")?.trim()
                if (!voice.isNullOrEmpty()) {
                    currentTtsVoice = voice
                }
                result.success(true)
            }
            "stopSpeaking" -> {
                stopSpeakingInternal()
                result.success(true)
            }
            "checkMicPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            "requestMicPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    result.success(true)
                } else {
                    pendingMicPermResult?.success(false)
                    pendingMicPermResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        REQ_RECORD_AUDIO
                    )
                }
            }
            "startListening" -> {
                val language = call.argument<String>("language") ?: "tr-TR"
                startVoiceListening(language, result)
            }
            "stopListening" -> {
                mainHandler.post {
                    try {
                        speechRecognizer?.stopListening()
                    } catch (_: Exception) {}
                }
                result.success(true)
            }
            "cancelListening" -> {
                mainHandler.post {
                    destroySpeechRecognizer()
                }
                result.success(true)
            }
            "setMusic" -> {
                val track = call.argument<String>("track")
                val volume = (call.argument<Double>("volume") ?: 0.35).toFloat()
                setBackgroundMusic(track, volume)
                result.success(true)
            }
            "playSfx" -> {
                val kind = call.argument<String>("kind") ?: "tick"
                val volume = (call.argument<Double>("volume") ?: 0.55).toFloat()
                playSynthesizedSfx(kind, volume)
                result.success(true)
            }
            "pickFiles" -> {
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
                openFilePicker(mimeType, allowMultiple, result)
            }
            "saveFile" -> {
                val fileName = call.argument<String>("fileName") ?: "bilgili_export.json"
                val mimeType = call.argument<String>("mimeType") ?: "application/json"
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                openFileSaver(fileName, mimeType, bytes, result)
            }
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                val title = call.argument<String>("title") ?: "Bilgili Paylaşım"
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                startActivity(Intent.createChooser(sendIntent, title))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun speakText(
        text: String,
        languageTag: String,
        voice: String?,
        rate: Float,
        awaitCompletion: Boolean,
        result: MethodChannel.Result
    ) {
        if (text.isEmpty()) {
            result.success(true)
            return
        }
        initTts()
        stopSpeakingInternal()
        val token = ++activeSpeakToken
        if (!voice.isNullOrBlank()) {
            currentTtsVoice = voice
        }
        val resolvedVoice = EdgeTtsClient.resolveVoice(currentTtsVoice, languageTag)
        if (resolvedVoice == EdgeTtsClient.SYSTEM_VOICE) {
            speakWithSystemTts(text, languageTag, rate, awaitCompletion, result)
            return
        }

        if (!awaitCompletion) {
            result.success(true)
        } else {
            pendingSpeakResult = result
        }

        val appCacheDir = applicationContext.cacheDir
        audioExecutor.execute {
            if (token != activeSpeakToken) return@execute
            val mp3File = EdgeTtsClient.synthesizeToFile(
                cacheDir = appCacheDir,
                text = text,
                voiceName = resolvedVoice,
                rate = rate
            )
            mainHandler.post {
                if (token != activeSpeakToken) return@post
                if (mp3File != null && mp3File.exists() && mp3File.length() > 128L) {
                    try {
                        stopTtsPlayerOnly()
                        val mp = MediaPlayer()
                        mp.setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        mp.setDataSource(mp3File.absolutePath)
                        mp.setOnCompletionListener { player ->
                            try {
                                player.release()
                            } catch (_: Exception) {}
                            if (ttsPlayer === player) {
                                ttsPlayer = null
                            }
                            if (token == activeSpeakToken && awaitCompletion) {
                                val res = pendingSpeakResult
                                pendingSpeakResult = null
                                res?.success(true)
                            }
                        }
                        mp.setOnErrorListener { player, _, _ ->
                            try {
                                player.release()
                            } catch (_: Exception) {}
                            if (ttsPlayer === player) {
                                ttsPlayer = null
                            }
                            if (token == activeSpeakToken) {
                                val res = pendingSpeakResult
                                pendingSpeakResult = null
                                speakWithSystemTts(text, languageTag, rate, awaitCompletion, res)
                            }
                            true
                        }
                        mp.prepare()
                        mp.start()
                        ttsPlayer = mp
                    } catch (_: Exception) {
                        val res = pendingSpeakResult
                        pendingSpeakResult = null
                        speakWithSystemTts(text, languageTag, rate, awaitCompletion, res)
                    }
                } else {
                    val res = pendingSpeakResult
                    pendingSpeakResult = null
                    speakWithSystemTts(text, languageTag, rate, awaitCompletion, res)
                }
            }
        }
    }

    private fun speakWithSystemTts(
        text: String,
        languageTag: String,
        rate: Float,
        awaitCompletion: Boolean,
        result: MethodChannel.Result?
    ) {
        val engine = tts
        if (engine == null || !ttsReady) {
            result?.success(false)
            return
        }
        val locale = Locale.forLanguageTag(languageTag)
        val avail = engine.isLanguageAvailable(locale)
        if (avail >= TextToSpeech.LANG_AVAILABLE) {
            engine.language = locale
        } else {
            val fallback = Locale.forLanguageTag(languageTag.substringBefore('-'))
            if (engine.isLanguageAvailable(fallback) >= TextToSpeech.LANG_AVAILABLE) {
                engine.language = fallback
            }
        }
        engine.setSpeechRate(rate.coerceIn(0.6f, 1.6f))
        val utteranceId = UUID.randomUUID().toString()
        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
        }
        if (awaitCompletion && result != null) {
            activeUtteranceId = utteranceId
            pendingSpeakResult = result
            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            if (code == TextToSpeech.ERROR) {
                activeUtteranceId = null
                pendingSpeakResult = null
                result.success(false)
            }
        } else {
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            result?.success(true)
        }
    }

    private fun stopTtsPlayerOnly() {
        val p = ttsPlayer
        ttsPlayer = null
        if (p != null) {
            try {
                if (p.isPlaying) p.stop()
            } catch (_: Exception) {}
            try {
                p.release()
            } catch (_: Exception) {}
        }
    }

    private fun stopSpeakingInternal() {
        activeSpeakToken++
        stopTtsPlayerOnly()
        try {
            tts?.stop()
        } catch (_: Exception) {}
        val pending = pendingSpeakResult
        pendingSpeakResult = null
        activeUtteranceId = null
        pending?.success(false)
    }

    private fun startVoiceListening(language: String, result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.error("NO_MIC_PERMISSION", "Mikrofon izni verilmedi.", null)
            return
        }
        mainHandler.post {
            try {
                destroySpeechRecognizer()
                if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                    result.error("SPEECH_UNAVAILABLE", "Bu cihazda ses tanıma servisi bulunamadı.", null)
                    return@post
                }
                val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer = recognizer
                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        emitVoiceEvent(mapOf("type" to "ready"))
                    }
                    override fun onBeginningOfSpeech() {
                        emitVoiceEvent(mapOf("type" to "speaking"))
                    }
                    override fun onRmsChanged(rmsdB: Float) {
                        val normalized = ((rmsdB + 2f) / 12f).coerceIn(0.02f, 1.0f)
                        emitVoiceEvent(mapOf("type" to "rms", "level" to normalized.toDouble()))
                    }
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {
                        emitVoiceEvent(mapOf("type" to "processing"))
                    }
                    override fun onError(error: Int) {
                        val message = when (error) {
                            SpeechRecognizer.ERROR_NO_MATCH -> "Ses anlaşılamadı. Tekrar söylemeyi dene."
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Konuşma algılanmadı."
                            SpeechRecognizer.ERROR_AUDIO -> "Mikrofon ses kaydı alınamadı."
                            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                                "Ses tanıma ağ bağlantısına ulaşamadı."
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Mikrofon izni gerekli."
                            else -> "Ses tanıma tamamlanamadı ($error)."
                        }
                        emitVoiceEvent(mapOf("type" to "error", "code" to error, "message" to message))
                    }
                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: arrayListOf()
                        val best = matches.firstOrNull() ?: ""
                        emitVoiceEvent(
                            mapOf(
                                "type" to "result",
                                "text" to best,
                                "alternatives" to matches
                            )
                        )
                    }
                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: arrayListOf()
                        val best = matches.firstOrNull() ?: ""
                        if (best.isNotEmpty()) {
                            emitVoiceEvent(mapOf("type" to "partial", "text" to best))
                        }
                    }
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                }
                recognizer.startListening(intent)
                result.success(true)
            } catch (e: Exception) {
                result.error("LISTEN_ERROR", e.localizedMessage ?: "Ses dinleme başlatılamadı.", null)
            }
        }
    }

    private fun emitVoiceEvent(payload: Map<String, Any>) {
        mainHandler.post {
            methodChannel?.invokeMethod("onVoiceEvent", payload)
        }
    }

    private fun destroySpeechRecognizer() {
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
    }

    private fun setBackgroundMusic(track: String?, volume: Float) {
        currentMusicVolume = volume.coerceIn(0f, 1f)
        val desired = if (track.isNullOrBlank() || track == "off") null else track
        if (desired == null) {
            stopMusicInternal()
            currentMusicTrack = null
            return
        }
        if (desired == currentMusicTrack && mediaPlayer != null) {
            try {
                mediaPlayer?.setVolume(currentMusicVolume, currentMusicVolume)
                if (mediaPlayer?.isPlaying == false) {
                    mediaPlayer?.start()
                }
                return
            } catch (_: Exception) {}
        }
        stopMusicInternal()
        val resId = when (desired) {
            "menu" -> resources.getIdentifier("muzik_menu", "raw", packageName)
            "game" -> resources.getIdentifier("muzik_oyun", "raw", packageName)
            else -> 0
        }
        if (resId == 0) return
        try {
            val mp = MediaPlayer.create(applicationContext, resId)
            if (mp != null) {
                mp.isLooping = true
                mp.setVolume(currentMusicVolume, currentMusicVolume)
                mp.start()
                mediaPlayer = mp
                currentMusicTrack = desired
            }
        } catch (_: Exception) {}
    }

    private fun stopMusicInternal() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    private fun playSynthesizedSfx(kind: String, volume: Float) {
        val notes: List<Pair<Double, Int>> = when (kind) {
            "start" -> listOf(523.25 to 75, 659.25 to 75, 783.99 to 130)
            "correct" -> listOf(659.25 to 70, 880.0 to 80, 1046.5 to 150)
            "wrong" -> listOf(311.13 to 110, 233.08 to 170)
            "tick" -> listOf(920.0 to 26)
            "timeout" -> listOf(440.0 to 90, 349.23 to 90, 261.63 to 170)
            "stage" -> listOf(523.25 to 70, 659.25 to 70, 783.99 to 70, 1046.5 to 160)
            "joker" -> listOf(739.99 to 65, 987.77 to 120)
            "victory" -> listOf(523.25 to 75, 659.25 to 75, 783.99 to 75, 1046.5 to 95, 1318.5 to 210)
            else -> listOf(660.0 to 45)
        }
        val gain = volume.coerceIn(0.05f, 1.0f).toDouble()
        audioExecutor.execute {
            try {
                val sampleRate = 24000
                val totalMs = notes.sumOf { it.second } + 20
                val totalSamples = (sampleRate * totalMs) / 1000
                val pcm = ShortArray(max(totalSamples, 256))
                var cursor = 0
                for ((freq, durMs) in notes) {
                    val count = (sampleRate * durMs) / 1000
                    for (i in 0 until count) {
                        if (cursor + i >= pcm.size) break
                        val t = i.toDouble() / sampleRate
                        val attack = min(1.0, i / (sampleRate * 0.006))
                        val decay = exp(-3.6 * i.toDouble() / count.toDouble())
                        val wave = sin(2.0 * PI * freq * t) + 0.28 * sin(4.0 * PI * freq * t)
                        val sample = (wave * 0.65 * gain * attack * decay * Short.MAX_VALUE).toInt()
                        pcm[cursor + i] = sample.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    }
                    cursor += count
                }
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val format = AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
                val track = AudioTrack.Builder()
                    .setAudioAttributes(attrs)
                    .setAudioFormat(format)
                    .setBufferSizeInBytes(pcm.size * 2)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()
                track.write(pcm, 0, pcm.size)
                track.play()
                Thread.sleep(totalMs.toLong() + 40L)
                track.stop()
                track.release()
            } catch (_: Exception) {}
        }
    }

    private fun openFilePicker(mimeType: String, allowMultiple: Boolean, result: MethodChannel.Result) {
        pendingPickResult?.success(emptyList<Map<String, Any>>())
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
        }
        startActivityForResult(intent, REQ_PICK_FILES)
    }

    private fun openFileSaver(fileName: String, mimeType: String, bytes: ByteArray, result: MethodChannel.Result) {
        pendingSaveResult?.success(false)
        pendingSaveResult = result
        pendingSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, REQ_SAVE_FILE)
    }

    private fun queryFileName(uri: Uri): String {
        var name = "dosya"
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) {
                name = cursor.getString(idx) ?: name
            }
        }
        return name
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val res = pendingMicPermResult
            pendingMicPermResult = null
            res?.success(granted)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_FILES) {
            val res = pendingPickResult
            pendingPickResult = null
            if (resultCode != Activity.RESULT_OK || data == null) {
                res?.success(emptyList<Map<String, Any>>())
                return
            }
            val items = mutableListOf<Map<String, Any>>()
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) {
                    val uri = clip.getItemAt(i).uri
                    contentResolver.openInputStream(uri)?.use { stream ->
                        items.add(mapOf("name" to queryFileName(uri), "bytes" to stream.readBytes()))
                    }
                }
            } else {
                data.data?.let { uri ->
                    contentResolver.openInputStream(uri)?.use { stream ->
                        items.add(mapOf("name" to queryFileName(uri), "bytes" to stream.readBytes()))
                    }
                }
            }
            res?.success(items)
        } else if (requestCode == REQ_SAVE_FILE) {
            val res = pendingSaveResult
            val bytes = pendingSaveBytes
            pendingSaveResult = null
            pendingSaveBytes = null
            if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) {
                res?.success(false)
                return
            }
            try {
                contentResolver.openOutputStream(data.data!!)?.use { out ->
                    out.write(bytes)
                    out.flush()
                }
                res?.success(true)
            } catch (_: Exception) {
                res?.success(false)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        if (mediaPlayer?.isPlaying == true) {
            try {
                mediaPlayer?.pause()
                musicPausedByLifecycle = true
            } catch (_: Exception) {}
        }
    }

    override fun onResume() {
        super.onResume()
        if (musicPausedByLifecycle && currentMusicTrack != null) {
            try {
                mediaPlayer?.start()
            } catch (_: Exception) {}
            musicPausedByLifecycle = false
        }
    }

    override fun onDestroy() {
        stopSpeakingInternal()
        destroySpeechRecognizer()
        stopMusicInternal()
        try {
            tts?.shutdown()
        } catch (_: Exception) {}
        audioExecutor.shutdownNow()
        super.onDestroy()
    }
}
