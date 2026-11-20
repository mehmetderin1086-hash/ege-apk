package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.MediaStore
import android.view.WindowManager
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import java.util.concurrent.atomic.AtomicBoolean
import java.util.function.Consumer
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.media.audiofx.AcousticEchoCanceler
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val liveDuplex by lazy { LiveDuplexCapture(this) }
    private val phoneSpeech by lazy { PhoneSpeech(this) }
    private val phoneAudioSpeech by lazy { PhoneAudioSpeech(this) }
    private val googleAccounts by lazy { GoogleAccountBridge(this) }
    private val microsoftAccounts by lazy { MicrosoftAccountBridge(this) }

    companion object {
        const val ACTION_LISTEN = "com.jarvis.assistant.LISTEN"
        const val ACTION_BRIEFING = "com.jarvis.assistant.BRIEFING"
        const val ACTION_LIVE = "com.jarvis.assistant.LIVE"
        const val ACTION_CHAT = "com.jarvis.assistant.CHAT"
        @Volatile var instance: MainActivity? = null
    }

    /** Uygulamayı açan dış eylem; Dart "takeLaunchAction" ile bir kez alır. */
    private var pendingLaunch: Map<String, Any>? = null

    fun notifyFlutter(method: String, args: Any?) {
        runOnUiThread {
            try { methodChannel?.invokeMethod(method, args) } catch (_: Throwable) {}
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        ManagedDownloads.init(this)
        // Yeniden oluşturma (döndürme/süreç ölümü) ya da son uygulamalardan geri dönüşte
        // eski başlatma intent'i yeniden oynatılmasın.
        val fromHistory = (intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !fromHistory) {
            pendingLaunch = parseLaunchIntent(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        instance = this
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val a = parseLaunchIntent(intent) ?: return
        if (methodChannel != null) notifyFlutter("onLaunchAction", a) else pendingLaunch = a
    }

    private fun parseLaunchIntent(i: Intent?): Map<String, Any>? {
        if (i == null) return null
        val shot = i.getStringExtra("jarvis_screenshot")
        val route = i.getStringExtra("jarvis_route")
        val base: MutableMap<String, Any> = when (i.action) {
            ACTION_LISTEN, Intent.ACTION_ASSIST, Intent.ACTION_VOICE_COMMAND, "android.intent.action.SEARCH_LONG_PRESS" ->
                mutableMapOf("action" to "listen", "source" to (i.getStringExtra("jarvis_source") ?: "intent"))
            ACTION_BRIEFING -> mutableMapOf("action" to "briefing")
            ACTION_LIVE -> mutableMapOf("action" to "live")
            ACTION_CHAT -> mutableMapOf("action" to "chat")
            Intent.ACTION_PROCESS_TEXT -> {
                val t = i.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString() ?: return null
                mutableMapOf("action" to "ask", "text" to t, "process" to true)
            }
            Intent.ACTION_SEND -> {
                val type = i.type ?: ""
                if (type.startsWith("image/")) {
                    @Suppress("DEPRECATION")
                    val uri = i.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM) ?: return null
                    val path = copySharedToCache(uri, "paylasilan_gorsel") ?: return null
                    mutableMapOf("action" to "image", "path" to path, "mime" to type)
                } else {
                    val t = (i.getStringExtra(Intent.EXTRA_TEXT) ?: i.getStringExtra(Intent.EXTRA_SUBJECT)) ?: return null
                    mutableMapOf("action" to "ask", "text" to t)
                }
            }
            else -> if (route != null) mutableMapOf("action" to route) else return null
        }
        if (shot != null) base["screenshot"] = shot
        return base
    }

    private fun copySharedToCache(uri: android.net.Uri, name: String): String? = try {
        val f = File(cacheDir, "${name}_${System.currentTimeMillis()}.jpg")
        contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(f).use { input.copyTo(it) } }
        f.absolutePath
    } catch (_: Throwable) { null }

    // ---- Canlı Ses ses yönlendirmesi (yankı engelleme iletişim modunda çalışır)
    private var savedAudioMode: Int? = null
    private var savedCallVolume: Int? = null
    @Volatile private var liveLastPlayMs = 0L
    @Volatile private var liveBargeIn = false

    private fun hasHeadset(am: AudioManager): Boolean = try {
        am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET ||
                (Build.VERSION.SDK_INT >= 31 && it.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
    } catch (_: Throwable) { false }

    private fun enterCommunicationAudio() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (hasHeadset(am)) return // kulaklıkta yankı yok; A2DP kalitesini bozma
            if (savedAudioMode == null) savedAudioMode = am.mode
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                am.availableCommunicationDevices
                    .firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    ?.let { am.setCommunicationDevice(it) }
            } else {
                @Suppress("DEPRECATION")
                am.isSpeakerphoneOn = true
            }
            val max = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            val cur = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            if (cur < (max * 0.6).toInt()) {
                savedCallVolume = cur
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (max * 0.85).toInt(), 0)
            }
        } catch (t: Throwable) {
            android.util.Log.w("JarvisLive", "iletisim modu acilamadi: ${t.message}")
        }
    }

    private fun exitCommunicationAudio() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            savedCallVolume?.let { am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, it, 0) }
            savedCallVolume = null
            if (savedAudioMode != null) {
                if (Build.VERSION.SDK_INT >= 31) {
                    am.clearCommunicationDevice()
                } else {
                    @Suppress("DEPRECATION")
                    am.isSpeakerphoneOn = false
                }
                am.mode = savedAudioMode ?: AudioManager.MODE_NORMAL
                savedAudioMode = null
            }
        } catch (_: Throwable) {}
    }

    // ---- "Hey Jarvis" mikrofonu: VOICE_RECOGNITION (işlenmemiş), 16 kHz, 100 ms
    @Volatile private var wakeMicOn = false
    private var wakeRecorder: AudioRecord? = null
    private var wakeThread: Thread? = null

    private fun startWakeMic(): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4431)
            return "PERMISSION_NEEDED"
        }
        stopWakeMic()
        val rate = 16000
        val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT).coerceAtLeast(4096)
        return try {
            val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, minBuf * 4)
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                return "UNAVAILABLE"
            }
            wakeRecorder = rec
            wakeMicOn = true
            rec.startRecording()
            wakeThread = Thread {
                val buf = ShortArray(1600)
                val bytes = ByteArray(buf.size * 2)
                while (wakeMicOn) {
                    val n = rec.read(buf, 0, buf.size)
                    if (n < 0) {
                        // Okuma hatası (ERROR_DEAD_OBJECT vb.): boşa dönmeden bırak.
                        wakeMicOn = false
                        try { rec.stop() } catch (_: Throwable) {}
                        try { rec.release() } catch (_: Throwable) {}
                        break
                    }
                    if (n == 0) { try { Thread.sleep(5) } catch (_: Throwable) {}; continue }
                    for (i in 0 until n) {
                        val v = buf[i].toInt()
                        bytes[i * 2] = (v and 0xFF).toByte()
                        bytes[i * 2 + 1] = ((v ushr 8) and 0xFF).toByte()
                    }
                    val copy = bytes.copyOf(n * 2)
                    runOnUiThread {
                        try { methodChannel?.invokeMethod("onWakePcm", copy) } catch (_: Throwable) {}
                    }
                }
            }.apply { name = "jarvis-wake-mic"; start() }
            "OK"
        } catch (_: Throwable) {
            stopWakeMic()
            "UNAVAILABLE"
        }
    }

    private fun stopWakeMic() {
        wakeMicOn = false
        try { wakeThread?.join(300) } catch (_: Throwable) {}
        wakeThread = null
        try {
            wakeRecorder?.let { r ->
                if (r.recordingState == AudioRecord.RECORDSTATE_RECORDING) r.stop()
                r.release()
            }
        } catch (_: Throwable) {}
        wakeRecorder = null
    }

    /** Telefon takvimi (bugünden itibaren [days] gün); izin yoksa ister, null döner. */
    private fun queryCalendarEvents(days: Int): List<Map<String, Any>>? {
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), 4441)
            return null
        }
        return try {
            val cal = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }
            val start = cal.timeInMillis
            val end = start + days.coerceIn(1, 14) * 86_400_000L
            val b = CalendarContract.Instances.CONTENT_URI.buildUpon()
            android.content.ContentUris.appendId(b, start)
            android.content.ContentUris.appendId(b, end)
            val proj = arrayOf(
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.EVENT_LOCATION,
            )
            val out = ArrayList<Map<String, Any>>()
            contentResolver.query(b.build(), proj, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
                while (c.moveToNext() && out.size < 60) {
                    out.add(mapOf(
                        "title" to (c.getString(0) ?: "(başlıksız)"),
                        "begin" to c.getLong(1),
                        "end" to c.getLong(2),
                        "allDay" to (c.getInt(3) == 1),
                        "location" to (c.getString(4) ?: ""),
                    ))
                }
            }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun callNumberInternal(number: String): String {
        val n = number.replace(Regex("[^0-9+*#]"), "")
        if (n.isEmpty()) return "ERROR"
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            return try {
                startActivity(
                    Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:" + android.net.Uri.encode(n)))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                "CALLING"
            } catch (_: Throwable) {
                if (dialNumberInternal(n)) "DIALER" else "ERROR"
            }
        }
        requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), 4421)
        return if (dialNumberInternal(n)) "DIALER" else "ERROR"
    }

    private val channelName = "com.jarvis.assistant/device"
    private val callControl by lazy { JarvisCalls(this) }
    private var methodChannel: MethodChannel? = null
    private var activePlayer: MediaPlayer? = null
    private var pendingAudioResult: MethodChannel.Result? = null

    @Volatile
    private var isRecordingMic = false
    private var micRecorder: AudioRecord? = null
    private var micThread: Thread? = null
    private var pcmBuffer: ByteArrayOutputStream? = null
    private var micVad: AdaptiveVad? = null

    @Volatile
    private var isStreamingLiveMic = false
    private var liveMicRecorder: AudioRecord? = null
    private var liveMicThread: Thread? = null
    private var liveMicAec: AcousticEchoCanceler? = null

    @Volatile
    private var liveAudioActive = false
    private var liveAudioTrack: AudioTrack? = null
    private var liveAudioThread: Thread? = null
    private var liveAudioQueue = LinkedBlockingQueue<ByteArray>()

    private var torchEnabledState = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeLaunchAction" -> {
                    result.success(pendingLaunch)
                    pendingLaunch = null
                }
                "keepAlive" -> {
                    val reason = call.argument<String>("reason") ?: "app"
                    if (call.argument<Boolean>("on") == true) {
                        result.success(JarvisKeepAlive.acquire(this, reason, call.argument<String>("text")))
                    } else {
                        JarvisKeepAlive.release(this, reason)
                        result.success(true)
                    }
                }
                "batteryOptStatus" -> result.success(JarvisKeepAlive.isIgnoringBattery(this))
                "requestBatteryOpt" -> result.success(JarvisKeepAlive.requestIgnoreBattery(this))
                "callNumber" -> result.success(callNumberInternal(call.argument<String>("number") ?: ""))
                "endCall" -> callControl.end(result)
                "callControlPermission" -> result.success(callControl.permitted())
                "requestCallControlPermission" -> result.success(callControl.requestPermission())
                "isDefaultAssistant" -> result.success(JarvisAssistantRole.isDefault(this))
                "requestDefaultAssistant" -> result.success(JarvisAssistantRole.openSettings(this))
                "notificationAccess" -> result.success(JarvisNotificationListener.hasAccess(this))
                "openWhatsAppNotification" -> result.success(
                    JarvisNotificationListener.instance?.openWhatsApp(
                        call.argument<String>("key") ?: ""
                    ) ?: false
                )
                "openNotificationAccess" -> result.success(JarvisNotificationListener.openSettings(this))
                "recentNotifications" -> result.success(
                    JarvisNotificationListener.recentList(call.argument<Int>("limit") ?: 10)
                )
                "replyNotification" -> result.success(
                    JarvisNotificationListener.instance?.reply(
                        call.argument<String>("key") ?: "",
                        call.argument<String>("text") ?: "",
                    ) ?: false
                )
                "wakeWordStart" -> {
                    val sens = call.argument<Double>("sensitivity") ?: 0.5
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4431)
                        result.success("Mikrofon izni gerekli; izin verdikten sonra yeniden başlatın.")
                    } else JarvisWakeWord.start(this, sens.toFloat(), result)
                }
                "wakeWordPause" -> { JarvisWakeWord.pause(); result.success(true) }
                "closeAssistantTask" -> {
                    result.success(true)
                    finishAndRemoveTask()
                }
                "wakeWordStop" -> {
                    JarvisWakeWord.stop(this)
                    result.success(true)
                }
                "wakeWordInfo" -> result.success(JarvisWakeWord.info(this))
                "wakeDiagnosticStart" -> result.success(JarvisWakeWord.beginDiagnostic())
                "wakeDiagnosticEnd" -> { JarvisWakeWord.endDiagnostic(); result.success(true) }
                "startWakeMic" -> result.success(startWakeMic())
                "stopWakeMic" -> {
                    stopWakeMic()
                    result.success(true)
                }
                "showAssistant" -> result.success(JarvisVoiceInteractionService.show())
                "earcon" -> {
                    try {
                        val cue = ToneGenerator(AudioManager.STREAM_MUSIC, 12)
                        cue.startTone(ToneGenerator.TONE_PROP_ACK, 55)
                        Handler(Looper.getMainLooper()).postDelayed({ cue.release() }, 150)
                    } catch (_: Throwable) {}
                    result.success(true)
                }
                "calendarEvents" -> {
                    val days = call.argument<Int>("days") ?: 1
                    runInBackground("jarvis-calendar", result, null) { queryCalendarEvents(days) }
                }
                "getDeviceInfo" -> result.success(collectDeviceInfo())
                "playTimerChime" -> {
                    playChimeAndVibrate()
                    result.success(true)
                }
                "playAudioBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val ext = call.argument<String>("ext") ?: "mp3"
                    if (bytes == null || bytes.isEmpty()) {
                        result.success(false)
                    } else {
                        // Dosya yazımı UI iş parçacığında değil; çalma ana iş parçacığında başlar.
                        stopAudioPlayer()
                        try {
                            Thread {
                                val written = try { writeTtsFile(bytes, ext); true } catch (_: Throwable) { false }
                                runOnUiThread {
                                    if (written) playAudioBytes(bytes, ext, result, true)
                                    else try { result.success(false) } catch (_: Throwable) {}
                                }
                            }.apply { name = "jarvis-tts-write"; isDaemon = true; start() }
                        } catch (_: Throwable) {
                            playAudioBytes(bytes, ext, result)
                        }
                    }
                }
                "stopAudio" -> {
                    stopAudioPlayer()
                    result.success(true)
                }
                "saveImageBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val fileName = call.argument<String>("fileName") ?: "jarvis_image.png"
                    if (bytes == null || bytes.isEmpty()) {
                        result.success(null)
                    } else {
                        result.success(saveImageFile(bytes, fileName))
                    }
                }
                "currentAppCommand" -> {
                    val action = call.argument<String>("action")
                    val service = JarvisAppControl.instance
                    if (service == null) result.success("Erişilebilirlik ayarlarında Ege uygulama kontrolünü aç.")
                    else if (action in listOf("inspect", "back", "leave")) service.currentAppCommand(action!!, result)
                    else result.success("Geçersiz gezinme işlemi.")
                }
                "phoneSnapshot" -> {
                    val service = JarvisAppControl.instance
                    if (service == null) result.success("Hata: Uygulama kontrolü erişilebilirlik izni kapalı.")
                    else service.readScreen(result)
                }
                "resumePhoneScreen" -> {
                    val service = JarvisAppControl.instance
                    if (service == null) result.success("Hata: Uygulama kontrolü erişilebilirlik izni kapalı.")
                    else service.resumeExternalScreen(result)
                }
                "phoneScreenImage" -> {
                    val service = JarvisAppControl.instance
                    if (service == null) result.success(mapOf("error" to "Erişilebilirlik izni kapalı."))
                    else service.captureScreen(call.argument<String>("package") ?: "", result)
                }
                "vaultStatus" -> result.success(vault.status())
                "vaultConnect" -> vault.connect(result)
                "vaultDisconnect" -> vault.disconnect(result)
                "vaultSync" -> vault.sync(call.argument<Map<String, String>>("files") ?: emptyMap(), result)
                "vaultSearch" -> vault.search(call.argument<String>("query") ?: "", result)
                "appControlEnabled" -> result.success(JarvisAppControl.instance != null)
                "controlApp" -> {
                    val service = JarvisAppControl.instance
                    if (service == null) result.success("Ayarlar → Uygulama kontrolü bölümünden erişilebilirlik iznini açın.")
                    else service.execute(call.argument<String>("package") ?: "", call.argument<String>("action") ?: "",
                        call.argument<String>("target") ?: "", call.argument<String>("text") ?: "", result,
                        call.argument<String>("query") ?: "", call.argument<String>("url") ?: "")
                }
                "startPhoneSpeech" -> phoneSpeech.start(result)
                "preparePhoneSpeech" -> { PhoneSpeechModels.prepare(this, force = call.argument<Boolean>("force") == true); result.success(true) }
                "transcribePhoneAudio" -> phoneAudioSpeech.start(call.argument<ByteArray>("pcm"), result)
                "microsoftAuthorize" -> microsoftAccounts.authorize(call.argument<String>("service") ?: "", call.argument<Boolean>("interactive") == true, result)
                "microsoftDisconnect" -> microsoftAccounts.disconnect(call.argument<String>("service") ?: "", result)
                "googleAuthorize" -> googleAccounts.authorize(call.argument<String>("service") ?: "", call.argument<Boolean>("interactive") == true, result)
                "stopPhoneSpeech" -> { phoneSpeech.stop(); result.success(true) }
                "cancelPhoneSpeech" -> { phoneSpeech.cancel(); phoneAudioSpeech.cancel(); result.success(true) }
                "speakerProfileRead" -> result.success(SpeakerProfileStore.read(this))
                "speakerProfileWrite" -> result.success(SpeakerProfileStore.write(this, call.argument<String>("json") ?: ""))
                "speakerProfileDelete" -> result.success(SpeakerProfileStore.delete(this))
                "duplexSpeakerDecision" -> { liveDuplex.speakerDecision(call.argument<Int>("token") ?: 0, call.argument<Boolean>("accepted") ?: false); result.success(true) }
                "startDuplexCapture" -> result.success(liveDuplex.start(call.argument<Int>("token") ?: 0, call.argument<Boolean>("bargeIn") ?: true, SpeakerProfileStore.enabled(this)))
                "duplexPlaybackEnded" -> { liveDuplex.playbackEnded(call.argument<Int>("token") ?: 0); result.success(true) }
                "stopDuplexCapture" -> { liveDuplex.stop(); result.success(true) }
                "startMicCapture" -> result.success(
                    startMicCapture(
                        call.argument<Int>("endSilenceMs") ?: 900,
                        call.argument<Int>("noSpeechMs") ?: 7000,
                    )
                )
                "micStats" -> result.success(lastMicStats)
                "stopMicCapture" -> runInBackground("jarvis-mic-stop", result, null) { stopMicCapture() }
                "cancelMicCapture" -> {
                    cancelMicCapture()
                    result.success(true)
                }
                "openLiveAudioStream" -> {
                    val sr = call.argument<Int>("sampleRate") ?: 24000
                    result.success(openLiveAudioStream(sr))
                }
                "feedLiveAudioPcm" -> {
                    val pcm = call.argument<ByteArray>("bytes")
                    if (pcm != null && pcm.isNotEmpty()) {
                        liveAudioQueue.offer(pcm)
                    }
                    result.success(true)
                }
                "interruptLiveAudioStream" -> {
                    interruptLiveAudioStream()
                    result.success(true)
                }
                "closeLiveAudioStream" -> {
                    closeLiveAudioStream()
                    result.success(true)
                }
                "startLivePcmMic" -> {
                    val sr = call.argument<Int>("sampleRate") ?: 16000
                    liveBargeIn = call.argument<Boolean>("bargeIn") == true
                    result.success(startLivePcmMic(sr))
                }
                "stopLivePcmMic" -> {
                    stopLivePcmMic()
                    result.success(true)
                }
                "setFlashlight" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(setFlashlightMode(enabled))
                }
                "getVolumeState" -> result.success(getVolumeState())
                "setVolumeLevel" -> {
                    val stream = call.argument<String>("stream") ?: "media"
                    val percent = call.argument<Int>("percent") ?: 50
                    result.success(setVolumePercent(stream, percent))
                }
                "controlMedia" -> {
                    val action = call.argument<String>("action") ?: "play_pause"
                    result.success(dispatchMediaAction(action))
                }
                "listInstalledApps" -> runInBackground("jarvis-list-apps", result, emptyList<Map<String, Any>>()) {
                    cachedInstalledApps()
                }
                "mediaSessionCommand" -> mediaSessionCommand(call.argument<String>("package").orEmpty(), call.argument<String>("action").orEmpty(), result)
                "spotifyControl" -> spotifyControl(call.argument<String>("action"), result)
                "playSpotifyMusic" -> playSpotifyMusic(result)
                "openYouTube" -> result.success(openYouTube(call.argument<String>("query") ?: ""))
                "launchApp" -> {
                    val q = call.argument<String>("query") ?: ""
                    runInBackground("jarvis-launch-app", result, null) { launchAppByQuery(q) }
                }
                "openSystemSettings" -> {
                    val target = call.argument<String>("target") ?: "general"
                    result.success(openSystemSettingsPanel(target))
                }
                "setSystemAlarm" -> {
                    val hour = call.argument<Int>("hour") ?: 7
                    val minute = call.argument<Int>("minute") ?: 0
                    val msg = call.argument<String>("message") ?: "Ege Alarm"
                    val days = call.argument<List<Int>>("days") ?: emptyList()
                    result.success(createSystemAlarm(hour, minute, msg, days))
                }
                "addCalendarEvent" -> {
                    val title = call.argument<String>("title") ?: "Etkinlik"
                    val desc = call.argument<String>("description") ?: ""
                    val startMs = call.argument<Number>("startMs")?.toLong() ?: System.currentTimeMillis()
                    val endMs = call.argument<Number>("endMs")?.toLong() ?: (startMs + 3600000L)
                    result.success(openCalendarInsert(title, desc, startMs, endMs))
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Ege"
                    val body = call.argument<String>("body") ?: ""
                    ensureNotificationPermission()
                    result.success(postNotification(title, body))
                }
                else -> {
                    try {
                        if (!handleExtendedCall(call, result)) result.notImplemented()
                    } catch (t: Throwable) {
                        try {
                            result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null)
                        } catch (_: Throwable) {}
                    }
                }
            }
        }
    }

    private fun stopAudioPlayer() {
        try {
            activePlayer?.let { p ->
                if (p.isPlaying) p.stop()
                p.release()
            }
        } catch (_: Throwable) {}
        activePlayer = null
        pendingAudioResult?.let { r ->
            pendingAudioResult = null
            try { r.success(false) } catch (_: Throwable) {}
        }
    }

    private fun writeTtsFile(bytes: ByteArray, ext: String): File {
        val safeExt = ext.replace(Regex("[^a-zA-Z0-9]"), "").ifEmpty { "mp3" }
        val outFile = File(cacheDir, "jarvis_tts_current.$safeExt")
        FileOutputStream(outFile).use { it.write(bytes) }
        return outFile
    }

    private fun playAudioBytes(bytes: ByteArray, ext: String, result: MethodChannel.Result, alreadyWritten: Boolean = false) {
        if (!alreadyWritten) stopAudioPlayer()
        try {
            val outFile = if (alreadyWritten) {
                File(cacheDir, "jarvis_tts_current." + ext.replace(Regex("[^a-zA-Z0-9]"), "").ifEmpty { "mp3" })
            } else {
                writeTtsFile(bytes, ext)
            }

            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build()
            )
            FileInputStream(outFile).use { fis ->
                mp.setDataSource(fis.fd)
            }
            mp.setVolume(1.0f, 1.0f)
            pendingAudioResult = result
            activePlayer = mp
            mp.setOnCompletionListener { player ->
                try { player.release() } catch (_: Throwable) {}
                if (activePlayer === player) activePlayer = null
                val pending = pendingAudioResult
                pendingAudioResult = null
                try { pending?.success(true) } catch (_: Throwable) {}
            }
            mp.setOnErrorListener { player, _, _ ->
                try { player.release() } catch (_: Throwable) {}
                if (activePlayer === player) activePlayer = null
                val pending = pendingAudioResult
                pendingAudioResult = null
                try { pending?.success(false) } catch (_: Throwable) {}
                true
            }
            mp.prepare()
            mp.start()
        } catch (_: Throwable) {
            stopAudioPlayer()
            try { result.success(false) } catch (_: Throwable) {}
        }
    }

    private fun saveImageFile(bytes: ByteArray, fileName: String): String? {
        return try {
            val dir = File(filesDir, "jarvis_images")
            if (!dir.exists()) dir.mkdirs()
            val safeName = fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val file = File(dir, safeName)
            FileOutputStream(file).use { it.write(bytes) }
            saveBytesToDownloads(bytes, safeName, guessMimeFromName(safeName) ?: "image/png", "Resimler")
            file.absolutePath
        } catch (_: Throwable) {
            null
        }
    }

    private fun startMicCapture(endSilenceMs: Int = 900, noSpeechMs: Int = 7000): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4412)
            return "PERMISSION_NEEDED"
        }
        cancelMicCapture()
        val sampleRate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(4096)

        return try {
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuf * 2,
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                return "UNAVAILABLE"
            }
            val out = ByteArrayOutputStream()
            pcmBuffer = out
            micRecorder = recorder
            val vad = AdaptiveVad(sampleRate, endSilenceMs.coerceIn(400, 4000), noSpeechMs.coerceIn(2000, 20000))
            micVad = vad
            isRecordingMic = true
            recorder.startRecording()

            micThread = Thread {
                val shortBuf = ShortArray(800) // 50 ms @16 kHz
                val byteBuf = ByteArray(shortBuf.size * 2)
                val maxPcmBytes = sampleRate * 2 * 45 // 45 sn güvenlik sınırı
                var endNotified = false
                var lastLevelPost = 0L

                while (isRecordingMic) {
                    val readCount = recorder.read(shortBuf, 0, shortBuf.size)
                    if (readCount < 0) {
                        isRecordingMic = false
                        runOnUiThread {
                            try { methodChannel?.invokeMethod("onMicSilence", "ERROR") } catch (_: Throwable) {}
                        }
                        break
                    }
                    if (readCount == 0) { try { Thread.sleep(5) } catch (_: Throwable) {}; continue }
                    for (i in 0 until readCount) {
                        val v = shortBuf[i].toInt()
                        byteBuf[i * 2] = (v and 0xFF).toByte()
                        byteBuf[i * 2 + 1] = ((v ushr 8) and 0xFF).toByte()
                    }
                    synchronized(out) {
                        if (out.size() < maxPcmBytes) out.write(byteBuf, 0, readCount * 2)
                    }
                    val rms = AdaptiveVad.rms(shortBuf, readCount)
                    val end = vad.process(rms, readCount)
                    val now = android.os.SystemClock.uptimeMillis()
                    if (now - lastLevelPost >= 80) {
                        lastLevelPost = now
                        val lvl = vad.level(rms)
                        runOnUiThread {
                            try { methodChannel?.invokeMethod("onMicLevel", lvl) } catch (_: Throwable) {}
                        }
                    }
                    if (!endNotified && end != AdaptiveVad.End.NONE) {
                        endNotified = true
                        android.util.Log.i(
                            "JarvisMic",
                            "kayit bitti: $end konusma=${vad.speechMs}ms taban=${"%.4f".format(vad.noiseFloor)} " +
                                "tepe=${"%.4f".format(vad.peakRms)} sure=${vad.processedSamples * 1000 / sampleRate}ms",
                        )
                        runOnUiThread {
                            try { methodChannel?.invokeMethod("onMicSilence", end.name) } catch (_: Throwable) {}
                        }
                    }
                }
            }.apply {
                name = "jarvis-mic-capture"
                start()
            }
            "OK"
        } catch (_: Throwable) {
            cancelMicCapture()
            "UNAVAILABLE"
        }
    }

    /** Son kaydın ölçümleri (Dart tarafı "ses duyulmadı" mesajı ve tanı için). */
    private var lastMicStats: Map<String, Any> = emptyMap()

    private fun stopMicCapture(): ByteArray? {
        isRecordingMic = false
        try {
            micThread?.join(500)
        } catch (_: Throwable) {}
        micThread = null
        try {
            micRecorder?.let { r ->
                if (r.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    r.stop()
                }
                r.release()
            }
        } catch (_: Throwable) {}
        micRecorder = null

        val rawPcm = pcmBuffer?.let { buf ->
            synchronized(buf) { buf.toByteArray() }
        } ?: ByteArray(0)
        pcmBuffer = null
        val vad = micVad
        micVad = null
        val totalMs = rawPcm.size / 32
        lastMicStats = mapOf(
            "heardSpeech" to (vad?.heardSpeech ?: false),
            "speechMs" to (vad?.speechMs ?: 0),
            "noiseFloor" to (vad?.noiseFloor ?: 0.0),
            "peakRms" to (vad?.peakRms ?: 0.0),
            "durationMs" to totalMs,
            "end" to (vad?.endReason?.name ?: "NONE"),
        )
        if (rawPcm.size < 320) return null
        if (vad != null && !vad.heardSpeech) {
            // Konuşma algılanmadı: zaman aşımıyla bittiyse ya da kayıt neredeyse
            // tamamen sessizse Whisper'ı boşuna çalıştırma (sessizlikte uydurur).
            if (vad.endReason == AdaptiveVad.End.NO_SPEECH || vad.peakRms < 0.004) {
                android.util.Log.i("JarvisMic", "konusma yok, Whisper atlandi ($totalMs ms, tepe=${vad.peakRms})")
                return null
            }
        }
        val trimmed = if (vad != null && vad.heardSpeech) {
            AdaptiveVad.trimAndNormalize(rawPcm, 16000, vad.speechStartSample, vad.lastSpeechSample)
        } else {
            AdaptiveVad.trimAndNormalize(rawPcm, 16000, -1, -1)
        }
        android.util.Log.i("JarvisMic", "Whisper'a giden: ${trimmed.size / 32} ms (ham $totalMs ms)")
        return buildWavWithHeader(trimmed, sampleRate = 16000, channels = 1, bitsPerSample = 16)
    }

    private fun cancelMicCapture() {
        isRecordingMic = false
        try {
            micThread?.join(300)
        } catch (_: Throwable) {}
        micThread = null
        try {
            micRecorder?.let { r ->
                if (r.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    r.stop()
                }
                r.release()
            }
        } catch (_: Throwable) {}
        micRecorder = null
        pcmBuffer = null
        micVad = null
    }

    private fun buildWavWithHeader(
        pcm: ByteArray,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
    ): ByteArray {
        val dataLen = pcm.size
        val chunkSize = 36 + dataLen
        val byteRate = sampleRate * channels * (bitsPerSample / 8)
        val blockAlign = channels * (bitsPerSample / 8)
        val out = ByteArray(44 + dataLen)

        fun writeLeInt(offset: Int, v: Int) {
            out[offset] = (v and 0xFF).toByte()
            out[offset + 1] = ((v ushr 8) and 0xFF).toByte()
            out[offset + 2] = ((v ushr 16) and 0xFF).toByte()
            out[offset + 3] = ((v ushr 24) and 0xFF).toByte()
        }

        fun writeLeShort(offset: Int, v: Int) {
            out[offset] = (v and 0xFF).toByte()
            out[offset + 1] = ((v ushr 8) and 0xFF).toByte()
        }

        out[0] = 'R'.code.toByte(); out[1] = 'I'.code.toByte(); out[2] = 'F'.code.toByte(); out[3] = 'F'.code.toByte()
        writeLeInt(4, chunkSize)
        out[8] = 'W'.code.toByte(); out[9] = 'A'.code.toByte(); out[10] = 'V'.code.toByte(); out[11] = 'E'.code.toByte()
        out[12] = 'f'.code.toByte(); out[13] = 'm'.code.toByte(); out[14] = 't'.code.toByte(); out[15] = ' '.code.toByte()
        writeLeInt(16, 16)
        writeLeShort(20, 1)
        writeLeShort(22, channels)
        writeLeInt(24, sampleRate)
        writeLeInt(28, byteRate)
        writeLeShort(32, blockAlign)
        writeLeShort(34, bitsPerSample)
        out[36] = 'd'.code.toByte(); out[37] = 'a'.code.toByte(); out[38] = 't'.code.toByte(); out[39] = 'a'.code.toByte()
        writeLeInt(40, dataLen)
        System.arraycopy(pcm, 0, out, 44, dataLen)
        return out
    }

    private fun openLiveAudioStream(sampleRate: Int): Boolean {
        closeLiveAudioStream()
        enterCommunicationAudio()
        return try {
            val minBuf = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            ).coerceAtLeast(4096)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(minBuf * 3)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            liveAudioQueue = LinkedBlockingQueue()
            liveAudioTrack = track
            liveAudioActive = true
            track.play()

            liveAudioThread = Thread {
                while (liveAudioActive) {
                    try {
                        val chunk = liveAudioQueue.poll(120, TimeUnit.MILLISECONDS) ?: continue
                        val activeTrack = liveAudioTrack ?: continue
                        if (liveAudioActive && chunk.isNotEmpty()) {
                            activeTrack.write(chunk, 0, chunk.size)
                            liveLastPlayMs = android.os.SystemClock.uptimeMillis()
                        }
                    } catch (_: Throwable) {
                        if (!liveAudioActive) break
                    }
                }
            }.apply {
                name = "jarvis-live-audio-out"
                start()
            }
            true
        } catch (_: Throwable) {
            closeLiveAudioStream()
            false
        }
    }

    private fun interruptLiveAudioStream() {
        liveAudioQueue.clear()
        try {
            liveAudioTrack?.let { t ->
                t.pause()
                t.flush()
                t.play()
            }
        } catch (_: Throwable) {}
    }

    private fun closeLiveAudioStream() {
        liveAudioActive = false
        liveAudioQueue.clear()
        try {
            liveAudioThread?.interrupt()
            liveAudioThread?.join(350)
        } catch (_: Throwable) {}
        liveAudioThread = null
        try {
            liveAudioTrack?.let { t ->
                t.pause()
                t.flush()
                t.stop()
                t.release()
            }
        } catch (_: Throwable) {}
        liveAudioTrack = null
        exitCommunicationAudio()
    }

    private fun startLivePcmMic(sampleRate: Int): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4413)
            return "PERMISSION_NEEDED"
        }
        stopLivePcmMic()
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(4096)

        return try {
            val recorder = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuf * 2,
            )
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                recorder.release()
                return "UNAVAILABLE"
            }
            try {
                if (AcousticEchoCanceler.isAvailable()) {
                    liveMicAec = AcousticEchoCanceler.create(recorder.audioSessionId)?.apply {
                        enabled = true
                    }
                }
            } catch (_: Throwable) {}

            liveMicRecorder = recorder
            isStreamingLiveMic = true
            recorder.startRecording()

            val chunkShorts = (sampleRate * 80) / 1000 // ~80ms frames
            liveMicThread = Thread {
                val shortBuf = ShortArray(chunkShorts)
                val byteBuf = ByteArray(chunkShorts * 2)
                var echoLevel = 0.02
                var bargeFrames = 0
                while (isStreamingLiveMic) {
                    val readCount = recorder.read(shortBuf, 0, shortBuf.size)
                    if (readCount < 0) {
                        isStreamingLiveMic = false
                        break
                    }
                    if (readCount == 0) { try { Thread.sleep(5) } catch (_: Throwable) {}; continue }
                    if (readCount > 0) {
                        var sumSq = 0.0
                        for (i in 0 until readCount) {
                            val s = shortBuf[i]
                            byteBuf[i * 2] = (s.toInt() and 0xFF).toByte()
                            byteBuf[i * 2 + 1] = ((s.toInt() ushr 8) and 0xFF).toByte()
                            sumSq += (s.toDouble() * s.toDouble())
                        }
                        val rms = sqrt(sumSq / readCount) / 32768.0
                        // Yankı kapısı: JARVIS konuşurken (çalma kuyruğu doluysa ya da
                        // son 450 ms'de çaldıysa) hoparlör sesi mikrofondan geri gidip
                        // Gemini'nin kendi sözünü kesmesine yol açıyordu. Araya girme
                        // açıksa yalnız yankıdan belirgin yüksek konuşma geçer.
                        val now = android.os.SystemClock.uptimeMillis()
                        val playing = liveAudioActive && (!liveAudioQueue.isEmpty() || now - liveLastPlayMs < 450)
                        if (playing) {
                            echoLevel = echoLevel * 0.95 + rms * 0.05
                            val loudEnough = rms > maxOf(0.06, echoLevel * 3.5)
                            bargeFrames = if (liveBargeIn && loudEnough) bargeFrames + 1 else 0
                            if (bargeFrames < 3) java.util.Arrays.fill(byteBuf, 0, readCount * 2, 0.toByte())
                        } else {
                            bargeFrames = 0
                        }
                        val normLevel = ((rms - 0.006) / 0.14).coerceIn(0.0, 1.0)
                        val chunkCopy = byteBuf.copyOf(readCount * 2)
                        runOnUiThread {
                            try {
                                methodChannel?.invokeMethod("onLivePcmChunk", chunkCopy)
                                methodChannel?.invokeMethod("onMicLevel", normLevel)
                            } catch (_: Throwable) {}
                        }
                    }
                }
            }.apply {
                name = "jarvis-live-mic-in"
                start()
            }
            "OK"
        } catch (_: Throwable) {
            stopLivePcmMic()
            "UNAVAILABLE"
        }
    }

    private fun stopLivePcmMic() {
        isStreamingLiveMic = false
        try {
            liveMicThread?.join(350)
        } catch (_: Throwable) {}
        liveMicThread = null
        try {
            liveMicAec?.release()
        } catch (_: Throwable) {}
        liveMicAec = null
        try {
            liveMicRecorder?.let { r ->
                if (r.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    r.stop()
                }
                r.release()
            }
        } catch (_: Throwable) {}
        liveMicRecorder = null
    }

    private fun setFlashlightMode(enabled: Boolean): Boolean {
        return try {
            val camMgr = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            var chosenId: String? = null
            for (id in camMgr.cameraIdList) {
                val chars = camMgr.getCameraCharacteristics(id)
                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                if (!hasFlash) continue
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                chosenId = id
                if (facing == CameraCharacteristics.LENS_FACING_BACK) break
            }
            if (chosenId == null) return false
            camMgr.setTorchMode(chosenId, enabled)
            torchEnabledState = enabled
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun getVolumeState(): Map<String, Any> {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val mMax = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            val mCur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            val rMax = am.getStreamMaxVolume(AudioManager.STREAM_RING).coerceAtLeast(1)
            val rCur = am.getStreamVolume(AudioManager.STREAM_RING)
            val aMax = am.getStreamMaxVolume(AudioManager.STREAM_ALARM).coerceAtLeast(1)
            val aCur = am.getStreamVolume(AudioManager.STREAM_ALARM)
            mapOf(
                "mediaPct" to ((mCur * 100) / mMax),
                "ringPct" to ((rCur * 100) / rMax),
                "alarmPct" to ((aCur * 100) / aMax),
                "torch" to torchEnabledState,
            )
        } catch (_: Throwable) {
            mapOf("mediaPct" to 50, "ringPct" to 50, "alarmPct" to 70, "torch" to torchEnabledState)
        }
    }

    private fun setVolumePercent(stream: String, percent: Int): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val st = when (stream.lowercase(Locale.ROOT)) {
                "ring", "zil" -> AudioManager.STREAM_RING
                "alarm" -> AudioManager.STREAM_ALARM
                else -> AudioManager.STREAM_MUSIC
            }
            val max = am.getStreamMaxVolume(st).coerceAtLeast(1)
            val clamped = percent.coerceIn(0, 100)
            val target = ((clamped * max) / 100.0).toInt().coerceIn(0, max)
            am.setStreamVolume(st, target, 0)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun dispatchMediaAction(action: String): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val code = when (action.lowercase(Locale.ROOT)) {
                "next", "sonraki" -> KeyEvent.KEYCODE_MEDIA_NEXT
                "previous", "prev", "önceki" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                "stop", "durdur" -> KeyEvent.KEYCODE_MEDIA_STOP
                "pause", "duraklat" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                "play", "oynat", "başlat" -> KeyEvent.KEYCODE_MEDIA_PLAY
                else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            }
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun normalizeTrApp(s: String): String {
        return s.replace("İ", "i").replace("I", "ı").lowercase(Locale.ROOT)
            .replace("ğ", "g").replace("ü", "u").replace("ş", "s")
            .replace("ı", "i").replace("ö", "o").replace("ç", "c")
            .replace(Regex("[^a-z0-9 ]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun queryInstalledApps(): List<Map<String, String>> {
        return try {
            val pm = packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolved = pm.queryIntentActivities(mainIntent, 0)
            val seen = HashSet<String>()
            val out = ArrayList<Map<String, String>>()
            for (ri in resolved) {
                val pkg = ri.activityInfo?.packageName ?: continue
                if (!seen.add(pkg)) continue
                val label = ri.loadLabel(pm)?.toString()?.trim() ?: pkg
                if (label.isNotEmpty()) {
                    out.add(mapOf("name" to label, "package" to pkg))
                }
            }
            out.sortBy { (it["name"] ?: "").lowercase(Locale.ROOT) }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun mediaSessionCommand(pkg: String, action: String, result: MethodChannel.Result) {
        val manager = getSystemService(android.media.session.MediaSessionManager::class.java)
        val playing = android.media.session.PlaybackState.STATE_PLAYING
        val paused = android.media.session.PlaybackState.STATE_PAUSED
        val stopped = android.media.session.PlaybackState.STATE_STOPPED
        val buffering = android.media.session.PlaybackState.STATE_BUFFERING
        val resume = action == "resume"
        try {
            val sessions = manager.getActiveSessions(ComponentName(this, JarvisNotificationListener::class.java))
                .filter { it.packageName != "com.android.server.telecom" && (pkg.isEmpty() || it.packageName == pkg) }
            val candidates = sessions.filter {
                if (resume) it.playbackState?.state == paused else it.playbackState?.state in listOf(playing, buffering)
            }
            val session = candidates.singleOrNull()
            if (session == null) {
                result.success(when {
                    candidates.size > 1 -> "Birden fazla oynatıcı var. Uygulamanın adını söyle."
                    pkg.isNotEmpty() && !resume && sessions.any { it.playbackState?.state in listOf(paused, stopped) } -> "Oynatma zaten durmuş."
                    else -> "NO_MEDIA"
                })
                return
            }
            if (resume) session.transportControls.play() else session.transportControls.pause()
            val deadline = android.os.SystemClock.elapsedRealtime() + 2500
            fun verify() {
                val state = session.playbackState?.state
                when {
                    if (resume) state == playing else state in listOf(paused, stopped) ->
                        result.success(if (resume) "Oynatma devam ediyor." else "Oynatma durduruldu.")
                    android.os.SystemClock.elapsedRealtime() >= deadline -> result.success("Oynatıcı komutu aldı, durum değişikliği doğrulanamadı.")
                    else -> mainHandler.postDelayed({ verify() }, 120)
                }
            }
            verify()
        } catch (_: SecurityException) { result.success("NO_ACCESS") }
          catch (_: Exception) { result.success("Oynatıcıya ulaşılamadı.") }
    }

    private fun spotifyControl(action: String?, result: MethodChannel.Result) {
        val manager = getSystemService(android.media.session.MediaSessionManager::class.java)
        try {
            val session = manager.getActiveSessions(ComponentName(this, JarvisNotificationListener::class.java))
                .firstOrNull { it.packageName == "com.spotify.music" }
            if (session == null) { result.success("Spotify’da açık oynatma oturumu yok."); return }
            val playing = android.media.session.PlaybackState.STATE_PLAYING
            val paused = android.media.session.PlaybackState.STATE_PAUSED
            when (action) {
                "status" -> {
                    val title = session.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
                    val artist = session.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
                    val track = listOfNotNull(title, artist).filter { it.isNotBlank() }.joinToString(" — ")
                    result.success(when (session.playbackState?.state) {
                        playing -> "Spotify çalıyor: $track"
                        paused -> "Spotify duraklatıldı: $track"
                        else -> "Spotify şu anda çalmıyor."
                    })
                }
                "pause" -> {
                    if (session.playbackState?.state != playing) { result.success("Spotify şu anda çalmıyor."); return }
                    session.transportControls.pause()
                    val until = android.os.SystemClock.elapsedRealtime() + 3000
                    fun verify() {
                        when {
                            session.playbackState?.state == paused -> result.success("Spotify duraklatıldı.")
                            android.os.SystemClock.elapsedRealtime() >= until -> result.success("Spotify duraklatma işlemi doğrulanamadı.")
                            else -> mainHandler.postDelayed({ verify() }, 120)
                        }
                    }
                    verify()
                }
                else -> result.success("Spotify komutu tanınmadı.")
            }
        } catch (_: SecurityException) { result.success("Spotify’yı denetlemek için Ege’nin bildirim erişimini aç.") }
    }

    private fun playSpotifyMusic(result: MethodChannel.Result) {
        val pkg = "com.spotify.music"
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        if (launch == null) {
            result.success("Spotify telefonda bulunamadı.")
            return
        }
        val manager = getSystemService(android.media.session.MediaSessionManager::class.java)
        val listener = ComponentName(this, JarvisNotificationListener::class.java)
        val deadline = android.os.SystemClock.elapsedRealtime() + 9000
        var sent = false
        var opened = false
        fun check() {
            try {
                val controller = manager.getActiveSessions(listener).firstOrNull { it.packageName == pkg }
                if (controller?.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING) {
                    val title = controller.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE)
                    result.success(if (title.isNullOrBlank()) "Spotify müzik çalıyor." else "Spotify çalıyor: $title")
                    return
                }
                if (!opened) {
                    opened = true
                    startActivity(launch)
                }
                if (controller != null && !sent && controller.playbackState?.state != android.media.session.PlaybackState.STATE_NONE) {
                    sent = true
                    controller.transportControls.play()
                }
                if (android.os.SystemClock.elapsedRealtime() >= deadline) {
                    result.success("Spotify açıldı ancak çalan bir parça doğrulanamadı.")
                    return
                }
                mainHandler.postDelayed({ check() }, 300)
            } catch (_: SecurityException) {
                result.success("Spotify oynatmasını denetlemek için Ege’nin bildirim erişimini aç.")
            } catch (_: Exception) {
                result.success("Spotify oynatması başlatılamadı.")
            }
        }
        check()
    }

    private fun openYouTube(query: String): String {
        val url = if (query.isBlank()) Uri.parse("https://www.youtube.com/")
            else Uri.parse("https://www.youtube.com/results").buildUpon().appendQueryParameter("search_query", query.trim()).build()
        try {
            val intent = if (query.isBlank()) packageManager.getLaunchIntentForPackage("com.google.android.youtube")
                else Intent(Intent.ACTION_VIEW, url).setPackage("com.google.android.youtube")
            if (intent != null) { startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return "app" }
        } catch (_: Throwable) {}
        return try { startActivity(Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); "browser" }
        catch (_: Throwable) { "unavailable" }
    }

    private fun launchAppByQuery(rawQuery: String): String? {
        // Commands resolved against the launcher already carry an exact package.
        // Open that package without enumerating every launcher activity again.
        val exact = rawQuery.trim()
        if (exact.contains('.') && !exact.contains(' ')) {
            val intent = packageManager.getLaunchIntentForPackage(exact)
            if (intent != null) {
                val label = packageManager.getApplicationLabel(packageManager.getApplicationInfo(exact, 0)).toString()
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return label
            }
        }
        val q = normalizeTrApp(rawQuery)
        if (q.isEmpty()) return null

        val aliasMap = mapOf(
            "kamera" to listOf("camera", "kamera"),
            "galeri" to listOf("gallery", "photos", "galeri"),
            "ayarlar" to listOf("settings", "ayarlar"),
            "hesap makinesi" to listOf("calculator", "hesap"),
            "saat" to listOf("clock", "alarm", "saat"),
            "takvim" to listOf("calendar", "takvim"),
            "mesajlar" to listOf("messages", "sms", "messaging"),
            "rehber" to listOf("contacts", "kisiler"),
            "haritalar" to listOf("maps", "harita"),
            "tarayici" to listOf("chrome", "browser"),
            "dosyalar" to listOf("files", "dosya"),
        )
        val candidates = ArrayList<String>().apply {
            add(q)
            aliasMap[q]?.let { addAll(it) }
        }

        val apps = queryInstalledApps()
        var bestMatch: Map<String, String>? = null
        var bestScore = -1
        for (app in apps) {
            val nameNorm = normalizeTrApp(app["name"] ?: "")
            val pkgNorm = (app["package"] ?: "").lowercase(Locale.ROOT)
            for (term in candidates) {
                val score = when {
                    pkgNorm == rawQuery.trim().lowercase(Locale.ROOT) -> 110
                    nameNorm == term || pkgNorm == term -> 100
                    nameNorm.startsWith(term) -> 80
                    nameNorm.contains(term) -> 60
                    pkgNorm.contains(term.replace(" ", "")) -> 40
                    else -> -1
                }
                if (score > bestScore) {
                    bestScore = score
                    bestMatch = app
                }
            }
        }
        val pkg = bestMatch?.get("package") ?: return null
        return try {
            val launchIntent = packageManager.getLaunchIntentForPackage(pkg) ?: return null
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            bestMatch["name"] ?: pkg
        } catch (_: Throwable) {
            null
        }
    }

    private fun openSystemSettingsPanel(target: String): Boolean {
        val action = when (target.lowercase(Locale.ROOT)) {
            "wifi", "wi-fi" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth", "bt" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "location", "konum", "gps" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "display", "ekran", "parlaklik", "parlaklık" -> Settings.ACTION_DISPLAY_SETTINGS
            "sound", "ses" -> Settings.ACTION_SOUND_SETTINGS
            "battery", "pil", "batarya" -> Intent.ACTION_POWER_USAGE_SUMMARY
            "apps", "uygulamalar" -> Settings.ACTION_APPLICATION_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        return try {
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Throwable) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Throwable) {
                false
            }
        }
    }

    private fun createSystemAlarm(hour: Int, minute: Int, message: String, days: List<Int> = emptyList()): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
                putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                if (days.isNotEmpty()) putExtra(AlarmClock.EXTRA_DAYS, ArrayList(days.filter { it in 1..7 }.distinct()))
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun openCalendarInsert(title: String, desc: String, startMs: Long, endMs: Long): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_INSERT).apply {
                data = CalendarContract.Events.CONTENT_URI
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.Events.DESCRIPTION, desc)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Android 13+ needs a runtime grant before any notification is shown. */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            try {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4460)
            } catch (_: Throwable) {}
        }
    }

    private fun postNotification(title: String, body: String): Boolean {
        return try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val chId = "jarvis_alerts"
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(chId, "Ege Bildirimleri", NotificationManager.IMPORTANCE_HIGH)
                nm.createNotificationChannel(ch)
                Notification.Builder(this, chId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val prefs = getSharedPreferences("jarvis_notif_ids", Context.MODE_PRIVATE)
            val nid = synchronized(MainActivity::class.java) {
                val next = (prefs.getInt("next", 0) + 1).let { if (it > 1_000_000) 1 else it }
                prefs.edit().putInt("next", next).apply()
                10000 + next
            }
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            val contentPi = launch?.let {
                PendingIntent.getActivity(this, nid, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val notif = builder
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setAutoCancel(true)
                .apply { if (contentPi != null) setContentIntent(contentPi) }
                .build()
            nm.notify(nid, notif)
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ======================================================================
    // EXTENDED DEVICE API (downloads, apps, system controls, contacts,
    // location, Termux). Every path catches Throwable and replies once.
    // ======================================================================

    private val downloadPrefsName = "jarvis_downloads"
    private val downloadPrefsKey = "ids"
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }
    private val defaultUserAgent = "Mozilla/5.0 (Linux; Android) JARVIS-Mobile/2.0"

    private fun safeReply(result: MethodChannel.Result, value: Any?) {
        val send = Runnable {
            try { result.success(value) } catch (_: Throwable) {}
        }
        if (Looper.myLooper() == Looper.getMainLooper()) send.run() else runOnUiThread(send)
    }

    private fun runInBackground(name: String, result: MethodChannel.Result, fallback: Any?, work: () -> Any?) {
        try {
            Thread {
                val value = try { work() } catch (_: Throwable) { fallback }
                safeReply(result, value)
            }.apply {
                this.name = name
                isDaemon = true
                start()
            }
        } catch (_: Throwable) {
            safeReply(result, fallback)
        }
    }

    private fun stringMapArg(call: MethodCall, key: String): Map<String, String> {
        val raw = call.argument<Any?>(key) as? Map<*, *> ?: return emptyMap()
        val out = LinkedHashMap<String, String>()
        for ((k, v) in raw) {
            if (k == null || v == null) continue
            out[k.toString()] = v.toString()
        }
        return out
    }

    private fun stringListArg(call: MethodCall, key: String): List<String> {
        val raw = call.argument<Any?>(key) as? List<*> ?: return emptyList()
        return raw.filterNotNull().map { it.toString() }
    }

    private fun handleExtendedCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            // ---------------- Downloads ----------------
            "enqueueDownload" -> {
                val url = call.argument<String>("url") ?: ""
                result.success(
                    enqueueDownload(
                        url = url,
                        fileName = call.argument<String>("fileName"),
                        mimeType = call.argument<String>("mimeType"),
                        subDir = call.argument<String>("subDir") ?: "Ege",
                        title = call.argument<String>("title"),
                        headers = stringMapArg(call, "headers"),
                    )
                )
            }
            "queryDownloads" -> runInBackground("jarvis-query-downloads", result, emptyList<Map<String, Any?>>()) {
                ManagedDownloads.rows() + queryDownloads()
            }
            "enqueueManagedDownload" -> {
                val id = ManagedDownloads.add(call.argument<String>("url") ?: "", call.argument<String>("fileName"), call.argument<String>("mimeType"))
                if (id != null && !JarvisDownloadService.start(this)) ManagedDownloads.control(id, "pause")
                result.success(id)
            }
            "managedDownloadControl" -> {
                val action = call.argument<String>("action") ?: ""
                val ok = ManagedDownloads.control(call.argument<Number>("id")?.toLong() ?: -1, action)
                if (ok && action == "resume") JarvisDownloadService.start(this)
                result.success(ok)
            }
            "downloadPreferences" -> {
                if (call.argument<Boolean>("save") == true) ManagedDownloads.configure(call.argument<Boolean>("wifiOnly") ?: false,
                    call.argument<Int>("limitKbps") ?: 0, call.argument<Int>("concurrency") ?: 2)
                result.success(mapOf("wifiOnly" to ManagedDownloads.wifiOnly, "limitKbps" to ManagedDownloads.limitKbps, "concurrency" to ManagedDownloads.concurrency))
            }
            "shareManagedDownload" -> result.success(ManagedDownloads.open(call.argument<Number>("id")?.toLong() ?: -1, true))
            "openDownload" -> {
                val id = call.argument<Number>("id")?.toLong() ?: -1L
                result.success(if (ManagedDownloads.contains(id)) ManagedDownloads.open(id, false) else openDownload(id))
            }
            "removeDownload" -> {
                val id = call.argument<Number>("id")?.toLong() ?: -1L
                result.success(if (ManagedDownloads.contains(id)) ManagedDownloads.control(id, "remove") else removeDownload(id))
            }
            "saveBytesToDownloads" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "jarvis_file"
                val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                val subDir = call.argument<String>("subDir") ?: ""
                if (bytes == null || bytes.isEmpty()) {
                    result.success(null)
                } else {
                    runInBackground("jarvis-save-bytes", result, null) {
                        saveBytesToDownloads(bytes, fileName, mime, subDir)
                    }
                }
            }
            "openFileUri" -> {
                val uri = call.argument<String>("uri") ?: ""
                result.success(openFileUri(uri, call.argument<String>("mimeType")))
            }
            "getCacheDir" -> result.success(cacheDir.absolutePath)
            // ---------------- Documents / music / reminders ----------------
            // ---------------- On-device Whisper (whisper.cpp) ----------------
            "whisperTranscribe" -> {
                val path = call.argument<String>("modelPath") ?: ""
                val wav = call.argument<ByteArray>("wav")
                val lang = call.argument<String>("language") ?: "tr"
                val fast = call.argument<Boolean>("fast") != false
                val prompt = call.argument<String>("prompt") ?: ""
                val threads = call.argument<Int>("threads") ?: 0
                if (wav == null || wav.isEmpty()) {
                    result.success(mapOf("ok" to false, "error" to "Ses verisi yok"))
                } else {
                    runInBackground("jarvis-whisper", result, mapOf("ok" to false, "error" to "Whisper çalışmadı")) {
                        JarvisWhisper.transcribe(path, wav, lang, fast, prompt, threads)
                    }
                }
            }
            "whisperRelease" -> runInBackground("jarvis-whisper-release", result, true) {
                JarvisWhisper.release()
                true
            }
            "whisperInfo" -> runInBackground("jarvis-whisper-info", result, mapOf("supported" to false)) {
                JarvisWhisper.info()
            }
            "renderPdf" -> {
                val spec = call.argument<String>("spec") ?: "{}"
                runInBackground("jarvis-pdf", result, null) { JarvisPdf.render(spec) }
            }
            "streamPlay" -> {
                val url = call.argument<String>("url") ?: ""
                val title = call.argument<String>("title") ?: ""
                result.success(JarvisStreamPlayer.play(this, url, title))
            }
            "streamPause" -> result.success(JarvisStreamPlayer.pause())
            "streamResume" -> result.success(JarvisStreamPlayer.resume())
            "streamStop" -> result.success(JarvisStreamPlayer.stop())
            "streamSeek" -> result.success(JarvisStreamPlayer.seek(call.argument<Number>("ms")?.toInt() ?: 0))
            "streamDuck" -> {
                JarvisStreamPlayer.duck(call.argument<Boolean>("on") == true)
                result.success(true)
            }
            "streamStatus" -> result.success(JarvisStreamPlayer.status())
            "requestNotificationPermission" -> {
                ensureNotificationPermission()
                result.success(true)
            }
            "deliverDueTimer" -> result.success(JarvisAlarms.deliverOnce(this, call.argument<String>("key").orEmpty()))
            "scheduleAlarm" -> {
                ensureNotificationPermission()
                val key = call.argument<String>("key") ?: "jarvis"
                val at = call.argument<Number>("atMs")?.toLong() ?: 0L
                val title = call.argument<String>("title") ?: "Ege"
                val body = call.argument<String>("body") ?: ""
                val daily = call.argument<Boolean>("daily") == true
                val route = call.argument<String>("route")
                result.success(JarvisAlarms.schedule(this, key, at, title, body, daily, route))
            }
            "cancelAlarm" -> result.success(JarvisAlarms.cancel(this, call.argument<String>("key") ?: ""))
            "canScheduleExactAlarms" -> result.success(JarvisAlarms.canExact(this))
            "openExactAlarmSettings" -> {
                result.success(
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        true
                    } catch (_: Throwable) { false }
                )
            }
            "installApk" -> {
                val path = call.argument<String>("path") ?: ""
                result.success(installApkFile(path))
            }

            // ---------------- App management ----------------
            "getAppIcon" -> {
                val pkg = call.argument<String>("package") ?: ""
                runInBackground("jarvis-app-icon", result, null) { renderAppIcon(pkg) }
            }
            "openAppInfo" -> {
                val pkg = call.argument<String>("package") ?: ""
                result.success(
                    pkg.isNotBlank() && tryStartActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                    )
                )
            }
            "uninstallApp" -> {
                val pkg = call.argument<String>("package") ?: ""
                result.success(
                    pkg.isNotBlank() && tryStartActivity(
                        Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
                    )
                )
            }
            "openPlayStore" -> {
                val q = call.argument<String>("query") ?: ""
                result.success(openPlayStore(q))
            }
            "hasUsageAccess" -> result.success(hasUsageAccess())
            "openUsageAccessSettings" -> {
                result.success(
                    tryStartActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) ||
                        tryStartActivity(Intent(Settings.ACTION_SETTINGS))
                )
            }
            "getAppUsageStats" -> {
                val days = (call.argument<Number>("days")?.toInt() ?: 1).coerceIn(1, 365)
                runInBackground("jarvis-usage-stats", result, emptyList<Map<String, Any>>()) {
                    queryAppUsageStats(days)
                }
            }
            "isPackageInstalled" -> {
                val pkg = call.argument<String>("package") ?: ""
                result.success(isPackageInstalledInternal(pkg))
            }

            // ---------------- System controls ----------------
            "openSettingsPanel" -> {
                val panel = call.argument<String>("panel") ?: ""
                result.success(openSettingsPanelNamed(panel))
            }
            "getBrightness" -> result.success(getBrightnessPercent())
            "setBrightness" -> {
                val pct = call.argument<Number>("percent")?.toInt() ?: 50
                result.success(setBrightnessPercent(pct))
            }
            "setRingerMode" -> {
                val mode = call.argument<String>("mode") ?: "normal"
                result.success(setRingerModeNamed(mode))
            }
            "getRingerMode" -> result.success(getRingerModeName())
            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on") ?: false
                result.success(setKeepScreenOn(on))
            }
            "vibrate" -> {
                val ms = call.argument<Number>("ms")?.toLong() ?: 300L
                result.success(vibrateFor(ms))
            }
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                result.success(shareTextInternal(text, call.argument<String>("package")))
            }

            // ---------------- Contacts & calling ----------------
            "searchContacts" -> {
                val query = call.argument<String>("query") ?: ""
                val limit = (call.argument<Number>("limit")?.toInt() ?: 10).coerceIn(1, 100)
                if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                    try {
                        requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), 4421)
                    } catch (_: Throwable) {}
                    result.success(emptyList<Map<String, String>>())
                } else {
                    runInBackground("jarvis-contacts", result, emptyList<Map<String, String>>()) {
                        searchContactsInternal(query, limit)
                    }
                }
            }
            "contactsPermission" -> {
                val granted = checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
                result.success(if (granted) "granted" else "denied")
            }
            "dialNumber" -> {
                val number = call.argument<String>("number") ?: ""
                result.success(dialNumberInternal(number))
            }

            // ---------------- Location ----------------
            "getCurrentLocation" -> getCurrentLocationAsync(result)

            // ---------------- Termux ----------------
            "runTermuxCommand" -> {
                val exe = call.argument<String>("executable") ?: ""
                result.success(
                    runTermuxCommandInternal(
                        executable = exe,
                        args = stringListArg(call, "args"),
                        workDir = call.argument<String>("workDir"),
                        background = call.argument<Boolean>("background") ?: true,
                    )
                )
            }
            else -> return false
        }
        return true
    }

    private fun tryStartActivity(intent: Intent, newTask: Boolean = true): Boolean {
        return try {
            if (newTask) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ---------------- Downloads ----------------

    private fun sanitizeFileName(name: String): String {
        val cleaned = name
            .replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_")
            .trim()
            .trim('.')
            .trim()
        val base = cleaned.ifEmpty { "jarvis_file" }
        return if (base.length > 120) {
            val dot = base.lastIndexOf('.')
            if (dot > 0 && base.length - dot <= 10) {
                base.substring(0, 120 - (base.length - dot)) + base.substring(dot)
            } else {
                base.take(120)
            }
        } else {
            base
        }
    }

    private fun sanitizeSubDir(sub: String): String {
        val parts = sub.split('/', '\\')
            .map { it.replace(Regex("[^\\p{L}\\p{N} _.-]"), "_").trim().trim('.') }
            .filter { it.isNotEmpty() }
        return if (parts.isEmpty()) "Ege" else if (parts.first() in listOf("Ege", "JARVIS")) (listOf("Ege") + parts.drop(1)).joinToString("/") else "Ege/" + parts.joinToString("/")
    }

    private fun loadDownloadIds(): MutableSet<Long> {
        return try {
            val prefs = getSharedPreferences(downloadPrefsName, Context.MODE_PRIVATE)
            val raw = prefs.getStringSet(downloadPrefsKey, emptySet()) ?: emptySet()
            raw.mapNotNull { it.toLongOrNull() }.toMutableSet()
        } catch (_: Throwable) {
            mutableSetOf()
        }
    }

    private fun saveDownloadIds(ids: Set<Long>) {
        try {
            getSharedPreferences(downloadPrefsName, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(downloadPrefsKey, HashSet(ids.map { it.toString() }))
                .apply()
        } catch (_: Throwable) {}
    }

    private fun enqueueDownload(
        url: String,
        fileName: String?,
        mimeType: String?,
        subDir: String,
        title: String?,
        headers: Map<String, String>,
    ): Long? {
        return try {
            val trimmedUrl = url.trim()
            val uri = Uri.parse(trimmedUrl)
            val scheme = uri.scheme?.lowercase(Locale.ROOT)
            if (scheme != "http" && scheme != "https") return null
            val rawName = if (fileName.isNullOrBlank()) {
                URLUtil.guessFileName(trimmedUrl, null, mimeType?.takeIf { it.isNotBlank() })
            } else {
                fileName
            }
            val safeName = sanitizeFileName(rawName)
            val safeSub = sanitizeSubDir(subDir)

            val req = DownloadManager.Request(uri)
            req.setTitle(title?.takeIf { it.isNotBlank() } ?: safeName)
            req.setDescription("Ege")
            if (!mimeType.isNullOrBlank()) req.setMimeType(mimeType)
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            req.setAllowedOverMetered(true)
            req.setAllowedOverRoaming(true)
            var hasUa = false
            for ((k, v) in headers) {
                if (k.isBlank()) continue
                if (k.equals("User-Agent", ignoreCase = true)) hasUa = true
                req.addRequestHeader(k, v)
            }
            if (!hasUa) req.addRequestHeader("User-Agent", defaultUserAgent)

            var publicOk = true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
            ) {
                publicOk = false
                try {
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4451)
                } catch (_: Throwable) {}
            }
            if (publicOk) {
                try {
                    req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "$safeSub/$safeName")
                } catch (_: Throwable) {
                    publicOk = false
                }
            }
            if (!publicOk) {
                // App-specific external storage needs no permission.
                req.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, "$safeSub/$safeName")
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                @Suppress("DEPRECATION")
                req.allowScanningByMediaScanner()
            }
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val id = dm.enqueue(req)
            val ids = loadDownloadIds()
            ids.add(id)
            saveDownloadIds(ids)
            id
        } catch (_: Throwable) {
            null
        }
    }

    private fun Cursor.strCol(col: String): String? {
        val i = getColumnIndex(col)
        return if (i >= 0 && !isNull(i)) getString(i) else null
    }

    private fun Cursor.longCol(col: String, def: Long): Long {
        val i = getColumnIndex(col)
        return if (i >= 0 && !isNull(i)) getLong(i) else def
    }

    private fun downloadStatusName(status: Int): String = when (status) {
        DownloadManager.STATUS_PENDING -> "pending"
        DownloadManager.STATUS_RUNNING -> "running"
        DownloadManager.STATUS_PAUSED -> "paused"
        DownloadManager.STATUS_SUCCESSFUL -> "successful"
        DownloadManager.STATUS_FAILED -> "failed"
        else -> "pending"
    }

    private fun downloadReasonText(status: Int, reason: Int): String {
        return when (status) {
            DownloadManager.STATUS_FAILED -> when (reason) {
                DownloadManager.ERROR_CANNOT_RESUME -> "İndirme devam ettirilemiyor"
                DownloadManager.ERROR_DEVICE_NOT_FOUND -> "Depolama birimi bulunamadı"
                DownloadManager.ERROR_FILE_ALREADY_EXISTS -> "Dosya zaten mevcut"
                DownloadManager.ERROR_FILE_ERROR -> "Dosya yazma hatası"
                DownloadManager.ERROR_HTTP_DATA_ERROR -> "HTTP veri hatası"
                DownloadManager.ERROR_INSUFFICIENT_SPACE -> "Yetersiz depolama alanı"
                DownloadManager.ERROR_TOO_MANY_REDIRECTS -> "Çok fazla yönlendirme"
                DownloadManager.ERROR_UNHANDLED_HTTP_CODE -> "Beklenmeyen HTTP yanıtı"
                DownloadManager.ERROR_UNKNOWN -> "Bilinmeyen hata"
                in 400..599 -> "Sunucu hatası (HTTP $reason)"
                else -> "İndirme başarısız ($reason)"
            }
            DownloadManager.STATUS_PAUSED -> when (reason) {
                DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "Wi-Fi bekleniyor"
                DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "Ağ bağlantısı bekleniyor"
                DownloadManager.PAUSED_WAITING_TO_RETRY -> "Yeniden denenecek"
                else -> "Duraklatıldı"
            }
            else -> ""
        }
    }

    private fun queryDownloads(): List<Map<String, Any?>> {
        return try {
            val ids = loadDownloadIds()
            if (ids.isEmpty()) return emptyList()
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val query = DownloadManager.Query().setFilterById(*ids.toLongArray())
            val out = ArrayList<Map<String, Any?>>()
            val found = HashSet<Long>()
            dm.query(query)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.longCol(DownloadManager.COLUMN_ID, -1L)
                    if (id < 0) continue
                    found.add(id)
                    val status = c.longCol(DownloadManager.COLUMN_STATUS, DownloadManager.STATUS_PENDING.toLong()).toInt()
                    val reason = c.longCol(DownloadManager.COLUMN_REASON, 0L).toInt()
                    out.add(
                        mapOf(
                            "id" to id,
                            "title" to (c.strCol(DownloadManager.COLUMN_TITLE) ?: ""),
                            "url" to (c.strCol(DownloadManager.COLUMN_URI) ?: ""),
                            "localUri" to (c.strCol(DownloadManager.COLUMN_LOCAL_URI) ?: ""),
                            "mimeType" to (c.strCol(DownloadManager.COLUMN_MEDIA_TYPE) ?: ""),
                            "totalBytes" to c.longCol(DownloadManager.COLUMN_TOTAL_SIZE_BYTES, -1L),
                            "downloadedBytes" to c.longCol(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR, 0L),
                            "status" to downloadStatusName(status),
                            "reason" to downloadReasonText(status, reason),
                            "lastModifiedMs" to c.longCol(DownloadManager.COLUMN_LAST_MODIFIED_TIMESTAMP, 0L),
                        )
                    )
                }
            }
            if (found.size != ids.size) {
                // Prune ids the system no longer knows about (cleared by user).
                saveDownloadIds(ids.filter { found.contains(it) }.toSet())
            }
            out.sortByDescending { (it["id"] as? Long) ?: 0L }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun openDownload(id: Long): Boolean {
        if (id < 0) return false
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val uri = dm.getUriForDownloadedFile(id) ?: return false
            val mime = dm.getMimeTypeForDownloadedFile(id)?.takeIf { it.isNotBlank() } ?: "*/*"
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(view, "Dosyayı aç").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun removeDownload(id: Long): Boolean {
        if (id < 0) return false
        val ids = loadDownloadIds()
        ids.remove(id)
        saveDownloadIds(ids)
        return try {
            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.remove(id)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun uniqueFile(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (f.exists() && i < 1000) {
            f = File(dir, "$base ($i)$ext")
            i++
        }
        return f
    }

    private fun saveBytesToDownloads(bytes: ByteArray, fileName: String, mimeType: String, subDir: String = ""): String? {
        val safeName = sanitizeFileName(fileName)
        val cleanSub = subDir.split('/', '\\')
            .map { sanitizeFileName(it) }
            .filter { it.isNotBlank() && it != "." && it != ".." }
            .joinToString("/")
        val relative = if (cleanSub.isEmpty()) "Ege" else "Ege/$cleanSub"
        val mime = mimeType.ifBlank { "application/octet-stream" }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + relative)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
                try {
                    val os = resolver.openOutputStream(uri) ?: throw IllegalStateException("no stream")
                    os.use { it.write(bytes) }
                    val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                    resolver.update(uri, done, null, null)
                } catch (t: Throwable) {
                    try { resolver.delete(uri, null, null) } catch (_: Throwable) {}
                    return null
                }
                uri.toString()
            } else {
                val dir: File = if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
                    @Suppress("DEPRECATION")
                    File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), relative)
                } else {
                    try {
                        requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4452)
                    } catch (_: Throwable) {}
                    File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir, relative)
                }
                if (!dir.exists()) dir.mkdirs()
                val file = uniqueFile(dir, safeName)
                FileOutputStream(file).use { it.write(bytes) }
                try {
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(file.absolutePath), arrayOf(mime), null)
                } catch (_: Throwable) {}
                file.absolutePath
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun guessMimeFromName(name: String): String? {
        val ext = MimeTypeMap.getFileExtensionFromUrl(name)?.takeIf { it.isNotEmpty() }
            ?: name.substringAfterLast('.', "").takeIf { it.isNotEmpty() }
            ?: return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase(Locale.ROOT))
    }

    private fun openFileUri(uriOrPath: String, mimeType: String?): Boolean {
        val trimmed = uriOrPath.trim()
        if (trimmed.isEmpty()) return false
        return try {
            val uri: Uri
            var fallbackName = trimmed
            if (trimmed.startsWith("content://")) {
                uri = Uri.parse(trimmed)
            } else {
                val path = if (trimmed.startsWith("file://")) Uri.parse(trimmed).path ?: return false else trimmed
                val file = File(path)
                if (!file.exists()) return false
                fallbackName = file.name
                uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            }
            val mime = mimeType?.takeIf { it.isNotBlank() }
                ?: try { contentResolver.getType(uri) } catch (_: Throwable) { null }
                ?: guessMimeFromName(fallbackName)
                ?: "*/*"
            val view = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(view, "Dosyayı aç").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Opens Android's package installer for an APK in the app cache. */
    private fun installApkFile(path: String): String {
        return try {
            val file = File(path)
            if (!file.exists() || file.length() < 1024) return "missing"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                val settingsIntent = Intent(
                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(settingsIntent)
                return "needs_permission"
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (t: Throwable) {
            "error: ${t.message}"
        }
    }

    // ---------------- App management ----------------

    // Uygulama listesi önbelleği (60 sn TTL): her çağrıda tüm paketler yeniden taranmasın.
    private val appListLock = Any()
    private var appListCache: List<Map<String, Any>>? = null
    private var appListCacheAtMs = 0L

    private fun cachedInstalledApps(): List<Map<String, Any>> {
        val now = android.os.SystemClock.elapsedRealtime()
        synchronized(appListLock) {
            val c = appListCache
            if (c != null && now - appListCacheAtMs < 60_000L) return c
        }
        val fresh = queryInstalledAppsDetailed()
        synchronized(appListLock) {
            if (fresh.isNotEmpty()) {
                appListCache = fresh
                appListCacheAtMs = android.os.SystemClock.elapsedRealtime()
            }
        }
        return fresh
    }

    private fun queryInstalledAppsDetailed(): List<Map<String, Any>> {
        return try {
            val pm = packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolved = pm.queryIntentActivities(mainIntent, 0)
            val seen = HashSet<String>()
            val out = ArrayList<Map<String, Any>>()
            for (ri in resolved) {
                val pkg = ri.activityInfo?.packageName ?: continue
                if (!seen.add(pkg)) continue
                val label = try { ri.loadLabel(pm)?.toString()?.trim() } catch (_: Throwable) { null } ?: pkg
                if (label.isEmpty()) continue
                var versionName = ""
                var isSystem = false
                var firstInstall = 0L
                var lastUpdate = 0L
                try {
                    @Suppress("DEPRECATION")
                    val info = pm.getPackageInfo(pkg, 0)
                    versionName = info.versionName ?: ""
                    firstInstall = info.firstInstallTime
                    lastUpdate = info.lastUpdateTime
                    val flags = info.applicationInfo?.flags ?: 0
                    isSystem = (flags and ApplicationInfo.FLAG_SYSTEM) != 0
                } catch (_: Throwable) {}
                out.add(
                    mapOf(
                        "name" to label,
                        "package" to pkg,
                        "versionName" to versionName,
                        "isSystem" to isSystem,
                        "firstInstallMs" to firstInstall,
                        "lastUpdateMs" to lastUpdate,
                    )
                )
            }
            out.sortBy { (it["name"] as? String ?: "").lowercase(Locale.ROOT) }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun renderAppIcon(pkg: String): ByteArray? {
        if (pkg.isBlank()) return null
        return try {
            val raw = packageManager.getApplicationIcon(pkg)
            val drawable = raw.constantState?.newDrawable(resources)?.mutate() ?: raw
            val size = 96
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && drawable is AdaptiveIconDrawable) {
                // Draw background + foreground layers (the adaptive mask is applied by draw()).
                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)
            } else {
                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)
            }
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            bmp.recycle()
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    private fun openPlayStore(rawQuery: String): Boolean {
        val q = rawQuery.trim()
        if (q.isEmpty()) {
            return tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=apps"))) ||
                tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps")))
        }
        val looksLikePackage = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)+$").matches(q)
        val encoded = Uri.encode(q)
        return if (looksLikePackage) {
            tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$encoded"))) ||
                tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$encoded")))
        } else {
            tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=$encoded&c=apps"))) ||
                tryStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/search?q=$encoded&c=apps")))
        }
    }

    private fun hasUsageAccess(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val uid = android.os.Process.myUid()
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, uid, packageName)
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, uid, packageName)
            }
            if (mode == AppOpsManager.MODE_DEFAULT) {
                checkCallingOrSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) == PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun queryAppUsageStats(days: Int): List<Map<String, Any>> {
        if (!hasUsageAccess()) return emptyList()
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return emptyList()
        val end = System.currentTimeMillis()
        val start = end - days.toLong() * 24L * 60L * 60L * 1000L
        val stats = usm.queryAndAggregateUsageStats(start, end) ?: return emptyList()
        val pm = packageManager
        val rows = ArrayList<Map<String, Any>>()
        for ((pkg, st) in stats) {
            val fg = st.totalTimeInForeground
            if (fg <= 0L) continue
            if (pkg == null) continue
            val label = try {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0).loadLabel(pm).toString()
            } catch (_: Throwable) {
                pkg
            }
            rows.add(
                mapOf(
                    "package" to pkg,
                    "name" to label,
                    "foregroundMs" to fg,
                    "lastUsedMs" to st.lastTimeUsed,
                )
            )
        }
        rows.sortByDescending { (it["foregroundMs"] as? Long) ?: 0L }
        return rows.take(30)
    }

    private fun isPackageInstalledInternal(pkg: String): Boolean {
        if (pkg.isBlank()) return false
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Throwable) {
            false
        }
    }

    // ---------------- System controls ----------------

    private fun openSettingsPanelNamed(panel: String): Boolean {
        val p = panel.trim().lowercase(Locale.ROOT).replace('-', '_').replace(' ', '_')
        val q = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        // Pair(intent, addNewTask). Panels are floating sheets on top of JARVIS.
        val candidates = ArrayList<Pair<Intent, Boolean>>()
        fun add(action: String, newTask: Boolean = true) = candidates.add(Pair(Intent(action), newTask))
        fun panelIntent(action: String) {
            if (q) candidates.add(Pair(Intent(action), false))
        }

        when (p) {
            "internet", "internet_connectivity", "mobile_data", "mobil_veri", "data", "veri" -> {
                panelIntent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
                add(Settings.ACTION_WIRELESS_SETTINGS)
            }
            "wifi", "wi_fi", "wlan" -> {
                panelIntent(Settings.Panel.ACTION_WIFI)
                add(Settings.ACTION_WIFI_SETTINGS)
            }
            "volume", "ses_paneli" -> {
                panelIntent(Settings.Panel.ACTION_VOLUME)
                add(Settings.ACTION_SOUND_SETTINGS)
            }
            "nfc" -> {
                panelIntent(Settings.Panel.ACTION_NFC)
                add(Settings.ACTION_NFC_SETTINGS)
                add(Settings.ACTION_WIRELESS_SETTINGS)
            }
            "bluetooth", "bt" -> add(Settings.ACTION_BLUETOOTH_SETTINGS)
            "hotspot", "tethering", "tether", "erisim_noktasi" -> {
                val tether = Intent().setComponent(
                    ComponentName("com.android.settings", "com.android.settings.TetherSettings")
                )
                val resolvable = try { tether.resolveActivity(packageManager) != null } catch (_: Throwable) { false }
                if (resolvable) candidates.add(Pair(tether, true))
                add(Settings.ACTION_WIRELESS_SETTINGS)
            }
            "airplane", "airplane_mode", "ucak_modu" -> add(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            "dnd", "do_not_disturb", "rahatsiz_etmeyin", "zen" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) add(Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS)
                add("android.settings.ZEN_MODE_SETTINGS")
                add(Settings.ACTION_SOUND_SETTINGS)
            }
            "battery_saver", "power_saver", "pil_tasarrufu" -> {
                add(Settings.ACTION_BATTERY_SAVER_SETTINGS)
                add(Intent.ACTION_POWER_USAGE_SUMMARY)
            }
            "battery", "pil", "batarya" -> add(Intent.ACTION_POWER_USAGE_SUMMARY)
            "developer", "developer_options", "gelistirici" -> add(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            "storage", "depolama" -> {
                add(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
                add(Settings.ACTION_MEMORY_CARD_SETTINGS)
            }
            "accessibility", "erisilebilirlik" -> add(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "date", "time", "date_time", "tarih", "saat" -> add(Settings.ACTION_DATE_SETTINGS)
            "language", "locale", "dil" -> add(Settings.ACTION_LOCALE_SETTINGS)
            "security", "guvenlik" -> add(Settings.ACTION_SECURITY_SETTINGS)
            "location", "konum", "gps" -> add(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "display", "ekran", "brightness", "parlaklik" -> add(Settings.ACTION_DISPLAY_SETTINGS)
            "sound", "ses" -> add(Settings.ACTION_SOUND_SETTINGS)
            "apps", "applications", "uygulamalar" -> add(Settings.ACTION_APPLICATION_SETTINGS)
            "default_apps", "varsayilan_uygulamalar" -> add(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            "vpn" -> add(Settings.ACTION_VPN_SETTINGS)
            "cast", "yansitma" -> add(Settings.ACTION_CAST_SETTINGS)
            "usage_access" -> add(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "notifications", "bildirimler", "notification" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    candidates.add(
                        Pair(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                            true,
                        )
                    )
                }
                add("android.settings.NOTIFICATION_SETTINGS")
                candidates.add(
                    Pair(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
                        true,
                    )
                )
            }
            "all_notifications" -> add("android.settings.NOTIFICATION_SETTINGS")
            else -> {}
        }
        add(Settings.ACTION_SETTINGS)
        for ((intent, newTask) in candidates) {
            if (tryStartActivity(intent, newTask)) return true
        }
        return false
    }

    private fun getBrightnessPercent(): Int {
        return try {
            val v = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
            ((v * 100.0) / 255.0).toInt().coerceIn(0, 100)
        } catch (_: Throwable) {
            50
        }
    }

    private fun setBrightnessPercent(percent: Int): String {
        val pct = percent.coerceIn(0, 100)
        return try {
            try {
                val lp = window.attributes
                lp.screenBrightness = (pct / 100f).coerceIn(0.01f, 1f)
                window.attributes = lp
            } catch (_: Throwable) {}
            if (Settings.System.canWrite(this)) {
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS_MODE,
                    Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
                )
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    ((pct * 255) / 100).coerceIn(1, 255),
                )
                // Sistem parlaklığı yazıldı: pencere geçersiz kılmasını kaldır (yoksa ayar uygulamada takılı kalır).
                try {
                    val lp2 = window.attributes
                    lp2.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    window.attributes = lp2
                } catch (_: Throwable) {}
                "OK"
            } else {
                tryStartActivity(
                    Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:$packageName"))
                )
                "PERMISSION_NEEDED"
            }
        } catch (_: Throwable) {
            "ERROR"
        }
    }

    private fun openNotificationPolicyAccess() {
        tryStartActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) ||
            tryStartActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
    }

    private fun setRingerModeNamed(mode: String): String {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val target = when (mode.trim().lowercase(Locale.ROOT)) {
                "normal", "ring", "sound", "ses", "zil" -> AudioManager.RINGER_MODE_NORMAL
                "vibrate", "vibration", "titresim" -> AudioManager.RINGER_MODE_VIBRATE
                "silent", "mute", "sessiz" -> AudioManager.RINGER_MODE_SILENT
                else -> return "ERROR"
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !nm.isNotificationPolicyAccessGranted) {
                val needsPolicy = target == AudioManager.RINGER_MODE_SILENT ||
                    am.ringerMode == AudioManager.RINGER_MODE_SILENT
                if (needsPolicy) {
                    openNotificationPolicyAccess()
                    return "PERMISSION_NEEDED"
                }
            }
            try {
                am.ringerMode = target
                "OK"
            } catch (_: SecurityException) {
                openNotificationPolicyAccess()
                "PERMISSION_NEEDED"
            }
        } catch (_: Throwable) {
            "ERROR"
        }
    }

    private fun getRingerModeName(): String {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (am.ringerMode) {
                AudioManager.RINGER_MODE_SILENT -> "silent"
                AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
                else -> "normal"
            }
        } catch (_: Throwable) {
            "normal"
        }
    }

    private fun setKeepScreenOn(on: Boolean): Boolean {
        return try {
            runOnUiThread {
                try {
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                } catch (_: Throwable) {}
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun vibrateFor(msRaw: Long): Boolean {
        val ms = msRaw.coerceIn(1L, 5000L)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (!v.hasVibrator()) return false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(ms)
                }
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun shareTextInternal(text: String, pkg: String?): Boolean {
        if (text.isEmpty()) return false
        return try {
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            if (!pkg.isNullOrBlank()) {
                send.setPackage(pkg)
                tryStartActivity(send)
            } else {
                tryStartActivity(Intent.createChooser(send, "Paylaş"))
            }
        } catch (_: Throwable) {
            false
        }
    }

    // ---------------- Contacts & calling ----------------

    private fun searchContactsInternal(query: String, limit: Int): List<Map<String, String>> {
        val q = query.trim()
        val phoneUri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val nameCol = ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
        val numCol = ContactsContract.CommonDataKinds.Phone.NUMBER
        val projection = arrayOf(nameCol, numCol)
        val out = LinkedHashMap<String, Map<String, String>>()

        fun addRow(name: String, phone: String) {
            val digits = phone.filter { it.isDigit() || it == '+' }
            if (digits.isEmpty()) return
            val key = name.lowercase(Locale.ROOT) + "|" + digits.takeLast(10)
            if (!out.containsKey(key)) out[key] = mapOf("name" to name, "phone" to phone.trim())
        }

        if (q.isNotEmpty()) {
            val escaped = q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            try {
                contentResolver.query(
                    phoneUri,
                    projection,
                    "$nameCol LIKE ? ESCAPE '\\'",
                    arrayOf("%$escaped%"),
                    "$nameCol ASC",
                )?.use { c ->
                    while (c.moveToNext() && out.size < limit) {
                        val name = c.strCol(nameCol) ?: continue
                        val phone = c.strCol(numCol) ?: continue
                        addRow(name, phone)
                    }
                }
            } catch (_: Throwable) {}
        }

        // Hits from SQL LIKE (accent-sensitive) are merged with a Turkish-insensitive
        // scan over ALL rows; ranked exact > word-prefix > contains.
        val nq = normalizeTrApp(q)
        val caseSuffixes = setOf("yi", "yu", "i", "e", "a", "ye", "ya")
        val tokens = nq.split(' ').filter { it.isNotEmpty() && !(it.length <= 2 && (it in caseSuffixes || it == "yı" || it == "yü" || it == "ı" || it == "ü")) }
        val scored = LinkedHashMap<String, Pair<Int, Map<String, String>>>()
        fun score(nn: String): Int {
            if (nq.isEmpty()) return 2
            if (nn == nq) return 0
            val words = nn.split(' ')
            if (words.any { it.startsWith(nq) } || nn.startsWith(nq)) return 1
            if (tokens.isNotEmpty() && tokens.all { tok -> words.any { it.startsWith(tok) } }) return 1
            return 2
        }
        fun keyOf(name: String, phone: String): String {
            val digits = phone.filter { it.isDigit() || it == '+' }
            return name.lowercase(Locale.ROOT) + "|" + digits.takeLast(10)
        }
        for ((key, row) in out) {
            scored[key] = Pair(score(normalizeTrApp(row["name"] ?: "")), row)
        }
        try {
            contentResolver.query(phoneUri, projection, null, null, "$nameCol ASC")?.use { c ->
                while (c.moveToNext()) {
                    val name = c.strCol(nameCol) ?: continue
                    val phone = c.strCol(numCol) ?: continue
                    if (phone.none { it.isDigit() }) continue
                    val key = keyOf(name, phone)
                    if (scored.containsKey(key)) continue
                    val nn = normalizeTrApp(name)
                    val words = nn.split(' ')
                    val match = nq.isEmpty() ||
                        nn.startsWith(nq) ||
                        words.any { it.startsWith(nq) } ||
                        (tokens.isNotEmpty() && tokens.all { tok -> words.any { it.startsWith(tok) } })
                    if (match) scored[key] = Pair(score(nn), mapOf("name" to name, "phone" to phone.trim()))
                }
            }
        } catch (_: Throwable) {}
        return scored.values.sortedBy { it.first }.map { it.second }.take(limit)
    }

    private fun dialNumberInternal(number: String): Boolean {
        val cleaned = number.filter { it.isDigit() || it == '+' || it == '*' || it == '#' || it == ',' || it == ';' }
        if (cleaned.isEmpty()) return false
        return tryStartActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(cleaned))))
    }

    // ---------------- Location ----------------

    @SuppressLint("MissingPermission")
    private fun bestLastKnownLocation(lm: LocationManager): Location? {
        var best: Location? = null
        for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)) {
            try {
                val loc = lm.getLastKnownLocation(p) ?: continue
                if (best == null || loc.time > best.time) best = loc
            } catch (_: Throwable) {}
        }
        return best
    }

    @SuppressLint("MissingPermission")
    private fun getCurrentLocationAsync(result: MethodChannel.Result) {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            try {
                requestPermissions(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                    4431,
                )
            } catch (_: Throwable) {}
            result.success(null)
            return
        }
        val replied = AtomicBoolean(false)
        fun reply(loc: Location?) {
            if (!replied.compareAndSet(false, true)) return
            val payload: Map<String, Any>? = loc?.let {
                mapOf(
                    "lat" to it.latitude,
                    "lon" to it.longitude,
                    "accuracy" to it.accuracy.toDouble(),
                    "provider" to (it.provider ?: ""),
                )
            }
            safeReply(result, payload)
        }

        try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            fun enabled(p: String): Boolean = try { lm.isProviderEnabled(p) } catch (_: Throwable) { false }

            var provider: String? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    if (lm.hasProvider(LocationManager.FUSED_PROVIDER) && enabled(LocationManager.FUSED_PROVIDER)) {
                        provider = LocationManager.FUSED_PROVIDER
                    }
                } catch (_: Throwable) {}
            }
            if (provider == null && enabled(LocationManager.NETWORK_PROVIDER)) provider = LocationManager.NETWORK_PROVIDER
            if (provider == null && fine && enabled(LocationManager.GPS_PROVIDER)) provider = LocationManager.GPS_PROVIDER

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (provider == null) {
                    reply(bestLastKnownLocation(lm))
                    return
                }
                val cancel = CancellationSignal()
                mainHandler.postDelayed({
                    if (!replied.get()) {
                        try { cancel.cancel() } catch (_: Throwable) {}
                        reply(bestLastKnownLocation(lm))
                    }
                }, 10_000L)
                lm.getCurrentLocation(provider, cancel, mainExecutor, Consumer { loc ->
                    reply(loc ?: bestLastKnownLocation(lm))
                })
            } else {
                val last = bestLastKnownLocation(lm)
                if (last != null || provider == null) {
                    reply(last)
                    return
                }
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        reply(location)
                        try { lm.removeUpdates(this) } catch (_: Throwable) {}
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                    override fun onProviderEnabled(provider: String) {}

                    override fun onProviderDisabled(provider: String) {}
                }
                mainHandler.postDelayed({
                    if (!replied.get()) {
                        try { lm.removeUpdates(listener) } catch (_: Throwable) {}
                        reply(null)
                    }
                }, 10_000L)
                @Suppress("DEPRECATION")
                lm.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }
        } catch (_: Throwable) {
            reply(null)
        }
    }

    // ---------------- Termux ----------------

    private fun runTermuxCommandInternal(
        executable: String,
        args: List<String>,
        workDir: String?,
        background: Boolean,
    ): String {
        if (executable.isBlank()) return "ERROR:executable is empty"
        if (!isPackageInstalledInternal("com.termux")) return "TERMUX_NOT_INSTALLED"
        val perm = "com.termux.permission.RUN_COMMAND"
        if (checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
            try {
                requestPermissions(arrayOf(perm), 4441)
            } catch (_: Throwable) {}
            return "PERMISSION_NEEDED"
        }
        return try {
            val intent = Intent("com.termux.RUN_COMMAND").apply {
                setClassName("com.termux", "com.termux.app.RunCommandService")
                putExtra("com.termux.RUN_COMMAND_PATH", executable)
                putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args.toTypedArray())
                if (!workDir.isNullOrBlank()) putExtra("com.termux.RUN_COMMAND_WORKDIR", workDir)
                putExtra("com.termux.RUN_COMMAND_BACKGROUND", background)
                putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            "OK"
        } catch (t: Throwable) {
            "ERROR:${t.message ?: t.javaClass.simpleName}"
        }
    }

    private val vault by lazy { JarvisVault(this) }
    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == JarvisVault.REQUEST) vault.onResult(resultCode, data)
        if (requestCode == GoogleAccountBridge.REQUEST) googleAccounts.onResult(resultCode, data)
    }

    override fun onDestroy() {
        liveDuplex.stop()
        vault.close()
        phoneSpeech.cancel()
        phoneAudioSpeech.cancel()
        googleAccounts.cancel()
        microsoftAccounts.cancel()
        val owner = instance === this
        if (instance === this) instance = null
        if (isFinishing || owner) {
            // Etkinlik ölünce canlı/ajan nedenleri takılı kalmasın; uyandırma sürsün.
            try {
                JarvisKeepAlive.release(applicationContext, "live")
                JarvisKeepAlive.release(applicationContext, "agent")
                JarvisWakeWord.resumeIfEnabled(applicationContext)
            } catch (_: Throwable) {}
        }
        stopWakeMic()
        cancelMicCapture()
        stopLivePcmMic()
        closeLiveAudioStream()
        stopAudioPlayer()
        super.onDestroy()
    }

    private fun collectDeviceInfo(): Map<String, Any> {
        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val batteryPct = if (level >= 0 && scale > 0) (level * 100) / scale else -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        val actMgr = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actMgr.getMemoryInfo(memInfo)
        val totalRamMb = (memInfo.totalMem / (1024L * 1024L)).toInt()
        val availRamMb = (memInfo.availMem / (1024L * 1024L)).toInt()
        val usedRamMb = (totalRamMb - availRamMb).coerceAtLeast(0)

        val stat = StatFs(Environment.getDataDirectory().path)
        val totalStorageGb = (stat.blockCountLong * stat.blockSizeLong) / (1024.0 * 1024.0 * 1024.0)
        val freeStorageGb = (stat.availableBlocksLong * stat.blockSizeLong) / (1024.0 * 1024.0 * 1024.0)

        val networkType = detectNetworkType()

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "batteryPct" to batteryPct,
            "charging" to charging,
            "totalRamMb" to totalRamMb,
            "usedRamMb" to usedRamMb,
            "totalStorageGb" to ((totalStorageGb * 10).toInt() / 10.0),
            "freeStorageGb" to ((freeStorageGb * 10).toInt() / 10.0),
            "networkType" to networkType,
        )
    }

    private fun detectNetworkType(): String {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "Bilinmiyor"
        val net = cm.activeNetwork ?: return "Çevrimdışı"
        val caps = cm.getNetworkCapabilities(net) ?: return "Çevrimdışı"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobil Veri"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "Bağlı"
        }
    }

    private fun playChimeAndVibrate() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(applicationContext, uri)
            if (ringtone != null) {
                ringtone.play()
            } else {
                val tg = ToneGenerator(AudioManager.STREAM_ALARM, 90)
                tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 600)
                Handler(Looper.getMainLooper()).postDelayed({ try { tg.release() } catch (_: Throwable) {} }, 800)
            }
        } catch (_: Throwable) {
            try {
                val tg = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)
                tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 500)
                Handler(Looper.getMainLooper()).postDelayed({ try { tg.release() } catch (_: Throwable) {} }, 700)
            } catch (_: Throwable) {}
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createOneShot(450, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createOneShot(450, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(450)
                }
            }
        } catch (_: Throwable) {}
    }
}
