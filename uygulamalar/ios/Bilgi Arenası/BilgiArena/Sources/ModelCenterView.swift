import SwiftUI

struct ModelCenterView: View {
    @EnvironmentObject var game: GameStore
    @State private var search = ""
    @State private var onlyText = true
    private var filtered: [PhoneModel] { game.models.filter { (!onlyText || $0.textCapable) && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) || $0.family.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(aqua); VStack(alignment: .leading, spacing: 5) { Text("Telefondaki hesapların").font(.headline); Text("\(game.inventory?.accountCount ?? 0) OAuth · \(game.inventory?.providerCount ?? 0) sağlayıcı").font(.caption).foregroundStyle(.secondary) } }
                    Label("iPhone → sağlayıcı", systemImage: "checkmark.shield.fill").foregroundStyle(aqua)
                    if let n = game.inventory?.expiringAccounts, n > 0 { Text("\(n) hesabın erişim belirteci yenilenmeli. CLI Proxy uygulamasında telefondan oturum aç; sunucu eşitlemesi bu uygulamada kapalıdır.").font(.caption).foregroundStyle(gold) }
                    Button("Hesapları ve modelleri yenile") { Task { await game.loadModels() } }.accessibilityIdentifier("refreshPhoneModels")
                } footer: { Text("CLI Proxy'nin ortak hesapları ve motoru uygulamanın içinde çalışır. İnternet, doğrudan model sağlayıcılarına erişmek için gerekir.") }
                Section("Model takımı") {
                    Toggle("Seçtiğim modeller sırayla soru üretsin", isOn: $game.teamEnabled).onChange(of: game.teamEnabled) { _, _ in game.persistSelection() }
                    if game.teamEnabled { Text("Aşağıdaki metin modellerinden takım seç. Her beş soruyu bir model hazırlar.").font(.caption).foregroundStyle(.secondary) }
                    Toggle("İkinci model ile soru kontrolü", isOn: $game.reviewEnabled).onChange(of: game.reviewEnabled) { _, _ in game.persistSelection() }
                    if game.reviewEnabled {
                        Picker("Denetçi", selection: $game.reviewer) { Text("Model seç").tag(""); ForEach(game.availableText) { Text($0.id).tag($0.id) } }.onChange(of: game.reviewer) { _, _ in game.persistSelection() }
                        Text("Denetçi, üretim takımından ayrı tutulur. Kontrol hatalı soruları azaltabilir; kaynak doğrulaması yerine geçmez.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if let current = game.checkingModel {
                        Text("\(game.auditProgress) · \(current)").font(.caption)
                        Button("Model testini durdur") { game.cancelAudit() }.foregroundStyle(gold)
                    } else { Button("Tüm metin modellerini gerçek istekle test et") { game.auditModels() }.accessibilityIdentifier("auditAllModels") }
                    Toggle("Yalnız soru üretebilen modeller", isOn: $onlyText)
                } footer: { Text("Listede görünmek kullanılabilir kota kanıtı değildir. Test, her modele küçük bir gerçek istek gönderir; sonuçlar ölçüm tarihine aittir.") }
                ForEach(Array(Set(filtered.map(\.family))).sorted(), id: \.self) { family in
                    Section(family) {
                        ForEach(filtered.filter { $0.family == family }) { model in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button {
                                        guard model.textCapable else { return }
                                        if game.teamEnabled { if game.teamModels.contains(model.id) { game.teamModels.remove(model.id) } else { game.teamModels.insert(model.id) } }
                                        else { game.selectedModel = model.id }
                                        game.persistSelection()
                                    } label: {
                                        HStack { Image(systemName: (game.teamEnabled ? game.teamModels.contains(model.id) : game.selectedModel == model.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(aqua); Text(model.id).font(.subheadline).foregroundStyle(.primary); Spacer() }
                                    }.buttonStyle(.plain).disabled(!model.textCapable)
                                    if model.textCapable { Button { game.auditModels(ids: [model.id]) } label: { Image(systemName: "waveform.path.ecg") }.disabled(game.checkingModel != nil).accessibilityLabel("\(model.id) bağlantısını test et") }
                                }
                                if let check = game.checks[model.id] {
                                    HStack { Image(systemName: check.success ? "checkmark.seal.fill" : "exclamationmark.circle.fill").foregroundStyle(check.success ? aqua : gold); Text(check.status).lineLimit(2); Spacer(); Text("\(check.milliseconds / 1000) sn"); Text(check.date, style: .time) }.font(.caption2).foregroundStyle(.secondary)
                                } else { Text(model.textCapable ? "Henüz test edilmedi" : "Metin sorusu üretimi için uygun olmayan yetenek").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 5)
                        }
                    }
                }
                if game.models.isEmpty { Section { Text("CLI Proxy uygulamasında bir hesap bağla ve buradan yenile.").foregroundStyle(.secondary) } }
            }.scrollContentBackground(.hidden).background(ArenaBackdrop()).navigationTitle("Model Merkezi").searchable(text: $search, prompt: "Model veya aile ara").tint(aqua)
        }
    }
}

struct CoachPanel: View {
    @EnvironmentObject var game: GameStore
    @State private var prompt = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Öğrenme koçu", systemImage: "sparkles").font(.headline).foregroundStyle(aqua)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(["Daha basit anlat", "Bir örnek ver", "Nasıl aklımda tutarım?"], id: \.self) { text in Button(text) { game.askCoach(text) }.font(.caption.bold()).padding(9).background(ink, in: Capsule()) } }
            }.disabled(game.coachLoading)
            HStack { TextField("Bu konuda neyi merak ediyorsun?", text: $prompt).font(.subheadline); Button { game.askCoach(prompt); prompt = "" } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || game.coachLoading) }
            if game.coachLoading { ProgressView("Koç yanıtlıyor…").font(.caption) }
            if !game.coachAnswer.isEmpty { Text(game.coachAnswer).font(.subheadline).textSelection(.enabled) }
        }.padding(17).arenaPanel(tint:aqua,radius:22)
    }
}
