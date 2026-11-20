import SwiftUI
import ProxyKit

struct HesaplarView: View {
    @Environment(AppModel.self) private var model
    @State private var login: OAuthProviderKind?

    var body: some View {
        List {
            ForEach(OAuthProviderKind.allCases, id: \.self) { kind in
                let accounts = model.state.oauth.filter { $0.provider == kind }
                if !accounts.isEmpty {
                    Section(kind.title) {
                        ForEach(accounts) { a in
                            NavigationLink { HesapDetay(qualifiedId: a.qualifiedId) } label: { HesapSatiri(account: a) }
                        }
                    }
                }
            }

            Section("API anahtarlı sağlayıcılar") {
                if model.state.apiProviders.isEmpty { Text("Henüz yok — sunucudan paket aktarın").foregroundStyle(.secondary) }
                ForEach(model.state.apiProviders) { p in
                    NavigationLink { SaglayiciDetay(name: p.name) } label: {
                        HStack {
                            Image(systemName: p.kind == .anthropic ? "a.circle" : p.baseURL.contains("google") ? "sparkles" : "key.horizontal")
                                .foregroundStyle(p.enabled ? Color.accentColor : .secondary).frame(width: 26)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.body.weight(.medium))
                                Text("\(p.models.count + p.aliases.count) model · \(p.kind.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !p.enabled { Text("Kapalı").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }

            Section {
                Button { login = .claude } label: { Label("Claude hesabıyla giriş yap", systemImage: "plus.circle") }
                Button { login = .codex } label: { Label("ChatGPT hesabıyla giriş yap", systemImage: "plus.circle") }
            } header: { Text("Telefonda yeni giriş") } footer: {
                Text("Telefonda giriş yapılan hesabın yenilemesini telefon yapar. Sunucudan taşınan hesaplar varsayılan olarak sunucu tarafından yenilenir, böylece iki taraf birbirinin oturumunu düşürmez.")
            }
        }
        .navigationTitle("Hesaplar")
        .refreshable { await model.syncNow() }
        .sheet(item: $login) { kind in GirisView(kind: kind) }
    }
}

extension OAuthProviderKind: @retroactive Identifiable { public var id: String { rawValue } }

struct HesapSatiri: View {
    @Environment(AppModel.self) private var model
    let account: OAuthAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(account.enabled ? Color.accentColor : .secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(account.label).font(.body.weight(.medium)).lineLimit(1)
                    if let plan = account.metadata["plan"] {
                        Text(plan.uppercased()).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: .capsule)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(account.lastError == nil ? Color.secondary : Color.red).lineLimit(2)
            }
            Spacer()
            if !account.enabled { Text("Kapalı").font(.caption).foregroundStyle(.secondary) }
        }
    }

    var icon: String {
        switch account.provider { case .claude: "asterisk"; case .codex: "circle.hexagongrid"; case .gemini: "sparkles"; case .antigravity: "airplane.up.right" }
    }

    var subtitle: String {
        if let e = account.lastError { return e }
        var parts: [String] = [account.refreshOwner == .sunucu ? "Sunucu yeniler" : "Telefon yeniler"]
        if let exp = account.expiresAt { parts.append(exp < Date() ? "süresi doldu" : "geçerli: \(exp.kisaGoreli)") }
        let cd = model.records.first { $0.route.hasPrefix(account.provider == .claude ? "Claude" : "Codex") }
        if let cd, cd.status == 429 { parts.append("son istek: kullanım sınırı") }
        return parts.joined(separator: " · ")
    }
}

struct HesapDetay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let qualifiedId: String
    @State private var testResult: String?
    @State private var testing = false
    @State private var confirmPhoneOwner = false

    var account: OAuthAccount? { model.state.oauth.first { $0.qualifiedId == qualifiedId } }

    var body: some View {
        if let a = account {
            Form {
                Section {
                    LabeledContent("Sağlayıcı", value: a.provider.title)
                    LabeledContent("Kimlik", value: a.id)
                    if let e = a.metadata["email"] { LabeledContent("E-posta", value: e) }
                    if let p = a.metadata["plan"] { LabeledContent("Plan", value: p) }
                    if let exp = a.expiresAt { LabeledContent("Erişim belirteci", value: exp < Date() ? "süresi doldu" : "geçerli, \(exp.kisaGoreli)") }
                    Toggle("Etkin", isOn: Binding(get: { a.enabled }, set: { v in
                        model.update { s in if let i = s.oauth.firstIndex(where: { $0.qualifiedId == qualifiedId }) { s.oauth[i].enabled = v } }
                    }))
                }
                if a.provider == .antigravity {
                    Section {
                        Text("Claude Opus/Sonnet 5.5, Gemini 3.x Flash ve GPT-OSS bu hesaptan doğrudan telefondan çağrılır. Gemini 4 Argon, Gemini 3.1 Pro ve görsel üretim yalnız sunucudaki Antigravity CLI'de var; oraya yönlendirilir. Google yenileme belirtecini değiştirmediği için telefon yenilemesi sunucuyu etkilemez.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if a.provider == .gemini {
                    Section {
                        Text("Gemini OAuth (Code Assist) hesabı sunucuda da kapalı. Telefonda saklanır; Gemini modelleri API anahtarıyla ya da sunucu üzerinden çalışır.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Yenilemeyi yapan", selection: Binding(get: { a.refreshOwner }, set: { v in
                        // Döndüren sağlayıcıda telefona geçmek sunucudaki oturumu düşürür: onay iste.
                        if v == .telefon && a.provider.rotatesRefreshToken { confirmPhoneOwner = true } else { model.setOwner(a, v) }
                    })) {
                        Text("Sunucu").tag(RefreshOwner.sunucu)
                        Text("Telefon").tag(RefreshOwner.telefon)
                    }
                    .pickerStyle(.segmented)
                    .disabled(a.refreshToken == nil)
                } header: { Text("Yenileme sahibi") } footer: {
                    Text(!a.provider.rotatesRefreshToken
                         ? "Bu sağlayıcı yenileme belirtecini değiştirmez: telefon kendisi yeniler, sunucudaki kopya etkilenmez."
                         : a.refreshOwner == .sunucu
                         ? "Telefon güncel erişim belirtecini sunucudan çeker. Sunucudaki Ders Video ve öbür servisler etkilenmez."
                         : "Telefon bu hesabı kendisi yeniler. Claude ve OpenAI yenileme belirtecini döndürdüğü için sunucudaki kopya bir sonraki yenilemede düşer; sunucuda bu hesabı kapatın ya da yalnız telefonda kullanın.")
                }
                Section {
                    Button {
                        Task { await model.refresh(a) }
                    } label: { Label(a.refreshOwner == .sunucu ? "Sunucudan şimdi güncelle" : "Şimdi yenile", systemImage: "arrow.clockwise") }
                    Button {
                        Task { await test(a) }
                    } label: { HStack { Label("Kısa bir istekle sına", systemImage: "checkmark.seal"); Spacer(); if testing { ProgressView() } } }
                    .disabled(testing || !a.enabled)
                    if let t = testResult { Text(t).font(.footnote.monospaced()).textSelection(.enabled) }
                    if let e = a.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Button("Hesabı telefondan kaldır", role: .destructive) { model.removeAccount(a); dismiss() }
                }
            }
            .navigationTitle(a.label)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Yenilemeyi telefon mu yapsın?", isPresented: $confirmPhoneOwner, titleVisibility: .visible) {
                Button("Telefona geç", role: .destructive) { model.setOwner(a, .telefon) }
            } message: {
                Text("\(a.provider.title) yenileme belirtecini her yenilemede değiştirir. Telefon yenilediğinde sunucudaki bu hesap (Ders Video, İkra'nın sunucu yolu) çalışmayı bırakır. Yalnız hesabı sunucuda kapattıysanız geçin.")
            }
        } else {
            ContentUnavailableView("Hesap bulunamadı", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    func test(_ a: OAuthAccount) async {
        testing = true
        defer { testing = false }
        let modelId = switch a.provider { case .claude: "claude-haiku-4-5"; case .antigravity: "antigravity-claude-sonnet-5-5"; default: "gpt-6-astra" }
        let t0 = Date()
        let body = #"{"model":"\#(modelId)","max_tokens":20,"messages":[{"role":"user","content":"Sadece 'tamam' yaz."}]}"#
        let r = await model.engine.handle(ProxyRequest(method: "POST", path: "/v1/chat/completions",
                                                       headers: ["authorization": "Bearer \(model.state.localKey)"], body: Data(body.utf8)))
        var d = Data()
        do { for try await c in r.body { d.append(c) } } catch {}
        let j = try? JSON.parse(d)
        let text = j?["choices"]?[0]?["message"]?["content"]?.string ?? j?["error"]?["message"]?.string ?? String(decoding: d.prefix(200), as: UTF8.self)
        let route = await model.log.records.first?.route ?? "-"
        testResult = "\(r.status) · \(Int(Date().timeIntervalSince(t0) * 1000)) ms · \(route)\n\(text)"
    }
}

struct SaglayiciDetay: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        if let p = model.state.apiProviders.first(where: { $0.name == name }) {
            Form {
                Section {
                    LabeledContent("Tür", value: p.kind.title)
                    LabeledContent("Adres", value: p.baseURL).font(.footnote)
                    CopyRow(title: "API anahtarı", value: p.apiKey, secret: true)
                    Toggle("Etkin", isOn: Binding(get: { p.enabled }, set: { v in
                        model.update { s in if let i = s.apiProviders.firstIndex(where: { $0.name == name }) { s.apiProviders[i].enabled = v } }
                    }))
                }
                if !p.models.isEmpty {
                    Section("Modeller") { ForEach(p.models, id: \.self) { Text($0).font(.footnote.monospaced()) } }
                }
                if !p.aliases.isEmpty {
                    Section("Takma adlar") {
                        ForEach(p.aliases.keys.sorted(), id: \.self) { k in
                            LabeledContent(k, value: p.aliases[k] ?? "").font(.footnote.monospaced())
                        }
                    }
                }
            }
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
