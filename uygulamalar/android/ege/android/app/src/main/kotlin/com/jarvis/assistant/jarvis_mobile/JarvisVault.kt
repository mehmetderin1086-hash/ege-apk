package com.jarvis.assistant.jarvis_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract as DC
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** User-selected Obsidian folder. Only Ege-managed Markdown is written. */
class JarvisVault(private val activity: MainActivity) {
    companion object { const val REQUEST = 7364 }
    private val ctx = activity.applicationContext
    private val prefs = ctx.getSharedPreferences("ege_vault", 0)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var picker: MethodChannel.Result? = null
    private val local = File(ctx.filesDir, "ege-vault").apply { mkdirs() }
    private fun tree(): Uri? = prefs.getString("tree", null)?.let { Uri.parse(it) }
    private fun hash(s: String) = MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
    fun status(): Map<String, Any> = mapOf("connected" to (tree() != null), "folder" to (tree()?.lastPathSegment ?: ""), "local" to true)
    fun connect(result: MethodChannel.Result) {
        if (picker != null) { result.success(mapOf("error" to "Klasör seçimi zaten açık.")); return }
        picker = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION), REQUEST)
        } catch (_: Exception) { picker = null; result.success(mapOf("error" to "Klasör seçici açılamadı.")) }
    }
    fun onResult(code: Int, data: Intent?) {
        val result = picker ?: return
        picker = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(mapOf("cancelled" to true)); return }
        try {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            ctx.contentResolver.takePersistableUriPermission(uri, flags)
            prefs.edit().putString("tree", uri.toString()).apply()
            result.success(status())
        } catch (_: Exception) { result.success(mapOf("error" to "Klasör erişimi alınamadı.")) }
    }
    fun disconnect(result: MethodChannel.Result) {
        tree()?.let { uri -> try { ctx.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } catch (_: Exception) {} }
        prefs.edit().remove("tree").apply()
        result.success(status())
    }
    private data class Doc(val uri: Uri, val name: String, val directory: Boolean)
    private fun children(parent: Uri): List<Doc> {
        val out = mutableListOf<Doc>()
        val uri = DC.buildChildDocumentsUriUsingTree(parent, DC.getDocumentId(parent))
        ctx.contentResolver.query(uri, arrayOf(DC.Document.COLUMN_DOCUMENT_ID, DC.Document.COLUMN_DISPLAY_NAME, DC.Document.COLUMN_MIME_TYPE), null, null, null)?.use { c ->
            while (c.moveToNext()) out.add(Doc(DC.buildDocumentUriUsingTree(parent, c.getString(0)), c.getString(1), c.getString(2) == DC.Document.MIME_TYPE_DIR))
        }
        return out
    }
    private fun root(uri: Uri) = DC.buildDocumentUriUsingTree(uri, DC.getTreeDocumentId(uri))
    private fun ensure(parent: Uri, name: String, directory: Boolean): Uri {
        val found = children(parent).firstOrNull { it.name == name }
        if (found != null) {
            require(found.directory == directory) { "Klasör/dosya çakışması: $name" }
            return found.uri
        }
        return DC.createDocument(ctx.contentResolver, parent, if (directory) DC.Document.MIME_TYPE_DIR else "text/markdown", name)
            ?: error("Dosya oluşturulamadı: $name")
    }
    private fun text(uri: Uri): String = ctx.contentResolver.openInputStream(uri)?.use { input ->
        val bytes = input.readBytesBounded(2_000_000)
        bytes.toString(Charsets.UTF_8)
    } ?: error("Dosya okunamadı")
    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = read(buffer)
            if (n < 0) break
            require(out.size() + n <= limit) { "Not boyutu sınırı aşıldı" }
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }
    fun sync(files: Map<String, String>, result: MethodChannel.Result) {
        val target = tree()
        worker.execute {
            var written = 0
            var conflicts = 0
            var error: String? = null
            try {
                for ((path, content) in files) {
                    require(VaultPaths.valid(path)) { "Geçersiz kasa yolu" }
                    val f = File(local, path)
                    f.parentFile?.mkdirs()
                    if (!f.exists() || f.readText() != content) {
                        val atomic = android.util.AtomicFile(f)
                        val output = atomic.startWrite()
                        try { output.write(content.toByteArray()); atomic.finishWrite(output) }
                        catch (t: Exception) { atomic.failWrite(output); throw t }
                    }
                    if (target == null) continue
                    var parent = root(target)
                    val parts = path.split('/')
                    for (part in parts.dropLast(1)) parent = ensure(parent, part, true)
                    val existing = children(parent).firstOrNull { it.name == parts.last() }
                    val key = "hash:${hash(target.toString() + path)}"
                    if (existing != null) {
                        val old = text(existing.uri)
                        if (old == content) continue
                        if (prefs.getString(key, null) != hash(old)) {
                            // Preserve notes changed in Obsidian before updating the generated copy.
                            val backup = ensure(parent, parts.last().removeSuffix(".md") + "-obsidian-${System.currentTimeMillis()}.md", false)
                            ctx.contentResolver.openOutputStream(backup, "wt")!!.use { it.write(old.toByteArray()) }
                            conflicts++
                        }
                    }
                    val file = existing?.uri ?: ensure(parent, parts.last(), false)
                    ctx.contentResolver.openOutputStream(file, "wt")!!.use { it.write(content.toByteArray()) }
                    prefs.edit().putString(key, hash(content)).apply()
                    written++
                }
            } catch (t: Exception) { error = t.message ?: "Kasa yazılamadı" }
            main.post { result.success(mapOf("connected" to (target != null), "written" to written, "conflicts" to conflicts, "error" to (error ?: ""))) }
        }
    }
    fun search(query: String, result: MethodChannel.Result) {
        val target = tree()
        if (target == null) { result.success(mapOf("hits" to emptyList<Any>(), "connected" to false)); return }
        worker.execute {
            val terms = VaultPaths.terms(query)
            val hits = mutableListOf<Map<String, Any>>()
            var count = 0
            var partial = false
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            try {
                fun visit(parent: Uri, path: String, depth: Int) {
                    if (depth > 10 || count >= 1000 || android.os.SystemClock.elapsedRealtime() > deadline) { partial = true; return }
                    for (doc in children(parent)) {
                        if (doc.name.startsWith('.')) continue
                        val name = "$path${doc.name}"
                        if (doc.directory) {
                            // Chats already have a full in-app index; don't duplicate them here.
                            if (name != "Ege/Sohbetler") visit(doc.uri, "$name/", depth + 1)
                        } else if (doc.name.endsWith(".md", true) && ++count <= 1000) {
                            try {
                                val body = text(doc.uri)
                                val folded = VaultPaths.fold(body)
                                val score = terms.count { folded.contains(it) }
                                if (score > 0) {
                                    val at = terms.map { folded.indexOf(it) }.filter { it >= 0 }.minOrNull() ?: 0
                                    val start = (at - 100).coerceAtLeast(0).coerceAtMost(body.length)
                                    hits.add(mapOf("path" to name, "text" to body.substring(start, (start + 600).coerceAtMost(body.length)), "score" to score))
                                }
                            } catch (_: Exception) { partial = true }
                        }
                        if (count >= 1000 || android.os.SystemClock.elapsedRealtime() > deadline) { partial = true; return }
                    }
                }
                if (terms.isNotEmpty()) visit(root(target), "", 0)
                main.post { result.success(mapOf("connected" to true, "partial" to partial, "hits" to hits.sortedByDescending { it["score"] as Int }.take(8))) }
            } catch (_: Exception) { main.post { result.success(mapOf("error" to "Obsidian klasörü okunamadı; erişimi yeniden bağla.", "hits" to emptyList<Any>())) } }
        }
    }
    fun close() { picker?.success(mapOf("error" to "Klasör seçimi kesildi.")); picker = null; worker.shutdown() }
}

internal object VaultPaths {
    fun valid(path: String) = path.startsWith("Ege/") && path.endsWith(".md") && path.length < 200 &&
        path.split('/').all { it.isNotEmpty() && it != "." && it != ".." && it.matches(Regex("[A-Za-z0-9_.-]+")) }
    fun fold(s: String) = s.lowercase(java.util.Locale.forLanguageTag("tr")).replace('ı', 'i').replace('ş', 's').replace('ğ', 'g').replace('ü', 'u').replace('ö', 'o').replace('ç', 'c')
    fun terms(s: String) = fold(s).split(Regex("[^a-z0-9]+")).filter { it.length >= 3 && it !in setOf("bir", "icin", "olan", "bana", "daha", "once", "ben", "benim", "hatirla", "nedir", "neler") }.distinct().take(12)
}
