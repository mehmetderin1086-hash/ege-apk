package com.jarvis.assistant.jarvis_mobile

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import org.json.JSONObject

// ===========================================================================
// Ön plan servisi: Canlı Ses / uyandırma sözcüğü sürerken realme'nin "Hans"
// dondurucusu uygulamayı durdurmasın ve ekran kapanınca oturum ölmesin.
// ===========================================================================
object JarvisKeepAlive {
    private val reasons = linkedSetOf<String>()
    private var wakeLock: PowerManager.WakeLock? = null

    /** Dart'tan: acquire("live" | "wake" | ...), release(...). */
    @Synchronized
    fun acquire(ctx: Context, reason: String, text: String? = null): Boolean {
        // Mikrofon izni yokken mikrofon tipli servis başlatılamaz (SDK 34+ SecurityException).
        if ((reason == "live" || reason == "wake") &&
            ctx.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return false
        val added = reasons.add(reason)
        if (text != null) JarvisForegroundService.statusText = text
        if (added || text != null) start(ctx)
        if (wakeLock?.isHeld != true) {
            try { wakeLock?.release() } catch (_: Throwable) {}
            wakeLock = null
            try {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "jarvis:keepalive").apply {
                    setReferenceCounted(false)
                    acquire(4 * 60 * 60 * 1000L)
                }
            } catch (_: Throwable) {}
        }
        return true
    }

    @Synchronized
    fun release(ctx: Context, reason: String) {
        if (!reasons.remove(reason)) return
        if (reasons.isEmpty()) {
            try { ctx.stopService(Intent(ctx, JarvisForegroundService::class.java)) } catch (_: Throwable) {}
            try { wakeLock?.release() } catch (_: Throwable) {}
            wakeLock = null
        } else {
            start(ctx)
        }
    }

    @Synchronized
    fun active(): List<String> = reasons.toList()

    private fun start(ctx: Context) {
        JarvisForegroundService.reasons = reasons.toList()
        val i = Intent(ctx, JarvisForegroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        } catch (t: Throwable) {
            // Android 12+: arka plandan ön plan servisi başlatılamaz; uygulama
            // görünürken yeniden denenir.
            Log.w("JarvisKeepAlive", "servis baslatilamadi: ${t.message}")
        }
    }

    // ---- pil iyileştirmesi muafiyeti (realme'nin arka planda dondurmasına karşı)
    fun isIgnoringBattery(ctx: Context): Boolean = try {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.isIgnoringBatteryOptimizations(ctx.packageName)
    } catch (_: Throwable) { false }

    @SuppressLint("BatteryLife")
    fun requestIgnoreBattery(ctx: Context): Boolean = try {
        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${ctx.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
        true
    } catch (_: Throwable) {
        try {
            ctx.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Throwable) { false }
    }
}

class JarvisForegroundService : Service() {
    companion object {
        const val CHANNEL = "jarvis_keepalive_v1"
        const val NID = 7301
        @Volatile var reasons: List<String> = emptyList()
        @Volatile var statusText: String = "Ege hazır"
        @Volatile var wakePaused: Boolean = false
        const val ACTION_RESTART = "RESTART"
    }

    private fun hasMic(): Boolean =
        checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun foregroundType(mic: Boolean): Int =
        if (mic) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC

    override fun onTaskRemoved(rootIntent: Intent?) {
        try {
            if (JarvisWakeWord.enabled(this)) {
                val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                val i = Intent(this, JarvisForegroundService::class.java).setAction(ACTION_RESTART)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    PendingIntent.getForegroundService(this, 3, i, flags)
                else PendingIntent.getService(this, 3, i, flags)
                am.setAndAllowWhileIdle(android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    android.os.SystemClock.elapsedRealtime() + 3000L, pi)
            }
        } catch (t: Throwable) {
            Log.w("JarvisKeepAlive", "yeniden baslatma kurulamadi: ${t.message}")
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            // Bildirimdeki "Durdur": Flutter tarafına haber ver, servisi kapat.
            MainActivity.instance?.notifyFlutter("onKeepAliveStop", null)
            JarvisWakeWord.stop(this)
            stopSelf()
            return START_NOT_STICKY
        }
        val mic = hasMic()
        // Süreç öldürülüp servis yeniden başlatıldı (null intent) ya da görev kaldırıldıktan sonra alarm.
        val restart = intent == null || intent.action == ACTION_RESTART
        if (restart && !JarvisKeepAlive.active().contains("wake")) {
            if (mic && JarvisWakeWord.enabled(this)) JarvisWakeWord.start(this, JarvisWakeWord.savedSensitivity(this))
            if (!JarvisKeepAlive.active().contains("wake")) {
                if (intent != null) {
                    // startForegroundService ile başlatıldı: söz gereği önce ön plana al.
                    try { startForegroundCompat(buildNotification(), false) } catch (_: Throwable) {}
                }
                stopSelf()
                return START_NOT_STICKY
            }
        }
        val notif = buildNotification()
        try {
            startForegroundCompat(notif, mic)
            if (mic) JarvisWakeWord.serviceReady(this)
            else JarvisWakeWord.fail(this, "Mikrofon izni yok; Asistan dinlenemiyor.")
        } catch (t: Throwable) {
            Log.w("JarvisKeepAlive", "startForeground reddedildi: ${t.message}")
            // Tipsiz / izinli tiple yeniden dene; yine olmazsa kapat.
            var fallbackOk = false
            try { startForegroundCompat(notif, false); fallbackOk = true } catch (_: Throwable) {}
            JarvisWakeWord.fail(this, "Mikrofon servisi reddedildi: ${t.message}")
            JarvisWakeNotices.post(this, JarvisWakeNotices.ID_STOPPED, "Asistan dinlemesi durdu, yeniden başlatmak için dokun", true)
            if (fallbackOk) {
                try { stopForeground(true) } catch (_: Throwable) {}
            }
            stopSelf()
        }
        return if (JarvisKeepAlive.active().contains("wake")) START_STICKY else START_NOT_STICKY
    }

    private fun startForegroundCompat(notif: Notification, mic: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NID, notif, foregroundType(mic))
        } else {
            startForeground(NID, notif)
        }
    }

    override fun onDestroy() {
        JarvisWakeWord.pause()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, "Ege etkin (Canlı Ses / uyandırma)", NotificationManager.IMPORTANCE_LOW)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val contentPi = launch?.let {
            PendingIntent.getActivity(this, 1, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val stopPi = PendingIntent.getService(
            this, 2, Intent(this, JarvisForegroundService::class.java).setAction("STOP"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val what = when {
            reasons.contains("live") -> "Canlı Ses açık"
            reasons.contains("wake") && wakePaused -> "Asistan duraklatıldı"
            reasons.contains("wake") -> "\"Asistan\" dinleniyor"
            else -> "Çalışıyor"
        }
        return builder
            .setContentTitle("Ege • $what")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .apply { if (contentPi != null) setContentIntent(contentPi) }
            .addAction(Notification.Action.Builder(null, "Durdur", stopPi).build())
            .build()
    }
}

// ===========================================================================
// Telefon yeniden başlayınca / uygulama güncellenince hatırlatıcıları geri kur.
// ===========================================================================
class JarvisBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        if (a == Intent.ACTION_BOOT_COMPLETED || a == Intent.ACTION_MY_PACKAGE_REPLACED ||
            a == "android.intent.action.QUICKBOOT_POWERON" || a == Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            val n = JarvisAlarms.restoreAll(context)
            Log.i("JarvisAlarms", "acilista $n hatirlatici yeniden kuruldu ($a)")
            // Arka plandan mikrofon tipli ön plan servisi başlatılamaz: kullanıcıya dokunma bildirimi bırak.
            if (a != Intent.ACTION_LOCKED_BOOT_COMPLETED && JarvisWakeWord.enabled(context)) {
                JarvisWakeNotices.post(context, JarvisWakeNotices.ID_BOOT, "Asistan dinlemesini başlatmak için dokun", false)
            }
        }
    }
}

/** Kalıcı hatırlatıcı kaydı (AlarmManager yeniden başlatmada her şeyi unutur). */
object JarvisAlarmStore {
    private const val PREFS = "jarvis_alarm_store"

    fun put(ctx: Context, key: String, atMs: Long, title: String, body: String, repeatDaily: Boolean = false, route: String? = null) {
        val o = JSONObject().put("at", atMs).put("title", title).put("body", body).put("daily", repeatDaily)
        if (route != null) o.put("route", route)
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(key, o.toString()).apply()
    }

    fun remove(ctx: Context, key: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply()
    }

    fun all(ctx: Context): Map<String, JSONObject> {
        val out = linkedMapOf<String, JSONObject>()
        for ((k, v) in ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).all) {
            try { out[k] = JSONObject(v.toString()) } catch (_: Throwable) {}
        }
        return out
    }
}

// Dokununca uygulamayı açan, "Asistan" durumunu bildiren bildirimler.
object JarvisWakeNotices {
    const val CHANNEL = "jarvis_wake_notice_v1"
    const val ID_STOPPED = 7302
    const val ID_BOOT = 7303

    fun post(ctx: Context, id: Int, text: String, ongoing: Boolean) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    nm.createNotificationChannel(NotificationChannel(CHANNEL, "Ege uyandırma durumu", NotificationManager.IMPORTANCE_DEFAULT))
                }
                Notification.Builder(ctx, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(ctx)
            }
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            val pi = launch?.let {
                PendingIntent.getActivity(ctx, id, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            val n = b.setContentTitle("Ege")
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)
                .apply { if (pi != null) setContentIntent(pi) }
                .build()
            nm.notify(id, n)
        } catch (t: Throwable) {
            Log.w("JarvisWakeNotices", "bildirim gosterilemedi: ${t.message}")
        }
    }

    fun cancel(ctx: Context, id: Int) {
        try { (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id) } catch (_: Throwable) {}
    }
}
