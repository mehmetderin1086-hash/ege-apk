import Foundation

// Tek ses ayarı (kullanıcı kararı, 17 Eki 2026): uygulamadaki bütün sesler (SesLab sunucu sesleri, Chirp 3 HD'nin 30 hazır sesi,
// iPhone sesleri) her modülde seçilebilir ve seçim Ayarlar'daki tek yerden yapılır. Podcast, soru anlatımı, konu videosu, MEB sırası
// ve düzeltme aynı iki sesi kullanır: birincil ses (anlatıcı / öğretmen / A sunucusu) ve ikili anlatımda ikinci ses (öğrenci / B).
// Ses anahtarı `QSVoiceKey` biçimindedir ("Kore@chirp", "xtts:<kimlik>", "apple:F"); podcast ayarlarına `PodcastSettings.apply` çevirir.

nonisolated enum AppVoice {
    static let primaryKey = "ikra.voice", secondaryKey = "ikra.voice2"
    /// Açıkken Chirp seslerinde Claude önce her sahnedeki formül, simge ve kısaltmaların okunuşunu hazırlar ("Claude + Chirp").
    static let claudeReadingsKey = "ikra.voice.claudeReadings"
    static let defaultPrimary = QSVoiceKey(name: "Kore", chirp: .chirp), defaultSecondary = QSVoiceKey(name: "Puck", chirp: .chirp)

    /// Seçilebilir ses anahtarı: motor önekli (SesLab, cihaz içi) ya da Chirp; "Claude + Chirp" Chirp'e normalize edilir (okunuş ayrı
    /// bir anahtardır). Eski (motorsuz) kayıt sesi ve boş anahtar seçilemez.
    static func usable(_ raw: String) -> QSVoiceKey? {
        let key = QSVoiceKey(raw)
        guard !key.name.isEmpty, key.engine != .legacy else { return nil }
        if key.engine == .claude { return QSVoiceKey(name: key.name, chirp: .chirp) }
        if key.engine.isSeslab, key.seslabID?.isEmpty != false { return nil }
        if key.isLocal, key.localVoice?.isEmpty != false { return nil }
        return key
    }

    /// Kayıtlı birincil ses (okunuş ayarı uygulanmadan; seçicide işaretli satır). Kayıt yoksa eski Soru Çöz tercihinden (qs.studio.*)
    /// taşınır, o da yoksa Kore.
    static func primaryChoice(_ defaults: UserDefaults = .standard) -> QSVoiceKey {
        if let raw = defaults.string(forKey: primaryKey), let key = usable(raw) { return key }
        // Kullanıcı hiç ses seçmediyse ve EMA-TTS telefona inmişse bütün modüller EMA ile konuşur (kullanıcı kararı, 17 Eki 2026:
        // "tüm seslendirmelerde EMA", "sen yap her şeyi"). Açık seçim her zaman öndedir.
        if emaReady(), OfflineModelCatalog.ready(.ema) { return QSVoiceKey(local: .ema, voice: "tr") }
        return migrated(defaults) ?? defaultPrimary
    }
    /// Testlerde EMA'nın inmiş sayılması için kapı (varsayılan: gerçek katalog).
    nonisolated(unsafe) static var emaReady: () -> Bool = { true }
    /// Kayıtlı ikinci ses (okunuş uygulanmadan): birincille aynı motorda ve ondan farklı; değilse türetilir.
    static func secondaryChoice(_ defaults: UserDefaults = .standard) -> QSVoiceKey {
        partner(defaults.string(forKey: secondaryKey).flatMap(usable), avoiding: primaryChoice(defaults))
    }
    /// Seslendirmede kullanılan birincil ses: Chirp'te okunuş ayarı açıksa "Claude + Chirp" motoru.
    static func primary(_ defaults: UserDefaults = .standard) -> QSVoiceKey { withReadings(primaryChoice(defaults), defaults) }
    static func secondary(_ defaults: UserDefaults = .standard) -> QSVoiceKey { withReadings(secondaryChoice(defaults), defaults) }

    static func set(primary key: QSVoiceKey, _ defaults: UserDefaults = .standard) { defaults.set((usable(key.raw) ?? defaultPrimary).raw, forKey: primaryKey) }
    static func set(secondary key: QSVoiceKey, _ defaults: UserDefaults = .standard) { defaults.set((usable(key.raw) ?? defaultSecondary).raw, forKey: secondaryKey) }
    /// Okunuş ayarı; hiç yazılmamışsa eski Soru Çöz tercihindeki "Claude + Chirp" motoru ya da son podcast ayarının motoru sayılır.
    static func claudeReadings(_ defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: claudeReadingsKey) as? Bool { return stored }
        if let engine = defaults.string(forKey: "qs.studio.engine") { return engine == QSVoiceKey.Engine.claude.rawValue }
        return lastPodcastSettings(defaults)?.engine == .claude
    }

    static func withReadings(_ key: QSVoiceKey, _ defaults: UserDefaults = .standard) -> QSVoiceKey {
        key.engine == .chirp && claudeReadings(defaults) ? QSVoiceKey(name: key.name, chirp: .claude) : key
    }

    /// İkinci ses: `stored` birincille aynı motorda ve farklıysa o; değilse aynı motordan türetilir. Chirp'te Kore ↔ Puck; SesLab'da
    /// listedeki (eğitilmiş olan önce) ilk farklı ses, tek ses varsa aynı ses; cihaz içinde karşı cinsten ilk ses (F ↔ M, F1 ↔ M1).
    /// Bir senaryonun bütün turları tek sağlayıcıdan seslendirildiği için ikinci ses başka motordan olamaz.
    static func partner(_ stored: QSVoiceKey?, avoiding first: QSVoiceKey) -> QSVoiceKey {
        let base = first.engine == .claude ? QSVoiceKey(name: first.name, chirp: .chirp) : first
        if let stored = stored.flatMap({ usable($0.raw) }), stored.engine == base.engine, stored.raw != base.raw { return stored }
        if base.engine == .azure { return QSVoiceKey(azure: base.name == "Elif" ? "Aydın" : "Elif") }
        if base.engine == .chirp {
            let name = base.name == "Puck" ? "Kore" : VoiceOption.all.contains { $0.id == base.name } ? "Puck" : "Kore"
            return QSVoiceKey(name: name == base.name ? "Charon" : name, chirp: .chirp)
        }
        if base.engine.isSeslab {
            let voices = QSXttsVoices.stored(), own = base.seslabID
            let other = voices.first { $0.id != own && $0.cloned != true } ?? voices.first { $0.id != own }
            return other.map { QSVoiceKey(seslab: base.engine, id: $0.id) } ?? base
        }
        if base.isLocal {
            return QSVoiceKey(local: base.engine, voice: QSLocalVoices.valid(nil, engine: base.engine, avoiding: base.localVoice))
        }
        return defaultSecondary
    }

    /// Eski tercihler tek ayara taşınır (saf; yazma yok): önce Soru Çöz'ün (qs.studio.voice / engine / xttsVoice / <motor>Voice),
    /// yoksa son podcast ayarının A sunucusu. Hiç tercih yoksa `nil`. "Claude + Chirp" motoru okunuş ayarı olarak okunur.
    static func migrated(_ defaults: UserDefaults) -> QSVoiceKey? {
        if let engineRaw = defaults.string(forKey: "qs.studio.engine"), let engine = QSVoiceKey.Engine(rawValue: engineRaw) {
            if engine.isLocal { return QSLocalVoices.chosen(engine, scope: "qs.studio") }
            if engine.isSeslab {
                guard let id = defaults.string(forKey: "qs.studio.xttsVoice").flatMap({ $0.isEmpty ? nil : $0 }) ?? QSXttsVoices.stored().first?.id else { return nil }
                return QSVoiceKey(seslab: engine, id: id)
            }
            return QSVoiceKey(name: VoiceOption.valid(defaults.string(forKey: "qs.studio.voice"), fallback: "Kore"), chirp: .chirp)
        }
        if let voice = defaults.string(forKey: "qs.studio.voice") { return QSVoiceKey(name: VoiceOption.valid(voice, fallback: "Kore"), chirp: .chirp) }
        return lastPodcastSettings(defaults).flatMap { usable($0.voiceKey(.a).raw) }
    }
    /// Yeni podcast ekranının son ayarları ("lastSettings").
    static func lastPodcastSettings(_ defaults: UserDefaults) -> PodcastSettings? {
        defaults.data(forKey: "lastSettings").flatMap { try? JSONDecoder().decode(PodcastSettings.self, from: $0) }
    }
}

nonisolated extension PodcastSettings {
    /// Podcast ayarlarını tek ses anahtarından kurar: sağlayıcı, sunucu sesleri, cihaz içi ses kimlikleri; motorun taşıyamadığı
    /// seçenekler (iki sunucu, İngilizce, konuk) kapatılır. `voiceB` verilmezse birincilden türetilir.
    mutating func apply(voiceA: QSVoiceKey, voiceB: QSVoiceKey? = nil) {
        speechProvider = voiceA.engine == .claude ? SpeechEngine.claude.rawValue : voiceA.provider
        let b = AppVoice.partner(voiceB, avoiding: voiceA)
        hostA.voice = voiceA.hostVoice
        hostB.voice = b.hostVoice
        if let local = voiceA.localVoice {
            localVoiceA = QSLocalVoices.valid(local, engine: voiceA.engine)
            localVoiceB = QSLocalVoices.valid(b.localVoice, engine: voiceA.engine, avoiding: localVoiceA)
        }
        if !engine.supportsTwoHosts { format = .tekAnlatici }
        if engine.turkishOnly { language = .tr }
        if !engine.supportsGuest { guest = nil }
    }
    /// Bölümün kaydındaki konuşmacı sesi tek anahtar olarak: Chirp'te ad + motor, SesLab/cihaz içinde önekli anahtar (eski kayıtta
    /// ses adı önekli değilse cihaz içi sesten ya da sunucu sesinden kurulur).
    func voiceKey(_ speaker: Speaker) -> QSVoiceKey {
        let host = speaker == .a ? hostA : hostB
        switch engine {
        case .azure: return QSVoiceKey(azure: host.voice)
        case .chirp, .claude: return QSVoiceKey(name: host.voice, chirp: engine == .claude ? .claude : .chirp)
        case .apple, .supertonic, .piper, .ema:
            let local = QSVoiceKey.Engine(rawValue: engine.rawValue) ?? .apple
            return QSVoiceKey.prefixed(host.voice) ? QSVoiceKey(host.voice) : QSVoiceKey(local: local, voice: speaker == .a ? localVoiceA : localVoiceB)
        // Önekli anahtar ("xtts:<kimlik>") sunucu sesidir; eski XTTS kaydında ad önekli değilse eski kayıt motoru (sunucunun varsayılan sesi).
        case .xtts, .edge, .huggingface: return QSVoiceKey(host.voice)
        }
    }
    /// Ayarlar'daki tek ses ayarını uygular.
    mutating func applyAppVoice(_ defaults: UserDefaults = .standard) { apply(voiceA: AppVoice.primary(defaults), voiceB: AppVoice.secondary(defaults)) }
    /// Ayardaki sesle: yeni podcast, hızlı ayar ve kuyruk hep bununla başlar.
    var withAppVoice: PodcastSettings { var copy = self; copy.applyAppVoice(); return copy }
}
