package com.mehmetderin.ritim

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadata
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.mehmetderin.ritim/platform"
        private const val REQ_PICK_MEDIA = 4101
        private const val REQ_PICK_LYRICS = 4102
        private const val REQ_PICK_BACKUP = 4103
        private const val REQ_EXPORT_BACKUP = 4104
        private const val REQ_EXPORT_MEDIA = 4105
        private const val REQ_POST_NOTIF = 4106
        const val NOTIF_CHANNEL_ID = "ritim_playback"
        const val NOTIF_ID = 4109

        @Volatile
        var methodChannel: MethodChannel? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun dispatchMediaAction(action: String, positionMs: Long? = null) {
            mainHandler.post {
                val payload = mutableMapOf<String, Any>("action" to action)
                if (positionMs != null) {
                    payload["positionMs"] = positionMs
                }
                try {
                    methodChannel?.invokeMethod("onMediaAction", payload)
                } catch (_: Exception) {
                }
            }
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingExportPath: String? = null
    private var pendingImportDir: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureNotificationChannel()
        requestNotificationPermissionIfNeeded()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickMediaFiles" -> {
                    val destDir = call.argument<String>("destDir")
                    if (pendingResult != null) {
                        result.error("BUSY", "Başka bir dosya seçimi sürüyor.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingImportDir = destDir
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf(
                                "audio/*",
                                "video/mp4",
                                "video/quicktime",
                                "application/octet-stream",
                            ),
                        )
                    }
                    startActivityForResult(intent, REQ_PICK_MEDIA)
                }

                "pickLyricsFile" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "Başka bir dosya seçimi sürüyor.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/plain", "application/octet-stream", "*/*"))
                    }
                    startActivityForResult(intent, REQ_PICK_LYRICS)
                }

                "pickBackupFile" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "Başka bir dosya seçimi sürüyor.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingImportDir = call.argument<String>("destDir")
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, REQ_PICK_BACKUP)
                }

                "exportBackupFile" -> {
                    val srcPath = call.argument<String>("path")
                    val suggestedName = call.argument<String>("suggestedName") ?: "ritim-yedek.ritimbackup"
                    if (srcPath.isNullOrEmpty() || pendingResult != null) {
                        result.error("INVALID", "Yedek dosyası dışa aktarılamadı.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingExportPath = srcPath
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, REQ_EXPORT_BACKUP)
                }

                "exportMediaFile" -> {
                    val srcPath = call.argument<String>("path")
                    val suggestedName = call.argument<String>("suggestedName") ?: "ritim-medya.m4a"
                    val mimeType = call.argument<String>("mimeType") ?: resolveMimeType(suggestedName)
                    if (srcPath.isNullOrEmpty() || !File(srcPath).exists() || pendingResult != null) {
                        result.error("INVALID", "Medya dosyası dışa aktarılamadı.", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    pendingExportPath = srcPath
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, REQ_EXPORT_MEDIA)
                }

                "inspectMedia" -> {
                    val path = call.argument<String>("path")
                    val artworkDir = call.argument<String>("artworkDir")
                    if (path.isNullOrEmpty()) {
                        result.error("ARGS", "Dosya yolu eksik.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val info = inspectMediaFile(path, artworkDir)
                            runOnUiThread { result.success(info) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("INSPECT", e.message, null) }
                        }
                    }.start()
                }

                "muxAudioVideo" -> {
                    val audioPath = call.argument<String>("audioPath")
                    val videoPath = call.argument<String>("videoPath")
                    val outPath = call.argument<String>("outPath")
                    if (audioPath.isNullOrEmpty() || videoPath.isNullOrEmpty() || outPath.isNullOrEmpty()) {
                        result.error("ARGS", "Ses/video yolları eksik.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            muxMp4(audioPath, videoPath, outPath)
                            runOnUiThread { result.success(outPath) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("MUX", e.message ?: "Medya birleştirilemedi.", null) }
                        }
                    }.start()
                }

                "extractAudio" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outPath = call.argument<String>("outPath")
                    if (inputPath.isNullOrEmpty() || outPath.isNullOrEmpty()) {
                        result.error("ARGS", "Kaynak/hedef dosya yolu eksik.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            extractAudioToM4a(inputPath, outPath)
                            runOnUiThread { result.success(outPath) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXTRACT", e.message ?: "Ses akışı ayrıştırılamadı.", null) }
                        }
                    }.start()
                }

                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val title = call.argument<String>("title") ?: "Paylaş"
                    val fileName = call.argument<String>("fileName")
                    val explicitMime = call.argument<String>("mimeType")
                    if (path.isNullOrEmpty()) {
                        result.error("ARGS", "Dosya bulunamadı.", null)
                        return@setMethodCallHandler
                    }
                    val srcFile = File(path)
                    if (!srcFile.exists() || srcFile.length() <= 0L) {
                        result.error("MISSING", "Paylaşılacak medya dosyası bulunamadı.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val shareDir = File(cacheDir, "share").apply { mkdirs() }
                            // Eski geçici paylaşım dosyalarını temizle
                            val now = System.currentTimeMillis()
                            shareDir.listFiles()?.forEach { old ->
                                if (now - old.lastModified() > 3_600_000L && old.name != fileName) {
                                    try {
                                        old.delete()
                                    } catch (_: Exception) {
                                    }
                                }
                            }

                            val cleanName = sanitizeFileName(
                                fileName?.takeIf { it.isNotBlank() } ?: srcFile.name,
                                fallbackExt = srcFile.extension.ifEmpty { "m4a" },
                            )
                            val targetFile = File(shareDir, cleanName)
                            if (!targetFile.exists() || targetFile.length() != srcFile.length()) {
                                srcFile.copyTo(targetFile, overwrite = true)
                            }

                            val uri = FileProvider.getUriForFile(
                                this@MainActivity,
                                "$packageName.fileprovider",
                                targetFile,
                            )
                            val mime = explicitMime?.takeIf { it.isNotBlank() }
                                ?: resolveMimeType(targetFile.name)

                            runOnUiThread {
                                try {
                                    val clip = ClipData.newRawUri(title, uri)
                                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                        type = mime
                                        putExtra(Intent.EXTRA_STREAM, uri)
                                        putExtra(Intent.EXTRA_TITLE, title)
                                        putExtra(Intent.EXTRA_SUBJECT, title)
                                        clipData = clip
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    }
                                    val chooser = Intent.createChooser(sendIntent, title).apply {
                                        clipData = clip
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    }
                                    startActivity(chooser)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("SHARE", e.message ?: "Paylaşım penceresi açılamadı.", null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SHARE", e.message ?: "Dosya paylaşıma hazırlanamadı.", null)
                            }
                        }
                    }.start()
                }

                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val active = call.argument<Boolean>("active") ?: false
                    val artworkPath = call.argument<String>("artworkPath")
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong() ?: 0L
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val playbackSpeed = (call.argument<Number>("playbackSpeed"))?.toFloat() ?: 1.0f
                    val activeDownloads = (call.argument<Number>("activeDownloads"))?.toInt() ?: 0

                    RitimPlaybackService.syncState(
                        context = this,
                        title = title,
                        artist = artist,
                        isPlaying = isPlaying,
                        active = active,
                        artworkPath = artworkPath,
                        durationMs = durationMs,
                        positionMs = positionMs,
                        playbackSpeed = playbackSpeed,
                        activeDownloads = activeDownloads,
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_POST_NOTIF)
            }
        }
    }

    private fun sanitizeFileName(raw: String, fallbackExt: String): String {
        val cleaned = raw
            .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        if (cleaned.isEmpty()) return "Ritim_Parca.$fallbackExt"
        return if (cleaned.contains('.')) cleaned else "$cleaned.$fallbackExt"
    }

    private fun resolveMimeType(fileName: String): String {
        return when (fileName.substringAfterLast('.', "").lowercase()) {
            "mp4", "m4v" -> "video/mp4"
            "mov" -> "video/quicktime"
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/mp4"
            "wav" -> "audio/wav"
            "ogg", "opus" -> "audio/ogg"
            "flac" -> "audio/flac"
            else -> "audio/*"
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_POST_NOTIF) return
        val callback = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingExportPath = null
            pendingImportDir = null
            callback.success(null)
            return
        }

        when (requestCode) {
            REQ_PICK_MEDIA -> {
                val destDir = pendingImportDir ?: filesDir.absolutePath
                pendingImportDir = null
                val uris = mutableListOf<Uri>()
                data.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) {
                        clip.getItemAt(i)?.uri?.let { uris.add(it) }
                    }
                } ?: data.data?.let { uris.add(it) }

                Thread {
                    val items = mutableListOf<Map<String, Any?>>()
                    val dir = File(destDir).apply { mkdirs() }
                    for (uri in uris) {
                        try {
                            val name = resolveDisplayName(uri) ?: "parca_${UUID.randomUUID().toString().take(8)}.m4a"
                            val safeExt = name.substringAfterLast('.', "m4a").lowercase()
                            val tempName = "${UUID.randomUUID()}.$safeExt"
                            val outFile = File(dir, tempName)
                            contentResolver.openInputStream(uri)?.use { input ->
                                FileOutputStream(outFile).use { output -> input.copyTo(output) }
                            }
                            if (outFile.exists() && outFile.length() > 0) {
                                items.add(
                                    mapOf(
                                        "path" to outFile.absolutePath,
                                        "originalName" to name,
                                        "size" to outFile.length(),
                                    ),
                                )
                            }
                        } catch (_: Exception) {
                        }
                    }
                    runOnUiThread { callback.success(items) }
                }.start()
            }

            REQ_PICK_LYRICS -> {
                val uri = data.data
                if (uri == null) {
                    callback.success(null)
                    return
                }
                Thread {
                    try {
                        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                        val name = resolveDisplayName(uri) ?: "sozler.lrc"
                        val text = decodeLyricsBytes(bytes)
                        runOnUiThread {
                            callback.success(mapOf("name" to name, "text" to text))
                        }
                    } catch (e: Exception) {
                        runOnUiThread { callback.error("LYRICS", e.message, null) }
                    }
                }.start()
            }

            REQ_PICK_BACKUP -> {
                val uri = data.data
                val destDir = pendingImportDir ?: cacheDir.absolutePath
                pendingImportDir = null
                if (uri == null) {
                    callback.success(null)
                    return
                }
                Thread {
                    try {
                        val name = resolveDisplayName(uri) ?: "yedek.ritimbackup"
                        val outFile = File(destDir, "import_${System.currentTimeMillis()}_$name")
                        outFile.parentFile?.mkdirs()
                        contentResolver.openInputStream(uri)?.use { input ->
                            FileOutputStream(outFile).use { output -> input.copyTo(output) }
                        }
                        runOnUiThread { callback.success(outFile.absolutePath) }
                    } catch (e: Exception) {
                        runOnUiThread { callback.error("BACKUP", e.message, null) }
                    }
                }.start()
            }

            REQ_EXPORT_BACKUP, REQ_EXPORT_MEDIA -> {
                val srcPath = pendingExportPath
                pendingExportPath = null
                val uri = data.data
                if (uri == null || srcPath == null) {
                    callback.success(false)
                    return
                }
                Thread {
                    try {
                        File(srcPath).inputStream().use { input ->
                            contentResolver.openOutputStream(uri)?.use { output -> input.copyTo(output) }
                        }
                        runOnUiThread { callback.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread { callback.error("EXPORT", e.message, null) }
                    }
                }.start()
            }
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) return cursor.getString(idx)
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun decodeLyricsBytes(bytes: ByteArray): String {
        if (bytes.size >= 2) {
            if (bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) {
                return String(bytes, Charsets.UTF_16LE)
            }
            if (bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) {
                return String(bytes, Charsets.UTF_16BE)
            }
        }
        return String(bytes, Charsets.UTF_8)
    }

    private fun inspectMediaFile(path: String, artworkDir: String?): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim()
            val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.trim()
                ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)?.trim()
            val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.trim()
            val trackRaw = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)?.trim()
            val discRaw = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER)?.trim()
            val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()

            var artworkPath: String? = null
            val pic = retriever.embeddedPicture
            if (pic != null && pic.isNotEmpty() && !artworkDir.isNullOrEmpty()) {
                val dir = File(artworkDir).apply { mkdirs() }
                val artFile = File(dir, "art_${UUID.randomUUID()}.jpg")
                FileOutputStream(artFile).use { it.write(pic) }
                artworkPath = artFile.absolutePath
            } else if (hasVideo && !artworkDir.isNullOrEmpty()) {
                try {
                    val frame = retriever.getFrameAtTime(
                        1_000_000L,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    )
                    if (frame != null) {
                        val dir = File(artworkDir).apply { mkdirs() }
                        val artFile = File(dir, "art_${UUID.randomUUID()}.jpg")
                        FileOutputStream(artFile).use { out ->
                            frame.compress(Bitmap.CompressFormat.JPEG, 86, out)
                        }
                        frame.recycle()
                        if (artFile.exists() && artFile.length() > 512) {
                            artworkPath = artFile.absolutePath
                        }
                    }
                } catch (_: Exception) {
                }
            }

            mapOf(
                "durationSeconds" to (durationMs / 1000.0),
                "title" to title,
                "artist" to artist,
                "album" to album,
                "trackNumber" to trackRaw?.substringBefore('/')?.trim()?.toIntOrNull(),
                "discNumber" to discRaw?.substringBefore('/')?.trim()?.toIntOrNull(),
                "hasVideo" to hasVideo,
                "width" to width,
                "height" to height,
                "artworkPath" to artworkPath,
            )
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun muxMp4(audioPath: String, videoPath: String, outPath: String) {
        val muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val videoEx = MediaExtractor()
        val audioEx = MediaExtractor()
        try {
            videoEx.setDataSource(videoPath)
            audioEx.setDataSource(audioPath)
            var vSrc = -1
            var vDst = -1
            for (i in 0 until videoEx.trackCount) {
                val fmt = videoEx.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    videoEx.selectTrack(i)
                    vSrc = i
                    vDst = muxer.addTrack(fmt)
                    break
                }
            }
            var aSrc = -1
            var aDst = -1
            for (i in 0 until audioEx.trackCount) {
                val fmt = audioEx.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioEx.selectTrack(i)
                    aSrc = i
                    aDst = muxer.addTrack(fmt)
                    break
                }
            }
            if (vSrc < 0 && aSrc < 0) throw IllegalStateException("Birleştirilecek akış bulunamadı.")
            muxer.start()
            val buf = ByteBuffer.allocateDirect(4 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            if (vDst >= 0) {
                var lastPts = -1L
                while (true) {
                    buf.clear()
                    val sampleSize = videoEx.readSampleData(buf, 0)
                    if (sampleSize < 0) break
                    val rawPts = videoEx.sampleTime.coerceAtLeast(0L)
                    val pts = if (rawPts <= lastPts) lastPts + 1L else rawPts
                    lastPts = pts
                    info.offset = 0
                    info.size = sampleSize
                    info.presentationTimeUs = pts
                    info.flags = if ((videoEx.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    muxer.writeSampleData(vDst, buf, info)
                    videoEx.advance()
                }
            }
            if (aDst >= 0) {
                var lastPts = -1L
                while (true) {
                    buf.clear()
                    val sampleSize = audioEx.readSampleData(buf, 0)
                    if (sampleSize < 0) break
                    val rawPts = audioEx.sampleTime.coerceAtLeast(0L)
                    val pts = if (rawPts <= lastPts) lastPts + 1L else rawPts
                    lastPts = pts
                    info.offset = 0
                    info.size = sampleSize
                    info.presentationTimeUs = pts
                    info.flags = if ((audioEx.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    muxer.writeSampleData(aDst, buf, info)
                    audioEx.advance()
                }
            }
            muxer.stop()
        } finally {
            try {
                muxer.release()
            } catch (_: Exception) {
            }
            try {
                videoEx.release()
            } catch (_: Exception) {
            }
            try {
                audioEx.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun extractAudioToM4a(inputPath: String, outPath: String) {
        File(outPath).parentFile?.mkdirs()
        if (File(outPath).exists()) File(outPath).delete()
        val muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)
            var audioTrackIndex = -1
            var dstTrack = -1
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    extractor.selectTrack(i)
                    audioTrackIndex = i
                    dstTrack = muxer.addTrack(fmt)
                    break
                }
            }
            if (audioTrackIndex < 0 || dstTrack < 0) {
                throw IllegalStateException("Kaynak dosyada ses kanalı bulunamadı.")
            }
            muxer.start()
            val buf = ByteBuffer.allocateDirect(2 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            var lastPts = -1L
            while (true) {
                buf.clear()
                val sampleSize = extractor.readSampleData(buf, 0)
                if (sampleSize < 0) break
                val rawPts = extractor.sampleTime.coerceAtLeast(0L)
                val pts = if (rawPts <= lastPts) lastPts + 1L else rawPts
                lastPts = pts
                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = pts
                info.flags = if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                muxer.writeSampleData(dstTrack, buf, info)
                extractor.advance()
            }
            muxer.stop()
        } finally {
            try {
                muxer.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Ritim Oynatıcı",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Arka plan müzik/video oynatıcı ve indirme kontrolleri"
                setShowBadge(false)
            }
            mgr.createNotificationChannel(ch)
        }
    }
}

class RitimPlaybackService : Service() {
    companion object {
        private const val ACTION_SYNC = "com.mehmetderin.ritim.ACTION_SYNC"
        private const val ACTION_PLAY_PAUSE = "com.mehmetderin.ritim.ACTION_PLAY_PAUSE"
        private const val ACTION_NEXT = "com.mehmetderin.ritim.ACTION_NEXT"
        private const val ACTION_PREV = "com.mehmetderin.ritim.ACTION_PREV"

        fun syncState(
            context: Context,
            title: String,
            artist: String,
            isPlaying: Boolean,
            active: Boolean,
            artworkPath: String?,
            durationMs: Long,
            positionMs: Long,
            playbackSpeed: Float,
            activeDownloads: Int,
        ) {
            val keepAlive = (active && title.isNotEmpty()) || activeDownloads > 0
            val intent = Intent(context, RitimPlaybackService::class.java).apply {
                action = ACTION_SYNC
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("isPlaying", isPlaying)
                putExtra("active", active)
                putExtra("artworkPath", artworkPath)
                putExtra("durationMs", durationMs)
                putExtra("positionMs", positionMs)
                putExtra("playbackSpeed", playbackSpeed)
                putExtra("activeDownloads", activeDownloads)
            }
            try {
                if (keepAlive) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } else {
                    context.stopService(intent)
                }
            } catch (_: Exception) {
                try {
                    context.startService(intent)
                } catch (_: Exception) {
                }
            }
        }
    }

    private var mediaSession: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var cachedArtworkPath: String? = null
    private var cachedArtworkBitmap: Bitmap? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        initMediaSession()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            val ch = NotificationChannel(
                MainActivity.NOTIF_CHANNEL_ID,
                "Ritim Oynatıcı",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Arka plan müzik/video oynatıcı ve indirme kontrolleri"
                setShowBadge(false)
            }
            mgr.createNotificationChannel(ch)
        }
    }

    private fun initMediaSession() {
        val session = MediaSession(this, "RitimMediaSession")
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() {
                MainActivity.dispatchMediaAction("play")
            }

            override fun onPause() {
                MainActivity.dispatchMediaAction("pause")
            }

            override fun onSkipToNext() {
                MainActivity.dispatchMediaAction("next")
            }

            override fun onSkipToPrevious() {
                MainActivity.dispatchMediaAction("prev")
            }

            override fun onSeekTo(pos: Long) {
                MainActivity.dispatchMediaAction("seek", pos)
            }
        })
        session.isActive = true
        mediaSession = session
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> {
                MainActivity.dispatchMediaAction("toggle")
                return START_STICKY
            }
            ACTION_NEXT -> {
                MainActivity.dispatchMediaAction("next")
                return START_STICKY
            }
            ACTION_PREV -> {
                MainActivity.dispatchMediaAction("prev")
                return START_STICKY
            }
        }

        val title = intent?.getStringExtra("title") ?: ""
        val artist = intent?.getStringExtra("artist") ?: ""
        val isPlaying = intent?.getBooleanExtra("isPlaying", false) ?: false
        val active = intent?.getBooleanExtra("active", false) ?: false
        val artworkPath = intent?.getStringExtra("artworkPath")
        val durationMs = intent?.getLongExtra("durationMs", 0L) ?: 0L
        val positionMs = intent?.getLongExtra("positionMs", 0L) ?: 0L
        val playbackSpeed = intent?.getFloatExtra("playbackSpeed", 1.0f) ?: 1.0f
        val activeDownloads = intent?.getIntExtra("activeDownloads", 0) ?: 0

        val hasMedia = active && title.isNotEmpty()
        if (!hasMedia && activeDownloads <= 0) {
            updateLocks(false)
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        updateLocks(isPlaying || activeDownloads > 0)
        val artBitmap = resolveArtwork(artworkPath)
        updateMediaSessionState(
            title = if (hasMedia) title else "Ritim İndirme Motoru",
            artist = if (hasMedia) artist else "$activeDownloads indirme arka planda sürüyor",
            isPlaying = isPlaying,
            durationMs = durationMs,
            positionMs = positionMs,
            playbackSpeed = playbackSpeed,
            artwork = artBitmap,
        )

        val notif = buildNotification(
            title = if (hasMedia) title else "Ritim İndirme Motoru",
            artist = if (hasMedia) (artist.ifEmpty { "Ritim" }) else "$activeDownloads dosya indiriliyor…",
            isPlaying = isPlaying,
            hasMedia = hasMedia,
            activeDownloads = activeDownloads,
            artwork = artBitmap,
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    MainActivity.NOTIF_ID,
                    notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(MainActivity.NOTIF_ID, notif)
            }
        } catch (_: Exception) {
            val mgr = getSystemService(NotificationManager::class.java)
            mgr.notify(MainActivity.NOTIF_ID, notif)
        }

        return START_STICKY
    }

    private fun resolveArtwork(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        if (path == cachedArtworkPath && cachedArtworkBitmap != null) {
            return cachedArtworkBitmap
        }
        return try {
            val f = File(path)
            if (!f.exists()) return null
            val bmp = BitmapFactory.decodeFile(f.absolutePath)
            if (bmp != null) {
                cachedArtworkPath = path
                cachedArtworkBitmap = bmp
            }
            bmp
        } catch (_: Exception) {
            null
        }
    }

    private fun updateMediaSessionState(
        title: String,
        artist: String,
        isPlaying: Boolean,
        durationMs: Long,
        positionMs: Long,
        playbackSpeed: Float,
        artwork: Bitmap?,
    ) {
        val session = mediaSession ?: return
        val metaBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist.ifEmpty { "Ritim" })
        if (durationMs > 0L) {
            metaBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
        }
        if (artwork != null) {
            metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, artwork)
            metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ART, artwork)
        }
        session.setMetadata(metaBuilder.build())

        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_SEEK_TO

        val stateBuilder = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                positionMs.coerceAtLeast(0L),
                if (isPlaying) playbackSpeed else 0f,
            )
        session.setPlaybackState(stateBuilder.build())
    }

    private fun buildNotification(
        title: String,
        artist: String,
        isPlaying: Boolean,
        hasMedia: Boolean,
        activeDownloads: Int,
        artwork: Bitmap?,
    ): Notification {
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPending = PendingIntent.getActivity(
            this,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MainActivity.NOTIF_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val subText = when {
            hasMedia && activeDownloads > 0 -> "${if (isPlaying) "Çalıyor" else "Duraklatıldı"} · $activeDownloads indirme"
            hasMedia -> if (isPlaying) "Çalıyor" else "Duraklatıldı"
            else -> "Arka planda indiriliyor"
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(subText)
            .setContentIntent(contentPending)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying || activeDownloads > 0)
            .setOnlyAlertOnce(true)

        if (artwork != null) {
            builder.setLargeIcon(artwork)
        }

        if (hasMedia) {
            val prevIntent = serviceActionPendingIntent(ACTION_PREV, 101)
            val toggleIntent = serviceActionPendingIntent(ACTION_PLAY_PAUSE, 102)
            val nextIntent = serviceActionPendingIntent(ACTION_NEXT, 103)

            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_previous),
                    "Önceki",
                    prevIntent,
                ).build(),
            )
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(
                        this,
                        if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                    ),
                    if (isPlaying) "Duraklat" else "Oynat",
                    toggleIntent,
                ).build(),
            )
            builder.addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_next),
                    "Sonraki",
                    nextIntent,
                ).build(),
            )

            val style = Notification.MediaStyle()
                .setShowActionsInCompactView(0, 1, 2)
            mediaSession?.sessionToken?.let { style.setMediaSession(it) }
            builder.style = style
        }

        return builder.build()
    }

    private fun serviceActionPendingIntent(action: String, reqCode: Int): PendingIntent {
        val intent = Intent(this, RitimPlaybackService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            reqCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun updateLocks(shouldHold: Boolean) {
        try {
            if (shouldHold) {
                if (wakeLock == null) {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = pm.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "Ritim::BackgroundPlaybackWakeLock",
                    ).apply {
                        setReferenceCounted(false)
                    }
                }
                if (wakeLock?.isHeld == false) {
                    wakeLock?.acquire(6 * 60 * 60 * 1000L) // max 6 saat koruma
                }

                if (wifiLock == null) {
                    val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    } else {
                        @Suppress("DEPRECATION")
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    }
                    wifiLock = wm.createWifiLock(mode, "Ritim::BackgroundWifiLock").apply {
                        setReferenceCounted(false)
                    }
                }
                if (wifiLock?.isHeld == false) {
                    wifiLock?.acquire()
                }
            } else {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        updateLocks(false)
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
        } catch (_: Exception) {
        }
        mediaSession = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
