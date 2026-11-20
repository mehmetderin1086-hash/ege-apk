package com.jarvis.assistant.jarvis_mobile

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.service.quicksettings.TileService
import android.util.Log

// ===========================================================================
// Bildirim dinleyici: gelen mesajları sesli okuma ("Bildirimleri oku"),
// yanıtlama (RemoteInput). Kullanıcı ayarlardan erişim vermelidir; dışarıdan
// kurulan APK'larda Android 13+ önce "Kısıtlanmış ayarlara izin ver" ister.
// ===========================================================================
class JarvisNotificationListener : NotificationListenerService() {
    companion object {
        @Volatile var instance: JarvisNotificationListener? = null
        private val recent = ArrayDeque<Map<String, Any>>()
        private const val MAX = 40

        fun hasAccess(ctx: Context): Boolean {
            val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
            return flat.split(':').any { it.startsWith(ctx.packageName + "/") }
        }

        fun openSettings(ctx: Context): Boolean {
            val cn = ComponentName(ctx, JarvisNotificationListener::class.java)
            val tries = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    add(Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                        .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, cn.flattenToString()))
                }
                add(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
            for (i in tries) {
                try {
                    ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    return true
                } catch (_: Throwable) {}
            }
            return false
        }

        @Synchronized
        fun recentList(limit: Int): List<Map<String, Any>> = recent.toList().takeLast(limit).reversed()

        @Synchronized
        private fun push(m: Map<String, Any>) {
            recent.removeAll { it["key"] == m["key"] }
            recent.addLast(m)
            while (recent.size > MAX) recent.removeFirst()
        }

        @Synchronized
        private fun drop(key: String) {
            recent.removeAll { it["key"] == key }
        }
    }

    override fun onListenerConnected() {
        instance = this
        try {
            activeNotifications?.sortedBy { it.postTime }?.forEach { describe(it)?.let(::push) }
        } catch (_: Throwable) {}
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        val m = describe(n) ?: return
        push(m)
        MainActivity.instance?.notifyFlutter("onNotification", m)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn?.key?.let(::drop)
    }

    private fun describe(sbn: StatusBarNotification): Map<String, Any>? {
        if (sbn.packageName == packageName) return null
        val n = sbn.notification ?: return null
        if (sbn.isOngoing || (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return null
        val ex: Bundle = n.extras ?: return null
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return null
        val app = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (_: Throwable) { sbn.packageName }
        val canReply = n.actions?.any { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true } == true
        return mapOf(
            "key" to sbn.key,
            "package" to sbn.packageName,
            "app" to app,
            "title" to title,
            "text" to text,
            "time" to sbn.postTime,
            "canReply" to canReply,
        )
    }

    /** Open the original conversation without sending a reply. */
    fun openWhatsApp(key: String): Boolean {
        return try {
            val sbn = activeNotifications?.firstOrNull { it.key == key } ?: return false
            if (sbn.packageName != "com.whatsapp" && sbn.packageName != "com.whatsapp.w4b") return false
            val intent = sbn.notification.contentIntent ?: return false
            intent.send()
            true
        } catch (_: Throwable) { false }
    }

    /** Bildirimdeki "Yanıtla" eylemiyle metin gönderir (WhatsApp, Telegram, SMS…). */
    fun reply(key: String, message: String): Boolean {
        val sbn = activeNotifications?.firstOrNull { it.key == key } ?: return false
        val action = sbn.notification.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true } ?: return false
        return try {
            val intent = Intent()
            val bundle = Bundle()
            action.remoteInputs.filter { it.allowFreeFormInput }.forEach { bundle.putCharSequence(it.resultKey, message) }
            RemoteInput.addResultsToIntent(action.remoteInputs, intent, bundle)
            action.actionIntent.send(this, 0, intent)
            true
        } catch (t: PendingIntent.CanceledException) {
            Log.w("JarvisNotif", "yanit gonderilemedi: ${t.message}")
            false
        } catch (_: Throwable) { false }
    }
}

// ===========================================================================
// Hızlı ayarlar kutucuğu: bildirim panelinden tek dokunuşla Ege'le konuş.
// ===========================================================================
class JarvisTileService : TileService() {
    override fun onStartListening() {
        qsTile?.let {
            it.label = "Ege"
            it.state = android.service.quicksettings.Tile.STATE_ACTIVE
            it.updateTile()
        }
    }

    override fun onClick() {
        val i = Intent(this, MainActivity::class.java)
            .setAction(MainActivity.ACTION_LISTEN)
            .putExtra("jarvis_source", "tile")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val pi = PendingIntent.getActivity(this, 11, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(i)
            }
        } catch (t: Throwable) {
            Log.w("JarvisTile", "acilamadi: ${t.message}")
        }
    }
}
