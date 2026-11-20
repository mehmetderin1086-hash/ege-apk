package com.mehmetderin.asistan

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale

class AppControlService : AccessibilityService() {
    companion object {
        var connected: AppControlService? = null
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastApp: String? = null

    override fun onServiceConnected() {
        connected = this
    }

    override fun onDestroy() {
        if (connected === this) connected = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val active = rootInActiveWindow?.packageName?.toString()
        if (active != null && active == event.packageName?.toString() &&
            active != packageName && active != "com.android.systemui" &&
            packageManager.getLaunchIntentForPackage(active) != null
        ) {
            lastApp = active
        }
    }

    override fun onInterrupt() = Unit

    fun targetPackage(): String? = lastApp

    fun execute(expected: String?, action: String, target: String, reply: (String) -> Unit) {
        if (expected == null) {
            reply("Önce kontrol etmek istediğiniz uygulamayı açın.")
            return
        }
        handler.postDelayed({
            val root = rootInActiveWindow
            if (root == null || root.packageName?.toString() != expected) {
                reply("Son kullanılan uygulamanın ekranına erişilemedi.")
                return@postDelayed
            }
            when (action) {
                "back" -> reply(if (performGlobalAction(GLOBAL_ACTION_BACK)) "Geri dönüldü." else "Geri dönülemedi.")
                "click" -> reply(click(root, target))
                "write" -> {
                    val field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                    val args = Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, target)
                    }
                    val written = field?.isEditable == true &&
                        field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    reply(if (written) "Metin yazıldı." else "Önce yazılabilir bir alan seçin.")
                }
                "up", "down", "left", "right" -> swipe(root, action, reply)
                else -> reply("Bu ekran işlemi tanınmadı.")
            }
        }, 400)
    }

    private fun click(root: AccessibilityNodeInfo, target: String): String {
        val locale = Locale.forLanguageTag("tr-TR")
        val normalized = target.trim().lowercase(locale)
        val parents = linkedSetOf<AccessibilityNodeInfo>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (node.isVisibleToUser && listOf(node.text, node.contentDescription).any {
                    it?.toString()?.trim()?.lowercase(locale) == normalized
                }) {
                var button: AccessibilityNodeInfo? = node
                while (button != null && !button.isClickable) button = button.parent
                if (button?.isEnabled == true) parents.add(button)
            }
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let(queue::addLast)
            }
        }
        if (parents.size > 1) return "Bu adda birden fazla öğe var."
        return if (parents.singleOrNull()?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true) {
            "‘$target’ öğesine dokunuldu."
        } else {
            "Ekranda ‘$target’ adlı dokunulabilir öğe bulunamadı."
        }
    }

    private fun swipe(root: AccessibilityNodeInfo, action: String, reply: (String) -> Unit) {
        val bounds = Rect().also(root::getBoundsInScreen)
        if (bounds.isEmpty) {
            reply("Ekran kaydırılamadı.")
            return
        }
        val x = bounds.exactCenterX()
        val y = bounds.exactCenterY()
        val dx = bounds.width() * 0.22f
        val dy = bounds.height() * 0.22f
        val path = Path().apply {
            when (action) {
                "down" -> { moveTo(x, y + dy); lineTo(x, y - dy) }
                "up" -> { moveTo(x, y - dy); lineTo(x, y + dy) }
                "right" -> { moveTo(x + dx, y); lineTo(x - dx, y) }
                else -> { moveTo(x - dx, y); lineTo(x + dx, y) }
            }
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300)).build()
        val started = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription) = reply("Ekran kaydırıldı.")
            override fun onCancelled(gestureDescription: GestureDescription) = reply("Kaydırma tamamlanamadı.")
        }, handler)
        if (!started) reply("Ekran kaydırılamadı.")
    }
}
