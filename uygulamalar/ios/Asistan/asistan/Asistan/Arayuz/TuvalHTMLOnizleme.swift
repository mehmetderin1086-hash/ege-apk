import SwiftUI
import WebKit

/// Ağsız mini uygulama: kalıcı çerez, dosya yetkisi ve native mesaj köprüsü yoktur.
struct TuvalHTMLOnizleme: UIViewRepresentable {
    let html: String
    nonisolated static let politika = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
    nonisolated static func belge(_ html: String) -> String {
        "<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"\(politika)\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"></head><body>\(html)</body></html>"
    }
    func makeCoordinator() -> Bekci { Bekci() }
    func makeUIView(context: Context) -> WKWebView {
        let w = Self.gorunum()
        w.navigationDelegate = context.coordinator
        return w
    }
    static func gorunum() -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .nonPersistent()
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        let w = WKWebView(frame: .zero, configuration: c)
        w.isInspectable = false
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {
        guard context.coordinator.son != html else { return }
        context.coordinator.son = html
        w.loadHTMLString(Self.belge(html), baseURL: nil)
    }
    static func dismantleUIView(_ w: WKWebView, coordinator: Bekci) { w.stopLoading(); w.navigationDelegate = nil }
    @MainActor final class Bekci: NSObject, WKNavigationDelegate {
        var son: String?
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // loadHTMLString'in ilk about:blank yüklemesi dışında gezinme yoktur.
            decisionHandler(navigationAction.navigationType == .other && url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}
