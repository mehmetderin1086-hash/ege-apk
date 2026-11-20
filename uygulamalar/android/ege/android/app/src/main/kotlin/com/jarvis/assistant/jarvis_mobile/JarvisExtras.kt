package com.jarvis.assistant.jarvis_mobile

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.StyleSpan
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

// ===========================================================================
// PDF generation (Windows JARVIS "PDF oluştur" equivalent). Uses Android's
// PdfDocument + system Roboto font, so Turkish characters render correctly.
// Spec: {title, paragraphs[], sections[{heading, paragraphs[], bullets[]}],
//        tables[{headers[], rows[[...]]}]}
// ===========================================================================
object JarvisPdf {
    private const val PAGE_W = 595
    private const val PAGE_H = 842
    private const val MARGIN = 48f
    private const val FOOTER = 30f

    private class Writer {
        val doc = PdfDocument()
        var pageNo = 0
        lateinit var page: PdfDocument.Page
        lateinit var canvas: Canvas
        var y = MARGIN
        val contentW = (PAGE_W - 2 * MARGIN).toInt()
        val bottom = PAGE_H - MARGIN - FOOTER

        fun newPage() {
            if (pageNo > 0) finishPage()
            pageNo++
            page = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, pageNo).create())
            canvas = page.canvas
            y = MARGIN
        }

        fun finishPage() {
            val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = 9f
                color = Color.parseColor("#64748B")
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("Sayfa $pageNo", PAGE_W / 2f, PAGE_H - MARGIN / 2f, p)
            doc.finishPage(page)
        }

        fun ensure(h: Float) {
            if (y + h > bottom) newPage()
        }

        /** Draws a layout, splitting it across pages line by line if needed. */
        fun drawLayout(layout: StaticLayout, x: Float, gapAfter: Float) {
            var line = 0
            while (line < layout.lineCount) {
                if (y + (layout.getLineBottom(line) - layout.getLineTop(line)) > bottom) newPage()
                val startTop = layout.getLineTop(line)
                var last = line
                while (last + 1 < layout.lineCount &&
                    y + (layout.getLineBottom(last + 1) - startTop) <= bottom
                ) {
                    last++
                }
                val h = (layout.getLineBottom(last) - startTop).toFloat()
                canvas.save()
                canvas.translate(x, y - startTop)
                canvas.clipRect(0f, startTop.toFloat(), layout.width.toFloat(), layout.getLineBottom(last).toFloat())
                layout.draw(canvas)
                canvas.restore()
                y += h
                line = last + 1
            }
            y += gapAfter
        }
    }

    private fun paint(size: Float, bold: Boolean, color: String = "#0F172A"): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            this.color = Color.parseColor(color)
        }

    /** Turns **bold** markers into bold spans. */
    private fun rich(text: String): CharSequence {
        val sb = SpannableStringBuilder()
        val re = Regex("\\*\\*(.+?)\\*\\*")
        var last = 0
        for (m in re.findAll(text)) {
            sb.append(text.substring(last, m.range.first))
            val start = sb.length
            sb.append(m.groupValues[1])
            sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            last = m.range.last + 1
        }
        sb.append(text.substring(last))
        return sb
    }

    private fun layout(text: CharSequence, p: TextPaint, width: Int): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, p, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(2f, 1.1f)
            .setIncludePad(false)
            .build()

    private fun strings(arr: JSONArray?): List<String> {
        if (arr == null) return emptyList()
        return (0 until arr.length()).mapNotNull { i -> arr.optString(i, null)?.takeIf { it.isNotBlank() } }
    }

    private fun drawTable(w: Writer, table: JSONObject) {
        val headers = strings(table.optJSONArray("headers"))
        val rowsArr = table.optJSONArray("rows") ?: JSONArray()
        val rows = (0 until rowsArr.length()).map { i ->
            val r = rowsArr.optJSONArray(i)
            if (r == null) emptyList() else (0 until r.length()).map { j -> r.optString(j, "") }
        }
        val cols = minOf(maxOf(headers.size, rows.maxOfOrNull { it.size } ?: 0), 12)
        if (cols == 0) return
        val colW = w.contentW / cols
        val pad = 4
        val border = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.6f
            color = Color.parseColor("#94A3B8")
        }
        val headFill = Paint().apply { color = Color.parseColor("#0F172A") }

        fun drawRow(cells: List<String>, header: Boolean) {
            val p = if (header) paint(9.5f, true, "#FFFFFF") else paint(9.5f, false)
            val layouts = (0 until cols).map { c -> layout(rich(cells.getOrElse(c) { "" }), p, colW - 2 * pad) }
            val h = (layouts.maxOf { it.height } + 2 * pad).toFloat()
            w.ensure(h)
            val top = w.y
            for (c in 0 until cols) {
                val left = MARGIN + c * colW
                if (header) w.canvas.drawRect(left, top, left + colW, top + h, headFill)
                w.canvas.drawRect(left, top, left + colW, top + h, border)
                w.canvas.save()
                w.canvas.translate(left + pad, top + pad)
                layouts[c].draw(w.canvas)
                w.canvas.restore()
            }
            w.y += h
        }

        if (headers.isNotEmpty()) drawRow(headers, true)
        for (r in rows) drawRow(r, false)
        w.y += 10f
    }

    fun render(specJson: String): ByteArray {
        val spec = JSONObject(specJson)
        val w = Writer()
        w.newPage()
        val title = spec.optString("title", "").trim()
        if (title.isNotEmpty()) {
            w.drawLayout(layout(title, paint(19f, true), w.contentW), MARGIN, 4f)
            val line = Paint().apply { color = Color.parseColor("#22D3EE"); strokeWidth = 2f }
            w.canvas.drawLine(MARGIN, w.y, MARGIN + 80f, w.y, line)
            w.y += 12f
        }
        val body = paint(10.5f, false, "#1E293B")
        for (para in strings(spec.optJSONArray("paragraphs"))) {
            w.drawLayout(layout(rich(para), body, w.contentW), MARGIN, 7f)
        }
        val sections = spec.optJSONArray("sections") ?: JSONArray()
        for (i in 0 until sections.length()) {
            val sec = sections.optJSONObject(i) ?: continue
            val heading = sec.optString("heading", "").trim()
            if (heading.isNotEmpty()) {
                w.ensure(40f)
                w.y += 4f
                w.drawLayout(layout(heading, paint(13f, true), w.contentW), MARGIN, 5f)
            }
            for (para in strings(sec.optJSONArray("paragraphs"))) {
                w.drawLayout(layout(rich(para), body, w.contentW), MARGIN, 6f)
            }
            for (b in strings(sec.optJSONArray("bullets"))) {
                val l = layout(rich(b), body, w.contentW - 16)
                w.ensure(l.getLineBottom(0).toFloat())
                w.canvas.drawText("•", MARGIN + 3f, w.y + l.getLineBaseline(0), body)
                w.drawLayout(l, MARGIN + 16f, 3f)
            }
            val secTables = sec.optJSONArray("tables")
            if (secTables != null) {
                for (t in 0 until secTables.length()) secTables.optJSONObject(t)?.let { drawTable(w, it) }
            }
            w.y += 6f
        }
        val tables = spec.optJSONArray("tables") ?: JSONArray()
        for (t in 0 until tables.length()) tables.optJSONObject(t)?.let { drawTable(w, it) }
        w.finishPage()
        val out = ByteArrayOutputStream()
        w.doc.writeTo(out)
        w.doc.close()
        return out.toByteArray()
    }
}

// ===========================================================================
// Streaming music player (YouTube audio inside JARVIS). Ducks while JARVIS
// speaks, like the Windows version lowers the video volume.
// ===========================================================================
object JarvisStreamPlayer {
    private var player: MediaPlayer? = null
    private var state = "idle"
    private var title = ""
    private var url = ""
    private var error = ""
    private var ducked = false

    fun play(ctx: Context, streamUrl: String, streamTitle: String): Boolean {
        stop()
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            try {
                mp.setWakeMode(ctx.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            } catch (_: Throwable) {}
            mp.setDataSource(
                ctx.applicationContext,
                Uri.parse(streamUrl),
                mapOf("User-Agent" to "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/143 Mobile Safari/537.36")
            )
            mp.setOnPreparedListener {
                state = "playing"
                applyVolume()
                it.start()
            }
            mp.setOnCompletionListener { state = "completed" }
            mp.setOnErrorListener { _, what, extra ->
                state = "error"
                error = "MediaPlayer $what/$extra"
                true
            }
            player = mp
            title = streamTitle
            url = streamUrl
            error = ""
            state = "preparing"
            mp.prepareAsync()
            true
        } catch (t: Throwable) {
            state = "error"
            error = t.message ?: "oynatılamadı"
            false
        }
    }

    private fun applyVolume() {
        val v = if (ducked) 0.18f else 1f
        try { player?.setVolume(v, v) } catch (_: Throwable) {}
    }

    fun pause(): Boolean = try {
        player?.let { if (it.isPlaying) { it.pause(); state = "paused" } }
        true
    } catch (_: Throwable) { false }

    fun resume(): Boolean = try {
        player?.let { if (state == "paused" || state == "completed") { it.start(); state = "playing" } }
        true
    } catch (_: Throwable) { false }

    fun stop(): Boolean {
        try {
            player?.let {
                try { if (it.isPlaying) it.stop() } catch (_: Throwable) {}
                it.release()
            }
        } catch (_: Throwable) {}
        player = null
        if (state != "error") state = "idle"
        return true
    }

    fun seek(ms: Int): Boolean = try { player?.seekTo(ms); true } catch (_: Throwable) { false }

    fun duck(on: Boolean) {
        ducked = on
        applyVolume()
    }

    fun status(): Map<String, Any> {
        val p = player
        var pos = 0
        var dur = 0
        try {
            if (p != null && (state == "playing" || state == "paused" || state == "completed")) {
                pos = p.currentPosition
                dur = p.duration
            }
        } catch (_: Throwable) {}
        return mapOf(
            "state" to state,
            "title" to title,
            "positionMs" to pos,
            "durationMs" to dur,
            "error" to error,
        )
    }
}

// ===========================================================================
// Reminders that fire even when JARVIS is closed (AlarmManager + notification).
// ===========================================================================
class JarvisAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Ege"
        val body = intent.getStringExtra("body") ?: "Hatırlatıcı"
        val nid = intent.getIntExtra("nid", 4242)
        val key = intent.getStringExtra("key") ?: ""
        val route = intent.getStringExtra("route")
        val daily = intent.getBooleanExtra("daily", false)
        val cronId = if (route?.startsWith("cron:") == true) route.substring(5) else null
        val app = MainActivity.instance
        if (key.isNotEmpty() && daily) {
            // Bir sonraki gün aynı saate yeniden kur (bildirimden ve Dart'tan önce).
            var next = intent.getLongExtra("at", System.currentTimeMillis()) + 24L * 3600_000L
            while (next <= System.currentTimeMillis()) next += 24L * 3600_000L
            JarvisAlarms.schedule(context, key, next, title, body, true, route)
        }
        if (cronId != null) {
            // Zamanlanmış görev: Dart çalışırken CPU uyanık kalsın (en çok 2 dk).
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "jarvis:cron").acquire(2L * 60_000L)
            } catch (_: Throwable) {}
            // Yedek bildirim HER ZAMAN gönderilir; Dart görevi başlatınca ack ile iptal eder.
            JarvisAlarms.notify(context, nid, title, "Zamanlanmış görev hazır, çalıştırmak için dokun.", route)
            if (app != null) {
                try { app.notifyFlutter("onCronDue", cronId) } catch (_: Throwable) {}
            }
            // Tek seferlik kayıt Dart ack'leyene kadar silinmez (cancelAlarm 'ack:' önekiyle).
        } else {
            if (key.isNotEmpty() && !daily) JarvisAlarms.deliverOnce(context, key)
            else JarvisAlarms.notify(context, nid, title, body, route)
        }
    }
}

object JarvisAlarms {
    private const val CHANNEL = "jarvis_alarms_v1"

    private fun pending(
        ctx: Context, key: String, title: String, body: String,
        atMs: Long = 0L, daily: Boolean = false, route: String? = null,
    ): PendingIntent {
        val nid = key.hashCode() and 0x7fffffff
        val intent = Intent(ctx, JarvisAlarmReceiver::class.java)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("nid", nid)
            .putExtra("key", key)
            .putExtra("at", atMs)
            .putExtra("daily", daily)
            .apply { if (route != null) putExtra("route", route) }
        return PendingIntent.getBroadcast(
            ctx, nid, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun canExact(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    }

    @Synchronized
    fun deliverOnce(ctx: Context, key: String): Boolean {
        val record = JarvisAlarmStore.all(ctx)[key] ?: return false
        if (record.optBoolean("daily") || record.optLong("at") > System.currentTimeMillis()) return false
        JarvisAlarmStore.remove(ctx, key)
        notify(ctx, key.hashCode() and 0x7fffffff, record.optString("title"), record.optString("body"),
            if (record.has("route")) record.optString("route") else null)
        return true
    }

    fun schedule(
        ctx: Context, key: String, atMs: Long, title: String, body: String,
        daily: Boolean = false, route: String? = null,
    ): String {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // Kalıcı kayıt: telefon yeniden başlayınca JarvisBootReceiver geri kurar.
        JarvisAlarmStore.put(ctx, key, atMs, title, body, daily, route)
        val pi = pending(ctx, key, title, body, atMs, daily, route)
        return try {
            if (canExact(ctx)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                "exact"
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
                "inexact"
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pi)
            "inexact"
        } catch (t: Throwable) {
            "error: ${t.message}"
        }
    }

    /**
     * Dart görevi devraldı: yedek bildirimi iptal et; tek seferlik kaydı sil.
     * Günlük kayıt (zaten yarına kurulu) ve AlarmManager'a dokunulmaz.
     */
    fun ack(ctx: Context, key: String): Boolean = try {
        val o = JarvisAlarmStore.all(ctx)[key]
        if (o == null || !o.optBoolean("daily")) JarvisAlarmStore.remove(ctx, key)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(key.hashCode() and 0x7fffffff)
        true
    } catch (_: Throwable) { false }

    fun cancel(ctx: Context, key: String): Boolean = if (key.startsWith("ack:")) ack(ctx, key.substring(4)) else try {
        JarvisAlarmStore.remove(ctx, key)
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pending(ctx, key, "", ""))
        true
    } catch (_: Throwable) { false }

    /** Açılışta kayıtlı hatırlatıcıları yeniden kurar; kaçanları (6 sa içi) bildirir. */
    fun restoreAll(ctx: Context): Int {
        var n = 0
        val now = System.currentTimeMillis()
        for ((key, o) in JarvisAlarmStore.all(ctx)) {
            try {
                var at = o.optLong("at")
                val daily = o.optBoolean("daily")
                val title = o.optString("title", "Ege")
                val body = o.optString("body", "Hatırlatıcı")
                val route = if (o.has("route")) o.optString("route") else null
                if (at <= now) {
                    if (daily) {
                        while (at <= now) at += 24L * 3600_000L
                    } else {
                        if (now - at < 6L * 3600_000L) notify(ctx, key.hashCode() and 0x7fffffff, title, "$body (kaçırıldı)", route)
                        JarvisAlarmStore.remove(ctx, key)
                        continue
                    }
                }
                schedule(ctx, key, at, title, body, daily, route)
                n++
            } catch (_: Throwable) {}
        }
        return n
    }

    fun notify(ctx: Context, nid: Int, title: String, body: String, route: String? = null) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    val ch = NotificationChannel(CHANNEL, "Ege Hatırlatıcılar", NotificationManager.IMPORTANCE_HIGH)
                    ch.enableVibration(true)
                    ch.setSound(
                        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    nm.createNotificationChannel(ch)
                }
                Notification.Builder(ctx, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(ctx)
            }
            val launch = if (route != null) {
                Intent(ctx, MainActivity::class.java)
                    .setAction(if (route == "briefing") MainActivity.ACTION_BRIEFING else Intent.ACTION_MAIN)
                    .putExtra("jarvis_route", route)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            } else {
                ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            }
            val contentPi = launch?.let {
                PendingIntent.getActivity(ctx, nid, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            val notif = builder
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .apply { if (contentPi != null) setContentIntent(contentPi) }
                .build()
            nm.notify(nid, notif)
        } catch (_: Throwable) {}
    }
}
