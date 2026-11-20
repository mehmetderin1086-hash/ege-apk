import SwiftUI

// Tek ses seçici: uygulamadaki bütün sesler gruplar hâlinde (sunucu sesleri, Chirp 3 HD, iPhone) örnek dinlemeli listelenir.
// Ayarlar'daki "Ses" bölümü ve modüllerin ses satırları (yeni podcast, hızlı ayar, soru anlatımı, konu videosu, sesi yeniden üret)
// aynı listeyi açar; seçim `AppVoice` anahtarlarına yazılır ya da (yerel seçimde) verilen bağlamaya.

struct AppVoiceEntry: Identifiable, Hashable, Sendable {
    let key: QSVoiceKey
    let title: String
    let detail: String
    var id: String { key.raw }
}

struct AppVoiceGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let footer: String
    let entries: [AppVoiceEntry]
}

extension AppVoice {
    /// Seçicideki gruplar. SesLab sesleri sunucunun bildirdiği her motor için ayrı grup (XTTS önce); liste alınmamışsa boş grup
    /// açıklamasıyla. Cihaz içi sinir ağı motorları (Supertonic, Piper) yalnız modeli inmişse listelenir.
    @MainActor static func groups() -> [AppVoiceGroup] {
        var groups: [AppVoiceGroup] = [AppVoiceGroup(id: "azure", title: "Azure HD · Asistan sesleri", footer: "Asistan uygulamasındaki Türkçe sesler. İnternet bağlantısı gerekir.", entries: [
            AppVoiceEntry(key: QSVoiceKey(azure: "Elif"), title: "Elif", detail: "Kadın · Azure HD"),
            AppVoiceEntry(key: QSVoiceKey(azure: "Aydın"), title: "Aydın", detail: "Erkek · Azure HD")
        ])]
        let xtts = QSXttsVoices.shared
        let seslabEngines = QSVoiceKey.Engine.allCases.filter { $0.isSeslab && xtts.engines.contains($0.rawValue) }
        for engine in seslabEngines.isEmpty ? [.xtts] : seslabEngines {
            let entries = xtts.voices.map { voice in
                AppVoiceEntry(key: QSVoiceKey(seslab: engine, id: voice.id), title: voice.name,
                              detail: engine == .xtts ? (voice.cloned == true ? "Referans kaydından klon" : "Eğitilmiş ses · XTTS-v2") : "\(QSSeslabNote.source(engine)) klon · \(QSSeslabNote.model(engine))")
            }
            let footer = entries.isEmpty ? "Sunucudaki sesler bağlantı kurulunca listelenir."
                : QSSeslabNote.text(engine, mac: xtts.mac) ?? "Sesler sunucuda (SesLab, XTTS-v2) üretilir; kota harcamaz. Örnek, sesin hazır önizlemesi ya da eğitimde kullanılan kaydıdır."
            groups.append(AppVoiceGroup(id: engine.rawValue, title: "Sunucu sesleri · " + QSSeslabNote.model(engine) + (xtts.macEngines.contains(engine.rawValue) ? " · Mac" : ""), footer: footer, entries: entries))
        }
        groups.append(AppVoiceGroup(id: "chirp", title: "Google Chirp 3 HD",
                                    footer: "İnternet ve Google Cloud kotası kullanır. Ayarlar'daki “Okunuşları Claude hazırlasın” açıksa Claude önce formül, simge ve kısaltmaların okunuşunu hazırlar.",
                                    entries: VoiceOption.all.map { AppVoiceEntry(key: QSVoiceKey(name: $0.id, chirp: .chirp), title: $0.id, detail: $0.trait) }))
        var local: [AppVoiceEntry] = QSLocalVoices.options(.apple).map {
            AppVoiceEntry(key: QSVoiceKey(local: .apple, voice: $0.id), title: "Apple · \($0.title)", detail: DeviceSpeech.qualityDescription(speaker: $0.id == "M" ? .b : .a))
        }
        // Bütün iPhone sesleri her zaman listelenir (kullanıcı kararı, 17 Eki 2026); modeli inmemiş olan seçilince indirme başlar.
        for engine in QSLocalVoices.engines where engine != .apple {
            guard let speech = engine.speech else { continue }
            let state = OfflineSpeechModels.shared.state(speech)
            let detail = state.ready ? "iPhone’da üretilir, kota harcamaz"
                : state.downloading ? "Model indiriliyor · %\(Int(state.progress * 100))"
                : "Model indirilmemiş · \(OfflineModelCatalog.sizeLabel(speech)) · seçince indirme başlar"
            local += QSLocalVoices.options(engine).map { AppVoiceEntry(key: QSVoiceKey(local: engine, voice: $0.id), title: "\(speech.title.components(separatedBy: " ·").first ?? speech.title) · \($0.title)", detail: detail) }
        }
        groups.append(AppVoiceGroup(id: "iphone", title: "iPhone", footer: "Ses telefonda üretilir; internet ve kota gerekmez. Daha doğal Apple sesi için iPhone Ayarlar → Erişilebilirlik → Seslendirilen İçerik → Sesler’den Türkçe “Geliştirilmiş” ya da “Premium” ses indir.", entries: local))
        return groups
    }

    /// Satırda görünen ad: "Kore — Kararlı", "Müşfik · XTTS-v2", "Apple · Kadın".
    @MainActor static func title(_ key: QSVoiceKey) -> String {
        switch key.engine {
        case .azure: key.name + " · Azure HD"
        case .chirp, .claude: VoiceOption.title(key.name) + (key.engine == .claude ? " · Claude okunuşlu" : "")
        case .xtts, .chatterbox, .voxcpm, .trendyol: QSXttsVoices.shared.name(of: key.seslabID ?? "") + " · " + QSSeslabNote.model(key.engine)
        case .apple, .supertonic, .piper, .ema:
            (key.engine.speech?.title.components(separatedBy: " ·").first ?? key.engine.rawValue) + " · " + (QSLocalVoices.options(key.engine).first { $0.id == key.localVoice }?.title ?? key.localVoice ?? "")
        case .legacy: key.name + " · Önceki kayıt"
        }
    }
}

/// Form satırı: seçili sesi gösterir, dokununca bütün seslerin listesini açar. `raw`: `QSVoiceKey.raw`.
struct AppVoiceRow: View {
    let title: String
    @Binding var raw: String
    /// Listede gösterilmeyecek sesler (öbür konuşmacının sesi); seçili olan hep görünür.
    var excluded: [String] = []
    /// Yalnız bu motorun sesleri listelenir (ikinci ses anlatıcıyla aynı motordan olmalı: bir senaryo tek sağlayıcıdan seslendirilir).
    var onlyEngine: QSVoiceKey.Engine? = nil
    var body: some View {
        NavigationLink { AppVoicePickerList(title: title, raw: $raw, excluded: excluded, onlyEngine: onlyEngine) } label: {
            LabeledContent(title, value: AppVoice.title(QSVoiceKey(raw)))
        }
        .accessibilityHint("Bütün sesleri dinleyip seçmek için dokun")
    }
}

/// Ayarlar'daki tek ses ayarına bağlı satır (bütün modüller bunu kullanır).
struct AppVoiceSettingRow: View {
    enum Slot { case primary, secondary }
    let title: String
    let slot: Slot
    @AppStorage(AppVoice.primaryKey) private var primaryRaw = ""
    @AppStorage(AppVoice.secondaryKey) private var secondaryRaw = ""
    var body: some View {
        // Birincil satır hiçbir sesi dışlamaz (ikinci ses gerekirse yeniden türetilir); ikinci satır birincilin motoruna sınırlıdır.
        let primary = AppVoice.usable(primaryRaw) ?? AppVoice.primaryChoice()
        let secondary = AppVoice.partner(AppVoice.usable(secondaryRaw), avoiding: primary)
        AppVoiceRow(title: title, raw: Binding(
            get: { slot == .primary ? primary.raw : secondary.raw },
            set: { if slot == .primary { primaryRaw = $0 } else { secondaryRaw = $0 } }),
            excluded: slot == .secondary ? [primary.raw] : [], onlyEngine: slot == .secondary ? primary.engine : nil)
    }
}

struct AppVoicePickerList: View {
    let title: String
    @Binding var raw: String
    var excluded: [String] = []
    var onlyEngine: QSVoiceKey.Engine? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var samples = VoicePreview.shared
    @State private var seslab = QSXttsPreviewPlayer.shared
    @State private var xtts = QSXttsVoices.shared
    @State private var offline = OfflineVoicePreview.shared
    @State private var offlineModels = OfflineSpeechModels.shared
    @State private var groups: [AppVoiceGroup] = []

    private var selected: String { AppVoice.usable(raw)?.raw ?? raw }

    var body: some View {
        List {
            ForEach(groups.filter { group in onlyEngine.map { engine in group.entries.contains { $0.key.engine == engine } } ?? true }) { group in
                Section {
                    ForEach(group.entries.filter { (onlyEngine == nil || $0.key.engine == onlyEngine) && (!excluded.contains($0.key.raw) || $0.key.raw == selected) }) { entry in row(entry) }
                } header: { Text(group.title) } footer: { Text(group.footer) }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { groups = AppVoice.groups(); await xtts.load(force: xtts.voices.isEmpty); groups = AppVoice.groups() }
        // İndirme ekranından dönüldüğünde yeni inen model hemen listeye girsin.
        .onAppear { offlineModels.refresh(); groups = AppVoice.groups() }
        .onChange(of: offlineModels.states) { groups = AppVoice.groups() }
        .onChange(of: xtts.voices) { groups = AppVoice.groups() }
        .onLeave { samples.stop(); seslab.stop(); offline.stop() }
    }

    @ViewBuilder private func row(_ entry: AppVoiceEntry) -> some View {
        HStack(spacing: 12) {
            preview(entry)
            Button {
                raw = entry.key.raw; samples.stop(); seslab.stop(); offline.stop()
                // Modeli inmemiş iPhone sesi: indirme hemen başlar (ilerleme Ayarlar › iPhone ses modelleri'nde ve bu listede görünür).
                if let speech = entry.key.engine.speech, speech.isNeuralOnDevice, !offlineModels.state(speech).ready { offlineModels.download(speech) }
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                        Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.key.raw == selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.title), \(entry.detail)")
            .accessibilityAddTraits(entry.key.raw == selected ? .isSelected : [])
        }
    }

    /// Örnek: Chirp'te gömülü örnek, SesLab'da sunucudaki önizleme, Supertonic/Piper'da telefonda üretilen kısa cümle; Apple'da yok.
    @ViewBuilder private func preview(_ entry: AppVoiceEntry) -> some View {
        let key = entry.key
        if key.engine == .chirp {
            Button { samples.play(key.name) } label: { Image(systemName: samples.playing == key.name ? "stop.circle.fill" : "play.circle.fill").font(.title2).frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(samples.playing == key.name ? "\(entry.title) örneğini durdur" : "\(entry.title) örneğini dinle")
        } else if let id = key.seslabID {
            Button { seslab.toggle(id, engine: key.engine) } label: {
                if seslab.loading == id { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: seslab.playing == id ? "stop.circle.fill" : "play.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }
            .buttonStyle(.borderless).accessibilityLabel(seslab.playing == id ? "\(entry.title) örneğini durdur" : "\(entry.title) örneğini dinle")
        } else if let speech = key.engine.speech, speech.isNeuralOnDevice, let voice = key.localVoice {
            let id = "appvoice:" + key.raw
            Button { offline.play(id: id, engine: speech, voice: voice) } label: {
                if offline.activeID == id, offline.preparing { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: offline.activeID == id ? "stop.circle.fill" : "play.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }
            .buttonStyle(.borderless).accessibilityLabel(offline.activeID == id ? "\(entry.title) örneğini durdur" : "\(entry.title) örneğini dinle")
        } else {
            Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary).frame(width: 44, height: 44)
        }
    }
}

/// Ayarlar › Ses: uygulamanın tek ses ayarı.
struct VoiceSettingsSection: View {
    @AppStorage(AppVoice.claudeReadingsKey) private var claudeReadings = false
    @AppStorage(AppVoice.primaryKey) private var primaryRaw = ""
    var body: some View {
        Section {
            AppVoiceSettingRow(title: "Anlatıcı sesi", slot: .primary)
            AppVoiceSettingRow(title: "İkinci ses", slot: .secondary)
            if (AppVoice.usable(primaryRaw) ?? AppVoice.primaryChoice()).engine == .chirp {
                Toggle("Okunuşları Claude hazırlasın", isOn: $claudeReadings)
            }
        } header: { Text("Ses") } footer: {
            Text("Bu iki ses podcastte, soru anlatımında, konu videosunda ve MEB sırasında kullanılır. İkinci ses yalnız iki kişilik anlatımlarda (sohbet, öğretmen-öğrenci) konuşur ve anlatıcıyla aynı motordan seçilir." + ((AppVoice.usable(primaryRaw) ?? AppVoice.primaryChoice()).engine == .chirp ? " Claude okunuşları açıkken Claude her sahnedeki formül, simge ve kısaltmaların okunuşunu hazırlar; sesi yine Chirp üretir." : ""))
        }
    }
}
