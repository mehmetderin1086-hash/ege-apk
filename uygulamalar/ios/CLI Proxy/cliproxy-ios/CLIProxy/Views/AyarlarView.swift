import SwiftUI
import UniformTypeIdentifiers
import ProxyKit

struct AyarlarView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var confirmReset = false

    var body: some View {
        let r = model.state.remote
        Form {
            Section {
                TextField("Taban adres (…/v1)", text: bind(\.remote.baseURL))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                SecureField("Kişisel erişim belirteci (X-Personal-Token)", text: bind(\.remote.personalToken))
                SecureField("Eşitleme belirteci (X-Sync-Token)", text: bind(\.remote.syncToken))
                Toggle("Sunucu bağlantısı", isOn: bind(\.remote.enabled))
                Toggle("Telefon yolu hata verirse sunucuya düş", isOn: bind(\.remote.fallbackOnError)).disabled(!r.enabled)
            } header: { Text("Sunucudaki CLI Proxy") } footer: {
                Text("Telefonda çalışamayan modeller (Antigravity, Gemini Pro hesabı, Qwen, görsel üretim) bu adrese yönlendirilir. Eşitleme belirteci sunucu yenilemeli hesapların güncel erişim belirtecini almak için kullanılır.")
            }

            Section {
                Button { importing = true } label: { Label("Paket dosyasından içe aktar", systemImage: "square.and.arrow.down") }
                if let d = model.state.importedAt {
                    LabeledContent("Son aktarım", value: "\(d.kisaGoreli) · \(model.state.importSource ?? "")")
                }
            } header: { Text("Sunucudan taşıma") } footer: {
                Text("Paket sunucuda telefon-paketi.py ile üretilir. Mac'ten Finder > iPhone > Dosyalar > CLI Proxy klasörüne \"telefon-paketi.json\" bırakırsanız uygulama açılışta alır ve dosyayı siler.")
            }

            Section("İstemci anahtarları") {
                CopyRow(title: "Bu telefonun anahtarı", value: model.state.localKey, secret: true)
                Button("Yeni yerel anahtar üret") { model.regenerateLocalKey() }
                ForEach(model.state.clientKeys) { k in
                    Toggle(isOn: Binding(get: { k.enabled }, set: { v in
                        model.update { s in if let i = s.clientKeys.firstIndex(where: { $0.sha256 == k.sha256 }) { s.clientKeys[i].enabled = v } }
                    })) {
                        VStack(alignment: .leading) {
                            Text(k.name)
                            Text("sunucudan · yalnız özeti saklanır").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Yönlendirme (sunucudan)") {
                let router = ModelRouter(state: model.state)
                if model.state.routing.isEmpty { Text("Kural yok").foregroundStyle(.secondary) }
                ForEach(Array(model.state.routing.enumerated()), id: \.offset) { _, rule in
                    HStack {
                        Text(rule.pattern).font(.caption.monospaced())
                        Spacer()
                        let route = rule.pattern.contains("*") ? nil : router.resolve(rule.pattern)
                        Text(route.map(\.description) ?? rule.target).font(.caption)
                            .foregroundStyle(route == .remote ? Color.orange : Color.secondary)
                    }
                }
            }

            Section {
                Button("Telefondaki bütün hesapları ve ayarları sil", role: .destructive) { confirmReset = true }
            } footer: {
                Text("CLI Proxy 1.0 · sunucudaki CLI Proxy API 0.4.0 ile uyumlu").font(.caption2)
            }
        }
        .navigationTitle("Ayarlar")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { try await model.importBundle(Data(contentsOf: url)) }
                catch { model.show("Paket okunamadı: \(error.localizedDescription)", error: true) }
            }
        }
        .confirmationDialog("Bütün veriler silinsin mi?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { Task { await model.resetAll() } }
        } message: { Text("Hesaplar, anahtarlar ve kayıtlar telefondan kaldırılır. Sunucudaki hesaplar etkilenmez.") }
    }

    func bind<T: Sendable>(_ kp: WritableKeyPath<ProxyState, T> & Sendable) -> Binding<T> {
        Binding(get: { model.state[keyPath: kp] }, set: { v in
            model.state[keyPath: kp] = v
            model.update { $0[keyPath: kp] = v }
        })
    }
}
