package com.mehmetderin.bilgiarena

import android.app.Activity
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout

class AtlasActivity : Activity() {
    private lateinit var browser: WebView

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            fitsSystemWindows = true
        }
        val back = Button(this, null, android.R.attr.borderlessButtonStyle).apply {
            text = "‹  Bilgi Arenası’na dön"
            isAllCaps = false
            gravity = android.view.Gravity.CENTER_VERTICAL or android.view.Gravity.START
            setOnClickListener { finish() }
        }
        layout.addView(back)
        browser = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.blockNetworkLoads = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) =
                    request.url.toString().substringBefore('#') != "file:///android_asset/atlas/index.html"
            }
        }
        layout.addView(browser, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(layout)
        browser.loadUrl("file:///android_asset/atlas/index.html")
    }

    override fun onDestroy() {
        (browser.parent as? LinearLayout)?.removeView(browser)
        browser.destroy()
        super.onDestroy()
    }
}
