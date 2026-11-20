package com.jarvis.assistant.jarvis_mobile

import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.google.android.gms.common.api.ApiException
import io.flutter.plugin.common.MethodChannel

/** Tokens are returned only to the app's HTTP client, never persisted or logged. */
class GoogleAccountBridge(private val activity: Activity) {
    companion object { const val REQUEST = 7021 }
    private var pending: MethodChannel.Result? = null
    private var requested = emptyList<String>()
    private val scopes = mapOf(
        "gmail" to listOf("https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.send"),
        "drive" to listOf("https://www.googleapis.com/auth/drive.readonly", "https://www.googleapis.com/auth/drive.file"),
        "calendar" to listOf("https://www.googleapis.com/auth/calendar.events", "https://www.googleapis.com/auth/calendar.calendarlist.readonly")
    )
    fun authorize(service: String, interactive: Boolean, result: MethodChannel.Result) {
        if (pending != null) { result.success(mapOf("status" to "BUSY")); return }
        val names = scopes[service] ?: run { result.success(mapOf("status" to "INVALID_SERVICE")); return }
        pending = result
        requested = names
        val request = AuthorizationRequest.builder().setRequestedScopes(names.map { Scope(it) }).build()
        Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener { auth ->
                if (pending !== result) return@addOnSuccessListener
                if (auth.hasResolution()) {
                    if (!interactive) finish(mapOf("status" to "NEEDS_AUTH"))
                    else try {
                        activity.startIntentSenderForResult(auth.pendingIntent!!.intentSender, REQUEST, null, 0, 0, 0)
                    } catch (_: Exception) { finish(mapOf("status" to "ERROR", "message" to "Google izin ekranı açılamadı.")) }
                } else complete(auth)
            }
            .addOnFailureListener { e ->
                if (pending !== result) return@addOnFailureListener
                val code = (e as? ApiException)?.statusCode
                finish(mapOf("status" to "ERROR", "message" to "Google yetkilendirme başarısız (kod $code). Ege Android OAuth kaydı ve etkin API'leri kontrol edin."))
            }
    }
    private fun complete(auth: AuthorizationResult) {
        if (!auth.grantedScopes.containsAll(requested) || auth.accessToken.isNullOrBlank()) {
            finish(mapOf("status" to "NEEDS_AUTH")); return
        }
        finish(mapOf("status" to "OK", "token" to auth.accessToken))
    }
    fun onResult(resultCode: Int, data: Intent?) {
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK) { finish(mapOf("status" to "CANCELLED")); return }
        try { complete(Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data)) }
        catch (_: Exception) { finish(mapOf("status" to "ERROR", "message" to "Google yetkisi alınamadı.")) }
    }
    private fun finish(value: Map<String, Any?>) { val result = pending; pending = null; result?.success(value) }
    fun cancel() = finish(mapOf("status" to "CANCELLED"))
}
