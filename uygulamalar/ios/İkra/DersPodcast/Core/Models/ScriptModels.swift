import Foundation

// Sunucu sözleşmesi: docs/API.md. Alan adları birebir aynı tutulmalı.

nonisolated struct Host: Codable, Hashable, Sendable {
    var name: String
    var voice: String
}

nonisolated enum Speaker: String, Codable, Sendable {
    case a = "A"
    case b = "B"
    /// #9 konuk uzman; yalnız `settings.guest` varken ve A ile aynı sahnede.
    case c = "C"
}

nonisolated struct ScriptTurn: Codable, Hashable, Sendable {
    var speaker: Speaker
    var text: String
    var style: String
    var sourcePage: Int?
    /// #23: bu soru turundan sonra bırakılacak düşünme payı (sn, 3–8).
    var think: Double?
}

nonisolated struct ScriptScene: Codable, Hashable, Sendable {
    var turns: [ScriptTurn]
}

nonisolated struct ScriptChapter: Codable, Hashable, Sendable {
    var title: String
    var scenes: [ScriptScene]
    /// #9: "sohbet" | "anlatim" | "hizliSoru" | "vaka"
    var style: String?
    /// #6: konunun dayandığı kaynak sayfaları (1 tabanlı).
    var sourcePages: [Int]?
}

nonisolated struct PodcastScript: Codable, Hashable, Sendable {
    var title: String
    var summary: String
    var keyPoints: [String]
    var chapters: [ScriptChapter]
    var sourceNotes: String
    /// #2/#7: süre ve doğallık karnesi; bozuksa yalnız bu alan nil olur.
    var quality: ScriptQualityReport?

    /// Tüm sahneler, bölüm sırasıyla ve global indeksle.
    var flatScenes: [(chapterIndex: Int, scene: ScriptScene)] {
        chapters.enumerated().flatMap { ci, chapter in chapter.scenes.map { (ci, $0) } }
    }

    var totalCharacters: Int {
        chapters.reduce(0) { $0 + $1.scenes.reduce(0) { $0 + $1.turns.reduce(0) { $0 + $1.text.count } } }
    }
}

nonisolated extension PodcastScript {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        keyPoints = try c.decode([String].self, forKey: .keyPoints)
        chapters = try c.decode([ScriptChapter].self, forKey: .chapters)
        sourceNotes = try c.decode(String.self, forKey: .sourceNotes)
        quality = try? c.decodeIfPresent(ScriptQualityReport.self, forKey: .quality)
    }
}

nonisolated struct ScriptQualityReport: Codable, Hashable, Sendable {
    var targetMinutes: Double
    var estimatedMinutes: Double
    var words: Int
    var findings: [QualityFinding]
    /// Küresel sahne indeksi (flatScenes).
    var weakScenes: [WeakScene]
    var chapterErrors: [ChapterError]
}
nonisolated struct QualityFinding: Codable, Hashable, Sendable { var id: String; var label: String; var count: Int; var examples: [String]? }
nonisolated struct WeakScene: Codable, Hashable, Sendable { var scene: Int; var reasons: [String] }
nonisolated struct ChapterError: Codable, Hashable, Sendable { var index: Int; var title: String; var message: String }

/// #1/#31: seri bağlamı (kullanıcı talimatından ayrı). `index` 1 tabanlı (Episode.seriesIndex ile aynı).
nonisolated struct SeriesContext: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var index: Int
    var total: Int
    var previousTitles: [String]
    var previousKeyPoints: [String]
}

/// #40/#42: türev ve bağ bilgisi; sunucu yok sayar, P3 bölüm oluşunca `Episode.applyContext` ile işler.
nonisolated struct Derivation: Codable, Hashable, Sendable {
    /// "recap" | "gap" | "weekly" | "video" | "discriminate"
    var kind: String?
    var parentEpisodeID: UUID?
    var sourceLessonID: UUID?
    var sourceVideoTime: Double?
    var courseID: UUID?
}

nonisolated enum PodcastLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case genel, universite, kpss, ales, dgs, yds, mesleki
    var id: String { rawValue }
    var title: String {
        switch self {
        case .genel: "Genel"
        case .universite: "Üniversite"
        case .kpss: "KPSS"
        case .ales: "ALES"
        case .dgs: "DGS"
        case .yds: "YDS"
        case .mesleki: "Mesleki"
        }
    }
}

nonisolated enum PodcastTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case samimi, akademik, eglenceli, sinav
    var id: String { rawValue }
    var title: String {
        switch self {
        case .samimi: "Samimi"
        case .akademik: "Akademik"
        case .eglenceli: "Eğlenceli"
        case .sinav: "Sınav tekrarı"
        }
    }
    var symbol: String {
        switch self {
        case .samimi: "cup.and.saucer"
        case .akademik: "graduationcap"
        case .eglenceli: "face.smiling"
        case .sinav: "checklist"
        }
    }
}

nonisolated enum PodcastFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case sohbet, tekAnlatici, tartisma, sinavProvasi, hikaye
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sohbet: "Sohbet"
        case .tekAnlatici: "Tek anlatıcı"
        case .tartisma: "Tartışma"
        case .sinavProvasi: "Sınav provası"
        case .hikaye: "Hikâye"
        }
    }
    var detail: String {
        switch self {
        case .sohbet: "İki sunucu konuyu karşılıklı konuşarak anlatır."
        case .tekAnlatici: "Bir öğretmen dersi doğrudan sana anlatır."
        case .tartisma: "Sunucular farklı bakış açılarını tartışıp uzlaşır."
        case .sinavProvasi: "Soru sorulur, düşünme payı bırakılır, sonra cevaplanır."
        case .hikaye: "Konu bir hikâye üzerinden, olgulara sadık kalınarak işlenir."
        }
    }
    var symbol: String {
        switch self {
        case .sohbet: "bubble.left.and.bubble.right.fill"
        case .tekAnlatici: "person.wave.2.fill"
        case .tartisma: "arrow.left.arrow.right"
        case .sinavProvasi: "questionmark.bubble.fill"
        case .hikaye: "book.fill"
        }
    }
    var usesTwoHosts: Bool { self != .tekAnlatici }
}

nonisolated enum PodcastDepth: String, Codable, CaseIterable, Identifiable, Sendable {
    case ozet, dengeli, derin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ozet: "Özet"
        case .dengeli: "Dengeli"
        case .derin: "Derinlemesine"
        }
    }
}

nonisolated enum PodcastPace: String, Codable, CaseIterable, Identifiable, Sendable {
    case yavas, normal, hizli
    var id: String { rawValue }
    var title: String {
        switch self {
        case .yavas: "Yavaş"
        case .normal: "Normal"
        case .hizli: "Hızlı"
        }
    }
}

nonisolated enum PodcastLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case tr, en
    var id: String { rawValue }
    var title: String { self == .tr ? "Türkçe" : "İngilizce" }
}

nonisolated struct PodcastExtras: Codable, Hashable, Sendable {
    var examples = true
    var analogies = true
    var examTips = true
    var commonMistakes = true
    var recapQuestions = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        examples = try c.decodeIfPresent(Bool.self, forKey: .examples) ?? true
        analogies = try c.decodeIfPresent(Bool.self, forKey: .analogies) ?? true
        examTips = try c.decodeIfPresent(Bool.self, forKey: .examTips) ?? true
        commonMistakes = try c.decodeIfPresent(Bool.self, forKey: .commonMistakes) ?? true
        recapQuestions = try c.decodeIfPresent(Bool.self, forKey: .recapQuestions) ?? false
    }
}

nonisolated enum SpeechEngine: String, CaseIterable, Identifiable, Sendable {
    case azure, chirp, claude, xtts, apple, edge, huggingface, supertonic, piper, ema
    var id: String { rawValue }

    /// Seçilebilen motorlar (kullanıcı kararı, 17 Eki 2026: uygulamadaki bütün sesler her modülde seçilebilir; ses Ayarlar › Ses'ten
    /// seçilir, motor sesten türer — bkz. `AppVoice`). Edge ve Hugging Face sunulmaz.
    static let offered: [SpeechEngine] = [.azure, .chirp, .claude, .xtts, .apple, .supertonic, .piper, .ema]

    /// Sesi üreten motor: "Claude + Chirp"te Claude yalnız okunuşları hazırlar, sesi Chirp üretir.
    var voicedBy: SpeechEngine { self == .claude ? .chirp : self }

    var title: String {
        switch self {
        case .azure: "Azure HD · Asistan sesleri"
        case .xtts: "XTTS v2 · Sunucu sesleri"
        case .chirp: "Google Chirp 3 HD"
        case .claude: QSModelPlan.astraOnly ? "Astra + Chirp 3 HD" : "Claude + Chirp 3 HD"
        case .apple: "Apple · Yerel"
        case .edge: "Edge TTS · Ücretsiz"
        case .huggingface: "Hugging Face · MMS Türkçe"
        case .supertonic: "Supertonic 3 · iPhone"
        case .piper: "Piper Türkçe · iPhone"
        case .ema: "EMA-TTS · iPhone"
        }
    }
    var detail: String {
        switch self {
        case .azure: "Asistan uygulamasındaki Elif ve Aydın sesleri. İnternet kullanır; erişim anahtarı sunucuda tutulur."
        case .xtts: "Sunucuda eğitilmiş Türkçe sesler (SesLab, XTTS-v2). Kota harcamaz; sunucu CPU'sunda sırayla üretir, uzun sürer; Mac açıkken sesler orada, daha hızlı üretilir."
        case .chirp: "Google’ın 30 hazır sesi (Ayarlar › Ses). İnternet ve Google Cloud kotası gerekir."
        case .claude: QSModelPlan.astraOnly ? "Okunuşu Codex Astra hazırlar; sesi Google Chirp üretir." : "Claude okunuşu hazırlar; sesi Google Chirp üretir."
        case .apple: "Yelda ve Cem cihazda çalışır; bulut ses kotası kullanılmaz."
        case .edge: "Emel (kadın) ve Ahmet (erkek). API anahtarı gerekmez; internet gerekir. Resmî Azure API değildir, hizmet sınırları değişebilir."
        case .huggingface: "MMS Türkçe Mac’te çalışır; bulut kotası yoktur. Tek anlatıcı, standart kalite. Mac sunucusu açık olmalı. Model: Meta, CC-BY-NC 4.0 (ticari olmayan kullanım)."
        case .supertonic: "Model bir kez indirildikten sonra iPhone’da çevrimdışı çalışır. Beş kadın ve beş erkek ses; bulut ses kotası kullanmaz."
        case .piper: "Türkçe tek anlatıcı. Model indirildikten sonra iPhone’da çevrimdışı çalışır; bulut ses kotası kullanmaz."
        case .ema: "EMA-TTS: Türkçe tek ses, 48 kHz (Apache-2.0). Model (yaklaşık 220 MB) bir kez indirildikten sonra iPhone’da çevrimdışı çalışır; bulut ses kotası kullanmaz. Uzun cümlelerde en doğal sonucu verir."
        }
    }
    func voiceLabel(_ speaker: Speaker) -> String {
        switch self {
        case .chirp, .claude: speaker == .a ? "Kore" : "Puck"
        case .azure: speaker == .a ? "Elif" : "Aydın"
        case .xtts: speaker == .a ? "Sunucu sesi 1" : "Sunucu sesi 2"
        case .edge: speaker == .a ? "Emel" : "Ahmet"
        case .huggingface: "MMS · Tek ses"
        case .apple: "Apple"
        case .supertonic: "Supertonic · iPhone"
        case .piper: "DFKI · Tek ses"
        case .ema: "EMA · Tek ses"
        }
    }
    var isNeuralOnDevice: Bool { self == .supertonic || self == .piper || self == .ema }
    var usesServer: Bool { self != .apple && !isNeuralOnDevice }
    var supportsTwoHosts: Bool { self != .huggingface && self != .piper && self != .ema }
    var turkishOnly: Bool { [.azure, .chirp, .claude, .xtts, .edge, .huggingface, .piper, .ema].contains(self) }
    /// #9: konuk sesi yalnız tur başına ses seçebilen sunucu motorlarında.
    var supportsGuest: Bool { voicedBy == .chirp }
}

nonisolated struct PodcastSettings: Codable, Hashable, Sendable {
    var speechProvider: String = "chirp"
    /// Kaldırılan "gemini" değeri (kayıt çözümlenirken XTTS'e çevrilir) elle verilirse de sunucu seslerine düşer.
    /// Daha önce seslendirilmiş bölüm kendi motorunu korur (sahne düzenleme ve istatistikler tutarlı kalsın); yeni ses yalnız
    /// sunulan motorlarla üretilir (bkz. `forNewAudio`).
    var engine: SpeechEngine {
        let engine: SpeechEngine = speechProvider == "gemini" ? .xtts : SpeechEngine(rawValue: speechProvider) ?? .apple
        return engine
    }
    /// Yeni bir bölüm için ayarlar: motor artık sunulmuyorsa (kaldırılanlar) Chirp'e çevrilir, öbür ayarlar korunur.
    var forNewAudio: PodcastSettings {
        var copy = self
        let known = SpeechEngine(rawValue: speechProvider) ?? (speechProvider == "gemini" ? .xtts : nil)
        copy.speechProvider = (known.flatMap { SpeechEngine.offered.contains($0) ? $0 : nil } ?? .chirp).rawValue
        return copy
    }
    var usesChirp: Bool { engine.voicedBy == .chirp }
    var usesServerSpeech: Bool { engine.usesServer }
    // Kept separately from Host.voice: the script API still uses its existing
    // voice contract, while these identifiers belong to the on-device model.
    var localVoiceA: String = "F1"
    var localVoiceB: String = "M1"
    var durationMin: Int = 10
    var level: PodcastLevel = .universite
    var tone: PodcastTone = .samimi
    var focus: String?
    var hostA = Host(name: "Elif", voice: "Kore")
    var hostB = Host(name: "Can", voice: "Puck")
    var format: PodcastFormat = .sohbet
    var depth: PodcastDepth = .dengeli
    var pace: PodcastPace = .normal
    var language: PodcastLanguage = .tr
    var extras = PodcastExtras()
    var customInstructions: String?
    var scriptAI: ScriptAISettings?
    var series: SeriesContext?
    /// Uygulamanın ürettiği senaryo yönergeleri (şekil, karşılaştırma, iki dilli, tekrar yapısı).
    var directives: [String] = []
    var mixedFormat = false
    var guest: Host?
    var thinkPauses = true
    var recallFirst = false
    /// #15: nil = genel ayar (sound.identity).
    var soundIdentity: String?
    var derivation: Derivation?

    static let durations = [5, 10, 15, 20, 30, 45, 60]
    static let maxCustomInstructions = 500

    init(speechProvider: String = "chirp") { self.speechProvider = speechProvider }

    /// Eski sürümlerde kaydedilmiş ayarlar (yeni alanlar yok) sorunsuz açılsın.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Gemini seslendirmesi 11 Eki 2026'da kaldırıldı: eski kayıtlardaki seçim sunucu seslerine (XTTS) çevrilir.
        let storedProvider = try c.decodeIfPresent(String.self, forKey: .speechProvider) ?? "apple"
        speechProvider = storedProvider == "gemini" ? "xtts" : storedProvider
        localVoiceA = try c.decodeIfPresent(String.self, forKey: .localVoiceA) ?? "F1"
        localVoiceB = try c.decodeIfPresent(String.self, forKey: .localVoiceB) ?? "M1"
        let defaults = PodcastSettings()
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin) ?? defaults.durationMin
        level = (try? c.decodeIfPresent(PodcastLevel.self, forKey: .level)) ?? defaults.level
        tone = (try? c.decodeIfPresent(PodcastTone.self, forKey: .tone)) ?? defaults.tone
        focus = try c.decodeIfPresent(String.self, forKey: .focus)
        hostA = try c.decodeIfPresent(Host.self, forKey: .hostA) ?? defaults.hostA
        hostB = try c.decodeIfPresent(Host.self, forKey: .hostB) ?? defaults.hostB
        format = (try? c.decodeIfPresent(PodcastFormat.self, forKey: .format)) ?? defaults.format
        depth = (try? c.decodeIfPresent(PodcastDepth.self, forKey: .depth)) ?? defaults.depth
        pace = (try? c.decodeIfPresent(PodcastPace.self, forKey: .pace)) ?? defaults.pace
        language = (try? c.decodeIfPresent(PodcastLanguage.self, forKey: .language)) ?? defaults.language
        extras = try c.decodeIfPresent(PodcastExtras.self, forKey: .extras) ?? defaults.extras
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions)
        scriptAI = try c.decodeIfPresent(ScriptAISettings.self, forKey: .scriptAI)
        series = try? c.decodeIfPresent(SeriesContext.self, forKey: .series)
        directives = (try? c.decodeIfPresent([String].self, forKey: .directives)) ?? []
        mixedFormat = (try? c.decodeIfPresent(Bool.self, forKey: .mixedFormat)) ?? false
        guest = try? c.decodeIfPresent(Host.self, forKey: .guest)
        thinkPauses = (try? c.decodeIfPresent(Bool.self, forKey: .thinkPauses)) ?? true
        recallFirst = (try? c.decodeIfPresent(Bool.self, forKey: .recallFirst)) ?? false
        soundIdentity = try? c.decodeIfPresent(String.self, forKey: .soundIdentity)
        derivation = try? c.decodeIfPresent(Derivation.self, forKey: .derivation)
    }

    /// lastSettings, profil ve QuickSettings başlangıcı için: bölüme özgü bağlam temizlenir; artık sunulmayan ses motoru
    /// seçimi Chirp'e çevrilir (seçicide yalnız sunulan motorlar vardır).
    var reusable: PodcastSettings {
        var s = forNewAudio
        s.series = nil
        s.directives = []
        s.recallFirst = false
        s.derivation = nil
        return s
    }

    func displayName(for speaker: Speaker) -> String {
        switch speaker {
        case .a: hostA.name
        case .b: hostB.name
        case .c: guest?.name ?? "Konuk"
        }
    }

    /// Tahmini üretim süresi (dakika): senaryo + seslendirme.
    var estimatedGenerationMinutes: Int {
        max(1, Int((Double(durationMin) * 0.18 + 1).rounded()))
    }
}

nonisolated struct QuizItem: Codable, Hashable, Sendable {
    var question: String
    var options: [String]
    var answerIndex: Int
    var explanation: String
    var sourcePage: Int?
    /// #34: "mcq" | "osym" | "premise" | "truefalse" | "open"; nil = mcq.
    var kind: String?
    var chapterIndex: Int?
    /// Küresel tur indeksi (TimedTurn.id).
    var turnIndex: Int?
    /// 1–3
    var difficulty: Int?
    var answerText: String?
    var verified: Bool?
}

nonisolated struct Flashcard: Codable, Hashable, Sendable {
    var front: String
    var back: String
}

nonisolated struct Concept: Codable, Hashable, Sendable {
    var name: String
    var definition: String
    var related: [String]
    var sourcePage: Int?
}

nonisolated struct StudyPack: Codable, Hashable, Sendable {
    var quiz: [QuizItem]
    var flashcards: [Flashcard]
    var concepts: [Concept]?
    /// Kaynaktaki formüller (sunucu /v1/study; eski paketlerde yok).
    var formulas: [Formula]?
}

nonisolated struct Formula: Codable, Hashable, Sendable {
    var name: String
    var expression: String
    var meaning: String
    var when: String
}

nonisolated struct VisualCover: Codable, Hashable, Sendable {
    var title: String
    var subtitle: String
    var symbol: String
    var theme: String
    var motif: String
    var accessibilityLabel: String
    var imageData: String? = nil
    var mimeType: String? = nil
}

nonisolated struct LessonDiagram: Codable, Hashable, Sendable {
    struct Step: Codable, Hashable, Sendable {
        var title: String
        var detail: String
        var symbol: String
    }
    var title: String
    var caption: String
    var layout: String
    var steps: [Step]
    var imageData: String? = nil
    var mimeType: String? = nil
}

nonisolated struct VisualPack: Codable, Hashable, Sendable {
    var cover: VisualCover
    var diagrams: [LessonDiagram]
    var model: String
}

// MARK: - Zaman çizelgesi (ses birleştirildikten sonra)

nonisolated struct TimedTurn: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var chapterIndex: Int
    var speaker: Speaker
    var text: String
    var sourcePage: Int?
    var start: Double
    var end: Double
}

nonisolated struct TimedChapter: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var title: String
    var start: Double
}

nonisolated struct Timeline: Codable, Hashable, Sendable {
    var chapters: [TimedChapter]
    var turns: [TimedTurn]
    var duration: Double
    /// #23: düşünme payı aralıkları (mutlak sn).
    var thinkPauses: [ThinkPause]?
    /// #10/#20: küresel sahne başlangıçları (mutlak sn).
    var sceneStarts: [Double]?

    /// `time` anında konuşulan turun indeksi (ikili arama).
    func turnIndex(at time: Double) -> Int? {
        guard !turns.isEmpty else { return nil }
        var lo = 0, hi = turns.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if turns[mid].start <= time { lo = mid } else { hi = mid - 1 }
        }
        return turns[lo].start <= time + 0.05 ? lo : nil
    }

    func chapterIndex(at time: Double) -> Int {
        chapters.lastIndex { $0.start <= time + 0.05 } ?? 0
    }
}

nonisolated struct ThinkPause: Codable, Hashable, Sendable {
    /// Küresel tur indeksi (TimedTurn.id).
    var turnID: Int
    var start: Double
    var end: Double
}

// MARK: - Sesler

nonisolated struct VoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let trait: String

    /// Menüde görünen ad ("Kore — Kararlı"); listede yoksa kimliğin kendisi.
    static func title(_ id: String) -> String { all.first { $0.id == id }.map { "\($0.id) — \($0.trait)" } ?? id }
    /// Geçerli bir ses kimliği mi; değilse verilen yedek.
    static func valid(_ id: String?, fallback: String) -> String { all.contains { $0.id == id } ? id! : fallback }

    /// Chirp 3 HD hazır sesleri ve Google'ın verdiği karakter tanımları.
    static let all: [VoiceOption] = [
        .init(id: "Kore", trait: "Kararlı"), .init(id: "Puck", trait: "Neşeli"),
        .init(id: "Charon", trait: "Bilgilendirici"), .init(id: "Zephyr", trait: "Parlak"),
        .init(id: "Fenrir", trait: "Heyecanlı"), .init(id: "Leda", trait: "Genç"),
        .init(id: "Orus", trait: "Kararlı"), .init(id: "Aoede", trait: "Ferah"),
        .init(id: "Callirrhoe", trait: "Rahat"), .init(id: "Autonoe", trait: "Parlak"),
        .init(id: "Enceladus", trait: "Nefesli"), .init(id: "Iapetus", trait: "Net"),
        .init(id: "Umbriel", trait: "Rahat"), .init(id: "Algieba", trait: "Yumuşak"),
        .init(id: "Despina", trait: "Yumuşak"), .init(id: "Erinome", trait: "Net"),
        .init(id: "Algenib", trait: "Pürüzlü"), .init(id: "Rasalgethi", trait: "Bilgilendirici"),
        .init(id: "Laomedeia", trait: "Neşeli"), .init(id: "Achernar", trait: "Yumuşak"),
        .init(id: "Alnilam", trait: "Kararlı"), .init(id: "Schedar", trait: "Dengeli"),
        .init(id: "Gacrux", trait: "Olgun"), .init(id: "Pulcherrima", trait: "Atılgan"),
        .init(id: "Achird", trait: "Arkadaş canlısı"), .init(id: "Zubenelgenubi", trait: "Gündelik"),
        .init(id: "Vindemiatrix", trait: "Nazik"), .init(id: "Sadachbia", trait: "Canlı"),
        .init(id: "Sadaltager", trait: "Bilgili"), .init(id: "Sulafat", trait: "Sıcak"),
    ]
}


nonisolated struct ScriptAISettings: Codable, Hashable, Sendable {
    var provider: String
    var model: String
    var effort: String = "auto"

    static func effortTitle(_ value: String) -> String {
        switch value {
        case "auto": "Model varsayılanı"
        case "low": "Düşük · hızlı"
        case "medium": "Orta · dengeli"
        case "high": "Yüksek"
        case "xhigh": "Çok yüksek"
        case "max": "En yüksek"
        default: value
        }
    }
}

nonisolated struct ScriptModelCatalog: Decodable, Sendable {
    struct Provider: Decodable, Identifiable, Sendable {
        var id: String
        var title: String
    }
    struct Model: Decodable, Identifiable, Sendable {
        var id: String
        var provider: String
        var title: String
        var detail: String
        var efforts: [String]
    }
    var providers: [Provider]
    var models: [Model]
    var defaultSelection: ScriptAISettings
    /// Senaryo Claude ya da sunucu vekilindeki öbür hesapların modelleriyle yazılır (kullanıcı kararı, 16 Eki 2026: podcast da
    /// Ders Video'daki vekil ve model özelliklerine bağlı; Soru Çöz'deki sağlayıcı listesiyle aynı). Sunucu tanınmayan bir sağlayıcı
    /// bildirirse listeye girmez; varsayılan seçim öyle bir modelse listedeki ilk modele çekilir.
    static let allowedProviders: Set<String> = Set(QSCatalog.providers)
    init(providers: [Provider], models: [Model], defaultSelection: ScriptAISettings) {
        self.providers = providers.filter { Self.allowedProviders.contains($0.id) }
        self.models = models.filter { Self.allowedProviders.contains($0.provider) }
        self.defaultSelection = Self.allowedProviders.contains(defaultSelection.provider) ? defaultSelection
            : self.models.first.map { ScriptAISettings(provider: $0.provider, model: $0.id) } ?? defaultSelection
    }
    private enum CodingKeys: String, CodingKey { case providers, models, defaultSelection }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(providers: try values.decode([Provider].self, forKey: .providers), models: try values.decode([Model].self, forKey: .models),
                  defaultSelection: try values.decode(ScriptAISettings.self, forKey: .defaultSelection))
    }

    func model(for selection: ScriptAISettings?) -> Model? {
        guard let selection else { return nil }
        return models.first { $0.id == selection.model && $0.provider == selection.provider }
    }

    func accepts(_ selection: ScriptAISettings?) -> Bool {
        guard let selection, let model = model(for: selection) else { return false }
        return model.efforts.contains(selection.effort)
    }

    func selection(provider: String, modelID: String? = nil) -> ScriptAISettings? {
        guard let model = models.first(where: { $0.provider == provider && (modelID == nil || $0.id == modelID) }) else { return nil }
        return ScriptAISettings(provider: provider, model: model.id)
    }
}
