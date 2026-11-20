import SwiftUI
import AuthenticationServices
import ProxyKit

/// ASWebAuthenticationSession sarmalayıcısı. Geri dönüş özel şema yerine dışarıdan
/// (Codex için localhost:1455 dinleyicisi) yakalanabildiği için `cancel` açıkta.
@MainActor
final class WebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(_ url: URL, onClose: @escaping @MainActor () -> Void) {
        let s = ASWebAuthenticationSession(url: url, callback: .customScheme("cliproxy")) { _, _ in
            Task { @MainActor in onClose() }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    func cancel() { session?.cancel(); session = nil }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

struct GirisView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: OAuthProviderKind

    @State private var pkce = PKCE()
    @State private var pasted = ""
    @State private var working = false
    @State private var error: String?
    @State private var web = WebLogin()
    @State private var listener = OAuthCallbackListener()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(kind == .claude ? claudeHelp : codexHelp).font(.callout)
                    Button {
                        startBrowser()
                    } label: { Label("Giriş sayfasını aç", systemImage: "safari") }
                } header: { Text(kind.title) }

                Section(kind == .claude ? "Sayfanın verdiği kod" : "Otomatik yakalanmazsa: dönüş adresi") {
                    TextField(kind == .claude ? "kod#durum" : "http://localhost:1455/auth/callback?code=…", text: $pasted, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await finish(pasted) }
                    } label: { HStack { Text("Girişi tamamla"); Spacer(); if working { ProgressView() } } }
                    .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty || working)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.callout) } }
            }
            .navigationTitle("Hesap ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { close() } } }
        }
        .onDisappear { listener.stop(); web.cancel() }
    }

    var claudeHelp: String {
        "Claude sayfasında giriş yapıp izin verin. Sayfa bir kod gösterecek; kodu kopyalayın, tarayıcıyı kapatın ve aşağıya yapıştırın."
    }
    var codexHelp: String {
        "ChatGPT hesabınızla giriş yapın. Giriş bitince uygulama dönüşü kendiliğinden yakalar. \"Bağlanılamıyor\" sayfası görürseniz adres çubuğundaki adresi kopyalayıp aşağıya yapıştırın."
    }

    func startBrowser() {
        error = nil
        if kind == .claude {
            web.open(OAuthClient.claudeAuthorizeURL(pkce)) {}
        } else {
            do {
                try listener.start { url in
                    Task { @MainActor in
                        web.cancel()
                        await finish(url.absoluteString)
                    }
                }
            } catch {
                self.error = "1455 portu açılamadı: \(error.localizedDescription). Dönüş adresini elle yapıştırabilirsiniz."
            }
            web.open(OAuthClient.codexAuthorizeURL(pkce)) {}
        }
    }

    func finish(_ raw: String) async {
        working = true
        defer { working = false }
        let client = OAuthClient(transport: URLSessionTransport())
        do {
            let account: OAuthAccount
            if kind == .claude {
                let (code, state) = OAuthClient.parseClaudeCode(raw)
                account = try await client.exchangeClaude(code: code, state: state, pkce: pkce)
            } else {
                let code = try OAuthClient.parseCodexCallback(raw, expectedState: pkce.state)
                account = try await client.exchangeCodex(code: code, pkce: pkce)
            }
            await model.addAccount(account)
            close()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func close() {
        listener.stop()
        web.cancel()
        dismiss()
    }
}
