package com.mehmetderin.asistan

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.media.ToneGenerator
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Base64
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.URLConnection
import java.security.Key
import java.security.KeyStore
import java.security.PrivateKey
import java.security.spec.MGF1ParameterSpec
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.mehmetderin.asistan/native"
        private const val REQ_EXPORT_FILE = 9201
        private const val REQ_PICK_FILES = 9202
        private const val REQ_PERMISSIONS = 9203

        @Volatile
        var activeChannel: MethodChannel? = null

        fun notifyFlutter(method: String, args: Any?) {
            Handler(Looper.getMainLooper()).post {
                try {
                    activeChannel?.invokeMethod(method, args)
                } catch (_: Exception) {
                }
            }
        }
    }

    private var pendingExportBytes: ByteArray? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var pendingSpeechLocale: String = "tr-TR"
    private var pendingSpeechPartial: Boolean = true
    private var startSpeechAfterPerm: Boolean = false

    private var pendingLaunchPayload: MutableMap<String, Any?>? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListeningSpeech: Boolean = false
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var mediaPlayer: MediaPlayer? = null
    private var torchEnabled: Boolean = false

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initTts()
        inspectIncomingIntent(intent, fromNewIntent = false)
    }

    override fun onResume() {
        super.onResume()
        mainHandler.postDelayed({
            try {
                val clipKey = extractKeyFromClipboard()
                if (!clipKey.isNullOrBlank()) {
                    notifyFlutter("onClipboardProxyKey", mapOf("key" to clipKey))
                }
            } catch (_: Exception) {
            }
        }, 350L)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        inspectIncomingIntent(intent, fromNewIntent = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        activeChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLaunchPayload" -> {
                    val payload = pendingLaunchPayload
                    pendingLaunchPayload = null
                    result.success(payload)
                }
                "recoverLegacyProxyConfig" -> {
                    result.success(recoverLegacyProxyConfig())
                }
                "saveNativeProxyKey" -> {
                    val key = call.argument<String>("key") ?: ""
                    val url = call.argument<String>("url") ?: "http://127.0.0.1:8317"
                    result.success(saveNativeProxyKey(key, url))
                }
                "getClipboardText" -> {
                    result.success(readClipboardPlainText())
                }
                "openCliProxyApp" -> {
                    result.success(openCliProxyApp())
                }
                "playEarcon" -> {
                    val type = call.argument<String>("type") ?: "start"
                    playEarconTone(type)
                    result.success(true)
                }
                "updateBackgroundService" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val title = call.argument<String>("title") ?: "Asistan AI Aktif"
                    val subtitle = call.argument<String>("subtitle") ?: "Arka plan sesli asistan ve CLIProxy hazır"
                    val wakeWord = call.argument<Boolean>("wakeWord") ?: false
                    updateBackgroundService(enabled, title, subtitle, wakeWord)
                    result.success(true)
                }
                "startListening" -> {
                    val locale = call.argument<String>("locale") ?: "tr-TR"
                    val partial = call.argument<Boolean>("partial") ?: true
                    startSpeechListening(locale, partial, result)
                }
                "stopListening" -> {
                    stopSpeechListening()
                    result.success(true)
                }
                "speakTts" -> {
                    val text = call.argument<String>("text") ?: ""
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
                    val voiceName = call.argument<String>("voice")
                    val ok = speakWithTts(text, rate, pitch, voiceName)
                    result.success(ok)
                }
                "playAudioBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val ext = call.argument<String>("ext") ?: "mp3"
                    if (bytes == null || bytes.isEmpty()) {
                        result.success(false)
                    } else {
                        val ok = playAudioBytes(bytes, ext)
                        result.success(ok)
                    }
                }
                "stopTts" -> {
                    stopAllSpeechOutput()
                    result.success(true)
                }
                "getVoices" -> {
                    result.success(getAvailableTtsVoices())
                }
                "getDeviceStatus" -> {
                    result.success(getDeviceStatusMap())
                }
                "deviceAction" -> {
                    val action = call.argument<String>("action") ?: "status"
                    val value = call.argument<Int>("value")
                    val target = call.argument<String>("target")
                    result.success(handleDeviceAction(action, value, target))
                }
                "setAlarmOrTimer" -> {
                    val mode = call.argument<String>("mode") ?: "alarm"
                    val hour = call.argument<Int>("hour") ?: 8
                    val minute = call.argument<Int>("minute") ?: 0
                    val seconds = call.argument<Int>("seconds") ?: 60
                    val title = call.argument<String>("title") ?: "Asistan"
                    result.success(handleAlarmOrTimer(mode, hour, minute, seconds, title))
                }
                "scheduleReminder" -> {
                    val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % 100000).toInt()
                    val title = call.argument<String>("title") ?: "Asistan Hatırlatıcı"
                    val body = call.argument<String>("body") ?: ""
                    val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                        ?: (System.currentTimeMillis() + 60_000L)
                    result.success(scheduleNotificationReminder(id, title, body, triggerAtMillis))
                }
                "cancelReminder" -> {
                    val id = call.argument<Int>("id") ?: 0
                    result.success(cancelNotificationReminder(id))
                }
                "publishDownload" -> {
                    val path = call.argument<String>("path") ?: ""
                    val name = call.argument<String>("name") ?: "dosya"
                    val category = call.argument<String>("category") ?: "Diger"
                    Thread {
                        val output = publishDownload(path, name, category)
                        runOnUiThread { result.success(output) }
                    }.start()
                }
                "enqueueDownload" -> {
                    result.success(enqueueSystemDownload(call.argument<String>("url") ?: "", call.argument<Boolean>("wifiOnly") ?: false))
                }
                "showSystemDownloads" -> {
                    try {
                        startActivity(Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS))
                        result.success(true)
                    } catch (_: Exception) { result.success(false) }
                }
                "openAppSearch" -> {
                    result.success(openAppSearch(call.argument<String>("app") ?: "", call.argument<String>("query") ?: "", call.argument<Boolean>("play") ?: false, call.argument<String>("mode") ?: "global"))
                }
                "openAppOrUrl" -> {
                    val target = call.argument<String>("target") ?: ""
                    val url = call.argument<String>("url")
                    result.success(openAppOrUrl(target, url))
                }
                "openAppControlSettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(mapOf("message" to "Erişilebilirlik ayarlarında Asistan uygulama kontrolünü etkinleştirin."))
                }
                "controlApp" -> {
                    val service = AppControlService.connected
                    val action = call.argument<String>("action").orEmpty()
                    val target = call.argument<String>("target").orEmpty()
                    if (service == null) {
                        result.success(mapOf("message" to "Önce ‘uygulama kontrolünü ayarla’ deyip Asistan erişimini etkinleştirin."))
                    } else {
                        val expected = service.targetPackage()
                        if (expected != null && hasWindowFocus()) moveTaskToBack(true)
                        service.execute(expected, action, target) { message ->
                            result.success(mapOf("message" to message))
                        }
                    }
                }
                "openCommunication" -> {
                    val type = call.argument<String>("type") ?: "dial"
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val subject = call.argument<String>("subject") ?: ""
                    val email = call.argument<String>("email") ?: ""
                    result.success(openCommunicationIntent(type, phone, message, email, subject))
                }
                "queryContacts" -> {
                    val query = call.argument<String>("query") ?: ""
                    val limit = call.argument<Int>("limit") ?: 10
                    result.success(queryContactsList(query, limit))
                }
                "calendarAction" -> {
                    val mode = call.argument<String>("mode") ?: "list"
                    val title = call.argument<String>("title") ?: "Etkinlik"
                    val description = call.argument<String>("description") ?: ""
                    val location = call.argument<String>("location") ?: ""
                    val startMillis = call.argument<Number>("startMillis")?.toLong()
                        ?: System.currentTimeMillis()
                    val endMillis = call.argument<Number>("endMillis")?.toLong()
                        ?: (startMillis + 3600_000L)
                    val days = call.argument<Int>("days") ?: 7
                    result.success(handleCalendarAction(mode, title, description, location, startMillis, endMillis, days))
                }
                "mediaControl" -> {
                    val command = call.argument<String>("command") ?: "play_pause"
                    val query = call.argument<String>("query")
                    result.success(handleMediaControl(command, query))
                }
                "shareFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val title = call.argument<String>("title") ?: "Asistan Dosyası"
                    val mimeType = call.argument<String>("mimeType")
                    val text = call.argument<String>("text")
                    result.success(shareLocalFile(path, title, mimeType, text))
                }
                "openFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val mimeType = call.argument<String>("mimeType")
                    result.success(openLocalFile(path, mimeType))
                }
                "exportFile" -> {
                    val fileName = call.argument<String>("fileName") ?: "asistan_belge.pdf"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Dosya verisi boş", null)
                    } else {
                        startExportDocument(fileName, mimeType, bytes, result)
                    }
                }
                "saveToPublicDownloads" -> {
                    val fileName = call.argument<String>("fileName") ?: "asistan_dosya.bin"
                    val subFolder = call.argument<String>("subFolder") ?: "Asistan"
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    val sourcePath = call.argument<String>("sourcePath")
                    result.success(saveToPublicDownloads(fileName, subFolder, mimeType, bytes, sourcePath))
                }
                "synthesizeTtsToFile" -> {
                    val text = call.argument<String>("text") ?: ""
                    val title = call.argument<String>("title") ?: "Asistan_Ses_Kaydi"
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    val pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat()
                    synthesizeTtsToAudioFile(text, title, rate, pitch, result)
                }
                "pickFiles" -> {
                    val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
                    startPickFiles(allowMultiple, result)
                }
                "requestPermissions" -> {
                    requestRuntimePermissions(result)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun inspectIncomingIntent(intent: Intent?, fromNewIntent: Boolean) {
        if (intent == null) return
        val action = intent.action ?: ""
        val payload = mutableMapOf<String, Any?>()

        when (action) {
            Intent.ACTION_ASSIST,
            Intent.ACTION_VOICE_COMMAND,
            Intent.ACTION_SEARCH_LONG_PRESS,
            "com.mehmetderin.asistan.ACTION_VOICE_LISTEN" -> {
                payload["type"] = "assist_voice"
                payload["autoListen"] = true
            }
            "com.mehmetderin.asistan.ACTION_NEW_CHAT" -> {
                payload["type"] = "new_chat"
            }
            Intent.ACTION_SEND -> {
                payload["type"] = "share"
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                val files = mutableListOf<Map<String, Any?>>()
                if (streamUri != null) {
                    copyUriToIncomingCache(streamUri)?.let { files.add(it) }
                }
                payload["text"] = sharedText ?: ""
                payload["subject"] = sharedSubject ?: ""
                payload["files"] = files
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                payload["type"] = "share"
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                }
                val files = mutableListOf<Map<String, Any?>>()
                uris?.forEach { u ->
                    copyUriToIncomingCache(u)?.let { files.add(it) }
                }
                payload["text"] = sharedText ?: ""
                payload["files"] = files
            }
        }

        if (intent.getBooleanExtra("asistan_voice_trigger", false)) {
            payload["type"] = "assist_voice"
            payload["autoListen"] = true
        }
        val reminderTitle = intent.getStringExtra("asistan_reminder_title")
        if (!reminderTitle.isNullOrBlank()) {
            payload["type"] = "reminder"
            payload["title"] = reminderTitle
            payload["body"] = intent.getStringExtra("asistan_reminder_body") ?: ""
        }

        if (payload.isNotEmpty()) {
            if (fromNewIntent && activeChannel != null) {
                notifyFlutter("onLaunchPayload", payload)
            } else {
                pendingLaunchPayload = payload
            }
        }
    }

    private fun copyUriToIncomingCache(uri: Uri): Map<String, Any?>? {
        return try {
            var displayName = "paylasilan_dosya"
            var size = 0L
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) {
                        displayName = cursor.getString(nameIdx) ?: displayName
                    }
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                        size = cursor.getLong(sizeIdx)
                    }
                }
            }
            val safeName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "dosya" }
            val dir = File(cacheDir, "incoming")
            if (!dir.exists()) dir.mkdirs()
            val outFile = File(dir, "${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            }
            val mime = contentResolver.getType(uri)
                ?: URLConnection.guessContentTypeFromName(safeName)
                ?: "application/octet-stream"
            mapOf(
                "name" to safeName,
                "path" to outFile.absolutePath,
                "size" to (if (size > 0) size else outFile.length()),
                "mimeType" to mime
            )
        } catch (_: Exception) {
            null
        }
    }

    // ─── LEGACY & NATIVE CLIPROXY KEY RECOVERY + CLIPBOARD + EARCON ─────────

    private fun recoverLegacyProxyConfig(): Map<String, Any?> {
        var recoveredKey = ""
        var recoveredUrl = "http://127.0.0.1:8317"
        var keySource = "none"
        val debugSources = mutableListOf<String>()

        // 1. Check SharedPreferences: "ayarlar" and "FlutterSharedPreferences"
        try {
            val ayarlar = getSharedPreferences("ayarlar", Context.MODE_PRIVATE)
            val pUrl = ayarlar.getString("proxyAdres", null) ?: ayarlar.getString("flutter.proxyAdres", null)
            if (!pUrl.isNullOrBlank()) {
                recoveredUrl = pUrl.trim()
                debugSources.add("ayarlar.proxyAdres")
            }
            for ((k, v) in ayarlar.all) {
                val strVal = v?.toString()?.trim() ?: continue
                if (looksLikeProxyKey(strVal) && recoveredKey.isBlank()) {
                    recoveredKey = strVal
                    keySource = "ayarlar.$k"
                }
            }
        } catch (_: Exception) {
        }

        try {
            val fsp = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val pUrl = fsp.getString("flutter.proxyAdres", null) ?: fsp.getString("proxyAdres", null)
            if (!pUrl.isNullOrBlank()) {
                recoveredUrl = pUrl.trim()
                debugSources.add("FlutterSharedPreferences.proxyAdres")
            }
            for ((k, v) in fsp.all) {
                val strVal = v?.toString()?.trim() ?: continue
                if (looksLikeProxyKey(strVal) && recoveredKey.isBlank()) {
                    recoveredKey = strVal
                    keySource = "FlutterSharedPreferences.$k"
                }
            }
        } catch (_: Exception) {
        }

        // 2. Check no_backup/anahtar.bin with AndroidKeyStore alias "asistan.anahtar.v1" (fk.e in original APK)
        if (recoveredKey.isBlank()) {
            try {
                val anahtarFile = File(noBackupFilesDir, "anahtar.bin")
                if (anahtarFile.exists()) {
                    val bytes = anahtarFile.readBytes()
                    debugSources.add("anahtar.bin(${bytes.size}b)")
                    if (bytes.size > 13 && bytes[0] == 1.toByte()) {
                        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                        val entry = ks.getEntry("asistan.anahtar.v1", null) as? KeyStore.SecretKeyEntry
                        val secretKey = entry?.secretKey
                        if (secretKey != null) {
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            val spec = GCMParameterSpec(128, bytes, 1, 12)
                            cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
                            val plainBytes = cipher.doFinal(bytes, 13, bytes.size - 13)
                            val decoded = String(plainBytes, Charsets.UTF_8).trim()
                            if (decoded.isNotEmpty()) {
                                recoveredKey = decoded
                                keySource = "no_backup/anahtar.bin"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                debugSources.add("anahtar.bin_err:${e.javaClass.simpleName}")
            }
        }

        // 3. Check FlutterSecureStorage with both AES/GCM and RSA/ECB/OAEPPadding + AES/CBC/PKCS7Padding
        if (recoveredKey.isBlank()) {
            try {
                val fssDecrypted = tryDecryptFlutterSecureStorage()
                if (!fssDecrypted.isNullOrBlank()) {
                    recoveredKey = fssDecrypted.trim()
                    keySource = "FlutterSecureStorage"
                }
            } catch (e: Exception) {
                debugSources.add("fss_err:${e.javaClass.simpleName}")
            }
        }

        // 4. Check Clipboard for sk-iphone-* or sk-* key
        val clipKey = extractKeyFromClipboard()
        if (recoveredKey.isBlank() && !clipKey.isNullOrBlank()) {
            recoveredKey = clipKey
            keySource = "clipboard"
        }

        return mapOf(
            "apiKey" to recoveredKey,
            "proxyUrl" to recoveredUrl,
            "source" to keySource,
            "clipboardKey" to (clipKey ?: ""),
            "debugSources" to debugSources
        )
    }

    private fun tryDecryptFlutterSecureStorage(): String? {
        val fss = getSharedPreferences("FlutterSecureStorage", Context.MODE_PRIVATE)
        val allEntries = fss.all
        if (allEntries.isEmpty()) return null

        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val aliases = ks.aliases().toList()

        // Try unwrap secret key from FlutterSecureKeyStorage:FlutterSecureStorage or FlutterSecureStorage
        val keyPrefsList = listOf(
            getSharedPreferences("FlutterSecureKeyStorage:FlutterSecureStorage", Context.MODE_PRIVATE),
            fss
        )

        var unwrappedSecretKey: Key? = null

        // Mode A: RSA/ECB/OAEPPadding unwrap (m40.z)
        for (alias in aliases) {
            if (!alias.contains("FlutterSecureStorage", ignoreCase = true)) continue
            try {
                val privKey = ks.getKey(alias, null) as? PrivateKey ?: continue
                for (kp in keyPrefsList) {
                    for ((kName, kVal) in kp.all) {
                        if (!kName.contains("AES", ignoreCase = true) && !kName.contains("Key", ignoreCase = true)) continue
                        val b64 = kVal as? String ?: continue
                        val wrappedBytes = try { Base64.decode(b64, Base64.DEFAULT) } catch (_: Exception) { continue }
                        if (wrappedBytes.size < 32) continue
                        try {
                            val cipher = try {
                                Cipher.getInstance("RSA/ECB/OAEPPadding", "AndroidKeyStoreBCWorkaround")
                            } catch (_: Exception) {
                                Cipher.getInstance("RSA/ECB/OAEPPadding")
                            }
                            val spec = OAEPParameterSpec(
                                "SHA-256",
                                "MGF1",
                                MGF1ParameterSpec.SHA1,
                                PSource.PSpecified.DEFAULT
                            )
                            cipher.init(Cipher.UNWRAP_MODE, privKey, spec)
                            unwrappedSecretKey = cipher.unwrap(wrappedBytes, "AES", Cipher.SECRET_KEY)
                            if (unwrappedSecretKey != null) break
                        } catch (_: Exception) {
                        }
                    }
                    if (unwrappedSecretKey != null) break
                }
            } catch (_: Exception) {
            }
            if (unwrappedSecretKey != null) break
        }

        // Mode B: Direct AES SecretKey in KeyStore or wrapped with KeyStore AES/GCM (f90.r)
        var directKeystoreSecretKey: SecretKey? = null
        for (alias in aliases) {
            if (!alias.contains("FlutterSecureStorage", ignoreCase = true)) continue
            try {
                val sk = ks.getKey(alias, null) as? SecretKey
                if (sk != null) {
                    directKeystoreSecretKey = sk
                    // Also check if it wraps an inner AES key in FlutterSecureKeyStorage
                    for (kp in keyPrefsList) {
                        val wrappedB64 = kp.getString("BVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK", null)
                        val ivB64 = kp.getString("KeyStoreIV1", null)
                        if (!wrappedB64.isNullOrBlank() && !ivB64.isNullOrBlank()) {
                            try {
                                val wrapped = Base64.decode(wrappedB64, Base64.DEFAULT)
                                val iv = Base64.decode(ivB64, Base64.DEFAULT)
                                val c = Cipher.getInstance("AES/GCM/NoPadding")
                                c.init(Cipher.DECRYPT_MODE, sk, GCMParameterSpec(128, iv))
                                val rawKey = c.doFinal(wrapped)
                                unwrappedSecretKey = SecretKeySpec(rawKey, "AES")
                            } catch (_: Exception) {
                            }
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }

        // Now iterate over candidate entries in FlutterSecureStorage
        val candidateEntries = allEntries.entries.sortedByDescending { (k, _) ->
            when {
                k.contains("hey-asistan-anahtari", ignoreCase = true) -> 100
                k.contains("anahtar", ignoreCase = true) -> 90
                k.contains("key", ignoreCase = true) && !k.contains("AES") -> 80
                else -> 10
            }
        }

        for ((k, v) in candidateEntries) {
            if (k.contains("AES") || k == "KeyStoreIV1") continue
            val b64 = v as? String ?: continue
            if (looksLikeProxyKey(b64)) return b64.trim()
            val raw = try { Base64.decode(b64, Base64.DEFAULT) } catch (_: Exception) { continue }
            if (raw.size <= 12) continue

            // Try AES/CBC/PKCS7Padding with 16-byte IV using unwrappedSecretKey
            val keysToTry = listOfNotNull(unwrappedSecretKey, directKeystoreSecretKey)
            for (aesKey in keysToTry) {
                if (raw.size > 16) {
                    try {
                        val c = Cipher.getInstance("AES/CBC/PKCS7Padding")
                        c.init(Cipher.DECRYPT_MODE, aesKey, IvParameterSpec(raw, 0, 16))
                        val out = c.doFinal(raw, 16, raw.size - 16)
                        val str = String(out, Charsets.UTF_8).trim()
                        if (str.isNotEmpty() && str.all { it.code in 32..126 }) {
                            return str
                        }
                    } catch (_: Exception) {
                    }
                }
                // Try AES/GCM/NoPadding with 12-byte IV
                try {
                    val c = Cipher.getInstance("AES/GCM/NoPadding")
                    c.init(Cipher.DECRYPT_MODE, aesKey, GCMParameterSpec(128, raw, 0, 12))
                    val out = c.doFinal(raw, 12, raw.size - 12)
                    val str = String(out, Charsets.UTF_8).trim()
                    if (str.isNotEmpty() && str.all { it.code in 32..126 }) {
                        return str
                    }
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    private fun saveNativeProxyKey(key: String, url: String): Boolean {
        val cleanKey = key.trim()
        val cleanUrl = url.trim().ifEmpty { "http://127.0.0.1:8317" }
        try {
            getSharedPreferences("ayarlar", Context.MODE_PRIVATE).edit()
                .putString("proxyAdres", cleanUrl)
                .putString("proxyAnahtar", cleanKey)
                .apply()
        } catch (_: Exception) {
        }
        if (cleanKey.isEmpty()) return true
        return try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val existing = (ks.getEntry("asistan.anahtar.v1", null) as? KeyStore.SecretKeyEntry)?.secretKey
            val secretKey = existing ?: run {
                val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                val spec = KeyGenParameterSpec.Builder(
                    "asistan.anahtar.v1",
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build()
                kg.init(spec)
                kg.generateKey()
            }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            val iv = cipher.iv
            val enc = cipher.doFinal(cleanKey.toByteArray(Charsets.UTF_8))
            val out = ByteArray(1 + iv.size + enc.size)
            out[0] = 1
            System.arraycopy(iv, 0, out, 1, iv.size)
            System.arraycopy(enc, 0, out, 1 + iv.size, enc.size)
            val file = File(noBackupFilesDir, "anahtar.bin")
            FileOutputStream(file, false).use {
                it.write(out)
                it.fd.sync()
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun looksLikeProxyKey(text: String): Boolean {
        val t = text.trim()
        if (t.startsWith("sk-iphone-", ignoreCase = true) && t.length >= 16) return true
        if (t.startsWith("sk-", ignoreCase = true) && t.length in 16..180 && !t.contains(" ")) return true
        return false
    }

    private fun readClipboardPlainText(): String {
        return try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val clip = cm?.primaryClip
            if (clip != null && clip.itemCount > 0) {
                clip.getItemAt(0).coerceToText(this)?.toString()?.trim() ?: ""
            } else {
                ""
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun extractKeyFromClipboard(): String? {
        val raw = readClipboardPlainText()
        if (raw.isBlank()) return null
        if (looksLikeProxyKey(raw)) return raw
        val regex = Regex("(sk-iphone-[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{12,})")
        return regex.find(raw)?.value
    }

    private fun openCliProxyApp(): Boolean {
        return try {
            val pkg = "com.mehmetderin.cliproxy"
            val intent = packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun playEarconTone(type: String) {
        try {
            val tone = when (type.lowercase(Locale.ROOT)) {
                "start", "listen" -> ToneGenerator.TONE_PROP_BEEP
                "stop", "done" -> ToneGenerator.TONE_PROP_ACK
                "error" -> ToneGenerator.TONE_PROP_NACK
                else -> ToneGenerator.TONE_PROP_BEEP
            }
            val tg = ToneGenerator(AudioManager.STREAM_MUSIC, 45)
            tg.startTone(tone, 110)
            mainHandler.postDelayed({
                try {
                    tg.release()
                } catch (_: Exception) {
                }
            }, 200L)
        } catch (_: Exception) {
        }
    }

    // ─── FOREGROUND SERVICE CONTROL ──────────────────────────────────────────

    private fun updateBackgroundService(
        enabled: Boolean,
        title: String,
        subtitle: String,
        wakeWord: Boolean
    ) {
        try {
            val serviceIntent = Intent(this, AsistanBackgroundService::class.java).apply {
                action = if (enabled) AsistanBackgroundService.ACTION_START_OR_UPDATE else AsistanBackgroundService.ACTION_STOP
                putExtra(AsistanBackgroundService.EXTRA_TITLE, title)
                putExtra(AsistanBackgroundService.EXTRA_SUBTITLE, subtitle)
                putExtra(AsistanBackgroundService.EXTRA_WAKE_WORD, wakeWord)
            }
            if (enabled) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(this, serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            } else {
                stopService(serviceIntent)
            }
        } catch (_: Exception) {
        }
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                }
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    // ─── SPEECH RECOGNITION (TURKISH / SIRI & GOOGLE ASSISTANT STYLE) ────────

    private fun startSpeechListening(
        localeTag: String,
        partialResults: Boolean,
        result: MethodChannel.Result
    ) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            notifyFlutter("onSpeechError", mapOf("code" to 12, "message" to "Telefonda ses tanıma hizmeti bulunamadı."))
            result.success(false)
            return
        }
        pendingSpeechLocale = localeTag
        pendingSpeechPartial = partialResults
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            startSpeechAfterPerm = true
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), REQ_PERMISSIONS)
            result.success(true)
            return
        }
        startSpeechListeningInternal(localeTag, partialResults)
        result.success(true)
    }

    private fun recreateSpeechRecognizer() {
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(applicationContext)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                isListeningSpeech = true
                notifyFlutter("onSpeechState", mapOf("state" to "listening"))
            }

            override fun onBeginningOfSpeech() {
                notifyFlutter("onSpeechState", mapOf("state" to "speaking"))
            }

            override fun onRmsChanged(rmsdB: Float) {
                val normalized = ((rmsdB + 2f) / 12f).coerceIn(0.02f, 1.0f)
                notifyFlutter("onSpeechRms", mapOf("rms" to normalized.toDouble()))
            }

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                isListeningSpeech = false
                notifyFlutter("onSpeechState", mapOf("state" to "processing"))
            }

            override fun onError(error: Int) {
                isListeningSpeech = false
                if (error == SpeechRecognizer.ERROR_CLIENT || error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY) {
                    try {
                        speechRecognizer?.destroy()
                    } catch (_: Exception) {
                    }
                    speechRecognizer = null
                }
                val msg = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH -> "Ses eşleşmedi"
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Ses algılanmadı"
                    SpeechRecognizer.ERROR_AUDIO -> "Ses kaydı hatası"
                    SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Ağ hatası"
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Mikrofon izni gerekli"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Mikrofon meşgul"
                    SpeechRecognizer.ERROR_CLIENT -> "Ses istemcisi yenileniyor"
                    else -> "Ses tanıma hatası ($error)"
                }
                notifyFlutter("onSpeechError", mapOf("code" to error, "message" to msg))
            }

            override fun onResults(results: Bundle?) {
                isListeningSpeech = false
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull()?.trim() ?: ""
                notifyFlutter("onSpeechResult", mapOf("text" to text, "isFinal" to true))
            }

            override fun onPartialResults(partialBundle: Bundle?) {
                val matches = partialBundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull()?.trim() ?: ""
                if (text.isNotEmpty()) {
                    notifyFlutter("onSpeechPartial", mapOf("text" to text, "isFinal" to false))
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
    }

    private fun startSpeechListeningInternal(localeTag: String, partialResults: Boolean) {
        mainHandler.post {
            try {
                stopAllSpeechOutput()
                if (speechRecognizer == null) {
                    recreateSpeechRecognizer()
                } else if (isListeningSpeech) {
                    try {
                        speechRecognizer?.cancel()
                    } catch (_: Exception) {
                    }
                }

                val recognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeTag)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeTag)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1900L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1400L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1200L)
                }
                speechRecognizer?.startListening(recognizerIntent)
            } catch (_: Exception) {
                isListeningSpeech = false
                notifyFlutter("onSpeechError", mapOf("code" to 5, "message" to "Ses tanıma başlatılamadı. Yeniden deneyin."))
            }
        }
    }

    private fun stopSpeechListening() {
        startSpeechAfterPerm = false
        mainHandler.post {
            try {
                isListeningSpeech = false
                speechRecognizer?.cancel()
            } catch (_: Exception) {
            }
        }
    }

    // ─── TEXT-TO-SPEECH & NEURAL AUDIO PLAYBACK ──────────────────────────────

    private fun initTts() {
        try {
            tts = TextToSpeech(applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val trLocale = Locale.forLanguageTag("tr-TR")
                    val res = tts?.setLanguage(trLocale)
                    ttsReady = res != TextToSpeech.LANG_MISSING_DATA && res != TextToSpeech.LANG_NOT_SUPPORTED
                    if (!ttsReady) {
                        tts?.setLanguage(Locale.getDefault())
                        ttsReady = true
                    }
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            notifyFlutter("onTtsStart", mapOf("id" to (utteranceId ?: "")))
                        }

                        override fun onDone(utteranceId: String?) {
                            notifyFlutter("onTtsDone", mapOf("id" to (utteranceId ?: "")))
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            notifyFlutter("onTtsDone", mapOf("id" to (utteranceId ?: ""), "error" to true))
                        }
                    })
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun speakWithTts(text: String, rate: Float, pitch: Float, voiceName: String?): Boolean {
        if (text.isBlank()) return false
        return try {
            stopMediaPlayer()
            if (tts == null || !ttsReady) {
                initTts()
            }
            tts?.setSpeechRate(rate.coerceIn(0.5f, 2.2f))
            tts?.setPitch(pitch.coerceIn(0.5f, 2.0f))
            if (!voiceName.isNullOrBlank() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val matched = tts?.voices?.firstOrNull { it.name.equals(voiceName, ignoreCase = true) }
                if (matched != null) {
                    tts?.voice = matched
                }
            }
            val utteranceId = "utt_${System.currentTimeMillis()}"
            val params = Bundle().apply {
                putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_MUSIC)
            }
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId) == TextToSpeech.SUCCESS
        } catch (_: Exception) {
            false
        }
    }

    private fun playAudioBytes(bytes: ByteArray, ext: String): Boolean {
        return try {
            stopAllSpeechOutput()
            val dir = File(cacheDir, "tts_audio")
            if (!dir.exists()) dir.mkdirs()
            val cleanExt = ext.replace(".", "").ifBlank { "mp3" }
            val tempFile = File(dir, "speech_${System.currentTimeMillis()}.$cleanExt")
            FileOutputStream(tempFile).use { it.write(bytes) }

            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .build()
            )
            mp.setDataSource(tempFile.absolutePath)
            mp.setOnPreparedListener { player ->
                notifyFlutter("onTtsStart", mapOf("id" to tempFile.name))
                player.start()
            }
            mp.setOnCompletionListener { player ->
                try {
                    player.release()
                } catch (_: Exception) {
                }
                if (mediaPlayer === player) {
                    mediaPlayer = null
                }
                tempFile.delete()
                notifyFlutter("onTtsDone", mapOf("id" to tempFile.name))
            }
            mp.setOnErrorListener { player, _, _ ->
                try {
                    player.release()
                } catch (_: Exception) {
                }
                if (mediaPlayer === player) {
                    mediaPlayer = null
                }
                tempFile.delete()
                notifyFlutter("onTtsDone", mapOf("id" to tempFile.name, "error" to true))
                true
            }
            mediaPlayer = mp
            mp.prepareAsync()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopMediaPlayer() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        } finally {
            mediaPlayer = null
        }
    }

    private fun stopAllSpeechOutput() {
        try {
            tts?.stop()
        } catch (_: Exception) {
        }
        stopMediaPlayer()
    }

    private fun getAvailableTtsVoices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                tts?.voices?.forEach { v ->
                    val lang = v.locale?.toLanguageTag() ?: ""
                    if (lang.startsWith("tr", ignoreCase = true) || lang.startsWith("en", ignoreCase = true)) {
                        list.add(
                            mapOf(
                                "name" to v.name,
                                "locale" to lang,
                                "network" to v.isNetworkConnectionRequired
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) {
        }
        return list
    }

    // ─── DEVICE HARDWARE & SYSTEM TOOLS ──────────────────────────────────────

    private fun getDeviceStatusMap(): Map<String, Any?> {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryPct = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val tempTenths = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempC = tempTenths / 10.0

        val stat = StatFs(Environment.getDataDirectory().path)
        val totalBytes = stat.blockSizeLong * stat.blockCountLong
        val freeBytes = stat.blockSizeLong * stat.availableBlocksLong
        val totalGb = (totalBytes / (1024.0 * 1024.0 * 1024.0))
        val freeGb = (freeBytes / (1024.0 * 1024.0 * 1024.0))

        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxMusic = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val curMusic = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val musicPct = ((curMusic * 100.0) / maxMusic).toInt()
        val ringerMode = when (am.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "sessiz"
            AudioManager.RINGER_MODE_VIBRATE -> "titresim"
            else -> "normal"
        }

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val ignoringBatteryOpt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else true

        return mapOf(
            "batteryPercent" to batteryPct,
            "isCharging" to charging,
            "batteryTempC" to tempC,
            "storageTotalGb" to String.format(Locale.US, "%.1f", totalGb).toDouble(),
            "storageFreeGb" to String.format(Locale.US, "%.1f", freeGb).toDouble(),
            "volumePercent" to musicPct,
            "ringerMode" to ringerMode,
            "torchEnabled" to torchEnabled,
            "ignoringBatteryOptimizations" to ignoringBatteryOpt,
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "androidVersion" to Build.VERSION.RELEASE
        )
    }

    private fun handleDeviceAction(action: String, value: Int?, target: String?): Map<String, Any?> {
        return try {
            when (action.lowercase(Locale.ROOT)) {
                "fener_ac", "torch_on" -> {
                    setTorch(true)
                    mapOf("ok" to true, "message" to "El feneri açıldı.", "status" to getDeviceStatusMap())
                }
                "fener_kapat", "torch_off" -> {
                    setTorch(false)
                    mapOf("ok" to true, "message" to "El feneri kapatıldı.", "status" to getDeviceStatusMap())
                }
                "fener_degistir", "torch_toggle" -> {
                    setTorch(!torchEnabled)
                    val stateText = if (torchEnabled) "açıldı" else "kapatıldı"
                    mapOf("ok" to true, "message" to "El feneri $stateText.", "status" to getDeviceStatusMap())
                }
                "ses_ayarla", "set_volume" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val pct = (value ?: 50).coerceIn(0, 100)
                    val stream = when (target?.lowercase(Locale.ROOT)) {
                        "zil", "ring" -> AudioManager.STREAM_RING
                        "alarm" -> AudioManager.STREAM_ALARM
                        "bildirim", "notification" -> AudioManager.STREAM_NOTIFICATION
                        else -> AudioManager.STREAM_MUSIC
                    }
                    val maxVol = am.getStreamMaxVolume(stream).coerceAtLeast(1)
                    val newVol = ((pct / 100.0) * maxVol).toInt().coerceIn(0, maxVol)
                    am.setStreamVolume(stream, newVol, AudioManager.FLAG_SHOW_UI)
                    mapOf("ok" to true, "message" to "Ses seviyesi %$pct olarak ayarlandı.", "status" to getDeviceStatusMap())
                }
                "zil_modu", "ringer_mode" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val modeStr = target?.lowercase(Locale.ROOT) ?: "normal"
                    when {
                        modeStr.contains("titres") || modeStr.contains("vibrate") -> {
                            am.ringerMode = AudioManager.RINGER_MODE_VIBRATE
                        }
                        modeStr.contains("sessiz") || modeStr.contains("silent") || modeStr.contains("mute") -> {
                            am.ringerMode = AudioManager.RINGER_MODE_SILENT
                        }
                        else -> {
                            am.ringerMode = AudioManager.RINGER_MODE_NORMAL
                        }
                    }
                    mapOf("ok" to true, "message" to "Zil modu '$modeStr' olarak güncellendi.", "status" to getDeviceStatusMap())
                }
                "ayar_ac", "open_settings" -> {
                    val panel = target?.lowercase(Locale.ROOT) ?: ""
                    val settingsAction = when {
                        panel.contains("wifi") || panel.contains("wi-fi") || panel.contains("kablosuz") -> Settings.ACTION_WIFI_SETTINGS
                        panel.contains("bluetooth") -> Settings.ACTION_BLUETOOTH_SETTINGS
                        panel.contains("konum") || panel.contains("location") || panel.contains("gps") -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                        panel.contains("ekran") || panel.contains("parlaklik") || panel.contains("display") -> Settings.ACTION_DISPLAY_SETTINGS
                        panel.contains("ses") || panel.contains("sound") -> Settings.ACTION_SOUND_SETTINGS
                        panel.contains("pil") || panel.contains("batarya") || panel.contains("battery") -> Settings.ACTION_BATTERY_SAVER_SETTINGS
                        panel.contains("nfc") -> Settings.ACTION_NFC_SETTINGS
                        panel.contains("rahatsiz") || panel.contains("dnd") -> Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS
                        panel.contains("asistan") || panel.contains("varsayilan") || panel.contains("assist") -> Settings.ACTION_VOICE_INPUT_SETTINGS
                        panel.contains("uygulama") || panel.contains("app") -> Settings.ACTION_APPLICATION_SETTINGS
                        else -> Settings.ACTION_SETTINGS
                    }
                    val intent = Intent(settingsAction).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    mapOf("ok" to true, "message" to "Sistem ayarları ($panel) açıldı.", "status" to getDeviceStatusMap())
                }
                else -> {
                    mapOf("ok" to true, "message" to "Cihaz durumu alındı.", "status" to getDeviceStatusMap())
                }
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to "Cihaz işlemi başarısız: ${e.message}", "status" to getDeviceStatusMap())
        }
    }

    private fun setTorch(enable: Boolean): Boolean {
        return try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: cm.cameraIdList.firstOrNull()
            if (cameraId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.setTorchMode(cameraId, enable)
                torchEnabled = enable
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    // ─── ALARMS, TIMERS & SCHEDULED REMINDERS ────────────────────────────────

    private fun handleAlarmOrTimer(
        mode: String,
        hour: Int,
        minute: Int,
        seconds: Int,
        title: String
    ): Map<String, Any?> {
        return try {
            if (mode.equals("timer", ignoreCase = true) || mode.equals("sayac", ignoreCase = true)) {
                val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                    putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(5))
                    putExtra(AlarmClock.EXTRA_MESSAGE, title)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                mapOf("ok" to true, "message" to "$seconds saniyelik sayaç ekranı açıldı.")
            } else {
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
                    putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
                    putExtra(AlarmClock.EXTRA_MESSAGE, title)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                val hh = String.format(Locale.US, "%02d:%02d", hour, minute)
                mapOf("ok" to true, "message" to "Saat $hh için alarm ekranı açıldı. Alarmı saat uygulamasından kontrol edin.")
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to "Alarm/Sayaç kurulamadı: ${e.message}")
        }
    }

    private fun scheduleNotificationReminder(
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long
    ): Map<String, Any?> {
        return try {
            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AsistanReminderReceiver::class.java).apply {
                putExtra("id", id)
                putExtra("title", title)
                putExtra("body", body)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getBroadcast(this, id, intent, flags)
            val safeTime = triggerAtMillis.coerceAtLeast(System.currentTimeMillis() + 3000L)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTime, pi)
                } catch (_: SecurityException) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTime, pi)
                }
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, safeTime, pi)
            }
            mapOf("ok" to true, "id" to id, "triggerAtMillis" to safeTime)
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to e.message)
        }
    }

    private fun cancelNotificationReminder(id: Int): Boolean {
        return try {
            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AsistanReminderReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getBroadcast(this, id, intent, flags)
            am.cancel(pi)
            true
        } catch (_: Exception) {
            false
        }
    }

    // ─── APPS, URLS, COMMUNICATION, CONTACTS, CALENDAR, MEDIA ────────────────

    private fun publishDownload(path: String, name: String, category: String): Map<String, Any?> {
        var pendingUri: Uri? = null
        return try {
            val file = File(path).canonicalFile
            val allowed = File(applicationInfo.dataDir).canonicalPath + File.separator
            if (!file.path.startsWith(allowed) || !file.isFile) return mapOf("ok" to false, "message" to "Uygulamaya ait indirilmiş dosya bulunamadı.")
            val safeName = name.replace(Regex("[^a-zA-Z0-9._-]"), "_").take(100)
            val folder = if (category in listOf("Belgeler", "Gorseller", "Videolar", "Sesler", "Arsivler", "Diger")) category else "Diger"
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return mapOf("ok" to false, "message" to "Bu Android sürümünde Paylaş düğmesiyle dosyayı kaydedin.")
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.MIME_TYPE, URLConnection.guessContentTypeFromName(safeName) ?: "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Asistan/$folder")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return mapOf("ok" to false, "message" to "İndirilenler kaydı açılamadı.")
            pendingUri = uri
            val output = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Output unavailable")
            output.use { out -> file.inputStream().use { input -> input.copyTo(out, 65536) } }
            values.clear(); values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            mapOf("ok" to true, "message" to "İndirilenler/Asistan/$folder klasörüne kaydedildi.", "uri" to uri.toString())
        } catch (_: Exception) {
            pendingUri?.let { try { contentResolver.delete(it, null, null) } catch (_: Exception) {} }
            mapOf("ok" to false, "message" to "Dosya dışa aktarılamadı; uygulamadaki kopya korunuyor.")
        }
    }

    private fun enqueueSystemDownload(url: String, wifiOnly: Boolean): Map<String, Any?> {
        return try {
            val uri = Uri.parse(url.trim())
            if (uri.scheme !in listOf("https", "http") || uri.host.isNullOrBlank()) return mapOf("ok" to false, "message" to "Geçerli bir HTTP/HTTPS dosya bağlantısı girin.")
            val rawName = uri.lastPathSegment?.takeIf { it.isNotBlank() } ?: "dosya"
            val name = rawName.replace(Regex("[^a-zA-Z0-9._-]"), "_").take(100)
            val request = android.app.DownloadManager.Request(uri)
                .setTitle(name)
                .setDescription("Asistan dosya indirmesi")
                .setNotificationVisibility(android.app.DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverMetered(!wifiOnly)
                .setAllowedOverRoaming(false)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Asistan/${System.currentTimeMillis()}_$name")
            if (wifiOnly) request.setAllowedNetworkTypes(android.app.DownloadManager.Request.NETWORK_WIFI)
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as android.app.DownloadManager
            val id = manager.enqueue(request)
            mapOf("ok" to true, "id" to id, "message" to "İndirme Android kuyruğuna eklendi. Durumu İndirmeleri göster düğmesinden izleyin.")
        } catch (_: Exception) { mapOf("ok" to false, "message" to "İndirme kuyruğa eklenemedi. Bağlantıyı ve depolama erişimini kontrol edin.") }
    }

    private fun openAppSearch(app: String, query: String, play: Boolean, mode: String): Map<String, Any?> {
        val packages = mapOf("youtube" to "com.google.android.youtube", "spotify" to "com.spotify.music", "chrome" to "com.android.chrome", "telegram" to "org.telegram.messenger")
        val pkg = packages[app] ?: return mapOf("ok" to false, "message" to "Bu uygulama desteklenmiyor.")
        return try {
            if (app == "spotify" && play) {
                val playIntent = Intent("android.media.action.MEDIA_PLAY_FROM_SEARCH").apply {
                    setPackage(pkg)
                    putExtra("query", query)
                    putExtra("android.intent.extra.focus", "vnd.android.cursor.item/audio")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (playIntent.resolveActivity(packageManager) != null) {
                    startActivity(playIntent)
                    return mapOf("ok" to true, "message" to "Spotify'a '$query' için oynatma isteği iletildi. Çalmaya başladığı doğrulanmadı; Spotify ekranından kontrol edin.")
                }
            }
            val url = when (app) {
                "youtube" -> "https://www.youtube.com/results?search_query=${Uri.encode(query)}"
                "spotify" -> "https://open.spotify.com/search/${Uri.encode(query)}"
                "telegram" -> when {
                    mode == "contacts" -> "tg://contacts/search"
                    mode == "chat" && query.matches(Regex("[a-zA-Z0-9_]{5,32}")) -> "tg://resolve?domain=${Uri.encode(query)}"
                    else -> "tg://chats/search"
                }
                else -> if (query.startsWith("https://") || query.startsWith("http://")) query else "https://www.google.com/search?q=${Uri.encode(query)}"
            }
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).setPackage(pkg)
            val installedHandler = intent.resolveActivity(packageManager) != null
            if (!installedHandler) {
                if (app == "telegram") return mapOf("ok" to false, "message" to "Telegram arama bağlantısı bu telefonda açılamadı. Telegram uygulamasındaki arama düğmesini kullanın.")
                intent.setPackage(null)
            }
            startActivity(intent)
            val message = if (app == "telegram") when (mode) {
                "contacts" -> "Telegram kişi araması açıldı. Kişi adını burada yazın; sonuçlar Asistan tarafından okunmadı."
                "chat" -> "Telegram sohbeti açıldı. Sohbet menüsünden Ara seçeneğini kullanın; sohbet içeriğine API erişimi bağlı değil."
                else -> "Telegram genel araması açıldı. Kanal adını burada arayın; sonuçlar Asistan tarafından okunmadı."
            } else if (play) "Spotify arama ekranı açıldı; şarkıyı seçip oynatın. Oynatma başlatıldığı doğrulanmadı." else "$app araması/sayfası ${if (installedHandler) "uygulamada" else "tarayıcıda"} açıldı."
            mapOf("ok" to true, "message" to message)
        } catch (_: Exception) {
            mapOf("ok" to false, "message" to "İstenen uygulama işlemi açılamadı. Uygulamanın yüklü olduğunu kontrol edin.")
        }
    }

    private fun openAppOrUrl(target: String, url: String?): Map<String, Any?> {
        try {
            if (!url.isNullOrBlank()) {
                val normalizedUrl = if (url.startsWith("http://") || url.startsWith("https://") || url.contains("://")) {
                    url
                } else {
                    "https://$url"
                }
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(normalizedUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return mapOf("ok" to true, "message" to "Bağlantı açıldı: $normalizedUrl")
            }

            val query = target.trim().lowercase(Locale.forLanguageTag("tr-TR"))
            if (query.isEmpty()) return mapOf("ok" to false, "message" to "Uygulama adını söyleyin.")
            val aliases = mapOf(
                "ritim" to "com.mehmetderin.ritim",
                "bilgili" to "com.mehmetderin.bilgili",
                "kağıt" to "com.mehmetderin.kagit",
                "kagit" to "com.mehmetderin.kagit",
                "cliproxy" to "com.mehmetderin.cliproxy",
                "youtube" to "com.google.android.youtube",
                "whatsapp" to "com.whatsapp",
                "spotify" to "com.spotify.music",
                "chrome" to "com.android.chrome",
                "gmail" to "com.google.android.gm",
                "harita" to "com.google.android.apps.maps",
                "haritalar" to "com.google.android.apps.maps",
                "maps" to "com.google.android.apps.maps",
                "instagram" to "com.instagram.android",
                "telegram" to "org.telegram.messenger"
            )

            val isYouTube = query.replace(Regex("\\s+"), "") in setOf("youtube", "yutub")
            val directPkg = if (isYouTube) aliases["youtube"] else aliases[query] ?: query.takeIf { it.contains(".") }
            if (directPkg != null) {
                val launch = packageManager.getLaunchIntentForPackage(directPkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    return mapOf("ok" to true, "message" to "$target uygulaması açıldı.")
                }
            }

            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val apps = packageManager.queryIntentActivities(mainIntent, 0)
            val matched = apps.filter { it.activityInfo.packageName != packageName }.minByOrNull { info ->
                val label = info.loadLabel(packageManager).toString().lowercase(Locale.forLanguageTag("tr-TR"))
                val pkg = info.activityInfo.packageName.lowercase(Locale.ROOT)
                when {
                    label == query || pkg == query -> 0
                    label.startsWith(query) -> 1
                    label.contains(query) || pkg.contains(query) -> 2
                    else -> 3
                }
            }?.takeIf { info ->
                info.loadLabel(packageManager).toString().lowercase(Locale.forLanguageTag("tr-TR")).contains(query) ||
                    info.activityInfo.packageName.lowercase(Locale.ROOT).contains(query)
            }
            if (matched != null) {
                val launch = packageManager.getLaunchIntentForPackage(matched.activityInfo.packageName)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    val label = matched.loadLabel(packageManager).toString()
                    return mapOf("ok" to true, "message" to "$label uygulaması başlatıldı.")
                }
            }

            if (isYouTube) {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return mapOf("ok" to true, "message" to "YouTube tarayıcıda açıldı.")
            }
            if (query.startsWith("http") || query.contains(".com") || query.contains(".org") || query.contains(".tr")) {
                val webUri = if (query.startsWith("http")) Uri.parse(target) else Uri.parse("https://$target")
                startActivity(Intent(Intent.ACTION_VIEW, webUri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return mapOf("ok" to true, "message" to "Web sayfası açıldı: $target")
            }

            return mapOf("ok" to false, "message" to "'$target' adında kurulu bir uygulama bulunamadı.")
        } catch (e: Exception) {
            return mapOf("ok" to false, "message" to "Uygulama açılamadı: ${e.message}")
        }
    }

    private fun openCommunicationIntent(
        type: String,
        phone: String,
        message: String,
        email: String,
        subject: String
    ): Map<String, Any?> {
        return try {
            when (type.lowercase(Locale.ROOT)) {
                "call", "ara", "dial" -> {
                    val uri = Uri.parse("tel:${Uri.encode(phone)}")
                    val intent = Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    mapOf("ok" to true, "message" to "Telefon arama ekranı açıldı: $phone")
                }
                "sms", "mesaj" -> {
                    val uri = Uri.parse("smsto:${Uri.encode(phone)}")
                    val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                        putExtra("sms_body", message)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    mapOf("ok" to true, "message" to "SMS taslağı hazırlandı: $phone")
                }
                "whatsapp" -> {
                    val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
                    val url = "https://wa.me/${cleanPhone.removePrefix("+")}?text=${Uri.encode(message)}"
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    mapOf("ok" to true, "message" to "WhatsApp mesaj ekranı açıldı.")
                }
                "email", "eposta", "mail" -> {
                    val uri = Uri.parse("mailto:${Uri.encode(email)}")
                    val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        putExtra(Intent.EXTRA_TEXT, message)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    mapOf("ok" to true, "message" to "E-posta taslağı açıldı: $email")
                }
                else -> {
                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        this.type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        putExtra(Intent.EXTRA_TEXT, message)
                    }
                    startActivity(Intent.createChooser(sendIntent, "Paylaş").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    mapOf("ok" to true, "message" to "Paylaşım menüsü açıldı.")
                }
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to "İletişim ekranı açılamadı: ${e.message}")
        }
    }

    private fun queryContactsList(query: String, limit: Int): List<Map<String, String>> {
        val results = mutableListOf<Map<String, String>>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return results
        }
        var cursor: Cursor? = null
        try {
            val selection = if (query.isNotBlank()) {
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY} LIKE ? OR ${ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ?"
            } else null
            val args = if (query.isNotBlank()) arrayOf("%$query%", "%$query%") else null
            cursor = contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                selection,
                args,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY} ASC"
            )
            val seen = mutableSetOf<String>()
            while (cursor != null && cursor.moveToNext() && results.size < limit) {
                val name = cursor.getString(0) ?: ""
                val number = cursor.getString(1) ?: ""
                val key = "$name|$number"
                if (name.isNotBlank() && seen.add(key)) {
                    results.add(mapOf("name" to name, "phone" to number))
                }
            }
        } catch (_: Exception) {
        } finally {
            cursor?.close()
        }
        return results
    }

    private fun handleCalendarAction(
        mode: String,
        title: String,
        description: String,
        location: String,
        startMillis: Long,
        endMillis: Long,
        days: Int
    ): Map<String, Any?> {
        try {
            if (mode.equals("add", ignoreCase = true) || mode.equals("ekle", ignoreCase = true)) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
                ) {
                    var calId = 1L
                    contentResolver.query(
                        CalendarContract.Calendars.CONTENT_URI,
                        arrayOf(CalendarContract.Calendars._ID),
                        "${CalendarContract.Calendars.VISIBLE} = 1",
                        null,
                        null
                    )?.use { c ->
                        if (c.moveToFirst()) calId = c.getLong(0)
                    }
                    val values = ContentValues().apply {
                        put(CalendarContract.Events.DTSTART, startMillis)
                        put(CalendarContract.Events.DTEND, endMillis)
                        put(CalendarContract.Events.TITLE, title)
                        put(CalendarContract.Events.DESCRIPTION, description)
                        put(CalendarContract.Events.EVENT_LOCATION, location)
                        put(CalendarContract.Events.CALENDAR_ID, calId)
                        put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                    }
                    val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                    if (uri != null) {
                        return mapOf("ok" to true, "message" to "'$title' takvime eklendi.")
                    }
                }
                val intent = Intent(Intent.ACTION_INSERT).apply {
                    data = CalendarContract.Events.CONTENT_URI
                    putExtra(CalendarContract.Events.TITLE, title)
                    putExtra(CalendarContract.Events.DESCRIPTION, description)
                    putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                    putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMillis)
                    putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return mapOf("ok" to true, "message" to "Takvim etkinlik ekleme ekranı açıldı: $title")
            } else {
                val events = mutableListOf<Map<String, Any?>>()
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) {
                    val now = System.currentTimeMillis()
                    val endRange = now + days.coerceIn(1, 60) * 86_400_000L
                    val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
                    ContentUris.appendId(builder, now)
                    ContentUris.appendId(builder, endRange)
                    contentResolver.query(
                        builder.build(),
                        arrayOf(
                            CalendarContract.Instances.TITLE,
                            CalendarContract.Instances.BEGIN,
                            CalendarContract.Instances.END,
                            CalendarContract.Instances.EVENT_LOCATION
                        ),
                        null,
                        null,
                        "${CalendarContract.Instances.BEGIN} ASC"
                    )?.use { c ->
                        while (c.moveToNext() && events.size < 20) {
                            events.add(
                                mapOf(
                                    "title" to (c.getString(0) ?: "Etkinlik"),
                                    "startMillis" to c.getLong(1),
                                    "endMillis" to c.getLong(2),
                                    "location" to (c.getString(3) ?: "")
                                )
                            )
                        }
                    }
                }
                return mapOf("ok" to true, "events" to events)
            }
        } catch (e: Exception) {
            return mapOf("ok" to false, "message" to "Takvim işlemi başarısız: ${e.message}")
        }
    }

    private fun handleMediaControl(command: String, query: String?): Map<String, Any?> {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val cmd = command.lowercase(Locale.ROOT)
            if (!query.isNullOrBlank() && (cmd.contains("ara") || cmd.contains("cal") || cmd.contains("play_search"))) {
                val intent = Intent("android.media.action.MEDIA_PLAY_FROM_SEARCH").apply {
                    putExtra(android.app.SearchManager.QUERY, query)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return mapOf("ok" to true, "message" to "'$query' medya araması başlatıldı.")
                }
            }
            val keyCode = when {
                cmd.contains("next") || cmd.contains("sonraki") || cmd.contains("ileri") -> KeyEvent.KEYCODE_MEDIA_NEXT
                cmd.contains("prev") || cmd.contains("onceki") || cmd.contains("geri") -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                cmd.contains("pause") || cmd.contains("duraklat") -> KeyEvent.KEYCODE_MEDIA_PAUSE
                cmd.contains("stop") || cmd.contains("durdur") -> KeyEvent.KEYCODE_MEDIA_STOP
                cmd.contains("play") || cmd.contains("oynat") || cmd.contains("devam") -> KeyEvent.KEYCODE_MEDIA_PLAY
                else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            }
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
            mapOf("ok" to true, "message" to "Medya komutu gönderildi: $command")
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to "Medya kontrolü başarısız: ${e.message}")
        }
    }

    // ─── FILE SHARE, OPEN, EXPORT & PICKER ───────────────────────────────────

    private fun shareLocalFile(path: String, title: String, mimeType: String?, text: String?): Boolean {
        return try {
            val srcFile = File(path)
            if (!srcFile.exists()) return false

            val shareDir = File(cacheDir, "share")
            if (!shareDir.exists()) shareDir.mkdirs()

            val ext = srcFile.extension.ifBlank { "bin" }
            val safeBase = title.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { srcFile.nameWithoutExtension }
            val targetName = if (safeBase.endsWith(".$ext", ignoreCase = true)) safeBase else "$safeBase.$ext"
            val dstFile = File(shareDir, targetName)
            if (srcFile.absolutePath != dstFile.absolutePath) {
                srcFile.copyTo(dstFile, overwrite = true)
            }

            val authority = "${applicationContext.packageName}.fileprovider"
            val uri = FileProvider.getUriForFile(this, authority, dstFile)
            val resolvedMime = mimeType?.takeIf { it.isNotBlank() }
                ?: URLConnection.guessContentTypeFromName(dstFile.name)
                ?: "*/*"

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = resolvedMime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_TITLE, title)
                putExtra(Intent.EXTRA_SUBJECT, title)
                if (!text.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                clipData = ClipData.newRawUri(title, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, title).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openLocalFile(path: String, mimeType: String?): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val authority = "${applicationContext.packageName}.fileprovider"
            val uri = FileProvider.getUriForFile(this, authority, file)
            val resolvedMime = mimeType?.takeIf { it.isNotBlank() }
                ?: URLConnection.guessContentTypeFromName(file.name)
                ?: "*/*"
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, resolvedMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(viewIntent, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun startExportDocument(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        result: MethodChannel.Result
    ) {
        try {
            pendingExportBytes = bytes
            pendingExportResult = result
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            startActivityForResult(intent, REQ_EXPORT_FILE)
        } catch (e: Exception) {
            pendingExportBytes = null
            pendingExportResult = null
            result.error("EXPORT_ERR", e.message, null)
        }
    }

    private fun saveToPublicDownloads(
        fileName: String,
        subFolder: String,
        mimeType: String,
        bytes: ByteArray?,
        sourcePath: String?
    ): Map<String, Any?> {
        val rawBytes: ByteArray = when {
            bytes != null && bytes.isNotEmpty() -> bytes
            !sourcePath.isNullOrBlank() && File(sourcePath).exists() -> File(sourcePath).readBytes()
            else -> return mapOf("ok" to false, "message" to "Kaydedilecek dosya verisi bulunamadı.")
        }

        val safeName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "Asistan_Dosya_${System.currentTimeMillis()}" }
        val cleanSub = subFolder.replace(Regex("^/+|/+$"), "").ifEmpty { "Asistan" }

        // 1. Try direct write to /storage/emulated/0/Download/<cleanSub>/<safeName>
        try {
            val pubRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val targetDir = File(pubRoot, cleanSub)
            if (!targetDir.exists()) targetDir.mkdirs()
            val outFile = File(targetDir, safeName)
            FileOutputStream(outFile).use {
                it.write(rawBytes)
                it.flush()
            }
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(outFile.absolutePath),
                arrayOf(mimeType),
                null
            )
            return mapOf(
                "ok" to true,
                "path" to outFile.absolutePath,
                "displayPath" to "İndirilenler/$cleanSub/$safeName",
                "sizeBytes" to rawBytes.size
            )
        } catch (_: Exception) {
        }

        // 2. Fallback to Android 10+ MediaStore.Downloads
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                    put(MediaStore.Downloads.MIME_TYPE, mimeType)
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$cleanSub")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = applicationContext.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { out ->
                        out.write(rawBytes)
                        out.flush()
                    }
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)

                    // Also keep a local copy in app files so openFile/shareFile works with FileProvider
                    val localDir = File(filesDir, "downloads/$cleanSub")
                    if (!localDir.exists()) localDir.mkdirs()
                    val localCopy = File(localDir, safeName)
                    FileOutputStream(localCopy).use { it.write(rawBytes) }

                    return mapOf(
                        "ok" to true,
                        "path" to localCopy.absolutePath,
                        "uri" to uri.toString(),
                        "displayPath" to "İndirilenler/$cleanSub/$safeName",
                        "sizeBytes" to rawBytes.size
                    )
                }
            } catch (_: Exception) {
            }
        }

        // 3. Final fallback to app-specific external downloads
        return try {
            val extDir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir, cleanSub)
            if (!extDir.exists()) extDir.mkdirs()
            val outFile = File(extDir, safeName)
            FileOutputStream(outFile).use { it.write(rawBytes) }
            mapOf(
                "ok" to true,
                "path" to outFile.absolutePath,
                "displayPath" to "Uygulama İndirilenler/$cleanSub/$safeName",
                "sizeBytes" to rawBytes.size
            )
        } catch (e: Exception) {
            mapOf("ok" to false, "message" to e.message)
        }
    }

    private fun synthesizeTtsToAudioFile(
        text: String,
        title: String,
        rate: Float,
        pitch: Float,
        result: MethodChannel.Result
    ) {
        if (text.isBlank()) {
            result.success(mapOf("ok" to false, "message" to "Seslendirilecek metin boş."))
            return
        }
        try {
            if (tts == null || !ttsReady) {
                initTts()
            }
            tts?.setSpeechRate(rate.coerceIn(0.5f, 2.2f))
            tts?.setPitch(pitch.coerceIn(0.5f, 2.0f))

            val safeStem = title.replace(Regex("[\\\\/:*?\"<>|\\s]+"), "_").take(36).ifBlank { "Asistan_Ses" }
            val fileName = "${safeStem}_${System.currentTimeMillis() % 100000}.wav"
            val tempDir = File(filesDir, "asistan_atolye")
            if (!tempDir.exists()) tempDir.mkdirs()
            val outFile = File(tempDir, fileName)
            val uttId = "synth_${System.currentTimeMillis()}"

            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    if (utteranceId != uttId) {
                        notifyFlutter("onTtsStart", mapOf("id" to (utteranceId ?: "")))
                    }
                }
                override fun onDone(utteranceId: String?) {
                    if (utteranceId == uttId) {
                        val saved = saveToPublicDownloads(
                            fileName = fileName,
                            subFolder = "Asistan/Sesler",
                            mimeType = "audio/wav",
                            bytes = null,
                            sourcePath = outFile.absolutePath
                        )
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "path" to (saved["path"] ?: outFile.absolutePath),
                                    "displayPath" to (saved["displayPath"] ?: "İndirilenler/Asistan/Sesler/$fileName"),
                                    "sizeBytes" to outFile.length(),
                                    "format" to "wav",
                                    "mimeType" to "audio/wav"
                                )
                            )
                        }
                    } else {
                        notifyFlutter("onTtsDone", mapOf("id" to (utteranceId ?: "")))
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    if (utteranceId == uttId) {
                        mainHandler.post {
                            result.success(mapOf("ok" to false, "message" to "Ses dosyası sentezlenemedi."))
                        }
                    } else {
                        notifyFlutter("onTtsDone", mapOf("id" to (utteranceId ?: ""), "error" to true))
                    }
                }
            })

            val params = Bundle()
            val cleanText = if (text.length > 3500) text.substring(0, 3500) else text
            val code = tts?.synthesizeToFile(cleanText, params, outFile, uttId)
            if (code != TextToSpeech.SUCCESS) {
                result.success(mapOf("ok" to false, "message" to "TTS başlatılamadı."))
            }
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "message" to e.message))
        }
    }

    private fun startPickFiles(allowMultiple: Boolean, result: MethodChannel.Result) {
        try {
            pendingPickResult = result
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            }
            startActivityForResult(intent, REQ_PICK_FILES)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICK_ERR", e.message, null)
        }
    }

    private fun requestRuntimePermissions(result: MethodChannel.Result) {
        // General setup asks only for voice. Other sensitive permissions are not bundled.
        val perms = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missing = perms.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
        } else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQ_PERMISSIONS)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PERMISSIONS) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            val anyGranted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            res?.success(anyGranted)
            if (startSpeechAfterPerm) {
                startSpeechAfterPerm = false
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    startSpeechListeningInternal(pendingSpeechLocale, pendingSpeechPartial)
                } else {
                    notifyFlutter("onSpeechError", mapOf("code" to 9, "message" to "Mikrofon izni reddedildi. Uygulama izinlerinden mikrofonu açın."))
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_EXPORT_FILE) {
            val res = pendingExportResult
            val bytes = pendingExportBytes
            pendingExportResult = null
            pendingExportBytes = null
            if (resultCode == Activity.RESULT_OK && data?.data != null && bytes != null) {
                try {
                    contentResolver.openOutputStream(data.data!!)?.use { out ->
                        out.write(bytes)
                        out.flush()
                    }
                    res?.success(data.data.toString())
                } catch (e: Exception) {
                    res?.error("WRITE_ERR", e.message, null)
                }
            } else {
                res?.success(null)
            }
        } else if (requestCode == REQ_PICK_FILES) {
            val res = pendingPickResult
            pendingPickResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val list = mutableListOf<Map<String, Any?>>()
                val clip = data.clipData
                if (clip != null) {
                    for (i in 0 until clip.itemCount) {
                        copyUriToIncomingCache(clip.getItemAt(i).uri)?.let { list.add(it) }
                    }
                } else if (data.data != null) {
                    copyUriToIncomingCache(data.data!!)?.let { list.add(it) }
                }
                res?.success(list)
            } else {
                res?.success(emptyList<Map<String, Any?>>())
            }
        }
    }

    override fun onDestroy() {
        activeChannel = null
        try {
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        try {
            tts?.shutdown()
        } catch (_: Exception) {
        }
        stopMediaPlayer()
        super.onDestroy()
    }
}

// ─── SHARE TARGET ACTIVITY ALIAS (`GelenKutusuPaylas`) ──────────────────────

class GelenKutusuPaylas : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val forward = Intent(this, MainActivity::class.java).apply {
                action = intent?.action
                type = intent?.type
                if (intent?.extras != null) {
                    putExtras(intent.extras!!)
                }
                clipData = intent?.clipData
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(forward)
        } catch (_: Exception) {
        } finally {
            finish()
        }
    }
}

// ─── FOREGROUND BACKGROUND SERVICE (`AsistanBackgroundService`) ─────────────

class AsistanBackgroundService : Service() {
    companion object {
        const val CHANNEL_ID = "asistan_bg_channel_v3"
        const val NOTIF_ID = 8317
        const val ACTION_START_OR_UPDATE = "com.mehmetderin.asistan.BG_START_OR_UPDATE"
        const val ACTION_STOP = "com.mehmetderin.asistan.BG_STOP"
        const val ACTION_VOICE_TRIGGER = "com.mehmetderin.asistan.BG_VOICE_TRIGGER"
        const val ACTION_STOP_TTS = "com.mehmetderin.asistan.BG_STOP_TTS"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_SUBTITLE = "extra_subtitle"
        const val EXTRA_WAKE_WORD = "extra_wake_word"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var currentTitle: String = "Asistan AI Aktif"
    private var currentSubtitle: String = "Arka plan servisi ve sesli yanıt hazır"
    private var wakeWordEnabled: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_OR_UPDATE
        when (action) {
            ACTION_STOP -> {
                releaseLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_VOICE_TRIGGER -> {
                MainActivity.notifyFlutter("onBackgroundAction", mapOf("action" to "voice_listen"))
                val openIntent = Intent(this, MainActivity::class.java).apply {
                    putExtra("asistan_voice_trigger", true)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(openIntent)
            }
            ACTION_STOP_TTS -> {
                MainActivity.notifyFlutter("onBackgroundAction", mapOf("action" to "stop_tts"))
            }
            else -> {
                intent?.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
                intent?.getStringExtra(EXTRA_SUBTITLE)?.let { currentSubtitle = it }
                if (intent?.hasExtra(EXTRA_WAKE_WORD) == true) {
                    wakeWordEnabled = intent.getBooleanExtra(EXTRA_WAKE_WORD, false)
                }
                acquireLocks()
                val notification = buildNotification()
                val hasMicPerm = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        var fgTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                        if (hasMicPerm) {
                            fgTypes = fgTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        }
                        startForeground(NOTIF_ID, notification, fgTypes)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        var fgTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                        if (hasMicPerm) {
                            fgTypes = fgTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        }
                        startForeground(NOTIF_ID, notification, fgTypes)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NOTIF_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                        )
                    } else {
                        startForeground(NOTIF_ID, notification)
                    }
                } catch (_: Exception) {
                    try {
                        startForeground(NOTIF_ID, notification)
                    } catch (_: Exception) {
                    }
                }
            }
        }
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentPi = PendingIntent.getActivity(this, 100, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag)

        val voiceIntent = Intent(this, AsistanBackgroundService::class.java).apply {
            action = ACTION_VOICE_TRIGGER
        }
        val voicePi = PendingIntent.getService(this, 101, voiceIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag)

        val stopTtsIntent = Intent(this, AsistanBackgroundService::class.java).apply {
            action = ACTION_STOP_TTS
        }
        val stopTtsPi = PendingIntent.getService(this, 102, stopTtsIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag)

        val stopServiceIntent = Intent(this, AsistanBackgroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopServicePi = PendingIntent.getService(this, 103, stopServiceIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag)

        val statusSuffix = if (wakeWordEnabled) " • \"Hey Asistan\" Dinlemede" else ""

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(currentTitle)
            .setContentText("$currentSubtitle$statusSuffix")
            .setSubText("ChatGPT • Gemini • Claude • Siri Asistan")
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(android.R.drawable.ic_btn_speak_now, "Sesli Sor", voicePi)
            .addAction(android.R.drawable.ic_media_pause, "Sesi Sustur", stopTtsPi)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Kapat", stopServicePi)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Asistan Arka Plan Servisi",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Asistan'ın arka planda kesintisiz çalışmasını ve sesli yanıt vermesini sağlar."
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Asistan::BackgroundWakeLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(12 * 60 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "Asistan::BackgroundWifiLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

// ─── REMINDER BROADCAST RECEIVER (`AsistanReminderReceiver`) ────────────────

class AsistanReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val id = intent?.getIntExtra("id", 5001) ?: 5001
        val title = intent?.getStringExtra("title") ?: "Asistan Hatırlatıcı"
        val body = intent?.getStringExtra("body") ?: "Zamanlanmış hatırlatıcı zamanı geldi."

        val channelId = "asistan_reminders_v3"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                channelId,
                "Asistan Hatırlatıcılar",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Zamanlanmış Asistan hatırlatıcı bildirimleri"
                enableVibration(true)
            }
            nm.createNotificationChannel(ch)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("asistan_reminder_title", title)
            putExtra("asistan_reminder_body", body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pi = PendingIntent.getActivity(context, id, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag)

        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("🔔 $title")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        nm.notify(id, notif)
        MainActivity.notifyFlutter("onReminderTriggered", mapOf("id" to id, "title" to title, "body" to body))
    }
}
