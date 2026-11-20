package com.mehmetderin.kagit

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Kâğıt Android yerel platform köprüsü:
 * SAF dosya seçme/kaydetme, kamera tarama, FileProvider paylaşım,
 * PdfRenderer yüksek çözünürlüklü sayfa işleme, PdfDocument birleştirme/bölme/kitapçık/
 * filigran/numaralandırma/not yakma ve çevrimdışı ML Kit OCR motoru.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.mehmetderin.kagit/platform"
        private const val REQ_PICK_FILES = 5101
        private const val REQ_CAPTURE_PHOTO = 5102
        private const val REQ_SAVE_FILE = 5103
        private const val REQ_CAMERA_PERMISSION = 5104
    }

    private val executor = Executors.newCachedThreadPool()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPhotoFile: File? = null
    private var pendingSaveSourceFile: File? = null
    private var initialOpenedFilePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureExternalIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureExternalIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleMethodCall(call, result) }
    }

    private fun captureExternalIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val uri = intent.data ?: return
            val copied = copyUriToStorage(uri, File(filesDir, "imported"))
            if (copied != null) {
                initialOpenedFilePath = copied["path"] as? String
            }
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "consumeOpenedFile" -> {
                val p = initialOpenedFilePath
                initialOpenedFilePath = null
                result.success(p)
            }

            "pickFiles" -> {
                if (pendingResult != null) {
                    result.error("BUSY", "Başka bir dosya penceresi zaten açık.", null)
                    return
                }
                pendingResult = result
                val mimeTypes = call.argument<List<String>>("mimeTypes") ?: listOf("application/pdf")
                val allowMultiple = call.argument<Boolean>("allowMultiple") ?: false
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (mimeTypes.size == 1) mimeTypes[0] else "*/*"
                    if (mimeTypes.size > 1) {
                        putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                    }
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQ_PICK_FILES)
            }

            "capturePhoto" -> {
                if (pendingResult != null) {
                    result.error("BUSY", "Başka bir kamera veya dosya işlemi açık.", null)
                    return
                }
                pendingResult = result
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.CAMERA),
                        REQ_CAMERA_PERMISSION,
                    )
                } else {
                    launchCameraCapture()
                }
            }

            "saveFileAs" -> {
                if (pendingResult != null) {
                    result.error("BUSY", "Başka bir kayıt penceresi açık.", null)
                    return
                }
                val srcPath = call.argument<String>("srcPath")
                val suggestedName = call.argument<String>("suggestedName") ?: "belge.pdf"
                val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
                if (srcPath.isNullOrEmpty() || !File(srcPath).exists()) {
                    result.error("NOT_FOUND", "Kaynak dosya bulunamadı.", null)
                    return
                }
                pendingSaveSourceFile = File(srcPath)
                pendingResult = result
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mimeType
                    putExtra(Intent.EXTRA_TITLE, suggestedName)
                }
                @Suppress("DEPRECATION")
                startActivityForResult(intent, REQ_SAVE_FILE)
            }

            "shareFile" -> {
                val path = call.argument<String>("path") ?: ""
                val title = call.argument<String>("title") ?: "Belge Paylaş"
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                val file = File(path)
                if (!file.exists()) {
                    result.error("NOT_FOUND", "Paylaşılacak dosya bulunamadı.", null)
                    return
                }
                val shareTarget = File(cacheDir, "shared").apply { mkdirs() }
                    .let { File(it, file.name) }
                if (file.canonicalPath != shareTarget.canonicalPath) {
                    file.copyTo(shareTarget, overwrite = true)
                }
                val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", shareTarget)
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = mimeType
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(sendIntent, title))
                result.success(true)
            }

            "getPdfInfo" -> runAsync(result) {
                val path = call.argument<String>("path") ?: error("Dosya yolu boş")
                getPdfInfoInternal(File(path))
            }

            "renderPage" -> runAsync(result) {
                val path = call.argument<String>("path") ?: error("Dosya yolu boş")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                val maxWidth = call.argument<Int>("maxWidth") ?: 1200
                val outPath = call.argument<String>("outPath") ?: error("Çıktı yolu boş")
                val trimMargins = call.argument<Boolean>("trimMargins") ?: false
                renderPageInternal(File(path), pageIndex, maxWidth, File(outPath), trimMargins)
            }

            "runOcrOnPdf" -> runAsync(result) {
                val path = call.argument<String>("path") ?: error("Dosya yolu boş")
                val pageIndices = call.argument<List<Int>>("pageIndices")
                val scale = (call.argument<Double>("scale") ?: 2.1).toFloat()
                runOcrOnPdfInternal(File(path), pageIndices, scale)
            }

            "runOcrOnImages" -> runAsync(result) {
                val paths = call.argument<List<String>>("imagePaths") ?: emptyList()
                runOcrOnImagesInternal(paths)
            }

            "mergePdfs" -> runAsync(result) {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                val outPath = call.argument<String>("outPath") ?: error("Çıktı yolu boş")
                mergePdfsInternal(paths.map { File(it) }, File(outPath))
            }

            "assemblePdf" -> runAsync(result) {
                @Suppress("UNCHECKED_CAST")
                val spec = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                val outPath = spec["outPath"] as? String ?: error("Çıktı yolu boş")
                assemblePdfInternal(spec, File(outPath))
            }

            "imagesToPdf" -> runAsync(result) {
                val imagePaths = call.argument<List<String>>("imagePaths") ?: emptyList()
                val outPath = call.argument<String>("outPath") ?: error("Çıktı yolu boş")
                val filter = call.argument<String>("filter") ?: "normal"
                val pageSize = call.argument<String>("pageSize") ?: "a4"
                imagesToPdfInternal(imagePaths.map { File(it) }, File(outPath), filter, pageSize)
            }

            "buildTextPdf" -> runAsync(result) {
                @Suppress("UNCHECKED_CAST")
                val spec = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                val outPath = spec["outPath"] as? String ?: error("Çıktı yolu boş")
                buildTextPdfInternal(spec, File(outPath))
            }

            else -> result.notImplemented()
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (t: Throwable) {
                runOnUiThread {
                    result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun launchCameraCapture() {
        val res = pendingResult ?: return
        try {
            val scanDir = File(cacheDir, "scans").apply { mkdirs() }
            val photoFile = File(scanDir, "tarama_${System.currentTimeMillis()}.jpg")
            pendingPhotoFile = photoFile
            val photoUri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", photoFile)
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_CAPTURE_PHOTO)
        } catch (t: Throwable) {
            pendingResult = null
            pendingPhotoFile = null
            res.error("CAMERA_ERROR", "Kamera başlatılamadı: ${t.message}", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA_PERMISSION) {
            val res = pendingResult
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchCameraCapture()
            } else {
                pendingResult = null
                res?.success(null)
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val res = pendingResult ?: return
        pendingResult = null

        when (requestCode) {
            REQ_PICK_FILES -> {
                if (resultCode != Activity.RESULT_OK || data == null) {
                    res.success(emptyList<Map<String, Any>>())
                    return
                }
                executor.execute {
                    val out = mutableListOf<Map<String, Any>>()
                    val destDir = File(filesDir, "imported").apply { mkdirs() }
                    val clip = data.clipData
                    if (clip != null) {
                        for (i in 0 until clip.itemCount) {
                            clip.getItemAt(i)?.uri?.let { uri ->
                                copyUriToStorage(uri, destDir)?.let { out.add(it) }
                            }
                        }
                    } else {
                        data.data?.let { uri ->
                            copyUriToStorage(uri, destDir)?.let { out.add(it) }
                        }
                    }
                    runOnUiThread { res.success(out) }
                }
            }

            REQ_CAPTURE_PHOTO -> {
                val file = pendingPhotoFile
                pendingPhotoFile = null
                if (resultCode == Activity.RESULT_OK && file != null && file.exists() && file.length() > 0L) {
                    res.success(file.absolutePath)
                } else {
                    res.success(null)
                }
            }

            REQ_SAVE_FILE -> {
                val src = pendingSaveSourceFile
                pendingSaveSourceFile = null
                val destUri = data?.data
                if (resultCode != Activity.RESULT_OK || destUri == null || src == null || !src.exists()) {
                    res.success(false)
                    return
                }
                executor.execute {
                    val ok = try {
                        contentResolver.openOutputStream(destUri)?.use { out ->
                            src.inputStream().use { inp -> inp.copyTo(out) }
                        }
                        true
                    } catch (_: Throwable) {
                        false
                    }
                    runOnUiThread { res.success(ok) }
                }
            }
        }
    }

    private fun copyUriToStorage(uri: Uri, destDir: File): Map<String, Any>? {
        return try {
            destDir.mkdirs()
            val displayName = queryDisplayName(uri) ?: "belge_${System.currentTimeMillis()}"
            val cleanName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val dest = uniqueFile(destDir, cleanName)
            contentResolver.openInputStream(uri)?.use { inp ->
                FileOutputStream(dest).use { out -> inp.copyTo(out) }
            } ?: return null
            mapOf(
                "path" to dest.absolutePath,
                "name" to cleanName,
                "size" to dest.length(),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) return c.getString(idx)
            }
        }
        return uri.lastPathSegment
    }

    private fun uniqueFile(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 2
        while (f.exists()) {
            f = File(dir, "${stem}_$i$ext")
            i++
        }
        return f
    }

    private fun getPdfInfoInternal(file: File): Map<String, Any> {
        if (!file.exists()) error("PDF bulunamadı: ${file.path}")
        val pages = mutableListOf<Map<String, Any>>()
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                for (i in 0 until renderer.pageCount) {
                    renderer.openPage(i).use { page ->
                        pages.add(
                            mapOf(
                                "index" to i,
                                "width" to page.width,
                                "height" to page.height,
                            ),
                        )
                    }
                }
            }
        }
        return mapOf(
            "pageCount" to pages.size,
            "fileSize" to file.length(),
            "pages" to pages,
        )
    }

    private fun renderPageInternal(
        file: File,
        pageIndex: Int,
        maxWidth: Int,
        outFile: File,
        trimMargins: Boolean,
    ): Map<String, Any> {
        outFile.parentFile?.mkdirs()
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                val idx = pageIndex.coerceIn(0, max(0, renderer.pageCount - 1))
                renderer.openPage(idx).use { page ->
                    val ratio = maxWidth.toFloat() / max(1, page.width)
                    val w = max(64, (page.width * ratio).roundToInt()).coerceAtMost(2400)
                    val h = max(64, (page.height * ratio).roundToInt()).coerceAtMost(3400)
                    var bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    if (trimMargins) {
                        val trimmed = cropWhiteMargins(bmp)
                        if (trimmed !== bmp) {
                            bmp.recycle()
                            bmp = trimmed
                        }
                    }
                    try {
                        FileOutputStream(outFile).use { out ->
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                        }
                        return mapOf(
                            "path" to outFile.absolutePath,
                            "width" to bmp.width,
                            "height" to bmp.height,
                        )
                    } finally {
                        bmp.recycle()
                    }
                }
            }
        }
    }

    private fun cropWhiteMargins(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val row = IntArray(w)
        var top = h
        var bottom = -1
        var left = w
        var right = -1
        for (y in 0 until h step 2) {
            src.getPixels(row, 0, w, 0, y, w, 1)
            for (x in 0 until w step 2) {
                val c = row[x]
                val lum = (Color.red(c) + Color.green(c) + Color.blue(c)) / 3
                if (lum < 245) {
                    if (y < top) top = y
                    if (y > bottom) bottom = y
                    if (x < left) left = x
                    if (x > right) right = x
                }
            }
        }
        if (bottom <= top || right <= left) return src
        val padX = (w * 0.03f).roundToInt().coerceAtLeast(10)
        val padY = (h * 0.03f).roundToInt().coerceAtLeast(10)
        val l = (left - padX).coerceAtLeast(0)
        val t = (top - padY).coerceAtLeast(0)
        val r = (right + padX).coerceAtMost(w)
        val b = (bottom + padY).coerceAtMost(h)
        if (r - l < 40 || b - t < 40) return src
        return Bitmap.createBitmap(src, l, t, r - l, b - t)
    }

    private fun runOcrOnPdfInternal(
        file: File,
        pageIndices: List<Int>?,
        scale: Float,
    ): Map<String, Any> {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val results = mutableListOf<Map<String, Any>>()
        val textParts = mutableListOf<String>()

        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { renderer ->
                val targets = pageIndices?.filter { it in 0 until renderer.pageCount }
                    ?: (0 until renderer.pageCount).toList()
                for (idx in targets) {
                    renderer.openPage(idx).use { page ->
                        val effectiveScale = scale.coerceIn(1.2f, 2.8f)
                        val w = (page.width * effectiveScale).roundToInt().coerceIn(320, 2200)
                        val h = (page.height * effectiveScale).roundToInt().coerceIn(320, 3200)
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        try {
                            bmp.eraseColor(Color.WHITE)
                            page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val visionText = Tasks.await(recognizer.process(InputImage.fromBitmap(bmp, 0)))
                            val blocks = visionText.textBlocks.mapNotNull { blk ->
                                val box = blk.boundingBox ?: return@mapNotNull null
                                mapOf(
                                    "text" to blk.text,
                                    "x" to box.left.toDouble() / w,
                                    "y" to box.top.toDouble() / h,
                                    "w" to box.width().toDouble() / w,
                                    "h" to box.height().toDouble() / h,
                                )
                            }
                            val pageText = visionText.text.trim()
                            if (pageText.isNotEmpty()) {
                                textParts.add("--- Sayfa ${idx + 1} ---\n$pageText")
                            }
                            results.add(
                                mapOf(
                                    "pageIndex" to idx,
                                    "text" to pageText,
                                    "blocks" to blocks,
                                ),
                            )
                        } finally {
                            bmp.recycle()
                        }
                    }
                }
            }
        }
        recognizer.close()
        return mapOf(
            "pages" to results,
            "fullText" to textParts.joinToString("\n\n"),
        )
    }

    private fun runOcrOnImagesInternal(imagePaths: List<String>): Map<String, Any> {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val results = mutableListOf<Map<String, Any>>()
        val textParts = mutableListOf<String>()
        try {
            imagePaths.forEachIndexed { idx, p ->
                val bmp = decodeOrientedBitmap(File(p), 2000)
                try {
                    val visionText = Tasks.await(recognizer.process(InputImage.fromBitmap(bmp, 0)))
                    val blocks = visionText.textBlocks.mapNotNull { blk ->
                        val box = blk.boundingBox ?: return@mapNotNull null
                        mapOf(
                            "text" to blk.text,
                            "x" to box.left.toDouble() / bmp.width,
                            "y" to box.top.toDouble() / bmp.height,
                            "w" to box.width().toDouble() / bmp.width,
                            "h" to box.height().toDouble() / bmp.height,
                        )
                    }
                    val pageText = visionText.text.trim()
                    if (pageText.isNotEmpty()) {
                        textParts.add("--- Görsel ${idx + 1} ---\n$pageText")
                    }
                    results.add(
                        mapOf(
                            "pageIndex" to idx,
                            "text" to pageText,
                            "blocks" to blocks,
                        ),
                    )
                } finally {
                    bmp.recycle()
                }
            }
        } finally {
            recognizer.close()
        }
        return mapOf(
            "pages" to results,
            "fullText" to textParts.joinToString("\n\n"),
        )
    }

    private fun mergePdfsInternal(files: List<File>, outFile: File): Map<String, Any> {
        val entries = mutableListOf<Map<String, Any>>()
        for (f in files) {
            if (!f.exists()) continue
            ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    for (i in 0 until renderer.pageCount) {
                        entries.add(mapOf("path" to f.absolutePath, "pageIndex" to i, "rotateDeg" to 0))
                    }
                }
            }
        }
        return assemblePdfInternal(mapOf("pageEntries" to entries, "dpi" to 150), outFile)
    }

    private data class RenderedSlice(
        val bitmap: Bitmap?,
        val widthPt: Int,
        val heightPt: Int,
        val sourcePageIndex: Int,
        val isBlank: Boolean,
    )

    @Suppress("UNCHECKED_CAST")
    private fun assemblePdfInternal(spec: Map<String, Any?>, outFile: File): Map<String, Any> {
        outFile.parentFile?.mkdirs()
        val dpi = (spec["dpi"] as? Number)?.toInt()?.coerceIn(60, 240) ?: 150
        val scale = (dpi / 72.0f).coerceIn(0.8f, 3.0f)
        val pageSizeName = (spec["pageSize"] as? String) ?: "original"
        val nUp = (spec["nUp"] as? Number)?.toInt() ?: 1
        val booklet = (spec["booklet"] as? Boolean) ?: false
        val trimMargins = (spec["trimMargins"] as? Boolean) ?: false
        val watermark = spec["watermark"] as? Map<String, Any?>
        val pageNumbers = spec["pageNumbers"] as? Map<String, Any?>
        val headerFooter = spec["headerFooter"] as? Map<String, Any?>
        val schoolHeader = spec["schoolHeader"] as? Map<String, Any?>
        val annotationsByPage = spec["annotationsByPage"] as? Map<String, List<Map<String, Any?>>>

        val rawEntries = (spec["pageEntries"] as? List<Map<String, Any?>>) ?: run {
            val path = spec["path"] as? String ?: error("Kaynak PDF yok")
            val f = File(path)
            val list = mutableListOf<Map<String, Any?>>()
            ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    for (i in 0 until renderer.pageCount) {
                        list.add(mapOf("path" to path, "pageIndex" to i, "rotateDeg" to 0))
                    }
                }
            }
            list
        }

        // Open renderers grouped by file path so every page renders once cleanly
        val openPdfs = linkedMapOf<String, Pair<ParcelFileDescriptor, PdfRenderer>>()
        val slices = mutableListOf<RenderedSlice>()
        try {
            fun getRenderer(path: String): PdfRenderer {
                val existing = openPdfs[path]
                if (existing != null) return existing.second
                val pfd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                val rnd = PdfRenderer(pfd)
                openPdfs[path] = pfd to rnd
                return rnd
            }

            for (entry in rawEntries) {
                val isBlank = (entry["isBlank"] as? Boolean) ?: false
                if (isBlank) {
                    val bw = (entry["width"] as? Number)?.toInt() ?: 595
                    val bh = (entry["height"] as? Number)?.toInt() ?: 842
                    slices.add(RenderedSlice(null, bw, bh, -1, true))
                    continue
                }
                val srcPath = entry["path"] as? String ?: continue
                val pageIndex = (entry["pageIndex"] as? Number)?.toInt() ?: 0
                val rotateDeg = ((entry["rotateDeg"] as? Number)?.toInt() ?: 0) % 360
                val rnd = getRenderer(srcPath)
                if (pageIndex !in 0 until rnd.pageCount) continue
                rnd.openPage(pageIndex).use { page ->
                    val rawW = (page.width * scale).roundToInt().coerceIn(220, 2100)
                    val rawH = (page.height * scale).roundToInt().coerceIn(220, 2900)
                    var bmp = Bitmap.createBitmap(rawW, rawH, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                    if (trimMargins) {
                        val cropped = cropWhiteMargins(bmp)
                        if (cropped !== bmp) {
                            bmp.recycle()
                            bmp = cropped
                        }
                    }
                    if (rotateDeg != 0) {
                        val m = Matrix().apply { postRotate(rotateDeg.toFloat()) }
                        val rot = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                        bmp.recycle()
                        bmp = rot
                    }

                    // Burn vector annotations onto page slice before any imposition
                    val anns = annotationsByPage?.get(pageIndex.toString())
                    if (!anns.isNullOrEmpty()) {
                        drawAnnotationsOnBitmap(bmp, anns)
                    }

                    val swapped = rotateDeg == 90 || rotateDeg == 270
                    val ptW = if (swapped) page.height else page.width
                    val ptH = if (swapped) page.width else page.height
                    val (targetW, targetH) = resolveTargetPagePoints(pageSizeName, ptW, ptH)
                    slices.add(RenderedSlice(bmp, targetW, targetH, pageIndex, false))
                }
            }

            val doc = PdfDocument()
            try {
                if (booklet && slices.isNotEmpty()) {
                    emitBookletPages(doc, slices, watermark, pageNumbers, headerFooter, schoolHeader)
                } else if (nUp > 1 && slices.isNotEmpty()) {
                    emitNUpPages(doc, slices, nUp, watermark, pageNumbers, headerFooter)
                } else {
                    emitStandardPages(doc, slices, watermark, pageNumbers, headerFooter, schoolHeader)
                }
                FileOutputStream(outFile).use { out -> doc.writeTo(out) }
            } finally {
                doc.close()
            }
        } finally {
            slices.forEach { it.bitmap?.recycle() }
            openPdfs.values.forEach { (pfd, rnd) ->
                try { rnd.close() } catch (_: Throwable) {}
                try { pfd.close() } catch (_: Throwable) {}
            }
        }

        val info = getPdfInfoInternal(outFile)
        return mapOf(
            "path" to outFile.absolutePath,
            "pageCount" to (info["pageCount"] ?: 0),
            "fileSize" to outFile.length(),
        )
    }

    private fun resolveTargetPagePoints(sizeName: String, origW: Int, origH: Int): Pair<Int, Int> {
        return when (sizeName.lowercase()) {
            "a4" -> 595 to 842
            "a5" -> 420 to 595
            "letter" -> 612 to 792
            else -> origW to origH
        }
    }

    private fun emitStandardPages(
        doc: PdfDocument,
        slices: List<RenderedSlice>,
        watermark: Map<String, Any?>?,
        pageNumbers: Map<String, Any?>?,
        headerFooter: Map<String, Any?>?,
        schoolHeader: Map<String, Any?>?,
    ) {
        val total = slices.size
        slices.forEachIndexed { idx, slice ->
            val pw = slice.widthPt.coerceAtLeast(100)
            val ph = slice.heightPt.coerceAtLeast(100)
            val info = PdfDocument.PageInfo.Builder(pw, ph, idx + 1).create()
            val page = doc.startPage(info)
            val canvas = page.canvas
            canvas.drawColor(Color.WHITE)

            var topReserved = 0f
            if (idx == 0 && schoolHeader != null && (schoolHeader["enabled"] as? Boolean != false)) {
                topReserved = drawSchoolExamBanner(canvas, pw.toFloat(), schoolHeader)
            }

            val bmp = slice.bitmap
            if (bmp != null) {
                val availRect = RectF(0f, topReserved, pw.toFloat(), ph.toFloat())
                val dst = fitRect(bmp.width.toFloat(), bmp.height.toFloat(), availRect, margin = 0f)
                val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                canvas.drawBitmap(bmp, null, dst, p)
            }

            drawDecorations(canvas, pw.toFloat(), ph.toFloat(), idx + 1, total, watermark, pageNumbers, headerFooter)
            doc.finishPage(page)
        }
    }

    private fun emitNUpPages(
        doc: PdfDocument,
        slices: List<RenderedSlice>,
        nUp: Int,
        watermark: Map<String, Any?>?,
        pageNumbers: Map<String, Any?>?,
        headerFooter: Map<String, Any?>?,
    ) {
        val (cols, rows, pw, ph) = when (nUp) {
            2 -> listOf(2, 1, 842, 595)
            4 -> listOf(2, 2, 595, 842)
            6 -> listOf(2, 3, 595, 842)
            else -> listOf(3, 3, 595, 842)
        }
        val chunks = slices.chunked(cols * rows)
        val total = chunks.size
        chunks.forEachIndexed { sheetIdx, group ->
            val info = PdfDocument.PageInfo.Builder(pw, ph, sheetIdx + 1).create()
            val page = doc.startPage(info)
            val canvas = page.canvas
            canvas.drawColor(Color.WHITE)

            val pad = 16f
            val cellW = (pw - pad * (cols + 1)) / cols
            val cellH = (ph - pad * (rows + 1)) / rows
            val imgPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            val borderPaint = Paint().apply {
                color = Color.argb(40, 0, 0, 0)
                style = Paint.Style.STROKE
                strokeWidth = 0.8f
            }

            group.forEachIndexed { pos, slice ->
                val c = pos % cols
                val r = pos / cols
                val left = pad + c * (cellW + pad)
                val top = pad + r * (cellH + pad)
                val cellRect = RectF(left, top, left + cellW, top + cellH)
                canvas.drawRect(cellRect, borderPaint)
                slice.bitmap?.let { bmp ->
                    val dst = fitRect(bmp.width.toFloat(), bmp.height.toFloat(), cellRect, margin = 4f)
                    canvas.drawBitmap(bmp, null, dst, imgPaint)
                }
            }

            drawDecorations(canvas, pw.toFloat(), ph.toFloat(), sheetIdx + 1, total, watermark, pageNumbers, headerFooter)
            doc.finishPage(page)
        }
    }

    private fun emitBookletPages(
        doc: PdfDocument,
        slices: List<RenderedSlice>,
        watermark: Map<String, Any?>?,
        pageNumbers: Map<String, Any?>?,
        headerFooter: Map<String, Any?>?,
        schoolHeader: Map<String, Any?>?,
    ) {
        val padded = slices.toMutableList()
        while (padded.size % 4 != 0) {
            padded.add(RenderedSlice(null, 595, 842, -1, true))
        }
        val n = padded.size
        val sheets = n / 2
        val pw = 842
        val ph = 595
        val imgPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val foldPaint = Paint().apply {
            color = Color.argb(65, 120, 120, 120)
            style = Paint.Style.STROKE
            strokeWidth = 0.8f
        }

        for (i in 0 until sheets) {
            val leftIdx = if (i % 2 == 0) n - 1 - i else i
            val rightIdx = if (i % 2 == 0) i else n - 1 - i
            val info = PdfDocument.PageInfo.Builder(pw, ph, i + 1).create()
            val page = doc.startPage(info)
            val canvas = page.canvas
            canvas.drawColor(Color.WHITE)

            val halfW = pw / 2f
            canvas.drawLine(halfW, 12f, halfW, ph - 12f, foldPaint)

            listOf(padded[leftIdx] to RectF(10f, 10f, halfW - 10f, ph - 10f),
                   padded[rightIdx] to RectF(halfW + 10f, 10f, pw - 10f, ph - 10f)).forEach { (slice, rect) ->
                if (slice.sourcePageIndex == 0 && schoolHeader != null && (schoolHeader["enabled"] as? Boolean != false)) {
                    drawSchoolExamBanner(canvas, rect.width(), schoolHeader, offsetX = rect.left, offsetY = rect.top)
                }
                slice.bitmap?.let { bmp ->
                    val dst = fitRect(bmp.width.toFloat(), bmp.height.toFloat(), rect, margin = 4f)
                    canvas.drawBitmap(bmp, null, dst, imgPaint)
                }
            }

            drawDecorations(canvas, pw.toFloat(), ph.toFloat(), i + 1, sheets, watermark, pageNumbers, headerFooter)
            doc.finishPage(page)
        }
    }

    private fun fitRect(srcW: Float, srcH: Float, bounds: RectF, margin: Float): RectF {
        val availW = max(1f, bounds.width() - margin * 2)
        val availH = max(1f, bounds.height() - margin * 2)
        val s = min(availW / max(1f, srcW), availH / max(1f, srcH))
        val w = srcW * s
        val h = srcH * s
        val l = bounds.left + margin + (availW - w) / 2f
        val t = bounds.top + margin + (availH - h) / 2f
        return RectF(l, t, l + w, t + h)
    }

    private fun drawSchoolExamBanner(
        canvas: Canvas,
        width: Float,
        spec: Map<String, Any?>,
        offsetX: Float = 0f,
        offsetY: Float = 0f,
    ): Float {
        val bannerH = 88f
        val okul = (spec["okulAdi"] as? String).orEmpty().ifBlank { "T.C. MİLLÎ EĞİTİM BAKANLIĞI" }
        val ders = (spec["dersAdi"] as? String).orEmpty().ifBlank { "Ders Sınavı" }
        val tur = (spec["sinavTuru"] as? String).orEmpty().ifBlank { "Yazılı Yoklama" }
        val tarih = (spec["tarih"] as? String).orEmpty()
        val sure = (spec["sure"] as? String).orEmpty().ifBlank { "40 dk" }

        canvas.save()
        canvas.translate(offsetX, offsetY)
        val bg = Paint().apply { color = Color.rgb(248, 244, 236) }
        val border = Paint().apply {
            color = Color.rgb(45, 45, 50)
            style = Paint.Style.STROKE
            strokeWidth = 1.2f
        }
        val pad = 22f
        val box = RectF(pad, 14f, width - pad, bannerH - 4f)
        canvas.drawRect(box, bg)
        canvas.drawRect(box, border)

        val bold = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 11.5f
            typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val sub = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.DKGRAY
            textSize = 9.5f
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val small = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 8.5f
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        val cx = width / 2f
        canvas.drawText(okul, cx, 30f, bold)
        canvas.drawText("$ders • $tur", cx, 44f, sub)
        val metaY = 60f
        canvas.drawLine(pad, 50f, width - pad, 50f, border)
        canvas.drawText("Ad Soyad: ........................................", pad + 8f, metaY, small)
        canvas.drawText("Sınıf / No: ................", cx - 10f, metaY, small)
        canvas.drawText("Süre: $sure", width - pad - 115f, metaY, small)
        canvas.drawText(if (tarih.isNotBlank()) "Tarih: $tarih   Puan: ........" else "Puan: ........", width - pad - 115f, 75f, small)
        canvas.restore()
        return bannerH
    }

    private fun drawDecorations(
        canvas: Canvas,
        pw: Float,
        ph: Float,
        pageNo: Int,
        totalPages: Int,
        watermark: Map<String, Any?>?,
        pageNumbers: Map<String, Any?>?,
        headerFooter: Map<String, Any?>?,
    ) {
        if (watermark != null) {
            val text = (watermark["text"] as? String).orEmpty()
            if (text.isNotBlank()) {
                val opacity = ((watermark["opacity"] as? Number)?.toDouble() ?: 0.22).coerceIn(0.05, 0.85)
                val fontSize = ((watermark["fontSize"] as? Number)?.toFloat() ?: 42f).coerceIn(14f, 120f)
                val angle = (watermark["angle"] as? Number)?.toFloat() ?: -35f
                val tiled = (watermark["tiled"] as? Boolean) ?: false
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.argb((opacity * 255).roundToInt(), 175, 45, 45)
                    textSize = fontSize
                    typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                    textAlign = Paint.Align.CENTER
                }
                if (tiled) {
                    val stepY = max(140f, fontSize * 3.5f)
                    val stepX = max(190f, text.length * fontSize * 0.65f)
                    var y = stepY * 0.5f
                    while (y < ph) {
                        var x = stepX * 0.5f
                        while (x < pw) {
                            canvas.save()
                            canvas.rotate(angle, x, y)
                            canvas.drawText(text, x, y, paint)
                            canvas.restore()
                            x += stepX
                        }
                        y += stepY
                    }
                } else {
                    canvas.save()
                    canvas.rotate(angle, pw / 2f, ph / 2f)
                    canvas.drawText(text, pw / 2f, ph / 2f, paint)
                    canvas.restore()
                }
            }
        }

        if (headerFooter != null) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.DKGRAY
                textSize = 9.5f
            }
            val hl = (headerFooter["headerLeft"] as? String).orEmpty()
            val hc = (headerFooter["headerCenter"] as? String).orEmpty()
            val hr = (headerFooter["headerRight"] as? String).orEmpty()
            val fl = (headerFooter["footerLeft"] as? String).orEmpty()
            val fc = (headerFooter["footerCenter"] as? String).orEmpty()
            val fr = (headerFooter["footerRight"] as? String).orEmpty()

            if (hl.isNotBlank()) { paint.textAlign = Paint.Align.LEFT; canvas.drawText(hl, 24f, 18f, paint) }
            if (hc.isNotBlank()) { paint.textAlign = Paint.Align.CENTER; canvas.drawText(hc, pw / 2f, 18f, paint) }
            if (hr.isNotBlank()) { paint.textAlign = Paint.Align.RIGHT; canvas.drawText(hr, pw - 24f, 18f, paint) }
            if (fl.isNotBlank()) { paint.textAlign = Paint.Align.LEFT; canvas.drawText(fl, 24f, ph - 12f, paint) }
            if (fc.isNotBlank()) { paint.textAlign = Paint.Align.CENTER; canvas.drawText(fc, pw / 2f, ph - 12f, paint) }
            if (fr.isNotBlank()) { paint.textAlign = Paint.Align.RIGHT; canvas.drawText(fr, pw - 24f, ph - 12f, paint) }
        }

        if (pageNumbers != null && (pageNumbers["enabled"] as? Boolean == true)) {
            val startAt = (pageNumbers["startAt"] as? Number)?.toInt() ?: 1
            val prefix = (pageNumbers["prefix"] as? String).orEmpty()
            val pos = (pageNumbers["position"] as? String) ?: "bottomCenter"
            val label = "${prefix}${pageNo + startAt - 1} / $totalPages"
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(60, 60, 65)
                textSize = 9.5f
                typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
            }
            when (pos) {
                "bottomLeft" -> { paint.textAlign = Paint.Align.LEFT; canvas.drawText(label, 24f, ph - 12f, paint) }
                "bottomRight" -> { paint.textAlign = Paint.Align.RIGHT; canvas.drawText(label, pw - 24f, ph - 12f, paint) }
                "topRight" -> { paint.textAlign = Paint.Align.RIGHT; canvas.drawText(label, pw - 24f, 18f, paint) }
                else -> { paint.textAlign = Paint.Align.CENTER; canvas.drawText(label, pw / 2f, ph - 12f, paint) }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun drawAnnotationsOnBitmap(bmp: Bitmap, annotations: List<Map<String, Any?>>) {
        val canvas = Canvas(bmp)
        val w = bmp.width.toFloat()
        val h = bmp.height.toFloat()

        for (ann in annotations) {
            val kind = ann["kind"] as? String ?: continue
            val colorInt = (ann["color"] as? Number)?.toInt() ?: Color.RED
            when (kind) {
                "ink", "highlight", "signature" -> {
                    val pts = ann["points"] as? List<Map<String, Any?>> ?: continue
                    if (pts.size < 2) continue
                    val path = Path()
                    pts.forEachIndexed { idx, p ->
                        val px = ((p["x"] as? Number)?.toFloat() ?: 0f) * w
                        val py = ((p["y"] as? Number)?.toFloat() ?: 0f) * h
                        if (idx == 0) path.moveTo(px, py) else path.lineTo(px, py)
                    }
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeCap = Paint.Cap.ROUND
                        strokeJoin = Paint.Join.ROUND
                        val strokeNorm = (ann["strokeWidth"] as? Number)?.toFloat() ?: 0.004f
                        strokeWidth = max(2f, strokeNorm * w)
                        color = if (kind == "highlight") {
                            Color.argb(95, Color.red(colorInt), Color.green(colorInt), Color.blue(colorInt))
                        } else {
                            colorInt
                        }
                    }
                    canvas.drawPath(path, paint)
                }

                "redact" -> {
                    val rx = ((ann["x"] as? Number)?.toFloat() ?: 0f) * w
                    val ry = ((ann["y"] as? Number)?.toFloat() ?: 0f) * h
                    val rw = ((ann["w"] as? Number)?.toFloat() ?: 0.1f) * w
                    val rh = ((ann["h"] as? Number)?.toFloat() ?: 0.04f) * h
                    val paint = Paint().apply { color = Color.BLACK; style = Paint.Style.FILL }
                    canvas.drawRect(rx, ry, rx + rw, ry + rh, paint)
                }

                "text", "stamp", "puan" -> {
                    val tx = ((ann["x"] as? Number)?.toFloat() ?: 0.1f) * w
                    val ty = ((ann["y"] as? Number)?.toFloat() ?: 0.1f) * h
                    val text = (ann["text"] as? String).orEmpty()
                    if (text.isBlank()) continue
                    val fontSize = ((ann["fontSize"] as? Number)?.toFloat() ?: 0.022f) * w
                    val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = colorInt
                        textSize = max(14f, fontSize)
                        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
                    }
                    if (kind == "stamp" || kind == "puan") {
                        val bounds = Rect()
                        textPaint.getTextBounds(text, 0, text.length, bounds)
                        val pad = max(8f, fontSize * 0.35f)
                        val box = RectF(tx - pad, ty - bounds.height() - pad, tx + bounds.width() + pad, ty + pad)
                        val bg = Paint().apply { color = Color.argb(30, Color.red(colorInt), Color.green(colorInt), Color.blue(colorInt)) }
                        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            color = colorInt
                            style = Paint.Style.STROKE
                            strokeWidth = max(2f, fontSize * 0.1f)
                        }
                        canvas.drawRoundRect(box, 8f, 8f, bg)
                        canvas.drawRoundRect(box, 8f, 8f, border)
                    }
                    canvas.drawText(text, tx, ty, textPaint)
                }
            }
        }
    }

    private fun imagesToPdfInternal(
        files: List<File>,
        outFile: File,
        filter: String,
        pageSize: String,
    ): Map<String, Any> {
        outFile.parentFile?.mkdirs()
        val doc = PdfDocument()
        try {
            var count = 0
            for (imgFile in files) {
                if (!imgFile.exists()) continue
                var bmp = decodeOrientedBitmap(imgFile, 1900)
                if (filter != "normal") {
                    val filtered = applyScanFilter(bmp, filter)
                    if (filtered !== bmp) {
                        bmp.recycle()
                        bmp = filtered
                    }
                }
                try {
                    val isLandscape = bmp.width > bmp.height
                    val (pw, ph) = when (pageSize.lowercase()) {
                        "original" -> 595 to max(200, (595f * bmp.height / max(1, bmp.width)).roundToInt())
                        else -> if (isLandscape) 842 to 595 else 595 to 842
                    }
                    count++
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, count).create())
                    val canvas = page.canvas
                    canvas.drawColor(Color.WHITE)
                    val dst = fitRect(bmp.width.toFloat(), bmp.height.toFloat(), RectF(16f, 16f, pw - 16f, ph - 16f), margin = 0f)
                    canvas.drawBitmap(bmp, null, dst, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                    doc.finishPage(page)
                } finally {
                    bmp.recycle()
                }
            }
            FileOutputStream(outFile).use { out -> doc.writeTo(out) }
        } finally {
            doc.close()
        }
        val info = getPdfInfoInternal(outFile)
        return mapOf(
            "path" to outFile.absolutePath,
            "pageCount" to (info["pageCount"] ?: 0),
            "fileSize" to outFile.length(),
        )
    }

    private fun decodeOrientedBitmap(file: File, maxDim: Int): Bitmap {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)
        var sample = 1
        while (max(opts.outWidth, opts.outHeight) / sample > maxDim) {
            sample *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: error("Görsel açılamadı: ${file.name}")

        val orient = try {
            ExifInterface(file.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Throwable) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val deg = when (orient) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (deg == 0f) return decoded
        val m = Matrix().apply { postRotate(deg) }
        val rot = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, m, true)
        decoded.recycle()
        return rot
    }

    private fun applyScanFilter(src: Bitmap, filter: String): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint()
        val cm = ColorMatrix()
        when (filter.lowercase()) {
            "grayscale" -> cm.setSaturation(0f)
            "contrast" -> {
                val c = 1.45f
                val t = (-0.5f * c + 0.5f) * 255f
                cm.set(
                    floatArrayOf(
                        c, 0f, 0f, 0f, t,
                        0f, c, 0f, 0f, t,
                        0f, 0f, c, 0f, t,
                        0f, 0f, 0f, 1f, 0f,
                    ),
                )
            }
            "bw" -> {
                cm.setSaturation(0f)
                val c = 2.4f
                val t = (-0.58f * c + 0.5f) * 255f
                val contrast = ColorMatrix(
                    floatArrayOf(
                        c, 0f, 0f, 0f, t,
                        0f, c, 0f, 0f, t,
                        0f, 0f, c, 0f, t,
                        0f, 0f, 0f, 1f, 0f,
                    ),
                )
                cm.postConcat(contrast)
            }
        }
        paint.colorFilter = ColorMatrixColorFilter(cm)
        canvas.drawBitmap(src, 0f, 0f, paint)
        return out
    }

    @Suppress("UNCHECKED_CAST")
    private fun buildTextPdfInternal(spec: Map<String, Any?>, outFile: File): Map<String, Any> {
        outFile.parentFile?.mkdirs()
        val title = (spec["title"] as? String).orEmpty()
        val subtitle = (spec["subtitle"] as? String).orEmpty()
        val pattern = (spec["pattern"] as? String) ?: "blank"
        val body = (spec["body"] as? String).orEmpty()
        val blankPages = ((spec["pageCount"] as? Number)?.toInt() ?: 1).coerceIn(1, 30)
        val schoolHeader = spec["schoolHeader"] as? Map<String, Any?>

        val pw = 595
        val ph = 842
        val doc = PdfDocument()
        try {
            if (body.isBlank() && title.isBlank()) {
                for (i in 1..blankPages) {
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, i).create())
                    drawPaperPattern(page.canvas, pw.toFloat(), ph.toFloat(), pattern)
                    doc.finishPage(page)
                }
            } else {
                val marginX = 48
                val contentW = pw - marginX * 2
                val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.rgb(24, 24, 28)
                    textSize = 20f
                    typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
                }
                val subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.rgb(110, 102, 94)
                    textSize = 11f
                }
                val bodyPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.rgb(34, 34, 38)
                    textSize = 11.5f
                    typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
                }

                val blocks = body.split("\n\n").filter { it.isNotBlank() }
                var blockIdx = 0
                var pageNo = 1

                while (pageNo == 1 || blockIdx < blocks.size) {
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, pageNo).create())
                    val canvas = page.canvas
                    drawPaperPattern(canvas, pw.toFloat(), ph.toFloat(), pattern)

                    var cursorY = 48f
                    if (pageNo == 1) {
                        if (schoolHeader != null && (schoolHeader["enabled"] as? Boolean == true)) {
                            cursorY = drawSchoolExamBanner(canvas, pw.toFloat(), schoolHeader) + 18f
                        }
                        if (title.isNotBlank()) {
                            val tl = staticLayoutOf(title, titlePaint, contentW)
                            canvas.save()
                            canvas.translate(marginX.toFloat(), cursorY)
                            tl.draw(canvas)
                            canvas.restore()
                            cursorY += tl.height + 6f
                        }
                        if (subtitle.isNotBlank()) {
                            val sl = staticLayoutOf(subtitle, subPaint, contentW)
                            canvas.save()
                            canvas.translate(marginX.toFloat(), cursorY)
                            sl.draw(canvas)
                            canvas.restore()
                            cursorY += sl.height + 14f
                        }
                        val rule = Paint().apply {
                            color = Color.rgb(219, 61, 51)
                            strokeWidth = 1.5f
                        }
                        canvas.drawLine(marginX.toFloat(), cursorY - 6f, (pw - marginX).toFloat(), cursorY - 6f, rule)
                    }

                    while (blockIdx < blocks.size) {
                        val paragraph = blocks[blockIdx]
                        val layout = staticLayoutOf(paragraph, bodyPaint, contentW)
                        if (cursorY + layout.height > ph - 48f && cursorY > 90f) {
                            break
                        }
                        canvas.save()
                        canvas.translate(marginX.toFloat(), cursorY)
                        layout.draw(canvas)
                        canvas.restore()
                        cursorY += layout.height + 10f
                        blockIdx++
                    }

                    val foot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = Color.GRAY
                        textSize = 9f
                        textAlign = Paint.Align.CENTER
                    }
                    canvas.drawText("Sayfa $pageNo", pw / 2f, ph - 18f, foot)
                    doc.finishPage(page)
                    pageNo++
                    if (blockIdx >= blocks.size) break
                }
            }
            FileOutputStream(outFile).use { out -> doc.writeTo(out) }
        } finally {
            doc.close()
        }
        val info = getPdfInfoInternal(outFile)
        return mapOf(
            "path" to outFile.absolutePath,
            "pageCount" to (info["pageCount"] ?: 0),
            "fileSize" to outFile.length(),
        )
    }

    @Suppress("DEPRECATION")
    private fun staticLayoutOf(text: String, paint: TextPaint, width: Int): StaticLayout {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setLineSpacing(3.5f, 1.15f)
                .build()
        } else {
            StaticLayout(text, paint, width, Layout.Alignment.ALIGN_NORMAL, 1.15f, 3.5f, true)
        }
    }

    private fun drawPaperPattern(canvas: Canvas, pw: Float, ph: Float, pattern: String) {
        canvas.drawColor(Color.WHITE)
        val linePaint = Paint().apply {
            color = Color.argb(45, 95, 130, 175)
            strokeWidth = 0.7f
        }
        when (pattern.lowercase()) {
            "lined" -> {
                var y = 64f
                while (y < ph - 40f) {
                    canvas.drawLine(36f, y, pw - 36f, y, linePaint)
                    y += 24f
                }
                val marginPaint = Paint().apply {
                    color = Color.argb(80, 219, 61, 51)
                    strokeWidth = 1f
                }
                canvas.drawLine(64f, 24f, 64f, ph - 24f, marginPaint)
            }
            "grid" -> {
                var x = 24f
                while (x < pw - 24f) {
                    canvas.drawLine(x, 24f, x, ph - 24f, linePaint)
                    x += 20f
                }
                var y = 24f
                while (y < ph - 24f) {
                    canvas.drawLine(24f, y, pw - 24f, y, linePaint)
                    y += 20f
                }
            }
            "dot" -> {
                val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.argb(85, 110, 120, 140)
                }
                var y = 32f
                while (y < ph - 32f) {
                    var x = 32f
                    while (x < pw - 32f) {
                        canvas.drawCircle(x, y, 1.1f, dotPaint)
                        x += 20f
                    }
                    y += 20f
                }
            }
            "music" -> {
                val staffPaint = Paint().apply {
                    color = Color.argb(95, 45, 50, 60)
                    strokeWidth = 0.8f
                }
                var topY = 72f
                while (topY < ph - 72f) {
                    for (line in 0 until 5) {
                        val y = topY + line * 7.5f
                        canvas.drawLine(42f, y, pw - 42f, y, staffPaint)
                    }
                    topY += 68f
                }
            }
        }
    }
}
