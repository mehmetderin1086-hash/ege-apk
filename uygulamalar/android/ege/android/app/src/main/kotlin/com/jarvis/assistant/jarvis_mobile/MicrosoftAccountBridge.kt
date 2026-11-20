package com.jarvis.assistant.jarvis_mobile

import android.app.Activity
import android.content.Context
import com.microsoft.identity.client.*
import com.microsoft.identity.client.exception.MsalException
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** MSAL owns the encrypted token cache. No passwords or tokens enter app settings. */
class MicrosoftAccountBridge(private val activity: Activity) {
    private var app: IMultipleAccountPublicClientApplication? = null
    private var pending: MethodChannel.Result? = null
    private val prefs = activity.getSharedPreferences("ege_microsoft_accounts", Context.MODE_PRIVATE)
    private val scopes = mapOf(
        "outlook" to listOf("User.Read", "Mail.Read", "Mail.Send"),
        "onedrive" to listOf("User.Read", "Files.ReadWrite"),
        "calendar" to listOf("User.Read", "Calendars.ReadWrite")
    )

    fun authorize(service: String, interactive: Boolean, result: MethodChannel.Result) {
        if (pending != null) { result.success(mapOf("status" to "BUSY")); return }
        val names = scopes[service] ?: run { result.success(mapOf("status" to "INVALID_SERVICE")); return }
        val clientId = activity.getString(R.string.ege_microsoft_client_id).trim()
        if (!Regex("[0-9a-fA-F-]{36}").matches(clientId)) {
            result.success(mapOf("status" to "SETUP_REQUIRED", "message" to "Microsoft bağlantısı henüz etkinleştirilmedi. Ege uygulama kaydı tamamlandıktan sonra buradan hesabını seçebilirsin."))
            return
        }
        pending = result
        fun run(client: IMultipleAccountPublicClientApplication) {
            if (pending !== result) return
            val callback = object : AuthenticationCallback {
                override fun onSuccess(auth: IAuthenticationResult) {
                    if (pending !== result) return
                    if (!auth.scope.map { it.substringAfterLast('/').lowercase() }.containsAll(names.map { it.lowercase() }) || auth.accessToken.isBlank()) {
                        finish(mapOf("status" to "NEEDS_AUTH")); return
                    }
                    prefs.edit().putString(service, auth.account.id).apply()
                    finish(mapOf("status" to "OK", "token" to auth.accessToken, "account" to auth.account.username))
                }
                override fun onError(error: MsalException) {
                    if (pending === result) finish(mapOf("status" to "NEEDS_AUTH", "message" to "Microsoft izni alınamadı. Hesabı yeniden bağla; kurumsal hesaplarda yönetici izni gerekebilir."))
                }
                override fun onCancel() { if (pending === result) finish(mapOf("status" to "CANCELLED")) }
            }
            if (interactive) {
                try {
                    client.acquireToken(AcquireTokenParameters.Builder()
                        .startAuthorizationFromActivity(activity).withScopes(names)
                        .withPrompt(Prompt.SELECT_ACCOUNT).withCallback(callback).build())
                } catch (_: Exception) { finish(mapOf("status" to "ERROR")) }
            } else {
                val selected = prefs.getString(service, null)
                if (selected == null) { finish(mapOf("status" to "NEEDS_AUTH")); return }
                client.getAccounts(object : IPublicClientApplication.LoadAccountsCallback {
                    override fun onTaskCompleted(accounts: MutableList<IAccount>?) {
                        if (pending !== result) return
                        val account = accounts?.firstOrNull { it.id == selected }
                        if (account == null) { finish(mapOf("status" to "NEEDS_AUTH")); return }
                        try {
                            client.acquireTokenSilentAsync(AcquireTokenSilentParameters.Builder()
                                .forAccount(account).withScopes(names).fromAuthority(account.authority)
                                .withCallback(callback).build())
                        } catch (_: Exception) { finish(mapOf("status" to "NEEDS_AUTH")) }
                    }
                    override fun onError(error: MsalException) { if (pending === result) finish(mapOf("status" to "NEEDS_AUTH")) }
                })
            }
        }
        app?.let { run(it); return }
        try {
            val config = JSONObject().put("client_id", clientId)
                .put("redirect_uri", activity.getString(R.string.ege_microsoft_redirect_uri))
                .put("account_mode", "MULTIPLE").put("authorization_user_agent", "BROWSER")
                .put("broker_redirect_uri_registered", false)
                .put("logging", JSONObject().put("pii_enabled", false).put("log_level", "ERROR"))
                .put("authorities", JSONArray().put(JSONObject().put("type", "AAD").put("default", true)
                    .put("audience", JSONObject().put("type", "AzureADandPersonalMicrosoftAccount"))))
            val file = File(activity.noBackupFilesDir, "microsoft-config.json")
            file.writeText(config.toString())
            PublicClientApplication.createMultipleAccountPublicClientApplication(activity, file,
                object : IPublicClientApplication.IMultipleAccountApplicationCreatedListener {
                    override fun onCreated(application: IMultipleAccountPublicClientApplication) {
                        app = application
                        run(application)
                    }
                    override fun onError(error: MsalException) {
                        if (pending === result) finish(mapOf("status" to "ERROR", "message" to "Microsoft uygulama kaydı veya dönüş adresi doğrulanamadı."))
                    }
                })
        } catch (_: Exception) { finish(mapOf("status" to "ERROR")) }
    }

    fun disconnect(service: String, result: MethodChannel.Result) {
        // Disables this service without signing out other services using the same account.
        prefs.edit().remove(service).apply()
        result.success(true)
    }
    private fun finish(value: Map<String, Any?>) {
        val result = pending
        pending = null
        activity.runOnUiThread { result?.success(value) }
    }
    fun cancel() = finish(mapOf("status" to "CANCELLED"))
}
