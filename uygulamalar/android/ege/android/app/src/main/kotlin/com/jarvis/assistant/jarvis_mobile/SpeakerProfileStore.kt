package com.jarvis.assistant.jarvis_mobile

import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File

object SpeakerProfileStore {
    private fun file(ctx: Context) = AtomicFile(File(ctx.noBackupFilesDir, "ege-speaker-profile.json"))
    @Synchronized fun read(ctx: Context): String = try {
        file(ctx).openRead().use { it.readBytes().toString(Charsets.UTF_8) }
    } catch (_: java.io.FileNotFoundException) { "" }
      catch (_: Throwable) { "{\"enabled\":true,\"references\":[]}" }
    fun enabled(ctx: Context): Boolean = try {
        val raw = read(ctx)
        raw.isNotEmpty() && JSONObject(raw).optBoolean("enabled", true)
    } catch (_: Throwable) { true }
    @Synchronized fun write(ctx: Context, raw: String): Boolean {
        if (raw.length !in 10..64000) return false
        try { JSONObject(raw) } catch (_: Throwable) { return false }
        val atomic = file(ctx)
        val stream = try { atomic.startWrite() } catch (_: Throwable) { return false }
        return try {
            stream.write(raw.toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream); true
        } catch (_: Throwable) { atomic.failWrite(stream); false }
    }
    @Synchronized fun delete(ctx: Context): Boolean { file(ctx).delete(); return !file(ctx).baseFile.exists() }
}
