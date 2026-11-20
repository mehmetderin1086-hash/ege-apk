package com.jarvis.assistant.jarvis_mobile

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telecom.TelecomManager
import io.flutter.plugin.common.MethodChannel

/** A single hang-up request, followed by bounded observation. Never redials or toggles a headset key. */
internal class JarvisCalls(private val activity: Activity) {
    private var ending = false
    fun permitted(): Boolean = Build.VERSION.SDK_INT >= 28 &&
        permissions.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private val permissions get() = arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS)

    fun requestPermission(): String {
        if (Build.VERSION.SDK_INT < 28) return "UNSUPPORTED"
        if (permitted()) return "READY"
        activity.requestPermissions(permissions.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray(), 4422)
        return "PERMISSION_NEEDED"
    }

    @Suppress("DEPRECATION")
    fun end(result: MethodChannel.Result) {
        if (ending) { result.success("BUSY"); return }
        if (!permitted()) { result.success(requestPermission()); return }
        val telecom = activity.getSystemService(TelecomManager::class.java)
        if (telecom == null) { result.success("UNSUPPORTED"); return }
        try {
            if (!telecom.isInCall) { result.success("NO_ACTIVE_CALL"); return }
            if (!telecom.endCall()) { result.success("REJECTED"); return }
        } catch (_: SecurityException) { result.success("PERMISSION_NEEDED"); return }
        catch (_: Exception) { result.success("FAILED"); return }
        ending = true
        val started = SystemClock.uptimeMillis()
        val handler = Handler(Looper.getMainLooper())
        fun verify() {
            val active = try { telecom.isInCall } catch (_: Exception) { null }
            val state = CallEndCheck.afterRequest(active, SystemClock.uptimeMillis() - started)
            if (state == null) handler.postDelayed({ verify() }, 150)
            else { ending = false; result.success(state) }
        }
        verify()
    }
}

internal object CallEndCheck {
    fun afterRequest(active: Boolean?, elapsedMs: Long): String? = when {
        active == false -> "ENDED"
        active == null || elapsedMs >= 2500 -> "UNVERIFIED"
        else -> null
    }
}
