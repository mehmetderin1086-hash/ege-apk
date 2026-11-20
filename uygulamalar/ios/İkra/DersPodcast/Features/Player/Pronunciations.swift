import SwiftUI

/// Telaffuz sözlüğü: "sklera" → "sk-le-ra" gibi. Tüm bölümlerde uygulanır: sunucu motorlarında sunucu,
/// cihaz içi motorlarda `SpeakableText.prepare` (metin motora verilmeden önce).
nonisolated struct Pronunciation: Codable, Hashable, Sendable, Identifiable {
    /// #12: Türkçe katlama (İyon/iyon/IYON aynı kayıt).
    var id: String { TurkishFold.fold(from.trimmingCharacters(in: .whitespaces)) }
    var from: String
    var to: String
}

nonisolated enum Pronunciations {
    static let key = "pronunciations.v1"

    /// Okurken eski (`lowercased()` kimlikli) sürümden kalan katlanmış kopyalar ayıklanır ve temiz liste geri yazılır:
    /// "İyon" ile "iyon" artık aynı kimlik; çift kalırsa liste satırları ve silme karışır, sunucuya iki kayıt gider.
    static var all: [Pronunciation] {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    static func save(_ list: [Pronunciation], to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(Array(deduplicated(list).prefix(storageLimit))), forKey: key)
    }

    static func load(from defaults: UserDefaults) -> [Pronunciation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoded = (try? JSONDecoder().decode([Pronunciation].self, from: data)) ?? []
        let clean = deduplicated(decoded)
        if clean.count != decoded.count { defaults.set(try? JSONEncoder().encode(clean), forKey: key) }
        return clean
    }

    /// Katlanmış anahtara göre ilk kayıt kalır (en yeni kayıt başta tutulur); kelimesi boş kayıtlar düşer.
    static func deduplicated(_ list: [Pronunciation]) -> [Pronunciation] {
        var seen = Set<String>()
        return list.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    /// Sağlayıcıların istek sınırı değişmez; kişisel arşivin tamamı her isteğe gönderilmez.
    static let limit = 40
    static let storageLimit = 512
    /// Sunucu sınırları (`replacementsSchema`, `pronunciation-suggest` `known[]`): UTF-16 birimiyle sayılır.
    static let maxFromLength = 60
    static let maxToLength = 120

    static func set(_ from: String, _ to: String) {
        all = updated(all, from: from, to: to, maximum: storageLimit)
    }

    /// Katlanmış anahtara göre kaydı değiştirir (boş `to` siler); yeni kayıt başa gelir. Kelime 60, okunuş 120
    /// karaktere kırpılır. Sözlük doluyken YENİ kelime eklenmez (eski kayıt sessizce düşmesin); güncelleme yapılır.
    static func updated(_ list: [Pronunciation], from: String, to: String, maximum: Int = limit) -> [Pronunciation] {
        let word = clipped(from.trimmingCharacters(in: .whitespacesAndNewlines), to: maxFromLength)
        guard !word.isEmpty else { return list }
        let key = TurkishFold.fold(word)
        let spoken = clipped(to, to: maxToLength)
        let exists = list.contains { $0.id == key }
        let removing = spoken.trimmingCharacters(in: .whitespaces).isEmpty
        guard exists || removing || list.count < maximum else { return list }
        var list = list.filter { $0.id != key }
        if !removing { list.insert(Pronunciation(from: word, to: spoken), at: 0) }
        return Array(list.prefix(maximum))
    }

    /// Yeni kelime eklenebilir mi (dolu sözlükte yalnız mevcut kayıt güncellenir).
    static func canAdd(_ word: String, to list: [Pronunciation], maximum: Int = limit) -> Bool {
        list.count < maximum || entry(for: word, in: list) != nil
    }

    /// Yazılmış ama "Kaydet"e basılmamış kayıt: kelime de okunuş da doluysa ve sözlüğe girebiliyorsa kırpılmış çift.
    static func pending(word: String, spoken: String, list: [Pronunciation], maximum: Int = limit) -> (from: String, to: String)? {
        let from = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, canAdd(from, to: list, maximum: maximum) else { return nil }
        return (from, to)
    }

    /// Sunucunun kabul ettiği kayıt mı (kırpılmış kelime boş değil, sınırlar içinde).
    static func isValid(_ entry: Pronunciation) -> Bool {
        let word = entry.from.trimmingCharacters(in: .whitespacesAndNewlines)
        return !word.isEmpty && word.utf16.count <= maxFromLength && entry.to.utf16.count <= maxToLength
    }

    /// Metni UTF-16 uzunluğu `max`'ı aşmayacak şekilde karakter sınırından keser.
    static func clipped(_ text: String, to max: Int) -> String {
        guard text.utf16.count > max else { return text }
        var result = ""
        var length = 0
        for character in text {
            let size = character.utf16.count
            if length + size > max { break }
            result.append(character)
            length += size
        }
        return result
    }

    /// Katlanmış eşleşmeyle kayıt (yoksa nil).
    static func entry(for word: String, in list: [Pronunciation] = all) -> Pronunciation? {
        let key = TurkishFold.fold(word.trimmingCharacters(in: .whitespaces))
        return list.first { $0.id == key }
    }

    /// Yalnız sunucunun kabul edeceği kayıtlar gider (tek bozuk kayıt tüm seslendirmeleri 400'e düşürmesin).
    /// `extra`: bu isteğe özel okunuşlar ("Claude + Chirp"in sahne için hazırladıkları); kullanıcının kayıtlarından sonra gelir.
    static func attach(to request: TTSRequest, adding extra: [Pronunciation] = [], user: [Pronunciation] = all) -> TTSRequest {
        var r = request
        // Boş turla sözlüğü sorgulayan eski çağrılar korunur; gerçek ses isteğinde yalnız o sahnedeki ifadeler seçilir.
        let list = request.turns.isEmpty
            ? Array(deduplicated((user + extra + QSSpokenDefaults.list).filter(isValid)).prefix(limit))
            : selected(for: request.turns.map(\.text), user: user, adding: extra)
        r.replacements = list.isEmpty ? nil : list
        return r
    }

    /// Önce eşleşme, sonra 40 sınırı: 512. kişisel kayıt da metinde geçiyorsa seslendirmeye katılır.
    /// Öncelik kişisel > bu sahneye özel > varsayılan. Tur sınırından birleşik ifade üretilmez.
    /// Yerel motor, sunucu isteği ve sahne önbellek sözleşmesi aynı seçimi kullanır.
    static func selected(for texts: [String], user: [Pronunciation] = all,
                         adding extra: [Pronunciation] = [], defaults: [Pronunciation] = QSSpokenDefaults.list) -> [Pronunciation] {
        let candidates = deduplicated((user + extra + defaults).filter(isValid))
        return Array(SpeakableText.matchingEntries(in: texts, dictionary: candidates).prefix(limit))
    }

    /// Kullanıcının kayıtlarına isteğe özel okunuşları ekler: aynı sözcükte kullanıcının kaydı kalır, liste sunucu sınırını aşmaz.
    static func merged(_ own: [Pronunciation], with extra: [Pronunciation]) -> [Pronunciation] {
        guard !extra.isEmpty else { return own }
        return Array(deduplicated(own + extra.filter(isValid)).prefix(limit))
    }

    /// Sunucuya gidecek kayıtlar: geçerli olanlar, en çok `limit`.
    static func sanitized(_ list: [Pronunciation]) -> [Pronunciation] { Array(list.filter(isValid).prefix(limit)) }

    /// Turdaki kelimeler (noktalama atılır, tekrarsız, 3+ harf).
    static func words(in text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }).map(String.init)
            .filter { $0.count >= 3 && seen.insert(TurkishFold.fold($0)).inserted }
    }
}

struct PronunciationEditor: View {
    @Environment(\.dismiss) private var dismiss
    var text: String
    /// Kaydedince bu sahneyi yeniden seslendir (isteğe bağlı).
    var onRegenerate: (() async throws -> Void)? = nil
    @State private var word = ""
    @State private var regenerating = false
    @State private var error: String?
    @State private var spoken = ""
    @State private var list = Pronunciations.all
    @State private var speech = SpeechOut()

    private var full: Bool { list.count >= Pronunciations.storageLimit }
    /// Sözlük dolu ve yazılan kelime mevcut bir kaydın güncellemesi değil.
    private var blocked: Bool { !word.isEmpty && !Pronunciations.canAdd(word, to: list, maximum: Pronunciations.storageLimit) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Pronunciations.words(in: text), id: \.self) { w in
                                Button(w) { word = w; spoken = list.first { $0.id == TurkishFold.fold(w) }?.to ?? "" }
                                    .buttonStyle(.bordered).controlSize(.small).tint(w == word ? .accentColor : .gray)
                            }
                        }
                    }
                    TextField("Kelime", text: $word)
                        .onChange(of: word) { _, value in
                            let clipped = Pronunciations.clipped(value, to: Pronunciations.maxFromLength)
                            if clipped != value { word = clipped }
                        }
                    TextField("Nasıl okunsun? (örn. sık-le-ra)", text: $spoken)
                        .onChange(of: spoken) { _, value in
                            let clipped = Pronunciations.clipped(value, to: Pronunciations.maxToLength)
                            if clipped != value { spoken = clipped }
                        }
                    HStack {
                        Button("Dinle", systemImage: "speaker.wave.2") { Task { await speech.speak(spoken.isEmpty ? word : spoken) } }
                            .disabled(word.isEmpty)
                        Spacer()
                        Button("Kaydet") {
                            Pronunciations.set(word, spoken)
                            list = Pronunciations.all
                            word = ""; spoken = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty || spoken.trimmingCharacters(in: .whitespaces).isEmpty || blocked)
                    }
                } header: {
                    Text("Yanlış okunan kelimeyi seç")
                } footer: {
                    if full {
                        Text("Sözlük dolu (\(Pronunciations.storageLimit)/\(Pronunciations.storageLimit)). Yeni kelime eklemek için aşağıdan bir kaydı sola kaydırıp sil; var olan kelimenin okunuşunu güncelleyebilirsin.")
                            .foregroundStyle(blocked ? Color.red : Color.secondary)
                    } else {
                        Text("512 kişisel okunuş saklanabilir. Yeni üretilen seslerde, metinde geçen kayıtlar uygulanır. Bu bölüm için ⋯ → Sesi yeniden üret.")
                    }
                }
                if let onRegenerate, !list.isEmpty {
                    Section {
                        Button {
                            // Yazılıp kaydedilmemiş kelime önce sözlüğe girer: sahne eski okunuşla seslendirilip
                            // (kota harcanıp) yazılan kayıt kaybolmasın.
                            if let p = Pronunciations.pending(word: word, spoken: spoken, list: list, maximum: Pronunciations.storageLimit) {
                                Pronunciations.set(p.from, p.to)
                                list = Pronunciations.all
                                word = ""; spoken = ""
                            }
                            Task {
                                regenerating = true; error = nil
                                do { try await onRegenerate(); dismiss() } catch { self.error = error.localizedDescription }
                                regenerating = false
                            }
                        } label: {
                            Label(regenerating ? "Seslendiriliyor…" : "Bu sahneyi yeni telaffuzla seslendir", systemImage: "waveform.badge.magnifyingglass")
                        }
                        .disabled(regenerating)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                }
                AudioCheckSection()
                if !list.isEmpty {
                    Section("Sözlük (\(list.count)/\(Pronunciations.storageLimit))") {
                        ForEach(list) { p in LabeledContent(p.from, value: p.to) }
                            .onDelete { idx in
                                var l = list; l.remove(atOffsets: idx); Pronunciations.all = l; list = l
                            }
                    }
                }
            }
            .navigationTitle("Telaffuz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}

/// #13/#20: konuşma tanıma kullanan ses özellikleri (kelime senkronu, kalite kapısı). Ses cihazdan çıkmaz.
struct AudioCheckSection: View {
    @AppStorage(WordSync.autoKey) private var wordSync = true
    @AppStorage(SceneQualityGate.asrCheckKey) private var asrCheck = false
    @State private var state: SpeechAlignment.ModelState?
    @State private var denied = SpeechAlignment.isDenied
    @State private var downloading = false
    @State private var error: String?

    var body: some View {
        Section {
            Toggle("Gerçek kelime senkronu", isOn: $wordSync)
            Toggle("Seslendirmeyi konuşma tanımayla denetle", isOn: $asrCheck)
            if state == .needsDownload {
                Button {
                    Task { await download() }
                } label: {
                    HStack {
                        if downloading { ProgressView() }
                        Label("Türkçe konuşma modelini indir", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(downloading)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: {
            Text("Ses denetimi ve senkron")
        } footer: {
            Text(footer)
        }
        .task { await refresh() }
        .onChange(of: wordSync) { _, on in if on { Task { await authorize() } } }
        .onChange(of: asrCheck) { _, on in if on { Task { await authorize() } } }
    }

    private var footer: String {
        if denied { return "Konuşma tanıma izni kapalı. iPhone Ayarlar → \(Config.appName) bölümünden izin verebilirsin." }
        if state == .unsupported { return "Bu cihazda Türkçe konuşma tanıma yok; okurken takip tahmini zamanla sürer." }
        return "Kelime senkronu, 30 dakikaya kadar olan bölümlerde açılınca sesi iPhone'da tanır ve vurguyu sesin kendisine göre ilerletir. Denetim açıksa üretim ön plandayken cümle atlayan ya da tekrar eden sahne bir kez yeniden üretilir."
    }

    private func refresh() async {
        state = await SpeechAlignment.modelState()
        denied = SpeechAlignment.isDenied
    }

    private func authorize() async {
        if !SpeechAlignment.isAuthorized, !SpeechAlignment.isDenied { _ = await SpeechAlignment.requestAuthorization() }
        await refresh()
    }

    private func download() async {
        downloading = true
        error = nil
        defer { downloading = false }
        do {
            try await WordSync.downloadModel()
        } catch {
            self.error = error.localizedDescription
        }
        await refresh()
    }
}
