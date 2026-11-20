package com.jarvis.assistant.jarvis_mobile

import android.app.*
import android.content.*
import android.os.*
import android.net.*
import android.provider.MediaStore
import androidx.core.content.FileProvider
import org.json.*
import java.io.*
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Persistent download queue. Partial files stay private until a complete response is verified. */
object ManagedDownloads {
    private lateinit var context: Context
    private val jobs = linkedMapOf<Long, JSONObject>()
    private val running = mutableSetOf<Long>()
    private val connections = mutableMapOf<Long, HttpURLConnection>()
    private val executor = Executors.newFixedThreadPool(3)
    private var loaded = false
    var limitKbps = 0
    var wifiOnly = false
    var concurrency = 2
    private fun prefs() = context.getSharedPreferences("jarvis_download_queue", Context.MODE_PRIVATE)
    @Synchronized fun init(ctx: Context) {
        if (loaded) return
        context = ctx.applicationContext; loaded = true
        val p = prefs(); limitKbps = p.getInt("limit", 0); wifiOnly = p.getBoolean("wifi", false); concurrency = p.getInt("parallel", 2)
        try { val rows = JSONArray(p.getString("jobs", "[]")); for (i in 0 until rows.length()) {
            val j = rows.getJSONObject(i)
            if (j.optString("status") in listOf("running", "pending")) j.put("status", "paused").put("reason", "Uygulama kapandı; devam ettirebilirsin.")
            jobs[j.getLong("id")] = j
        } } catch (_: Throwable) {}
    }
    @Synchronized private fun persist() { prefs().edit().putString("jobs", JSONArray(jobs.values.toList()).toString()).apply() }
    @Synchronized fun configure(wifi: Boolean, kbps: Int, parallel: Int) {
        wifiOnly = wifi; limitKbps = kbps.coerceIn(0, 100000); concurrency = parallel.coerceIn(1, 3)
        prefs().edit().putBoolean("wifi", wifiOnly).putInt("limit", limitKbps).putInt("parallel", concurrency).apply()
    }
    @Synchronized fun add(url: String, name: String?, mime: String?): Long? {
        val uri = Uri.parse(url)
        if (uri.scheme != "http" && uri.scheme != "https") return null
        val id = maxOf(System.currentTimeMillis(), (jobs.keys.maxOrNull() ?: 0) + 1)
        val raw = name?.takeIf { it.isNotBlank() } ?: android.webkit.URLUtil.guessFileName(url, null, mime)
        val safe = raw.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_").trim('.').take(140).ifBlank { "download-$id" }
        jobs[id] = JSONObject().put("id", id).put("url", url).put("title", safe).put("mimeType", mime ?: "application/octet-stream")
            .put("status", "pending").put("downloadedBytes", 0).put("totalBytes", -1).put("managed", true).put("speed", 0).put("lastModifiedMs", id)
        persist(); return id
    }
    private fun part(id: Long) = File(context.filesDir, "download-parts/$id.part").also { it.parentFile?.mkdirs() }
    @Synchronized fun rows(): List<Map<String, Any?>> = jobs.values.toList().asReversed().map { j ->
        j.keys().asSequence().associateWith { k -> j.opt(k).takeUnless { it == JSONObject.NULL } }
    }
    @Synchronized fun contains(id: Long) = jobs.containsKey(id)
    @Synchronized fun control(id: Long, action: String): Boolean {
        val j = jobs[id] ?: return false
        when (action) {
            "pause" -> { j.put("status", "paused").put("speed", 0).put("reason", "Sen duraklattın"); connections[id]?.disconnect() }
            "resume" -> { if (j.optString("status") != "successful") j.put("status", "pending").put("reason", "") }
            "remove" -> {
                j.put("status", "cancelled"); connections[id]?.disconnect()
                val uri = j.optString("localUri")
                if (uri.startsWith("content:")) try { context.contentResolver.delete(Uri.parse(uri), null, null) } catch (_: Throwable) {}
                jobs.remove(id); if (!running.contains(id)) part(id).delete()
            }
            else -> return false
        }
        persist(); return true
    }
    @Synchronized fun pauseAll() { for (id in jobs.keys.toList()) if (jobs[id]?.optString("status") in listOf("pending", "running")) control(id, "pause") }
    @Synchronized fun hasPending() = jobs.values.any { it.optString("status") in listOf("pending", "running") }
    private fun networkAllowed(): Boolean {
        if (!wifiOnly) return true
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return cm.getNetworkCapabilities(cm.activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }
    @Synchronized fun pump() {
        if (!networkAllowed()) {
            for (j in jobs.values) if (j.optString("status") == "pending") j.put("reason", "Wi-Fi bekleniyor")
            return
        }
        for ((id, j) in jobs) {
            if (running.size >= concurrency) break
            if (j.optString("status") != "pending" || running.contains(id)) continue
            running.add(id); j.put("status", "running").put("reason", ""); persist()
            executor.execute { download(id) }
        }
    }
    @Synchronized private fun active(id: Long) = jobs[id]?.optString("status") == "running"
    @Synchronized private fun update(id: Long, block: (JSONObject) -> Unit) { jobs[id]?.let(block); persist() }
    private fun download(id: Long) {
        val j = synchronized(this) { jobs[id]?.let { JSONObject(it.toString()) } } ?: return
        val file = part(id)
        var conn: HttpURLConnection? = null
        try {
            var offset = file.length()
            val validator = j.optString("etag").takeIf { it.isNotBlank() && !it.startsWith("W/") } ?: j.optString("modified")
            if (offset > 0 && validator.isBlank()) { file.delete(); offset = 0 }
            val connection = URL(j.getString("url")).openConnection() as HttpURLConnection
            conn = connection
            connection.connectTimeout = 15000; connection.readTimeout = 20000
            connection.setRequestProperty("User-Agent", "JARVIS/4.3 Android")
            connection.setRequestProperty("Accept-Encoding", "identity")
            if (offset > 0) { connection.setRequestProperty("Range", "bytes=$offset-"); connection.setRequestProperty("If-Range", validator) }
            synchronized(this) { connections[id] = connection }
            val code = connection.responseCode
            if (!active(id)) return
            if (code == 416 && offset > 0) { file.delete(); throw IOException("Sunucu devam ettiremiyor. Yeniden dene ile baştan başlayacak.") }
            val bodyLength = connection.getHeaderFieldLong("Content-Length", -1)
            val total = DownloadRangePolicy.validate(offset, code, connection.getHeaderField("Content-Range"), bodyLength)
            if (code == 200 && offset > 0) { file.delete(); offset = 0 }
            if (total > 0 && total - offset > file.parentFile!!.usableSpace) throw IOException("Yetersiz depolama alanı")
            val mime = connection.contentType?.substringBefore(';') ?: j.optString("mimeType")
            update(id) { it.put("totalBytes", total).put("etag", connection.getHeaderField("ETag") ?: "").put("modified", connection.getHeaderField("Last-Modified") ?: "").put("mimeType", mime) }
            var bytes = offset; val start = SystemClock.elapsedRealtime(); var lastSave = start
            connection.inputStream.use { input -> FileOutputStream(file, offset > 0).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (active(id)) {
                    if (!networkAllowed()) throw IOException("Wi-Fi bağlantısı kesildi; devam ettirebilirsin")
                    val count = input.read(buffer); if (count < 0) break
                    output.write(buffer, 0, count); bytes += count
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastSave >= 600) { update(id) { it.put("downloadedBytes", bytes).put("speed", (bytes - offset) * 1000 / maxOf(1, now - start)) }; lastSave = now }
                    val cap = limitKbps
                    if (cap > 0) {
                        val expected = (bytes - offset) * 1000 / (cap * 1024L)
                        while (active(id) && SystemClock.elapsedRealtime() - start < expected) Thread.sleep(50)
                    }
                }
                output.flush()
            } }
            update(id) { it.put("downloadedBytes", file.length()).put("speed", 0) }
            if (!active(id)) return
            if (total >= 0 && file.length() != total) throw IOException("Bağlantı erken kapandı; devam ettirebilirsin")
            val uri = publish(file, j.getString("title"), mime, id)
            if (!active(id)) { context.contentResolver.delete(Uri.parse(uri), null, null); return }
            update(id) { it.put("status", "successful").put("localUri", uri).put("totalBytes", file.length()).put("downloadedBytes", file.length()).put("reason", "") }
            file.delete()
        } catch (e: Exception) {
            if (active(id)) update(id) { it.put("status", "failed").put("reason", e.message ?: "İndirme hatası").put("speed", 0).put("downloadedBytes", file.length()) }
        } finally {
            conn?.disconnect()
            synchronized(this) { running.remove(id); connections.remove(id); if (!jobs.containsKey(id)) file.delete() }
        }
    }
    private fun publish(file: File, name: String, mime: String, id: Long): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply { put(MediaStore.Downloads.DISPLAY_NAME, name); put(MediaStore.Downloads.MIME_TYPE, mime); put(MediaStore.Downloads.RELATIVE_PATH, "Download/Ege"); put(MediaStore.Downloads.IS_PENDING, 1) }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("Dosya oluşturulamadı")
            try {
                context.contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: throw IOException("Dosya yazılamadı")
                context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                return uri.toString()
            } catch (e: Exception) { context.contentResolver.delete(uri, null, null); throw e }
        }
        val target = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "Ege/$id-$name"); target.parentFile?.mkdirs(); file.copyTo(target)
        return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target).toString()
    }
    @Synchronized fun open(id: Long, share: Boolean): Boolean {
        val j = jobs[id] ?: return false
        if (j.optString("status") != "successful") return false
        return try {
            val uri = Uri.parse(j.getString("localUri")); val mime = j.optString("mimeType", "*/*")
            val intent = if (share) Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri) else Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(Intent.createChooser(intent, if (share) "Dosyayı paylaş" else "Dosyayı aç").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
        } catch (_: Throwable) { false }
    }
}

class JarvisDownloadService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable { override fun run() {
        ManagedDownloads.pump()
        if (ManagedDownloads.hasPending()) handler.postDelayed(this, 1000) else stopSelf()
    } }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate(); ManagedDownloads.init(this)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("jarvis_downloads", "Ege indirmeleri", NotificationManager.IMPORTANCE_LOW))
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "jarvis_downloads") else Notification.Builder(this)
        val pause = PendingIntent.getService(this, 73, Intent(this, JarvisDownloadService::class.java).setAction("pause"), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(this, 74, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(7043, builder.setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("Ege indiriyor").setContentText("İndirme kuyruğu arka planda çalışıyor").setContentIntent(open).setOngoing(true).addAction(Notification.Action.Builder(null, "Duraklat", pause).build()).build())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.removeCallbacks(tick)
        if (intent?.action == "pause") { ManagedDownloads.pauseAll(); stopSelf() } else handler.post(tick)
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { ManagedDownloads.pauseAll(); stopSelf() }
    override fun onDestroy() { handler.removeCallbacks(tick); super.onDestroy() }
    companion object { fun start(ctx: Context): Boolean = try {
        val intent = Intent(ctx, JarvisDownloadService::class.java)
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(intent) else ctx.startService(intent)
        true
    } catch (_: Throwable) { false } }
}
