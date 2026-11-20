package com.jarvis.assistant.jarvis_mobile

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.os.Bundle

/**
 * Arayüzsüz ara etkinlik: PROCESS_TEXT ve SEND intent'lerini tek MainActivity
 * örneğine iletir (ikinci FlutterEngine/MainActivity açılmasın).
 */
class ShareTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val src = intent
            if (src != null) {
                val fwd = Intent(src).apply {
                    setClass(this@ShareTrampolineActivity, MainActivity::class.java)
                    component = android.content.ComponentName(this@ShareTrampolineActivity, MainActivity::class.java)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                    // Paylaşılan içerik URI'si için okuma izni yeni etkinliğe de geçsin.
                    if (clipData == null) {
                        @Suppress("DEPRECATION")
                        val stream = src.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                        if (stream != null) clipData = ClipData.newRawUri("paylasilan", stream)
                    }
                }
                startActivity(fwd)
            }
        } catch (_: Throwable) {
        }
        finish()
    }
}
