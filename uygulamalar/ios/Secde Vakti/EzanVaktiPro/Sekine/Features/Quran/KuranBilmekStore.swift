import Foundation
import AVFoundation
import SwiftUI

// MARK: - Models for Kuran Bilmek Kelime Mana Meal

struct KBChapter: Codable, Identifiable, Hashable {
    let id: Int
    let revelation_place: String
    let revelation_order: Int
    let bismillah_pre: Bool
    let name_simple: String
    let name_complex: String
    let name_arabic: String
    let verses_count: Int
    let pages: [Int]
    let translated_name: KBTranslatedName

    struct KBTranslatedName: Codable, Hashable {
        let language_name: String?
        let name: String
    }

    var turkishName: String {
        switch id {
        case 1: return "Fâtiha"
        case 2: return "Bakara"
        case 3: return "Âl-i İmrân"
        case 4: return "Nisâ"
        case 5: return "Mâide"
        case 6: return "En'âm"
        case 7: return "A'râf"
        case 8: return "Enfâl"
        case 9: return "Tevbe"
        case 10: return "Yûnus"
        case 11: return "Hûd"
        case 12: return "Yûsuf"
        case 13: return "Ra'd"
        case 14: return "İbrâhîm"
        case 15: return "Hicr"
        case 16: return "Nahl"
        case 17: return "İsrâ"
        case 18: return "Kehf"
        case 19: return "Meryem"
        case 20: return "Tâhâ"
        case 21: return "Enbiyâ"
        case 22: return "Hac"
        case 23: return "Mü'minûn"
        case 24: return "Nûr"
        case 25: return "Furkan"
        case 26: return "Şuarâ"
        case 27: return "Neml"
        case 28: return "Kasas"
        case 29: return "Ankebût"
        case 30: return "Rûm"
        case 31: return "Lokmân"
        case 32: return "Secde"
        case 33: return "Ahzâb"
        case 34: return "Sebe'"
        case 35: return "Fâtır"
        case 36: return "Yâsîn"
        case 37: return "Sâffât"
        case 38: return "Sâd"
        case 39: return "Zümer"
        case 40: return "Mü'min"
        case 41: return "Fussilet"
        case 42: return "Şûrâ"
        case 43: return "Zuhruf"
        case 44: return "Duhân"
        case 45: return "Câsiye"
        case 46: return "Ahkâf"
        case 47: return "Muhammed"
        case 48: return "Fetih"
        case 49: return "Hucurât"
        case 50: return "Kâf"
        case 51: return "Zâriyât"
        case 52: return "Tûr"
        case 53: return "Necm"
        case 54: return "Kamer"
        case 55: return "Rahmân"
        case 56: return "Vâkıa"
        case 57: return "Hadîd"
        case 58: return "Mücâdele"
        case 59: return "Haşr"
        case 60: return "Mümtehine"
        case 61: return "Saf"
        case 62: return "Cuma"
        case 63: return "Münâfikûn"
        case 64: return "Tegâbün"
        case 65: return "Talâk"
        case 66: return "Tahrîm"
        case 67: return "Mülk"
        case 68: return "Kalem"
        case 69: return "Hâkka"
        case 70: return "Meâric"
        case 71: return "Nûh"
        case 72: return "Cin"
        case 73: return "Müzzemmil"
        case 74: return "Müddessir"
        case 75: return "Kıyâme"
        case 76: return "İnsân"
        case 77: return "Mürselât"
        case 78: return "Nebe'"
        case 79: return "Nâziât"
        case 80: return "Abese"
        case 81: return "Tekvîr"
        case 82: return "İnfitâr"
        case 83: return "Mutaffifîn"
        case 84: return "İnşikâk"
        case 85: return "Bürûc"
        case 86: return "Târık"
        case 87: return "A'lâ"
        case 88: return "Gâşiye"
        case 89: return "Fecr"
        case 90: return "Beled"
        case 91: return "Şems"
        case 92: return "Leyl"
        case 93: return "Duhâ"
        case 94: return "İnşirâh"
        case 95: return "Tîn"
        case 96: return "Alak"
        case 97: return "Kadir"
        case 98: return "Beyyine"
        case 99: return "Zilzâl"
        case 100: return "Âdiyât"
        case 101: return "Kâria"
        case 102: return "Tekâsür"
        case 103: return "Asr"
        case 104: return "Hümeze"
        case 105: return "Fîl"
        case 106: return "Kureyş"
        case 107: return "Mâûn"
        case 108: return "Kevser"
        case 109: return "Kâfirûn"
        case 110: return "Nasr"
        case 111: return "Tebbet"
        case 112: return "İhlâs"
        case 113: return "Felak"
        case 114: return "Nâs"
        default: return translated_name.name
        }
    }

    var revelationPlaceTurkish: String {
        revelation_place.lowercased() == "makkah" ? "Mekke" : "Medine"
    }

    var arabicBannerSubtitle: String {
        let placeAr = revelation_place.lowercased() == "makkah" ? "مَكِّيَّةٌ" : "مَدَنِيَّةٌ"
        return "\(placeAr) وَهِيَ \(verses_count) آيَةٌ - الترتيب الوحى \(revelation_order)"
    }

    var startPage: Int {
        pages.first ?? 1
    }
}

struct KBVerse: Codable, Identifiable, Hashable {
    let id: Int
    let verse_number: Int
    let verse_key: String
    let hizb_number: Int?
    let rub_el_hizb_number: Int?
    let page_number: Int?
    let juz_number: Int?
    let words: [KBWord]
    let translations: [KBTranslation]?

    var surahId: Int {
        Int(verse_key.split(separator: ":").first ?? "1") ?? 1
    }

    var actualWords: [KBWord] {
        words.filter { $0.char_type_name == "word" }
    }

    var fullArabicText: String {
        actualWords.compactMap { $0.text_uthmani ?? $0.text }.joined(separator: " ")
    }

    func translationText(for resourceId: Int) -> String? {
        guard let raw = translations?.first(where: { $0.resource_id == resourceId })?.text else { return nil }
        return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

struct KBWord: Codable, Identifiable, Hashable {
    let id: Int
    let position: Int
    let audio_url: String?
    let char_type_name: String
    let text_uthmani: String?
    let text_indopak: String?
    let text: String?
    let translation: KBWordText?
    let transliteration: KBWordText?

    struct KBWordText: Codable, Hashable {
        let text: String?
        let language_name: String?
    }

    var arabicDisplay: String {
        text_uthmani ?? text_indopak ?? text ?? ""
    }

    var hasTurkishMeaning: Bool {
        ["turkish", "tr", "türkçe"].contains(translation?.language_name?.lowercased() ?? "")
            && !(translation?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var turkishMeaning: String {
        guard hasTurkishMeaning else { return "Türkçe anlam henüz yok" }
        return translation?.text ?? ""
    }

    var turkishTransliteration: String {
        guard let raw = transliteration?.text, !raw.isEmpty else { return "" }
        // Latin transcription is a reading aid; never insert letters into Arabic text.
        return raw.replacingOccurrences(of: "ā", with: "â")
            .replacingOccurrences(of: "ī", with: "î").replacingOccurrences(of: "ū", with: "û")
            .replacingOccurrences(of: "ḥ", with: "h").replacingOccurrences(of: "ṣ", with: "s")
            .replacingOccurrences(of: "ḍ", with: "d").replacingOccurrences(of: "ṭ", with: "t")
            .replacingOccurrences(of: "ẓ", with: "z").replacingOccurrences(of: "sh", with: "ş")
            .replacingOccurrences(of: "th", with: "s").replacingOccurrences(of: "kh", with: "h")
            .replacingOccurrences(of: "gh", with: "ğ").replacingOccurrences(of: "w", with: "v")
            .replacingOccurrences(of: "j", with: "c")
    }

    var arabicRootLetters: String {
        ArabicRootExtractor.extractRoot(from: arabicDisplay).map(String.init).joined(separator: " ")
    }

    var fullAudioURL: URL? {
        guard let path = audio_url, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "https://audio.qurancdn.com/\(path)")
    }
}

struct KBTranslation: Codable, Identifiable, Hashable {
    let id: Int?
    let resource_id: Int
    let text: String
}

// MARK: - Arabic Triliteral Root Extractor (Sülâsi Kök Tahlili)

enum ArabicRootExtractor {
    private static let knownRoots: [String: String] = [
        "بسم": "س م و",
        "الله": "أ ل ه",
        "الرحمن": "ر ح م",
        "الرحيم": "ر ح م",
        "الحمد": "ح م د",
        "لله": "أ ل ه",
        "رب": "ر ب ب",
        "العالمين": "ع ل م",
        "مالك": "م ل ك",
        "ملك": "م ل ك",
        "يوم": "ي و م",
        "الدين": "د ي ن",
        "إياك": "أ ي ي",
        "نعبد": "ع ب د",
        "نستعين": "ع و ن",
        "اهدنا": "ه د ي",
        "الصراط": "ص ر ط",
        "المستقيم": "ق و م",
        "الذين": "ل ذ ي",
        "أنعمت": "ن ع م",
        "عليهم": "ع ل و",
        "غير": "غ ي ر",
        "المغضوب": "غ ض ب",
        "الضالين": "ض ل ل",
        "أحصيناه": "ح ص ي",
        "نحيي": "ح ي ي",
        "الموتى": "م و ت",
        "نكتب": "ك ت ب",
        "إمام": "أ م م",
        "مبين": "ب ي ن",
        "القرآن": "ق ر أ",
        "الحكيم": "ح ك م",
        "المرسلين": "ر س ل",
        "تنزيل": "ن ز ل",
        "العزيز": "ع ز ز",
        "الصلاة": "ص ل و",
        "الصلوة": "ص ل و",
        "الزكاة": "ز ك و",
        "الزكوة": "ز ك و",
        "يؤمنون": "أ م ن",
        "الغيب": "غ ي ب",
        "ينفقون": "ن ف ق"
    ]

    static func cleanConsonants(_ word: String) -> String {
        // Remove harakat, tatweel, sukun, shadda, small alef, etc.
        let diacritics = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0653}\u{0654}\u{0655}\u{0670}\u{0640}\u{06D6}\u{06D7}\u{06D8}\u{06D9}\u{06DA}\u{06DB}\u{06DC}\u{06DF}\u{06E0}\u{06E1}\u{06E2}\u{06E3}\u{06E4}\u{06E5}\u{06E6}\u{06E7}\u{06E8}\u{06EA}\u{06EB}\u{06EC}\u{06ED}")
        let normalized = word.unicodeScalars.filter { !diacritics.contains($0) }.map { Character($0) }
        var str = String(normalized)
        str = str.replacingOccurrences(of: "ٱ", with: "ا")
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ة", with: "ه")
        return str
    }

    static func extractRoot(from rawWord: String) -> [Character] {
        let cleaned = cleanConsonants(rawWord)
        for (k, v) in knownRoots {
            if cleanConsonants(k) == cleaned {
                return v.split(separator: " ").compactMap { $0.first }
            }
        }

        // Unknown words and loanwords must not receive a fabricated triliteral root.
        return []
    }
}

// MARK: - Bookmarks, Favorites, and Personal Notes Models

struct KBBookmark: Codable, Identifiable, Equatable {
    var id: String { "\(surahId):\(ayahNumber)" }
    let surahId: Int
    let surahName: String
    let ayahNumber: Int
    let pageNumber: Int
    let dateAdded: Date
}

struct KBVerseNote: Codable, Identifiable, Equatable {
    var id: String { "\(surahId):\(ayahNumber)" }
    let surahId: Int
    let surahName: String
    let ayahNumber: Int
    var noteText: String
    var updatedAt: Date
}

struct KBAsriSerif: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let surahId: Int
    let surahName: String
    let totalAyahs: Int
    let startAyah: Int
    let endAyah: Int
}

struct KBTopicItem: Identifiable {
    let id = UUID()
    let title: String
    let query: String
    let icon: String
    let description: String
}

// MARK: - Main Store for Kuran Bilmek

@MainActor
final class KuranBilmekStore: ObservableObject {
    static let shared = KuranBilmekStore()

    // Display settings matching Screenshot 3 ("Ana sayfa görünüm ayarları...")
    @Published var showMushafOnly: Bool = false
    @Published var showWordMeaning: Bool = true
    @Published var showWordLatin: Bool = true
    @Published var showVerseTranslations: Bool = true

    // Active Turkish meal authors
    @Published var showMealDiyanet: Bool = true       // 77
    @Published var fontSizeScale: Double = (UserDefaults.standard.object(forKey: "kb.fontSizeScale") as? Double) ?? 1.0 {
        didSet { UserDefaults.standard.set(fontSizeScale, forKey: "kb.fontSizeScale") }
    }
    @Published var arabicFontScale: Double = (UserDefaults.standard.object(forKey: "kb.arabicFontScale") as? Double) ?? 1.08 {
        didSet { UserDefaults.standard.set(arabicFontScale, forKey: "kb.arabicFontScale") }
    }
    @Published var turkishFontScale: Double = (UserDefaults.standard.object(forKey: "kb.turkishFontScale") as? Double) ?? 1.0 {
        didSet { UserDefaults.standard.set(turkishFontScale, forKey: "kb.turkishFontScale") }
    }
    @Published var arabicFontStyle: KBArabicFontStyle = KBArabicFontStyle(rawValue: UserDefaults.standard.string(forKey: "kb.arabicFontStyle") ?? "") ?? .amiriQuran {
        didSet { UserDefaults.standard.set(arabicFontStyle.rawValue, forKey: "kb.arabicFontStyle") }
    }
    @Published var turkishFontStyle: KBTurkishFontStyle = KBTurkishFontStyle(rawValue: UserDefaults.standard.string(forKey: "kb.turkishFontStyle") ?? "") ?? .bookSerif {
        didSet { UserDefaults.standard.set(turkishFontStyle.rawValue, forKey: "kb.turkishFontStyle") }
    }
    @Published var showColorTajweed: Bool = true
    @Published var showTajweedLegend: Bool = true
    @Published var selectedReciter: String = "ar.alafasy"

    @Published var chapters: [KBChapter] = []
    @Published var currentSurahId: Int = 1
    @Published var verses: [KBVerse] = []
    @Published var isLoading: Bool = false

    @Published var bookmarks: [KBBookmark] = []
    @Published var favoriteVerses: [KBBookmark] = []
    @Published var notes: [KBVerseNote] = []

    // Word audio player
    private var wordPlayer: AVPlayer?
    @Published var isPlayingWordId: Int? = nil

    // Search results
    @Published var searchResults: [KBSearchResultItem] = []
    @Published var searchTotalCount: Int = 0
    @Published private(set) var recentSearches = UserDefaults.standard.stringArray(forKey: "kb.search.history.v1") ?? []
    func rememberSearch(_ query: String) {
        recentSearches = KBAyahSearch.updatedHistory(recentSearches, adding: query)
        UserDefaults.standard.set(recentSearches, forKey: "kb.search.history.v1")
    }
    func clearSearchHistory() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "kb.search.history.v1")
    }
    @Published var lastSearchQuery = ""
    @Published var searchStatus = "Türkçe meal, Arapça metin veya sure–ayet ile arayın."
    private var searchGeneration = UUID()
    @Published var isSearching: Bool = false

    @Published private(set) var fullSearchCount = 0
    private var fullSearchIndex: KBFullQuranIndex?

    var fullSearchSource: String { fullSearchIndex?.source ?? "" }
    func fullAyah(for key: String) -> KBFullAyah? { fullSearchIndex?.byKey[key] }
    func adjacentFullAyah(_ ayah: KBFullAyah, offset: Int) -> KBFullAyah? {
        guard let index = fullSearchIndex, let position = index.positions[ayah.id], index.verses.indices.contains(position + offset) else { return nil }
        return index.verses[position + offset]
    }
    func hasWordVerse(_ ayah: KBFullAyah) -> Bool {
        cachedVersesBySurah[ayah.surah]?.contains { $0.verse_key == ayah.id } ?? false
    }

    private var bundledVerses: [String: [KBVerse]] = [:]
    private var cachedVersesBySurah: [Int: [KBVerse]] = [:]

    let reciters: [(id: String, name: String)] = [
        ("ar.alafasy", "Mişari Raşid el-Afasi"),
        ("ar.abdurrahmaansudais", "Abdurrahman es-Sudeys (Kâbe İmamı)"),
        ("ar.mahermuaiqly", "Mahir el-Muaykli (Kâbe İmamı)"),
        ("ar.saoodshuraym", "Suud eş-Şureym (Kâbe İmamı)"),
        ("ar.abdulbasitmurattal", "Abdülbasit Abdüssamed (Murattel)"),
        ("ar.abdulbasitmujawwad", "Abdülbasit Abdüssamed (Mücevved)"),
        ("ar.mustafaismail", "Şeyh Mustafa İsmail (Mısır)"),
        ("ar.husary", "Mahmud Halil el-Husari (Muallim)"),
        ("ar.minshawi", "Muhammed Sıddık el-Minşavi"),
        ("ar.ghamadi", "Sa'd el-Gâmidî (İkra Hafızı)"),
        ("ar.qatami", "Nâsır el-Katâmî"),
        ("ar.dussary", "Yâsir ed-Devserî (Kâbe İmamı)"),
        ("ar.ajamy", "Ahmed bin Ali el-Acemî"),
        ("ar.hudhaify", "Ali el-Huzeyfî (Medine İmamı)")
    ]

    let asriSerifList: [KBAsriSerif] = [
        KBAsriSerif(number: 1, title: "Âmenerrasûlü", surahId: 2, surahName: "Bakara", totalAyahs: 286, startAyah: 285, endAyah: 286),
        KBAsriSerif(number: 2, title: "Hüvallahüllezi", surahId: 59, surahName: "Haşr", totalAyahs: 24, startAyah: 22, endAyah: 24),
        KBAsriSerif(number: 3, title: "Âyetü'l-Kürsi", surahId: 2, surahName: "Bakara", totalAyahs: 286, startAyah: 255, endAyah: 255),
        KBAsriSerif(number: 4, title: "Tüm gün ve geceler için", surahId: 23, surahName: "Mü'minûn", totalAyahs: 118, startAyah: 1, endAyah: 11),
        KBAsriSerif(number: 5, title: "Ramazan ile ilgili olarak", surahId: 2, surahName: "Bakara", totalAyahs: 286, startAyah: 183, endAyah: 186),
        KBAsriSerif(number: 6, title: "Kur'an-ı Kerim ile ilgili toplantılarda", surahId: 35, surahName: "Fâtır", totalAyahs: 45, startAyah: 29, endAyah: 30),
        KBAsriSerif(number: 7, title: "Anne-Baba Hakkı ve Ahlak Esasları", surahId: 17, surahName: "İsrâ", totalAyahs: 111, startAyah: 23, endAyah: 29),
        KBAsriSerif(number: 8, title: "Yâsîn-i Şerif Başlangıcı", surahId: 36, surahName: "Yâsîn", totalAyahs: 83, startAyah: 1, endAyah: 12),
        KBAsriSerif(number: 9, title: "Mülk (Tebâreke) Sûresi", surahId: 67, surahName: "Mülk", totalAyahs: 30, startAyah: 1, endAyah: 5)
    ]

    let topics: [KBTopicItem] = [
        KBTopicItem(title: "Namaz ve İbadet", query: "namaz", icon: "figure.mind.and.body", description: "Kur'an'da namazın önemi, vakitleri ve huşû ile ilgili ayetler"),
        KBTopicItem(title: "Sabır ve Tevekkül", query: "sabır", icon: "heart.circle.fill", description: "Musibetlere karşı sabır, metanet ve Allah'a güven"),
        KBTopicItem(title: "Dua ve İstiğfar", query: "dua", icon: "hands.sparkles.fill", description: "Kur'an'da geçen Rabbenâ duaları ve bağışlanma ayetleri"),
        KBTopicItem(title: "Zekat ve İnfak", query: "zekat", icon: "gift.fill", description: "Mallardan Allah yolunda harcama, sadaka ve zekat hükümleri"),
        KBTopicItem(title: "Nikah ve Aile Hayatı", query: "nikah", icon: "person.2.fill", description: "Evlilik, eşlerin hakları ve aile huzuru ile ilgili ayetler"),
        KBTopicItem(title: "Anne ve Baba Hakkı", query: "anne baba", icon: "figure.2.and.child.holdinghands", description: "Ebeveyne iyilik (ihsan), merhamet ve saygı emirleri"),
        KBTopicItem(title: "Adalet ve Doğruluk", query: "adalet", icon: "scalemass.fill", description: "Hakkaniyetle hükmetmek, şahitlik ve dürüstlük"),
        KBTopicItem(title: "Tevbe ve Rahmet", query: "tevbe", icon: "sparkles", description: "Allah'ın sonsuz مغفرت ve rahmeti, günahlardan dönüş"),
        KBTopicItem(title: "Rızık ve Şükür", query: "rızık", icon: "leaf.fill", description: "Helal kazanç, bereket ve nimetlere şükür"),
        KBTopicItem(title: "Cennet ve Müjdeler", query: "cennet", icon: "sun.max.fill", description: "Müminlere vaat edilen ebedi saadet ve nimetler"),
        KBTopicItem(title: "Kıyamet ve Ahiret", query: "kıyamet", icon: "hourglass", description: "Hesap günü, diriliş (ba's) ve ahiret hayatı"),
        KBTopicItem(title: "İlim, Akıl ve Tefekkür", query: "akıl", icon: "brain.head.profile", description: "Kainatı düşünme, ilim öğrenme ve ibret alma")
    ]

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-uiTestSurah"), index + 1 < args.count,
           let surah = Int(args[index + 1]), (1...114).contains(surah) { currentSurahId = surah }
        #endif
        loadUserData()
        loadBundledDatabaseAsync()
    }

    var currentChapter: KBChapter? {
        chapters.first(where: { $0.id == currentSurahId }) ?? chapters.first
    }

    var currentHeaderSubtitle: String {
        let chName = currentChapter?.turkishName ?? "Fâtiha"
        let firstVerse = verses.first
        let juz = firstVerse?.juz_number ?? 1
        let hizb = firstVerse?.hizb_number ?? 1
        let page = firstVerse?.page_number ?? currentChapter?.startPage ?? 1
        return "\(chName)/\(currentSurahId) | \(juz). Cüz | \(hizb). Hizb | Syf. \(page)/604"
    }

    private func loadBundledDatabaseAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fullIndex = KBFullQuranIndex.load()
            guard let url = Bundle.main.url(forResource: "kuran_bilmek_offline", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                return
            }
            struct OfflineBundle: Codable {
                let chapters: [KBChapter]
                let bundled_verses: [String: [KBVerse]]
            }
            guard let decoded = try? JSONDecoder().decode(OfflineBundle.self, from: data) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fullSearchIndex = fullIndex
                self.fullSearchCount = fullIndex?.verses.count ?? 0
                self.chapters = decoded.chapters
                self.bundledVerses = decoded.bundled_verses
                for (k, v) in decoded.bundled_verses {
                    if let sid = Int(k) {
                        self.cachedVersesBySurah[sid] = v
                    }
                }
                if self.verses.isEmpty, let initial = decoded.bundled_verses["\(self.currentSurahId)"] ?? decoded.bundled_verses["1"] {
                    self.verses = initial
                }
            }
        }
    }

    func selectSurah(_ surahId: Int) async {
        self.currentSurahId = surahId
        if let cached = cachedVersesBySurah[surahId], !cached.isEmpty {
            self.verses = cached
            return
        }
        self.isLoading = true
        defer { self.isLoading = false }

        let urlStr = "https://api.quran.com/api/v4/verses/by_chapter/\(surahId)?language=tr&words=true&word_fields=text_uthmani,text_indopak,transliteration&translations=77&per_page=300"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Resp: Codable { let verses: [KBVerse] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            self.cachedVersesBySurah[surahId] = decoded.verses
            self.verses = decoded.verses
        } catch {
            print("KuranBilmek fetch error: \(error)")
        }
    }

    func loadByPage(_ page: Int) async {
        let clamped = max(1, min(604, page))
        self.isLoading = true
        defer { self.isLoading = false }
        let urlStr = "https://api.quran.com/api/v4/verses/by_page/\(clamped)?language=tr&words=true&word_fields=text_uthmani,text_indopak,transliteration&translations=77&per_page=50"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Resp: Codable { let verses: [KBVerse] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            if let first = decoded.verses.first {
                self.currentSurahId = first.surahId
            }
            self.verses = decoded.verses
        } catch {
            print("Load page error: \(error)")
        }
    }

    func loadByJuz(_ juz: Int) async {
        let clamped = max(1, min(30, juz))
        self.isLoading = true
        defer { self.isLoading = false }
        let urlStr = "https://api.quran.com/api/v4/verses/by_juz/\(clamped)?language=tr&words=true&word_fields=text_uthmani,text_indopak,transliteration&translations=77&per_page=50"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Resp: Codable { let verses: [KBVerse] }
            let decoded = try JSONDecoder().decode(Resp.self, from: data)
            if let first = decoded.verses.first {
                self.currentSurahId = first.surahId
            }
            self.verses = decoded.verses
        } catch {
            print("Load juz error: \(error)")
        }
    }

    // MARK: - Word Audio Playback

    func stopWordAudio() {
        wordPlayer?.pause(); wordPlayer = nil; isPlayingWordId = nil
    }

    func playWordAudio(_ word: KBWord) {
        QFSyncPlayer.shared.stop()
        stopWordAudio()
        isPlayingWordId = word.id
        if let url = word.fullAudioURL {
            let item = AVPlayerItem(url: url)
            wordPlayer = AVPlayer(playerItem: item)
            wordPlayer?.play()
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if self.isPlayingWordId == word.id {
                    self.isPlayingWordId = nil
                }
            }
        } else {
            AdhanPlayer.shared.speakText(word.arabicDisplay, language: "ar-SA")
            isPlayingWordId = nil
        }
    }

    func playSingleAyahAudio(surahId: Int, ayahNumber: Int) {
        IkraAudioAndRadioCenter.shared.selectedArabicReciterId = selectedReciter
        let verseMeal = verses.first(where: { $0.verse_number == ayahNumber })?.translationText(for: 77)
        IkraAudioAndRadioCenter.shared.playAyahIkra(
            surahId: surahId,
            ayahNumber: ayahNumber,
            surahName: surahName(for: surahId),
            fallbackTurkishText: verseMeal
        )
    }

    func playSingleAyahTurkishMealStudio(surahId: Int, ayahNumber: Int) {
        let sPad = String(format: "%03d", surahId)
        let aPad = String(format: "%03d", ayahNumber)
        let sName = surahName(for: surahId)
        let bundledName = "ayet_meal_\(sPad)_\(aPad)"
        if let bURL = Bundle.main.url(forResource: bundledName, withExtension: "mp3") {
            AdhanPlayer.shared.playLocalOrRemoteFile(
                url: bURL,
                title: "\(sName) Sûresi \(ayahNumber). Ayet (Türkçe Sesli Meal)",
                subtitle: "Sanatçı: Seyfullah Kartal · Stüdyo Kaydı"
            )
            return
        }
        if let remoteURL = URL(string: "https://archive.org/download/seyfullah-kartal-ayet-ayet-meal-arsivi/\(sPad)_\(aPad).mp3") {
            AdhanPlayer.shared.playLocalOrRemoteFile(
                url: remoteURL,
                title: "\(sName) Sûresi \(ayahNumber). Ayet (Türkçe Sesli Meal)",
                subtitle: "Sanatçı: Seyfullah Kartal · Stüdyo Sesli Meal"
            )
        }
    }

    func surahName(for id: Int) -> String {
        chapters.first(where: { $0.id == id })?.turkishName ?? "\(id). Sûre"
    }

    // MARK: - Word / Root Concordance & Full Quran Search

    func findLocalOccurrences(of word: KBWord) -> [(surahName: String, verse: KBVerse, matchedWord: KBWord)] {
        let targetClean = ArabicRootExtractor.cleanConsonants(word.arabicDisplay)
        let targetRoot = word.arabicRootLetters
        var matches: [(String, KBVerse, KBWord)] = []

        for (sid, vList) in cachedVersesBySurah.sorted(by: { $0.key < $1.key }) {
            let sName = surahName(for: sid)
            for v in vList {
                for w in v.actualWords {
                    let wClean = ArabicRootExtractor.cleanConsonants(w.arabicDisplay)
                    if wClean == targetClean || (!targetRoot.isEmpty && w.arabicRootLetters == targetRoot) {
                        matches.append((sName, v, w))
                        break
                    }
                }
            }
        }
        return matches
    }

    func performSearch(query: String, surahID: Int? = nil) async {
        lastSearchQuery = query
        let generation = UUID()
        searchGeneration = generation
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = []
        searchTotalCount = 0
        isSearching = false
        guard !trimmed.isEmpty else {
            searchStatus = "Türkçe meal, Arapça metin veya sure–ayet ile arayın."
            return
        }
        isSearching = true
        defer { if searchGeneration == generation { isSearching = false } }
        let reference = KBAyahSearch.reference(trimmed, chapters: chapters)
        let q = KBAyahSearch.normalize(trimmed)
        guard !q.isEmpty else { searchStatus = "Bir kelime veya sure–ayet numarası yazın."; return }
        if let index = fullSearchIndex {
            let matches = index.search(query: trimmed, chapters: chapters, surahID: surahID)
            searchResults = matches.map { ayah in
                KBSearchResultItem(id: ayah.id, surahId: ayah.surah,
                    surahName: surahName(for: ayah.surah), ayahNumber: ayah.number,
                    pageNumber: 0, arabicText: ayah.arabic_text, turkishText: ayah.translation,
                    highlightedWord: nil, highlightedMeaning: nil)
            }
            searchTotalCount = matches.count
            searchStatus = (surahID.map { surahName(for: $0) + " suresinde çevrimdışı arama\n" } ?? "114 sure · 6.236 ayet · Çevrimdışı arama\n") + index.source
            return
        }
        var items: [KBSearchResultItem] = []
        for (sid, verseList) in cachedVersesBySurah.sorted(by: { $0.key < $1.key }) {
            if let surahID, sid != surahID { continue }
            for verse in verseList {
                let meal = verse.translationText(for: 77) ?? ""
                let word = verse.actualWords.first {
                    KBAyahSearch.matches($0.turkishMeaning, query: q) ||
                    KBAyahSearch.matches($0.arabicDisplay, query: q)
                }
                let matched = reference.map { $0.surah == sid && $0.ayah == verse.verse_number } ??
                    (word != nil || KBAyahSearch.matches(meal, query: q) || KBAyahSearch.matches(verse.fullArabicText, query: q))
                if matched {
                    items.append(KBSearchResultItem(id: verse.verse_key, surahId: sid,
                        surahName: surahName(for: sid), ayahNumber: verse.verse_number,
                        pageNumber: verse.page_number ?? 1, arabicText: verse.fullArabicText,
                        turkishText: meal, highlightedWord: word?.arabicDisplay,
                        highlightedMeaning: word?.turkishMeaning))
                }
            }
        }
        searchResults = items
        searchTotalCount = items.count
        let coverage = cachedVersesBySurah.values.reduce(0) { $0 + $1.count }
        searchStatus = "Cihazdaki \(coverage) ayet tarandı."
        if reference != nil && !items.isEmpty { return }
        var remoteTotal = 0
        var onlineSucceeded = false
        var components = URLComponents(string: "https://api.quran.com/api/v4/search")!
        let remoteQuery = reference.map { "\($0.surah):\($0.ayah)" } ?? trimmed
        components.queryItems = [URLQueryItem(name: "q", value: remoteQuery),
            URLQueryItem(name: "language", value: "tr"), URLQueryItem(name: "size", value: "40")]
        if let url = components.url {
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 12))
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                struct SearchAPIResp: Codable {
                    struct SearchNode: Codable {
                        let total_results: Int?
                        let results: [ResultNode]?
                    }
                    struct ResultNode: Codable {
                        let verse_key: String
                        let text: String
                        struct TransNode: Codable { let text: String? }
                        let translations: [TransNode]?
                    }
                    let search: SearchNode?
                }
                let decoded = try JSONDecoder().decode(SearchAPIResp.self, from: data)
                if let total = decoded.search?.total_results, total > 0 {
                    remoteTotal = total
                }
                for r in decoded.search?.results ?? [] {
                    if !items.contains(where: { $0.id == r.verse_key }) {
                        let parts = r.verse_key.split(separator: ":")
                        let sid = Int(parts.first ?? "1") ?? 1
                        let anum = Int(parts.last ?? "1") ?? 1
                        let cleanTrans = (r.translations?.first?.text ?? "")
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        items.append(
                            KBSearchResultItem(
                                id: r.verse_key,
                                surahId: sid,
                                surahName: surahName(for: sid),
                                ayahNumber: anum,
                                pageNumber: chapters.first(where: { $0.id == sid })?.startPage ?? 1,
                                arabicText: r.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                                turkishText: cleanTrans,
                                highlightedWord: trimmed,
                                highlightedMeaning: nil
                            )
                        )
                    }
                }
                onlineSucceeded = decoded.search != nil
            } catch { /* Local results stay available when online search fails. */ }
        }
        guard searchGeneration == generation, !Task.isCancelled else { return }
        if let reference { items = items.filter { $0.surahId == reference.surah && $0.ayahNumber == reference.ayah } }
        if let surahID { items = items.filter { $0.surahId == surahID } }
        searchResults = items
        searchTotalCount = max(items.count, reference == nil && surahID == nil ? remoteTotal : items.count)
        searchStatus = onlineSucceeded
            ? "\(items.count) sonuç gösteriliyor."
            : "Çevrimiçi arama kullanılamıyor. Cihazdaki \(coverage) ayet içinde arandı; tüm Kur’an’ı kapsamayabilir."
    }

    // MARK: - Persistence for Bookmarks, Favorites, Notes

    func toggleBookmark(verse: KBVerse) {
        let sName = surahName(for: verse.surahId)
        let item = KBBookmark(
            surahId: verse.surahId,
            surahName: sName,
            ayahNumber: verse.verse_number,
            pageNumber: verse.page_number ?? 1,
            dateAdded: Date()
        )
        if let idx = bookmarks.firstIndex(where: { $0.id == item.id }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(item, at: 0)
        }
        saveUserData()
    }

    func isBookmarked(_ verse: KBVerse) -> Bool {
        let key = "\(verse.surahId):\(verse.verse_number)"
        return bookmarks.contains(where: { $0.id == key })
    }

    func toggleFavorite(verse: KBVerse) {
        let sName = surahName(for: verse.surahId)
        let item = KBBookmark(
            surahId: verse.surahId,
            surahName: sName,
            ayahNumber: verse.verse_number,
            pageNumber: verse.page_number ?? 1,
            dateAdded: Date()
        )
        if let idx = favoriteVerses.firstIndex(where: { $0.id == item.id }) {
            favoriteVerses.remove(at: idx)
        } else {
            favoriteVerses.insert(item, at: 0)
        }
        saveUserData()
    }

    func isFavorite(_ verse: KBVerse) -> Bool {
        let key = "\(verse.surahId):\(verse.verse_number)"
        return favoriteVerses.contains(where: { $0.id == key })
    }

    func saveNote(surahId: Int, ayahNumber: Int, text: String) {
        let sName = surahName(for: surahId)
        let key = "\(surahId):\(ayahNumber)"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeAll(where: { $0.id == key })
        } else if let idx = notes.firstIndex(where: { $0.id == key }) {
            notes[idx].noteText = trimmed
            notes[idx].updatedAt = Date()
        } else {
            notes.insert(
                KBVerseNote(surahId: surahId, surahName: sName, ayahNumber: ayahNumber, noteText: trimmed, updatedAt: Date()),
                at: 0
            )
        }
        saveUserData()
    }

    func noteText(for surahId: Int, ayahNumber: Int) -> String {
        let key = "\(surahId):\(ayahNumber)"
        return notes.first(where: { $0.id == key })?.noteText ?? ""
    }

    private func loadUserData() {
        let d = UserDefaults.standard
        if let bData = d.data(forKey: "kb_bookmarks_v1"),
           let b = try? JSONDecoder().decode([KBBookmark].self, from: bData) {
            self.bookmarks = b
        }
        if let fData = d.data(forKey: "kb_favorites_v1"),
           let f = try? JSONDecoder().decode([KBBookmark].self, from: fData) {
            self.favoriteVerses = f
        }
        if let nData = d.data(forKey: "kb_notes_v1"),
           let n = try? JSONDecoder().decode([KBVerseNote].self, from: nData) {
            self.notes = n
        }
    }

    private func saveUserData() {
        let d = UserDefaults.standard
        if let bData = try? JSONEncoder().encode(bookmarks) {
            d.set(bData, forKey: "kb_bookmarks_v1")
        }
        if let fData = try? JSONEncoder().encode(favoriteVerses) {
            d.set(fData, forKey: "kb_favorites_v1")
        }
        if let nData = try? JSONEncoder().encode(notes) {
            d.set(nData, forKey: "kb_notes_v1")
        }
    }
}

struct KBSearchResultItem: Identifiable {
    let id: String
    let surahId: Int
    let surahName: String
    let ayahNumber: Int
    let pageNumber: Int
    let arabicText: String
    let turkishText: String
    let highlightedWord: String?
    let highlightedMeaning: String?
}

// Shared normalization keeps Turkish keyboard variants and Arabic vowel marks out of matching.
enum KBAyahSearch {
    static func updatedHistory(_ history: [String], adding query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalize(trimmed)
        guard !key.isEmpty else { return history }
        return Array(([trimmed] + history.filter { normalize($0) != key }).prefix(12))
    }

    static func normalize(_ value: String) -> String {
        let text = ArabicRootExtractor.cleanConsonants(value)
            .lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
        return text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func matches(_ text: String, query: String) -> Bool {
        !query.isEmpty && normalize(text).contains(query)
    }

    static func reference(_ text: String, chapters: [KBChapter]) -> (surah: Int, ayah: Int)? {
        let normalized = normalize(text)
        if ["ayetel kursi", "ayete l kursi", "ayet el kursi", "ayetul kursi"].contains(normalized) { return (2, 255) }
        let parts = normalized.split(separator: " ").map(String.init)
            .filter { !["suresi", "sure", "ayet", "ayeti"].contains($0) }
        guard parts.count >= 2, let ayah = Int(parts.last!) else { return nil }
        let name = parts.dropLast().filter { !["suresi", "sure", "ayet", "ayeti"].contains($0) }.joined()
        let chapter = chapters.first {
            String($0.id) == name || [$0.turkishName, $0.name_simple, $0.name_complex, $0.name_arabic]
                .contains { normalize($0).replacingOccurrences(of: " ", with: "") == name }
        }
        guard let chapter, (1...chapter.verses_count).contains(ayah) else { return nil }
        return (chapter.id, ayah)
    }
}


struct KBFullAyah: Decodable, Identifiable {
    let sura: String
    let aya: String
    let arabic_text: String
    let translation: String
    let footnotes: String
    var id: String { "\(sura):\(aya)" }
    var surah: Int { Int(sura) ?? 0 }
    var number: Int { Int(aya) ?? 0 }
}

final class KBFullQuranIndex {
    struct Document: Decodable {
        struct Metadata: Decodable { let key: String; let version: String; let title: String }
        let metadata: Metadata
        let verses: [KBFullAyah]
    }
    let verses: [KBFullAyah]
    let byKey: [String: KBFullAyah]
    let positions: [String: Int]
    let source: String
    private let searchable: [(KBFullAyah, String, String)]
    private init(_ document: Document) {
        verses = document.verses
        byKey = Dictionary(uniqueKeysWithValues: verses.map { ($0.id, $0) })
        positions = Dictionary(uniqueKeysWithValues: verses.enumerated().map { ($0.element.id, $0.offset) })
        source = "Rowwad Türkçe Meali · QuranEnc.com · v" + document.metadata.version
        searchable = verses.map { ($0, KBAyahSearch.normalize($0.arabic_text), KBAyahSearch.normalize($0.translation)) }
    }
    static func load(bundle: Bundle = .main) -> KBFullQuranIndex? {
        guard let url = bundle.url(forResource: "quranenc", withExtension: "json", subdirectory: "QuranSearch"),
              let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(Document.self, from: data),
              document.verses.count == 6236, Set(document.verses.map(\.id)).count == 6236 else { return nil }
        return KBFullQuranIndex(document)
    }
    func search(query: String, chapters: [KBChapter], surahID: Int? = nil) -> [KBFullAyah] {
        if let ref = KBAyahSearch.reference(query, chapters: chapters) {
            guard surahID == nil || surahID == ref.surah else { return [] }
            return byKey["\(ref.surah):\(ref.ayah)"].map { [$0] } ?? []
        }
        let normalized = KBAyahSearch.normalize(query)
        guard !normalized.isEmpty else { return [] }
        if let chapter = chapters.first(where: { KBAyahSearch.normalize($0.turkishName) == normalized || KBAyahSearch.normalize($0.name_arabic) == normalized }) {
            return verses.filter { $0.surah == chapter.id && (surahID == nil || $0.surah == surahID) }
        }
        return searchable.compactMap { row in
            guard surahID == nil || row.0.surah == surahID else { return nil }
            return row.1.contains(normalized) || row.2.contains(normalized) ? row.0 : nil
        }
    }
}
