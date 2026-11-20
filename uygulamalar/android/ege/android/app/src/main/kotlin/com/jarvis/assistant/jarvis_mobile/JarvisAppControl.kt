package com.jarvis.assistant.jarvis_mobile

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.app.SearchManager
import android.net.Uri
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel

class JarvisAppControl : AccessibilityService() {
    companion object { var instance: JarvisAppControl? = null }
    override fun onServiceConnected() { instance = this }
    private var previousApp: String? = null
    private val homePackages by lazy {
        setOfNotNull(packageManager.resolveActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName)
    }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (pkg !in homePackages && packageManager.getLaunchIntentForPackage(pkg) == null) return
        if (pkg == packageName || pkg == "com.android.systemui" ||
            rootInActiveWindow?.window?.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD) return
        previousApp = pkg.takeUnless { it in homePackages }
    }
    override fun onInterrupt() {}
    override fun onDestroy() {
        captureCompletion?.invoke(mapOf("error" to "Ekran servisi kapandı."))
        handler.removeCallbacksAndMessages(null)
        finish("Hata: Kontrol servisi kapandı. İşlem sonucu doğrulanamadı.")
        if (instance === this) instance = null
        super.onDestroy()
    }
    private val handler = Handler(Looper.getMainLooper())
    private var busy = false
    private var captureCompletion: ((Map<String, Any>) -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null
    private var operationStarted = 0L
    private var operationAction = ""

    private fun safely(block: () -> Unit) {
        try { block() } catch (_: Exception) {
            finish("Hata: Ekran erişimi değişti. Sonuç doğrulanamadı; yeni ekranı oku, eylemi körlemesine tekrarlama.")
        }
    }

    private fun finish(message: String) {
        val result = pendingResult ?: return
        pendingResult = null
        busy = false
        // No screen text, URLs, queries or form values in diagnostics.
        android.util.Log.i("JarvisControl", "action=$operationAction elapsedMs=${SystemClock.uptimeMillis() - operationStarted} error=${message.startsWith("Hata")}")
        result.success(message)
    }

    private var generation = 0L
    private data class Observed(val node: AccessibilityNodeInfo, val signature: String)
    private val observed = mutableMapOf<String, Observed>()
    private fun signature(n: AccessibilityNodeInfo): String {
        val bounds = Rect().also { n.getBoundsInScreen(it) }
        return "${n.windowId}|${n.packageName}|${n.viewIdResourceName}|${n.text}|${n.contentDescription}|${n.isEditable}|${n.isEnabled}|${n.isChecked}|$bounds"
    }

    private data class Screen(val fingerprint: String, val hasControls: Boolean, val loading: Boolean)
    private fun inspect(root: AccessibilityNodeInfo): Screen {
        val parts = StringBuilder().append(root.windowId).append(root.packageName)
        var count = 0
        var controls = 0
        var loading = false
        fun visit(n: AccessibilityNodeInfo, depth: Int) {
            if (depth > 50 || count++ >= 500 || n.isPassword) return
            if (n.isVisibleToUser) {
                if (n.className?.toString()?.endsWith("ProgressBar") == true) loading = true
                if (!n.text.isNullOrBlank() || !n.contentDescription.isNullOrBlank() || n.isEditable || n.isClickable || n.isLongClickable || n.isScrollable || n.className?.toString()?.endsWith("ImageView") == true) {
                    controls++
                    parts.append(signature(n)).append(n.isSelected).append(n.isFocused)
                }
            }
            for (i in 0 until n.childCount) n.getChild(i)?.let { visit(it, depth + 1) }
        }
        visit(root, 0)
        return Screen(parts.toString(), controls > 0, loading)
    }

    private fun awaitScreen(pkg: String, baseline: String?, expectChange: Boolean, prefix: String, raw: Boolean = false) {
        val wait = PhoneScreenWait(SystemClock.uptimeMillis(), baseline, expectChange)
        fun poll() {
            if (!busy) return
            val root = rootInActiveWindow
            val screen = root?.takeIf { it.packageName?.toString() == pkg }?.let { inspect(it) }
            val state = wait.observe(SystemClock.uptimeMillis(), screen?.fingerprint, screen?.hasControls == true, screen?.loading == true)
            if (state == PhoneScreenWait.State.WAIT) {
                handler.postDelayed({ safely { poll() } }, 100)
                return
            }
            val status = when (state) {
                PhoneScreenWait.State.READY -> "Ekran kısa süreli kararlı; bu, görevin tamamlandığı anlamına gelmez."
                PhoneScreenWait.State.UNCHANGED -> "Görünür ekran değişikliği doğrulanamadı. Eylemi körlemesine tekrarlama; sonucu incele."
                else -> "Ekran henüz hazır değil veya hedef uygulama önde değil. İşlem sonucu belirsiz; phone_snapshot ile yeniden gözle, eylemi tekrarlama."
            }
            if (raw) finish(if (root?.packageName?.toString() == pkg) snapshot() else "Uygulama ekranı değişti.")
            else finish("$prefix $status İstenen içerik ve işlem sonucunu doğrula: " + snapshot())
        }
        safely { poll() }
    }

    fun readScreen(result: MethodChannel.Result) {
        if (busy || captureCompletion != null) { result.success("Hata: Önceki telefon işlemi sürüyor; bitmesini bekle."); return }
        val root = rootInActiveWindow
        val pkg = root?.packageName?.toString()
        if (pkg == null) { result.success("Hata: Ekran erişilebilir değil."); return }
        busy = true
        pendingResult = result
        operationStarted = SystemClock.uptimeMillis()
        operationAction = "snapshot"
        awaitScreen(pkg, null, false, "Ekran gözlemi.")
    }

    /** Resolve only inside the requested package; never fall through to a browser/other app. */
    private fun startInPackage(intent: Intent, pkg: String): Boolean {
        intent.setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val resolved = intent.resolveActivity(packageManager) ?: return false
        if (resolved.packageName != pkg) return false
        return try { startActivity(intent); true } catch (_: Exception) { false }
    }

    private fun openSearch(pkg: String, query: String): Boolean {
        val direct = when (pkg) {
            "com.google.android.youtube" -> Uri.parse("https://www.youtube.com/results").buildUpon().appendQueryParameter("search_query", query).build()
            "com.spotify.music" -> Uri.parse("spotify:search:${Uri.encode(query)}")
            else -> null
        }
        if (direct != null && startInPackage(Intent(Intent.ACTION_VIEW, direct), pkg)) return true
        return listOf("com.google.android.gms.actions.SEARCH_ACTION", Intent.ACTION_SEARCH).any { action ->
            startInPackage(Intent(action).putExtra(SearchManager.QUERY, query), pkg)
        }
    }

    private fun screenLinks(text: CharSequence?): org.json.JSONArray {
        val links = if (text is android.text.Spanned) text.getSpans(0, text.length, android.text.style.URLSpan::class.java).map { it.url } else emptyList()
        return org.json.JSONArray(links.filter { val u = Uri.parse(it); u.scheme in listOf("http", "https") && !u.host.isNullOrBlank() && u.userInfo == null }.distinct().take(8))
    }

    fun snapshot(): String {
        observed.clear()
        generation++
        val root = rootInActiveWindow ?: return "Ekran erişilebilir değil."
        val rows = org.json.JSONArray()
        fun visit(n: AccessibilityNodeInfo, depth: Int, parent: String = "") {
            var childParent = parent
            if (depth > 50 || rows.length() >= 160 || n.isPassword) return
            if (n.isVisibleToUser) {
                val text = n.text?.toString().orEmpty()
                val description = n.contentDescription?.toString().orEmpty()
                val hint = if (android.os.Build.VERSION.SDK_INT >= 26) n.hintText?.toString().orEmpty() else ""
                if (text.isNotBlank() || description.isNotBlank() || hint.isNotBlank() || n.isEditable || n.isClickable || n.isLongClickable || n.isScrollable || n.className?.toString()?.endsWith("ImageView") == true) {
                    val id = "@$generation:${rows.length()}"
                    observed[id] = Observed(n, signature(n))
                    childParent = id
                    rows.put(org.json.JSONObject().put("target", id).put("parent", parent).put("depth", depth)
                        .put("textTruncated", text.length > 1200 || description.length > 1200)
                        .put("label", text.ifBlank { description.ifBlank { hint } }.take(1200))
                        .put("resourceId", n.viewIdResourceName.orEmpty()).put("description", description.take(1200)).put("hint", hint.take(1200))
                        .put("role", n.className).put("enabled", n.isEnabled)
                        .put("longClickable", n.isLongClickable || n.actionList.any { it.id == AccessibilityNodeInfo.ACTION_LONG_CLICK })
                        .put("bounds", Rect().also { n.getBoundsInScreen(it) }.toShortString())
                        .put("links", screenLinks(n.text))
                        .put("clickable", n.isClickable).put("editable", n.isEditable).put("scrollable", n.isScrollable)
                        .put("checkable", n.isCheckable).put("checked", n.isChecked).put("selected", n.isSelected)
                        .put("focused", n.isFocused).put("inputType", if (n.isEditable) n.inputType else 0)
                        .put("state", if (android.os.Build.VERSION.SDK_INT >= 30) n.stateDescription?.toString().orEmpty().take(120) else "")
                        .put("canSubmit", android.os.Build.VERSION.SDK_INT >= 30 && n.actionList.any { it.id == AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id }))
                }
            }
            for (i in 0 until n.childCount) n.getChild(i)?.let { visit(it, depth + 1, childParent) }
        }
        visit(root, 0)
        return org.json.JSONObject().put("package", root.packageName?.toString()).put("controls", rows)
            .put("truncated", rows.length() >= 160).toString()
    }

    fun currentAppCommand(action: String, result: MethodChannel.Result) {
        if (busy || captureCompletion != null) { result.success("Başka bir ekran işlemi sürüyor."); return }
        val front = rootInActiveWindow?.packageName?.toString()
        val expected = if (front == packageName) previousApp else front
        if (front != packageName && (expected == null || expected in homePackages || expected == "com.android.systemui")) {
            result.success("NO_APP"); return
        }
        busy = true
        pendingResult = result
        operationStarted = SystemClock.uptimeMillis()
        operationAction = action
        safely {
            val restore = if (front == packageName && expected != null) packageManager.getLaunchIntentForPackage(expected) else null
            if (restore != null) {
                restore.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                startActivity(restore)
            } else if (front == packageName && MainActivity.instance?.moveTaskToBack(true) != true) {
                finish("Önceki uygulama gösterilemedi."); return@safely
            }
            fun applyWhenVisible() {
                val root = rootInActiveWindow
                val actual = root?.packageName?.toString()
                if (actual in homePackages && expected == null) { finish("NO_APP"); return }
                if (root == null || actual.isNullOrEmpty() || actual == packageName || actual == "com.android.systemui" ||
                    (expected != null && expected != actual)) {
                    if (SystemClock.uptimeMillis() - operationStarted < 1800)
                        handler.postDelayed({ safely { applyWhenVisible() } }, 100)
                    else finish("Beklenen uygulama ekranda görünmüyor. İşlem yapılmadı.")
                    return
                }
                if (action == "inspect") { awaitScreen(actual, null, false, "", raw = true); return }
                val before = inspect(root).fingerprint
                val global = if (action == "back") GLOBAL_ACTION_BACK else GLOBAL_ACTION_HOME
                if (!performGlobalAction(global)) { finish("Android gezinme işlemini kabul etmedi."); return }
                fun verify() {
                    val after = rootInActiveWindow
                    val pkg = after?.packageName?.toString()
                    val changed = if (action == "leave") pkg in homePackages else
                        pkg != null && (pkg != actual || inspect(after).fingerprint != before)
                    if (changed) finish(if (action == "leave") "Uygulamadan çıktım." else "Geri döndüm.")
                    else if (SystemClock.uptimeMillis() - operationStarted < 3000)
                        handler.postDelayed({ safely { verify() } }, 120)
                    else finish("Android komutu aldı, ekran değişikliğini doğrulayamadım.")
                }
                handler.postDelayed({ safely { verify() } }, 180)
            }
            applyWhenVisible()
        }
    }

    /** Explicit user request only: reveal the existing task behind Ege, never relaunch it. */
    fun resumeExternalScreen(result: MethodChannel.Result) {
        if (busy || captureCompletion != null) { result.success("Hata: Önceki ekran işlemi sürüyor."); return }
        busy = true
        pendingResult = result
        operationStarted = SystemClock.uptimeMillis()
        operationAction = "resume_screen"
        safely {
            if (rootInActiveWindow?.packageName?.toString() == packageName) {
                if (MainActivity.instance?.moveTaskToBack(true) != true) {
                    finish("Hata: Önceki uygulama gösterilemedi. Okunacak ekranı açıp yeniden sor.")
                    return@safely
                }
            }
            fun poll() {
                if (!busy) return
                val pkg = rootInActiveWindow?.packageName?.toString()
                if (!pkg.isNullOrBlank() && pkg != packageName) {
                    awaitScreen(pkg, null, false, "Ege dışındaki güncel ekran. Hedef uygulama olduğunu kontrol et.")
                } else if (SystemClock.uptimeMillis() - operationStarted < 2000) {
                    handler.postDelayed({ safely { poll() } }, 100)
                } else finish("Hata: Dış uygulamanın ekranı okunamadı; eski ekran kullanılmadı.")
            }
            poll()
        }
    }

    /** On-demand only, RAM only; honor secure screens and refuse password fields. */
    fun captureScreen(expectedPackage: String, result: MethodChannel.Result) {
        if (busy || captureCompletion != null) { result.success(mapOf("error" to "Ekran işlemi sürüyor.")); return }
        if (android.os.Build.VERSION.SDK_INT < 30) { result.success(mapOf("error" to "Bu Android sürümünde ekran görüntüsü desteklenmiyor.")); return }
        val root = rootInActiveWindow
        if (root == null || expectedPackage.isBlank() || expectedPackage == packageName || root.packageName?.toString() != expectedPackage) {
            result.success(mapOf("error" to "Ekran değişti; önce güncel ekranı oku.")); return
        }
        var visited = 0
        fun unsafe(n: AccessibilityNodeInfo, depth: Int): Boolean {
            if (++visited > 500 || depth > 50) return true
            if (n.isVisibleToUser && n.isPassword) return true
            for (i in 0 until n.childCount) if (n.getChild(i)?.let { unsafe(it, depth + 1) } == true) return true
            return false
        }
        if (unsafe(root, 0)) { result.success(mapOf("error" to "Parola alanı veya eksik ekran denetimi nedeniyle yalnız erişilebilir metin kullanılıyor.")); return }
        val window = root.windowId
        val before = inspect(root).fingerprint
        var done = false
        val complete: (Map<String, Any>) -> Unit = { value ->
            if (!done) { done = true; captureCompletion = null; result.success(value) }
        }
        captureCompletion = complete
        handler.postDelayed({ complete(mapOf("error" to "Ekran görüntüsü zaman aşımı.")) }, 4000)
        try {
            takeScreenshot(android.view.Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(shot: ScreenshotResult) {
                    val buffer = shot.hardwareBuffer
                    try {
                        if (done) return
                        val current = rootInActiveWindow
                        if (current == null || current.packageName?.toString() != expectedPackage || current.windowId != window || inspect(current).fingerprint != before) {
                            complete(mapOf("error" to "Görüntü alınırken ekran değişti; eski görüntü kullanılmadı.")); return
                        }
                        val hardware = android.graphics.Bitmap.wrapHardwareBuffer(buffer, shot.colorSpace)
                        val bitmap = hardware?.copy(android.graphics.Bitmap.Config.ARGB_8888, false)
                        hardware?.recycle()
                        if (bitmap == null) { complete(mapOf("error" to "Ekran görüntüsü alınamadı.")); return }
                        val scale = minOf(1.0, 1920.0 / maxOf(bitmap.width, bitmap.height))
                        val scaled = if (scale < 1) android.graphics.Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
                        val out = java.io.ByteArrayOutputStream()
                        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, out)
                        if (scaled !== bitmap) scaled.recycle()
                        bitmap.recycle()
                        complete(mapOf("image" to out.toByteArray(), "package" to expectedPackage))
                    } catch (_: Exception) { complete(mapOf("error" to "Görüntü işlenemedi.")) }
                    finally { buffer.close() }
                }
                override fun onFailure(errorCode: Int) {
                    complete(mapOf("error" to "Android ekran görüntüsüne izin vermedi ($errorCode). Yalnız erişilebilir metin kullanılabilir."))
                }
            })
        } catch (_: Exception) { complete(mapOf("error" to "Ekran görüntüsü alınamadı.")) }
    }

    fun execute(pkg: String, action: String, target: String, text: String, result: MethodChannel.Result, query: String = "", url: String = "") {
        if (busy || captureCompletion != null) { result.success("Hata: Bir önceki işlem sürüyor."); return }
        if (!PhoneActionPolicy.valid(action, target, query, url)) {
            result.success("Hata: Geçersiz işlem, hedef veya açılış parametreleri."); return
        }
        val webUri = if (url.isNotEmpty()) Uri.parse(url) else null
        if (webUri != null && (webUri.scheme !in listOf("https", "http") || webUri.host.isNullOrBlank() || webUri.userInfo != null)) {
            result.success("Hata: Geçerli bir http/https web adresi gerekli."); return
        }
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        if (launch == null) { result.success("Hata: Bu uygulama başlatılamıyor."); return }
        busy = true
        pendingResult = result
        operationStarted = SystemClock.uptimeMillis()
        operationAction = action
        val before = try {
            rootInActiveWindow?.takeIf { it.packageName?.toString() == pkg }?.let { inspect(it).fingerprint }
        } catch (_: Exception) {
            finish("Hata: İlk ekran okunamadı; işlem yapılmadı."); return
        }
        var prefix = "Uygulama ekranı."
        var directOpened = false
        if (action == "open" && webUri != null) {
            directOpened = startInPackage(Intent(Intent.ACTION_VIEW, webUri), pkg)
            if (!directOpened) { finish("Hata: Web adresi istenen uygulamada açılamadı."); return }
            prefix = "Web adresini açma isteği iletildi; yüklenen adresi ve sayfayı doğrula."
        } else if (action == "open" && query.isNotEmpty()) {
            directOpened = openSearch(pkg, query)
            prefix = if (directOpened) "Doğrudan arama isteği iletildi. Sorgunun ve sonuçların doğru olduğunu kontrol et; içerik henüz seçilmedi/oynatılmadı."
                else "Doğrudan arama desteklenmedi. Uygulamanın görünen arama kontrolünü kullan; henüz arama yapılmadı."
        }
        // Only an explicit open may launch. Re-launching between actions can reset
        // an app's search/navigation state, or act on a different screen.
        if (action == "open" && !directOpened && rootInActiveWindow?.packageName?.toString() != pkg) {
            try { startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            catch (_: Exception) { finish("Hata: Uygulama açılamadı."); return }
        }
        fun attempt() {
            if (!busy) return
            val root = rootInActiveWindow
            if (root == null || root.packageName?.toString() != pkg) {
                if (action == "open" && SystemClock.uptimeMillis() - operationStarted < 3500) handler.postDelayed({ safely { attempt() } }, 100)
                else finish("Hata: Hedef uygulama ön planda değil. phone_open_app ile aç ve yeni ekranı oku. Kontrol eylemi yapılmadı.")
                return
            }
            if (action == "open") { awaitScreen(pkg, before, directOpened || before == null, prefix); return }
            val baseline = inspect(root).fingerprint
            val nodes = mutableListOf<AccessibilityNodeInfo>()
            fun collect(n: AccessibilityNodeInfo, depth: Int) {
                if (depth > 50 || nodes.size >= 500 || n.isPassword) return
                if (n.isVisibleToUser && !n.isPassword) nodes.add(n)
                for (i in 0 until n.childCount) n.getChild(i)?.let { collect(it, depth + 1) }
            }
            collect(root, 0)
            val saved = observed[target]
            if (target.startsWith("@") && (saved == null || !saved.node.refresh() ||
                saved.node.packageName?.toString() != pkg || saved.node.windowId != root.windowId ||
                !saved.node.isVisibleToUser || saved.node.isPassword || signature(saved.node) != saved.signature)) {
                finish("Hata: Kontrol kimliği eski veya ekran değişmiş. Yeni ekrandaki target değerini kullan: " + snapshot())
                return
            }
            val matched = if (saved != null) listOf(saved.node) else nodes.filter { n -> target.isNotBlank() &&
                (n.text?.toString()?.equals(target, true) == true || n.contentDescription?.toString()?.equals(target, true) == true ||
                (android.os.Build.VERSION.SDK_INT >= 26 && n.hintText?.toString()?.equals(target, true) == true)) }
            var reason = "İstenen kontrol bulunamadı veya erişilebilir değil. İşlem yapılmadı."
            val ok = when (action) {
                "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
                "scroll", "scroll_back" -> {
                    val areas = (if (target.isNotBlank()) matched else nodes).filter { it.isScrollable && it.isEnabled }
                    if (areas.size > 1) reason = "Birden fazla kaydırma alanı var. Güncel target kimliği gerekli. İşlem yapılmadı."
                    areas.singleOrNull()?.performAction(if (action == "scroll") AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) == true
                }
                "long_click" -> {
                    val targets = matched.mapNotNull { n ->
                        var candidate: AccessibilityNodeInfo? = n
                        var depth = 0
                        fun supported(v: AccessibilityNodeInfo) = v.isLongClickable || v.actionList.any { it.id == AccessibilityNodeInfo.ACTION_LONG_CLICK }
                        while (candidate != null && !supported(candidate) && depth++ < 5) candidate = candidate.parent
                        candidate?.takeIf { supported(it) && it.isEnabled && it.isVisibleToUser && !it.isPassword && it.packageName?.toString() == pkg && it.windowId == root.windowId }
                    }.distinct()
                    if (targets.size != 1) reason = "Uzun basılacak hedef belirsiz veya uzun basmayı desteklemiyor. İşlem yapılmadı."
                    targets.singleOrNull()?.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK) == true
                }
                "click" -> {
                    val clickable = matched.mapNotNull { n ->
                        var candidate: AccessibilityNodeInfo? = n
                        var depth = 0
                        while (candidate != null && !candidate.isClickable && depth++ < 5) candidate = candidate.parent
                        candidate?.takeIf { it.isClickable && it.isEnabled && it.isVisibleToUser && it.packageName?.toString() == pkg && it.windowId == root.windowId }
                    }.distinct()
                    if (clickable.size > 1) reason = "Aynı isimde birden fazla kontrol var. İşlem yapılmadı."
                    clickable.singleOrNull()?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
                }
                "text" -> {
                    val fields = matched.filter { it.isEditable && it.isEnabled }
                    if (fields.size > 1) reason = "Aynı isimde birden fazla metin alanı var. İşlem yapılmadı."
                    fields.singleOrNull()?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,
                        Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }) == true
                }
                "submit" -> {
                    val fields = matched.filter { it.isEditable && it.isEnabled }
                    val field = fields.singleOrNull()
                    if (android.os.Build.VERSION.SDK_INT >= 30 && field != null && field.actionList.any { it.id == AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id }) {
                        field.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)
                    } else {
                        reason = "Alan klavye gönderimini desteklemiyor veya belirsiz. Ekrandaki Ara/Gönder düğmesini kullan. İşlem yapılmadı."
                        false
                    }
                }
                else -> false
            }
            if (ok) awaitScreen(pkg, baseline, true, "Kontrol eylemi uygulandı; görev sonucu henüz doğrulanmadı.")
            else finish("Hata: $reason Yeni ekran: " + snapshot())
        }
        safely { attempt() }
    }
}
