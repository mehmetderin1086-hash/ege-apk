import Foundation
import AVFoundation
import SwiftUI
import CoreText

// MARK: - 1. Bundled Arabic Mushaf TTF Font Registrar

enum CustomFontRegistrar {
    private static var didRegister = false

    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        let fontFiles = [
            "AmiriQuran-Regular",
            "Amiri-Regular",
            "Amiri-Bold",
            "ScheherazadeNew-Regular",
            "ScheherazadeNew-Bold",
            "Lateef-Regular", "NotoNaskhArabic", "NotoSansArabic", "Lora", "SourceSerif4", "Roboto"
        ]

        for name in fontFiles {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

// MARK: - 2. Arabic Mushaf & Turkish Typography Styles

enum KBArabicFontStyle: String, CaseIterable, Identifiable {
    case notoNaskh, notoSansArabic
    case amiriQuran = "amiriQuran"
    case scheherazade = "scheherazade"
    case amiriBold = "amiriBold"
    case lateef = "lateef"
    case geezaOsmanli = "geezaOsmanli"
    case damascusModern = "damascusModern"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notoNaskh: return "Noto Naskh Arabic · Nesih"
        case .notoSansArabic: return "Noto Sans Arabic · Modern"
        case .amiriQuran: return "Amiri Quran · Mushaf"
        case .scheherazade: return "Scheherazade New · Nesih"
        case .amiriBold: return "Amiri Rahle Kalın Hat"
        case .lateef: return "Lateef Zarif İnce Hat"
        case .geezaOsmanli: return "Geeza Klasik Hareke Hattı"
        case .damascusModern: return "Damascus Modern Okunaklı Hat"
        }
    }

    var shortBadge: String {
        switch self {
        case .notoNaskh: return "Noto Naskh"
        case .notoSansArabic: return "Noto Sans Arabic"
        case .amiriQuran: return "Amiri Mushaf"
        case .scheherazade: return "Nesih Hattı"
        case .amiriBold: return "Rahle Kalın"
        case .lateef: return "Lateef Hat"
        case .geezaOsmanli: return "Geeza Klasik"
        case .damascusModern: return "Damascus"
        }
    }

    var subtitle: String {
        switch self {
        case .notoNaskh: return "Uzun Arapça metinler için nesih karakterli Noto ailesi"
        case .notoSansArabic: return "Sade çizgili modern Arapça Noto ailesi"
        case .amiriQuran: return "Kur’an işaretleri için hazırlanmış Amiri ailesi"
        case .scheherazade: return "Harekeleri ve tecvid işaretleri ekstra belirgin açık Nesih hattı"
        case .amiriBold: return "Uzaktan ve rahleden okumaya uygun dolgun kaligrafik Kur'an hattı"
        case .lateef: return "Kelime meali kutularında ferah görünüm sağlayan zarif hat"
        case .geezaOsmanli: return "Apple iOS yerel klasik Arapça matbaa hattı"
        case .damascusModern: return "Yeni öğrenenler için harfleri net ayrıştırılmış modern hat"
        }
    }

    func font(size: CGFloat) -> Font {
        CustomFontRegistrar.registerBundledFontsIfNeeded()
        switch self {
        case .notoNaskh: return .custom("NotoNaskhArabic-Regular", size: size)
        case .notoSansArabic: return .custom("NotoSansArabic-Regular", size: size)
        case .amiriQuran:
            return .custom("AmiriQuran-Regular", size: size)
        case .scheherazade:
            return .custom("ScheherazadeNew-Regular", size: size)
        case .amiriBold:
            return .custom("Amiri-Bold", size: size)
        case .lateef:
            return .custom("Lateef-Regular", size: size * 1.15)
        case .geezaOsmanli:
            return .custom("GeezaPro", size: size)
        case .damascusModern:
            return .custom("Damascus", size: size)
        }
    }
}

enum KBTurkishFontStyle: String, CaseIterable, Identifiable {
    case lora, sourceSerif, roboto
    case bookSerif = "bookSerif"
    case palatinoClassic = "palatinoClassic"
    case baskervilleTefsir = "baskervilleTefsir"
    case roundedModern = "roundedModern"
    case systemClean = "systemClean"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lora: return "Lora · Edebî okuma"
        case .sourceSerif: return "Source Serif 4 · Kitap"
        case .roboto: return "Roboto · Modern"
        case .bookSerif: return "Kitap Serif (Klasik Meal Baskısı)"
        case .palatinoClassic: return "Palatino Akademik Tefsir Fontu"
        case .baskervilleTefsir: return "Baskerville Edebi Meal Fontu"
        case .roundedModern: return "Modern Yuvarlak (Göz Yormayan)"
        case .systemClean: return "SF Pro Net (Yüksek Okunurluk)"
        }
    }

    var shortBadge: String {
        switch self {
        case .lora: return "Lora"
        case .sourceSerif: return "Source Serif 4"
        case .roboto: return "Roboto"
        case .bookSerif: return "Kitap Serif"
        case .palatinoClassic: return "Palatino"
        case .baskervilleTefsir: return "Baskerville"
        case .roundedModern: return "Yuvarlak"
        case .systemClean: return "SF Net"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        CustomFontRegistrar.registerBundledFontsIfNeeded()
        switch self {
        case .lora: return .custom("Lora-Regular", size: size).weight(weight)
        case .sourceSerif: return .custom("SourceSerif4Roman-Regular", size: size).weight(weight)
        case .roboto: return .custom("Roboto-Regular", size: size).weight(weight)
        case .bookSerif:
            return .system(size: size, weight: weight, design: .serif)
        case .palatinoClassic:
            return .custom("Palatino-Roman", size: size)
        case .baskervilleTefsir:
            return .custom("Baskerville", size: size)
        case .roundedModern:
            return .system(size: size, weight: weight, design: .rounded)
        case .systemClean:
            return .system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - 3. Renkli Tecvid Motoru (Color-Coded Tajweed Engine)

enum TajweedRuleInfo: String, CaseIterable, Identifiable {
    case ghunnahIkhfa = "Gunne & İhfa"
    case qalqalah = "Kalkale"
    case madd = "Med (Uzatma)"
    case tafkhim = "Kalın / Lafzatullah"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .ghunnahIkhfa: return Color(red: 0.08, green: 0.58, blue: 0.26) // Yeşil
        case .qalqalah: return Color(red: 0.06, green: 0.42, blue: 0.78)     // Mavi
        case .madd: return Color(red: 0.82, green: 0.14, blue: 0.18)         // Kırmızı
        case .tafkhim: return Color(red: 0.72, green: 0.34, blue: 0.02)      // Kehribar/Turuncu
        }
    }

    var explanation: String {
        switch self {
        case .ghunnahIkhfa: return "Şeddeli Nun/Mim (نّ مّ) ve İhfa/İdgam geniz sesi (2 elif tutulur)"
        case .qalqalah: return "Cezimli ق ط ب ج د (Kutbu Cedin) harfleri vurgulu çarptırılarak okunur"
        case .madd: return "Med işareti (ٓ) ve uzatma harfleri 2-4 elif miktarı uzatılır"
        case .tafkhim: return "Kalın harfler (خ ص ض غ ط ق ظ) ve Lafzatullah tok okunur"
        }
    }
}

enum TajweedColorizer {
    private final class CachedText: NSObject {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }
    private static let cache: NSCache<NSString, CachedText> = {
        let cache = NSCache<NSString, CachedText>()
        cache.countLimit = 1500
        return cache
    }()

    private static let qalqalahChars: Set<Character> = ["ق", "ط", "ب", "ج", "د"]
    private static let tafkhimChars: Set<Character> = ["خ", "ص", "ض", "غ", "ظ"]
    private static let ghunnahBaseChars: Set<Character> = ["ن", "م"]

    static func colorizedArabic(_ text: String, defaultColor: Color = .black.opacity(0.9)) -> AttributedString {
        let key = (text + "|" + String(describing: defaultColor)) as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        var result = AttributedString()
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            // Collect base character + all following combining diacritics/marks
            var cluster = String(ch)
            var j = i + 1
            while j < chars.count && isArabicMark(chars[j]) {
                cluster.append(chars[j])
                j += 1
            }

            var attr = AttributedString(cluster)
            let scalars = cluster.unicodeScalars

            // 1. Check Madd (Maddah \u0653, dagger alif \u0670, or long alif/waw/ya with madd)
            if scalars.contains(where: { $0.value == 0x0653 || $0.value == 0x0670 || $0.value == 0x06E4 }) || ch == "آ" {
                attr.foregroundColor = TajweedRuleInfo.madd.color
            }
            // 2. Check Qalqalah (ق ط ب ج د with sukun \u0652 or \u06E1)
            else if qalqalahChars.contains(ch) && scalars.contains(where: { $0.value == 0x0652 || $0.value == 0x06E1 }) {
                attr.foregroundColor = TajweedRuleInfo.qalqalah.color
            }
            // 3. Check Ghunnah / Ikhfa (ن or م with shadda \u0651, sukun, or tanween \u064B-\u064D)
            else if (ghunnahBaseChars.contains(ch) && scalars.contains(where: { $0.value == 0x0651 || $0.value == 0x0652 || $0.value == 0x06E1 })) ||
                    scalars.contains(where: { (0x064B...0x064D).contains($0.value) }) {
                attr.foregroundColor = TajweedRuleInfo.ghunnahIkhfa.color
            }
            // 4. Check Tafkhim (Heavy letters or Qaf/Ta without sukun)
            else if tafkhimChars.contains(ch) || ch == "ق" || ch == "ط" {
                attr.foregroundColor = TajweedRuleInfo.tafkhim.color
            } else {
                attr.foregroundColor = defaultColor
            }

            result.append(attr)
            i = j
        }

        cache.setObject(CachedText(result), forKey: key)
        return result
    }

    private static func isArabicMark(_ c: Character) -> Bool {
        guard let first = c.unicodeScalars.first else { return false }
        let v = first.value
        return (0x064B...0x065F).contains(v) || (0x0670...0x0670).contains(v) || (0x06D6...0x06ED).contains(v)
    }
}

// MARK: - 4. Ünlü Türkçe Sesli Meal Sanatçıları & İkra Sesleri

enum IkraPlaybackMode: String, CaseIterable, Identifiable {
    case ikraCombined = "ikraCombined"
    case turkishMealOnly = "turkishMealOnly"
    case arabicRecitationOnly = "arabicRecitationOnly"
    case ayahByAyahIkra = "ayahByAyahIkra"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ikraCombined: return "İkra Mealli Hatim (Arapça + Sanatçı Türkçe Meal)"
        case .turkishMealOnly: return "Sadece Türkçe Sesli Meal (Sanatçı Seslendirmesi)"
        case .arabicRecitationOnly: return "Sadece Arapça Tilavet (Ünlü Hafızlar)"
        case .ayahByAyahIkra: return "Ayet Ayet İkra (1 Ayet Hafız + 1 Ayet Türkçe Meal)"
        }
    }

    var shortLabel: String {
        switch self {
        case .ikraCombined: return "İkra (Ar+Tr)"
        case .turkishMealOnly: return "Türkçe Meal"
        case .arabicRecitationOnly: return "Arapça Hafız"
        case .ayahByAyahIkra: return "Ayet Ayet İkra"
        }
    }
}

struct TurkishMealVoiceArtist: Identifiable, Hashable {
    let id: String
    let name: String
    let roleBadge: String
    let description: String
    let archiveIdentifier: String
    let catalogKey: String
    let includesArabicRecitation: Bool
    let pairedArabicReciter: String
}

struct FamousQuranReciter: Identifiable, Hashable {
    let id: String
    let name: String
    let countryAndTitle: String
    let styleBadge: String
    let everyAyahFolder: String
    let mp3QuranServer: String
    let islamicNetworkId: String
    var diyanetAyahPath: String? = nil
    var isTurkish: Bool { id.hasPrefix("tr.") }

    func ayahURL(surah: Int, ayah: Int) -> URL? {
        guard (1...114).contains(surah), ayah > 0 else { return nil }
        if let path = diyanetAyahPath {
            return URL(string: "https://kuran.diyanet.gov.tr/api/audio/kuran/kuranikerim/Sound/\(path)/\(surah)_\(ayah).mp3")
        }
        guard !everyAyahFolder.isEmpty else { return nil }
        return URL(string: String(format: "https://everyayah.com/data/%@/%03d%03d.mp3", everyAyahFolder, surah, ayah))
    }
}

struct LiveIslamicRadioStation: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: String
    let streamURL: String
    let badgeColorHex: String
    let icon: String
}

// MARK: - 5. Çevrimdışı İndirme ve İkra Ses Merkezi (OfflineAudioDownloadManager)

@MainActor
final class IkraAudioAndRadioCenter: ObservableObject {
    static let shared = IkraAudioAndRadioCenter()

    @Published var playbackMode: IkraPlaybackMode = .ikraCombined
    @Published var selectedTurkishArtistId: String = "hayri_kucukdeniz_gamidi"
    @Published var selectedArabicReciterId: String = UserDefaults.standard.string(forKey: "quran.reciter") ?? "ar.alafasy" {
        didSet { UserDefaults.standard.set(selectedArabicReciterId, forKey: "quran.reciter") }
    }
    @Published var playbackSpeed: Float = 1.0
    @Published var repeatCountPerTrack: Int = 1

    // Downloading states
    @Published var activeDownloads: [String: Double] = [:] // key -> progress 0.0...1.0
    @Published var downloadedFiles: Set<String> = []
    @Published var lastDownloadStatusBanner: String? = nil

    private var catalogFiles: [String: [String]] = [:]

    // Famous Turkish Voice Actors & İkra Collections
    let turkishVoiceArtists: [TurkishMealVoiceArtist] = [
        TurkishMealVoiceArtist(
            id: "hayri_kucukdeniz_gamidi",
            name: "Hayri Küçükdeniz & Sa'd el-Gâmidî",
            roleBadge: "İkra Efsane Ses · Ar+Tr",
            description: "Ünlü tiyatro ve seslendirme sanatçısı Hayri Küçükdeniz'in tok sesiyle Türkçe Meal + Hafız Sa'd el-Gâmidî Arapça tilaveti (114 Sûre)",
            archiveIdentifier: "Saad-Gamidi-Hayri-Kucukdeniz-Mealli-Hatim-Sureli",
            catalogKey: "hayri_kucukdeniz_gamidi",
            includesArabicRecitation: true,
            pairedArabicReciter: "Sa'd el-Gâmidî"
        ),
        TurkishMealVoiceArtist(
            id: "ahmet_deniz",
            name: "Ahmet Deniz (Diyanet / Açık Kuran Sesli Meal)",
            roleBadge: "Sadece Türkçe Sesli Meal",
            description: "Ünlü seslendirme sanatçısı Ahmet Deniz'in berrak stüdyo kaydıyla sadece Türkçe Kur'an-ı Kerim Meali (114 Sûre)",
            archiveIdentifier: "Ahmet_Deniz_Meal_Kuran_Sureler",
            catalogKey: "ahmet_deniz",
            includesArabicRecitation: false,
            pairedArabicReciter: "Sadece Türkçe Meal"
        ),
        TurkishMealVoiceArtist(
            id: "mehmet_emin_ay",
            name: "Prof. Dr. Mehmet Emin Ay",
            roleBadge: "Gönül Dili Türkçe Meal",
            description: "Prof. Dr. Mehmet Emin Ay'ın huzur veren hitabetiyle sûrelerin tamamının Türkçe sesli meali (114 Sûre)",
            archiveIdentifier: "Mehmet-Emin-Ay-Sureler-Turkce-Meal",
            catalogKey: "mehmet_emin_ay",
            includesArabicRecitation: false,
            pairedArabicReciter: "Sadece Türkçe Meal"
        ),
        TurkishMealVoiceArtist(
            id: "suud_sureym_mealli",
            name: "Kâbe İmamı Suud eş-Şureym & Türkçe Meal",
            roleBadge: "Kâbe Hatmi + Türkçe Meal",
            description: "Mescid-i Haram (Kâbe) İmamı Suud eş-Şureym'in tilaveti ve profesyonel Türkçe sesli meali (114 Sûre)",
            archiveIdentifier: "kabeimamlariturkcemeallihatim",
            catalogKey: "suud_sureym_mealli",
            includesArabicRecitation: true,
            pairedArabicReciter: "Suud eş-Şureym"
        ),
        TurkishMealVoiceArtist(
            id: "seyfullah_kartal_ayet",
            name: "Seyfullah Kartal (6.236 Ayet Tek Tek Sesli Meal)",
            roleBadge: "Ayet Ayet Stüdyo Meal",
            description: "Kur'an'daki 6.236 ayetin her biri için ayrı stüdyo kaydı! Seçtiğiniz Arapça hafızla 1 Ayet Arapça + 1 Ayet Türkçe İkra okuma",
            archiveIdentifier: "seyfullah-kartal-ayet-ayet-meal-arsivi",
            catalogKey: "seyfullah_kartal_ayet",
            includesArabicRecitation: false,
            pairedArabicReciter: "Tüm Hafızlarla Eşleşir"
        ),
        TurkishMealVoiceArtist(
            id: "yusuf_ziya_ozkan",
            name: "Yusuf Ziya Özkan (Elmalılı Hamdi Yazır Meali)",
            roleBadge: "604 Sayfa & 30 Cüz Meal",
            description: "Elmalılı Muhammed Hamdi Yazır'ın Hak Dini Kur'an Dili mealinin Yusuf Ziya Özkan tarafından sayfa sayfa seslendirilmesi",
            archiveIdentifier: "Yusuf_Ziya_Ozkan_Turkce_Meal",
            catalogKey: "yusuf_ziya_ozkan",
            includesArabicRecitation: false,
            pairedArabicReciter: "Elmalılı Sesli Meal"
        ),
        TurkishMealVoiceArtist(
            id: "huzeyfi_hayri_kucukdeniz",
            name: "Medine İmamı Ali el-Huzeyfî & Hayri Küçükdeniz",
            roleBadge: "30 Cüz Mealli Hatim",
            description: "Mescid-i Nebevî İmamı Ali el-Huzeyfî tilaveti + Hayri Küçükdeniz'den Abdullah Yücel Türkçe Meali",
            archiveIdentifier: "huzeyfi_mealli_kuran",
            catalogKey: "huzeyfi_hayri_kucukdeniz",
            includesArabicRecitation: true,
            pairedArabicReciter: "Ali el-Huzeyfî"
        )
    ]

    // Verified Turkish and international reciters.
    let famousArabicReciters: [FamousQuranReciter] = [
        FamousQuranReciter(id: "tr.tayyar", name: "Tayyar Altıkulaç", countryAndTitle: "Türkiye · Diyanet", styleBadge: "Ayet ayet tilavet", everyAyahFolder: "", mp3QuranServer: "", islamicNetworkId: "", diyanetAyahPath: "ar_TayyarAltikulac"),
        FamousQuranReciter(id: "tr.ishak", name: "İshak Danış", countryAndTitle: "Türkiye · Diyanet", styleBadge: "Ayet ayet tilavet", everyAyahFolder: "", mp3QuranServer: "", islamicNetworkId: "", diyanetAyahPath: "ar_ishakdemir"),
        FamousQuranReciter(id: "tr.davut", name: "Davut Kaya", countryAndTitle: "Türkiye · Diyanet", styleBadge: "Ayet ayet tilavet", everyAyahFolder: "", mp3QuranServer: "", islamicNetworkId: "", diyanetAyahPath: "ar_davutkaya"),
        FamousQuranReciter(id: "tr.mehmetcevik", name: "Mehmet Çevik", countryAndTitle: "Türkiye · Diyanet", styleBadge: "Ayet ayet tilavet", everyAyahFolder: "", mp3QuranServer: "", islamicNetworkId: "", diyanetAyahPath: "ar_mehmetcevik"),
        FamousQuranReciter(id: "tr.osman", name: "Osman Şahin", countryAndTitle: "Türkiye · Diyanet", styleBadge: "Ayet ayet tilavet", everyAyahFolder: "", mp3QuranServer: "", islamicNetworkId: "", diyanetAyahPath: "ar_OsmanSahin"),
        FamousQuranReciter(id: "ar.ayyub", name: "Muhammed Eyyûb", countryAndTitle: "Suudi Arabistan", styleBadge: "Kur’an tilaveti", everyAyahFolder: "Muhammad_Ayyoub_128kbps", mp3QuranServer: "https://cdn.mp3quran.net/audio/muhammad-ayyub/r1", islamicNetworkId: ""),
        FamousQuranReciter(id: "ar.jibreel", name: "Muhammed Cibril", countryAndTitle: "Mısır", styleBadge: "Kur’an tilaveti", everyAyahFolder: "Muhammad_Jibreel_128kbps", mp3QuranServer: "https://cdn.mp3quran.net/audio/muhammad-jibreel/r1", islamicNetworkId: ""),
        FamousQuranReciter(id: "ar.shatri", name: "Ebubekir eş-Şâtırî", countryAndTitle: "Suudi Arabistan", styleBadge: "Kur’an tilaveti", everyAyahFolder: "Abu_Bakr_Ash-Shaatree_128kbps", mp3QuranServer: "https://cdn.mp3quran.net/audio/abubakr-shatri/r1", islamicNetworkId: ""),
        FamousQuranReciter(id: "ar.rifai", name: "Hani er-Rifai", countryAndTitle: "Suudi Arabistan", styleBadge: "Kur’an tilaveti", everyAyahFolder: "Hani_Rifai_192kbps", mp3QuranServer: "https://cdn.mp3quran.net/audio/hani-rifai/r1", islamicNetworkId: ""),
        FamousQuranReciter(id: "ar.ayman", name: "Eymen Rüşdi Süveyd", countryAndTitle: "Suriye", styleBadge: "Kur’an tilaveti", everyAyahFolder: "Ayman_Sowaid_64kbps", mp3QuranServer: "https://server15.mp3quran.net/a-rushdi/Almusshaf-Al-Mo-lim", islamicNetworkId: ""),
        FamousQuranReciter(
            id: "ar.alafasy",
            name: "Mişari Raşid el-Afasi",
            countryAndTitle: "Kuveyt · Ulu Camii İmamı",
            styleBadge: "Murattel · Berrak Makam",
            everyAyahFolder: "Alafasy_128kbps",
            mp3QuranServer: "https://server8.mp3quran.net/afs",
            islamicNetworkId: "ar.alafasy"
        ),
        FamousQuranReciter(
            id: "ar.abdurrahmaansudais",
            name: "Abdurrahman es-Sudeys",
            countryAndTitle: "Mekke · Kâbe Baş İmamı",
            styleBadge: "Haremeyn Coşkulu Tilavet",
            everyAyahFolder: "Abdurrahmaan_As-Sudais_192kbps",
            mp3QuranServer: "https://server11.mp3quran.net/sds",
            islamicNetworkId: "ar.abdurrahmaansudais"
        ),
        FamousQuranReciter(
            id: "ar.mahermuaiqly",
            name: "Mahir el-Muaykli",
            countryAndTitle: "Mekke · Kâbe İmamı",
            styleBadge: "Huşû & Hüzünlü Makam",
            everyAyahFolder: "MaherAlMuaiqly128kbps",
            mp3QuranServer: "https://server12.mp3quran.net/maher",
            islamicNetworkId: "ar.mahermuaiqly"
        ),
        FamousQuranReciter(
            id: "ar.saoodshuraym",
            name: "Suud eş-Şureym",
            countryAndTitle: "Mekke · Kâbe İmamı",
            styleBadge: "Süratli & Akıcı Hatim",
            everyAyahFolder: "Saood_ash-Shuraym_128kbps",
            mp3QuranServer: "https://server7.mp3quran.net/shur",
            islamicNetworkId: "ar.saoodshuraym"
        ),
        FamousQuranReciter(
            id: "ar.abdulbasitmurattal",
            name: "Abdülbasit Abdüssamed (Murattel)",
            countryAndTitle: "Mısır · Kur'an'ın Altın Sesi",
            styleBadge: "Klasik Mısır Murattel",
            everyAyahFolder: "Abdul_Basit_Murattal_192kbps",
            mp3QuranServer: "https://server7.mp3quran.net/basit",
            islamicNetworkId: "ar.abdulbasitmurattal"
        ),
        FamousQuranReciter(
            id: "ar.abdulbasitmujawwad",
            name: "Abdülbasit Abdüssamed (Mücevved)",
            countryAndTitle: "Mısır · Efsanevi Uzun Nefes",
            styleBadge: "Mücevved · Yüksek Makam",
            everyAyahFolder: "Abdul_Basit_Mujawwad_128kbps",
            mp3QuranServer: "https://server7.mp3quran.net/basit/Almusshaf-Al-Mojawwad",
            islamicNetworkId: "ar.abdulbasitmujawwad"
        ),
        FamousQuranReciter(
            id: "ar.mustafaismail",
            name: "Şeyh Mustafa İsmail",
            countryAndTitle: "Mısır · Makam Üstadı",
            styleBadge: "Rast, Beyati & Hicaz",
            everyAyahFolder: "Mustafa_Ismail_48kbps",
            mp3QuranServer: "https://server8.mp3quran.net/mustafa",
            islamicNetworkId: "ar.mustafaismail"
        ),
        FamousQuranReciter(
            id: "ar.husary",
            name: "Mahmud Halil el-Husari",
            countryAndTitle: "Mısır · Şeyhu'l-Kurrâ (Muallim)",
            styleBadge: "Tecvid Öğretici Tane Tane",
            everyAyahFolder: "Husary_128kbps",
            mp3QuranServer: "https://server13.mp3quran.net/husr",
            islamicNetworkId: "ar.husary"
        ),
        FamousQuranReciter(
            id: "ar.minshawi",
            name: "Muhammed Sıddık el-Minşavi",
            countryAndTitle: "Mısır · Ağlayan Hafız",
            styleBadge: "Derin Ruhani Tilavet",
            everyAyahFolder: "Minshawy_Murattal_128kbps",
            mp3QuranServer: "https://server10.mp3quran.net/minsh",
            islamicNetworkId: "ar.minshawi"
        ),
        FamousQuranReciter(
            id: "ar.ghamadi",
            name: "Sa'd el-Gâmidî",
            countryAndTitle: "Suudi Arabistan · Mescid-i Nebevî Eski İmamı",
            styleBadge: "İkra Hatim Hafızı",
            everyAyahFolder: "Ghamadi_40kbps",
            mp3QuranServer: "https://server7.mp3quran.net/s_gmd",
            islamicNetworkId: "ar.saoodshuraym"
        ),
        FamousQuranReciter(
            id: "ar.qatami",
            name: "Nâsır el-Katâmî",
            countryAndTitle: "Riyad · Prenses Latife Camii İmamı",
            styleBadge: "Kalbe Dokunan Kıraat",
            everyAyahFolder: "Nasser_Alqatami_128kbps",
            mp3QuranServer: "https://server6.mp3quran.net/qtm",
            islamicNetworkId: "ar.alafasy"
        ),
        FamousQuranReciter(
            id: "ar.dussary",
            name: "Yâsir ed-Devserî",
            countryAndTitle: "Mekke · Kâbe İmamı",
            styleBadge: "Güçlü Makam & Kıraat",
            everyAyahFolder: "Yasser_Ad-Dussary_128kbps",
            mp3QuranServer: "https://server11.mp3quran.net/yasser",
            islamicNetworkId: "ar.alafasy"
        ),
        FamousQuranReciter(
            id: "ar.ajamy",
            name: "Ahmed bin Ali el-Acemî",
            countryAndTitle: "Suudi Arabistan · Haremeyn",
            styleBadge: "Gür & Akıcı Tilavet",
            everyAyahFolder: "Ahmed_ibn_Ali_al-Ajamy_128kbps_ketaballah.net",
            mp3QuranServer: "https://server10.mp3quran.net/ajm",
            islamicNetworkId: "ar.ahmedajamy"
        ),
        FamousQuranReciter(
            id: "ar.hudhaify",
            name: "Ali bin Abdurrahman el-Huzeyfî",
            countryAndTitle: "Medine · Mescid-i Nebevî Baş İmamı",
            styleBadge: "Medine Tavrı · Ağırbaşlı",
            everyAyahFolder: "Hudhaify_128kbps",
            mp3QuranServer: "https://server9.mp3quran.net/hthfi",
            islamicNetworkId: "ar.hudhaify"
        )
    ]

    // Only the two radio providers selected by the user.
    let liveRadioStations: [LiveIslamicRadioStation] = [
        LiveIslamicRadioStation(
            id: "diyanet_kuran_radyo",
            title: "Diyanet Kur’an Radyo",
            subtitle: "Kur’an tilaveti, meal ve Diyanet programları",
            category: "Diyanet · Canlı",
            streamURL: "https://eustr76.mediatriple.net/videoonlylive/mtikoimxnztxlive/broadcast_5e3c14192aa92.smil/playlist.m3u8",
            badgeColorHex: "#1E8E5A",
            icon: "antenna.radiowaves.left.and.right"
        ),
        LiveIslamicRadioStation(
            id: "vav_radyo",
            title: "Vav Radyo",
            subtitle: "Vav Radyo’nun resmî canlı yayını",
            category: "Vav · Canlı",
            streamURL: "https://trkvz-radyolar.ercdn.net/radyovav/playlist.m3u8",
            badgeColorHex: "#D4AD57",
            icon: "radio.fill"
        )
    ]

    init() {
        CustomFontRegistrar.registerBundledFontsIfNeeded()
        loadCatalog()
        refreshDownloadedFilesList()
    }

    var currentTurkishArtist: TurkishMealVoiceArtist {
        turkishVoiceArtists.first(where: { $0.id == selectedTurkishArtistId }) ?? turkishVoiceArtists[0]
    }

    var currentArabicReciter: FamousQuranReciter {
        famousArabicReciters.first(where: { $0.id == selectedArabicReciterId }) ?? famousArabicReciters[0]
    }

    private func loadCatalog() {
        guard let url = Bundle.main.url(forResource: "ikra_audio_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        self.catalogFiles = decoded
    }

    // MARK: - URL Resolution (Bundled -> Downloaded Offline -> Remote Archive.org / MP3Quran)

    private var offlineDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("OfflineQuranAudio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func refreshDownloadedFilesList() {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: offlineDirectory.path) else { return }
        self.downloadedFiles = Set(items)
    }

    func offlineFileName(surahId: Int, mode: IkraPlaybackMode, artistId: String, reciterId: String) -> String {
        let sPad = String(format: "%03d", surahId)
        switch mode {
        case .ikraCombined, .turkishMealOnly, .ayahByAyahIkra:
            return "meal_\(artistId)_\(sPad).mp3"
        case .arabicRecitationOnly:
            let cleanRec = reciterId.replacingOccurrences(of: ".", with: "_")
            return "arabic_\(cleanRec)_\(sPad).mp3"
        }
    }

    func isSurahAvailableOffline(surahId: Int) -> Bool {
        if bundledAudioURL(surahId: surahId, artistId: selectedTurkishArtistId, mode: playbackMode) != nil {
            return true
        }
        let fname = offlineFileName(
            surahId: surahId,
            mode: playbackMode,
            artistId: selectedTurkishArtistId,
            reciterId: selectedArabicReciterId
        )
        return downloadedFiles.contains(fname)
    }

    private func bundledAudioURL(surahId: Int, artistId: String, mode: IkraPlaybackMode) -> URL? {
        if mode == .arabicRecitationOnly {
            if surahId == 1, let u = Bundle.main.url(forResource: "besmele", withExtension: "mp3") {
                return u
            }
            return nil
        }

        // Check bundled studio MP3s in Sekine/Resources/Sounds/
        if artistId == "hayri_kucukdeniz_gamidi" {
            let map: [Int: String] = [
                1: "ikra_001_fatiha",
                103: "ikra_103_asr",
                108: "ikra_108_kevser",
                112: "ikra_112_ihlas",
                113: "ikra_113_felak",
                114: "ikra_114_nas"
            ]
            if let res = map[surahId], let u = Bundle.main.url(forResource: res, withExtension: "mp3") {
                return u
            }
        } else if artistId == "ahmet_deniz" {
            let map: [Int: String] = [
                1: "meal_ahmet_deniz_001",
                112: "meal_ahmet_deniz_112"
            ]
            if let res = map[surahId], let u = Bundle.main.url(forResource: res, withExtension: "mp3") {
                return u
            }
        } else if artistId == "mehmet_emin_ay" {
            if surahId == 1, let u = Bundle.main.url(forResource: "meal_mehmet_emin_ay_001", withExtension: "mp3") {
                return u
            }
        } else if artistId == "suud_sureym_mealli" {
            let map: [Int: String] = [
                1: "shuraim_001_fatiha",
                112: "shuraim_112_ihlas"
            ]
            if let res = map[surahId], let u = Bundle.main.url(forResource: res, withExtension: "mp3") {
                return u
            }
        }
        return nil
    }

    func remoteSurahAudioURL(surahId: Int, mode: IkraPlaybackMode? = nil, artistId: String? = nil, reciterId: String? = nil) -> URL? {
        let activeMode = mode ?? playbackMode
        let activeArtist = artistId ?? selectedTurkishArtistId
        let activeReciterId = reciterId ?? selectedArabicReciterId
        let idx = max(0, min(113, surahId - 1))
        let sPad = String(format: "%03d", surahId)

        if activeMode == .arabicRecitationOnly {
            let rec = famousArabicReciters.first(where: { $0.id == activeReciterId }) ?? currentArabicReciter
            guard !rec.mp3QuranServer.isEmpty else { return nil }
            return URL(string: "\(rec.mp3QuranServer)/\(sPad).mp3")
        }

        // Turkish Voice Artist / İkra Combined
        if let list = catalogFiles[activeArtist], idx < list.count {
            let fileName = list[idx]
            let artistMeta = turkishVoiceArtists.first(where: { $0.id == activeArtist }) ?? turkishVoiceArtists[0]
            let encodedFile = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
            return URL(string: "https://archive.org/download/\(artistMeta.archiveIdentifier)/\(encodedFile)")
        }

        // Special case for Seyfullah Kartal (Ayah 1 of the Surah)
        if activeArtist == "seyfullah_kartal_ayet" {
            return URL(string: "https://archive.org/download/seyfullah-kartal-ayet-ayet-meal-arsivi/\(sPad)_001.mp3")
        }

        // Special case for Yusuf Ziya Özkan (Page-based 001..604)
        if activeArtist == "yusuf_ziya_ozkan" {
            return URL(string: "https://archive.org/download/Yusuf_Ziya_Ozkan_Turkce_Meal/\(sPad).mp3")
        }

        // Special case for Huzeyfi + Hayri Küçükdeniz (Juz 1..30)
        if activeArtist == "huzeyfi_hayri_kucukdeniz" {
            let juz = max(1, min(30, (surahId / 4) + 1))
            let jPad = String(format: "%02d", juz)
            let encoded = "Cüz \(jPad).mp3".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "C%C3%BCz%2001.mp3"
            return URL(string: "https://archive.org/download/huzeyfi_mealli_kuran/\(encoded)")
        }

        // Fallback to Hayri Küçükdeniz + Saad Al-Ghamdi
        if let fallbackList = catalogFiles["hayri_kucukdeniz_gamidi"], idx < fallbackList.count {
            let fname = fallbackList[idx].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fallbackList[idx]
            return URL(string: "https://archive.org/download/Saad-Gamidi-Hayri-Kucukdeniz-Mealli-Hatim-Sureli/\(fname)")
        }
        return nil
    }

    // MARK: - Playback Trigger Functions

    func playArabicAyah(surahId: Int, ayah: Int, title: String) {
        let reciter = currentArabicReciter
        guard let url = reciter.ayahURL(surah: surahId, ayah: ayah) else { return }
        AdhanPlayer.shared.playLocalOrRemoteFile(url: url, title: title, subtitle: reciter.name, rate: playbackSpeed)
    }

    func playArabicSurah(_ surah: SurahMeta) {
        let reciter = currentArabicReciter
        if reciter.diyanetAyahPath != nil {
            let urls = (1...surah.ayahCount).compactMap { reciter.ayahURL(surah: surah.number, ayah: $0) }
            AdhanPlayer.shared.playRecitationSequence(urls: urls, title: "\(surah.nameTr) Sûresi", subtitle: reciter.name, rate: playbackSpeed)
        } else if let url = remoteSurahAudioURL(surahId: surah.number, mode: .arabicRecitationOnly) {
            AdhanPlayer.shared.playLocalOrRemoteFile(url: url, title: "\(surah.nameTr) Sûresi", subtitle: reciter.name, rate: playbackSpeed)
        }
    }

    func playSurah(surahId: Int, surahName: String) {
        if playbackMode == .arabicRecitationOnly, currentArabicReciter.diyanetAyahPath != nil,
           let surah = QuranAndLibraryView.allSurahs.first(where: { $0.number == surahId }) {
            playArabicSurah(surah)
            return
        }
        let fname = offlineFileName(
            surahId: surahId,
            mode: playbackMode,
            artistId: selectedTurkishArtistId,
            reciterId: selectedArabicReciterId
        )
        let localFileURL = offlineDirectory.appendingPathComponent(fname)

        let subtitle: String
        switch playbackMode {
        case .ikraCombined:
            subtitle = "İkra: \(currentTurkishArtist.name)"
        case .turkishMealOnly:
            subtitle = "Türkçe Sesli Meal: \(currentTurkishArtist.name)"
        case .arabicRecitationOnly:
            subtitle = "Hafız: \(currentArabicReciter.name)"
        case .ayahByAyahIkra:
            subtitle = "Ayet Ayet İkra: \(currentArabicReciter.name) + Türkçe Meal"
        }

        if playbackMode == .ayahByAyahIkra {
            playAyahIkra(surahId: surahId, ayahNumber: 1, surahName: surahName)
            return
        }

        // 1. Check downloaded file in Documents/OfflineQuranAudio
        if FileManager.default.fileExists(atPath: localFileURL.path) {
            AdhanPlayer.shared.playLocalOrRemoteFile(
                url: localFileURL,
                title: "\(surahName) Sûresi (Çevrimdışı)",
                subtitle: subtitle,
                rate: playbackSpeed
            )
            return
        }

        // 2. Check bundled offline MP3 in Sekine/Resources/Sounds
        if let bundledURL = bundledAudioURL(surahId: surahId, artistId: selectedTurkishArtistId, mode: playbackMode) {
            AdhanPlayer.shared.playLocalOrRemoteFile(
                url: bundledURL,
                title: "\(surahName) Sûresi (Yerleşik Stüdyo Kaydı)",
                subtitle: subtitle,
                rate: playbackSpeed
            )
            return
        }

        // 3. Stream from Archive.org / MP3Quran
        if let remoteURL = remoteSurahAudioURL(surahId: surahId) {
            AdhanPlayer.shared.playLocalOrRemoteFile(
                url: remoteURL,
                title: "\(surahName) Sûresi",
                subtitle: subtitle,
                rate: playbackSpeed
            )
        }
    }

    /// Plays 1 Ayah in Arabic by the selected famous Reciter, followed automatically by studio-recorded Turkish Voiceover MP3 (Seyfullah Kartal / bundled)!
    func playAyahIkra(surahId: Int, ayahNumber: Int, surahName: String, fallbackTurkishText: String? = nil) {
        let sPad = String(format: "%03d", surahId)
        let aPad = String(format: "%03d", ayahNumber)
        let reciter = currentArabicReciter
        let arabicURLStr = reciter.ayahURL(surah: surahId, ayah: ayahNumber)?.absoluteString ?? ""

        // Check bundled ayah Turkish meal first
        let bundledMealName = "ayet_meal_\(sPad)_\(aPad)"
        let turkishAudioURL: URL?
        if let bURL = Bundle.main.url(forResource: bundledMealName, withExtension: "mp3") {
            turkishAudioURL = bURL
        } else {
            turkishAudioURL = URL(string: "https://archive.org/download/seyfullah-kartal-ayet-ayet-meal-arsivi/\(sPad)_\(aPad).mp3")
        }

        if playbackMode == .turkishMealOnly {
            if let mealURL = turkishAudioURL {
                AdhanPlayer.shared.playLocalOrRemoteFile(
                    url: mealURL,
                    title: "\(surahName) \(ayahNumber). Ayet (Türkçe Sesli Meal)",
                    subtitle: "Sanatçı: Seyfullah Kartal / \(currentTurkishArtist.name)",
                    rate: playbackSpeed
                )
            } else if let text = fallbackTurkishText {
                AdhanPlayer.shared.speakTurkish(text: text, title: "\(surahName) \(ayahNumber). Ayet Meali")
            }
            return
        }

        if playbackMode == .arabicRecitationOnly {
            if let arURL = URL(string: arabicURLStr) {
                AdhanPlayer.shared.playLocalOrRemoteFile(
                    url: arURL,
                    title: "\(surahName) Sûresi, \(ayahNumber). Ayet",
                    subtitle: "Hafız: \(reciter.name)",
                    rate: playbackSpeed
                )
            }
            return
        }

        // İkra Sequential Mode: 1st Arabic Reciter -> 2nd Studio Turkish Meal MP3!
        if let arURL = URL(string: arabicURLStr) {
            AdhanPlayer.shared.playSequentialIkraPair(
                arabicURL: arURL,
                turkishMealURL: turkishAudioURL,
                fallbackTurkishText: fallbackTurkishText,
                title: "\(surahName) Sûresi, \(ayahNumber). Ayet (İkra)",
                arabicReciterName: reciter.name,
                turkishArtistName: "Türkçe Sesli Meal Sanatçısı",
                rate: playbackSpeed
            )
        }
    }

    func playLiveRadio(_ station: LiveIslamicRadioStation) {
        guard let url = URL(string: station.streamURL) else { return }
        AdhanPlayer.shared.playLiveRadioStation(
            url: url,
            title: station.title,
            subtitle: station.subtitle
        )
    }

    // MARK: - Offline Audio Downloader

    func downloadSurahForOffline(surahId: Int, surahName: String) async {
        let fname = offlineFileName(
            surahId: surahId,
            mode: playbackMode,
            artistId: selectedTurkishArtistId,
            reciterId: selectedArabicReciterId
        )
        guard activeDownloads[fname] == nil else { return }
        guard let remoteURL = remoteSurahAudioURL(surahId: surahId) else { return }

        activeDownloads[fname] = 0.15
        lastDownloadStatusBanner = "İndiriliyor: \(surahName) Sûresi (\(currentTurkishArtist.name))..."

        do {
            var req = URLRequest(url: remoteURL)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            activeDownloads[fname] = 0.45
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1000 {
                let destURL = offlineDirectory.appendingPathComponent(fname)
                try data.write(to: destURL, options: .atomic)
                activeDownloads.removeValue(forKey: fname)
                refreshDownloadedFilesList()
                let mb = Double(data.count) / (1024.0 * 1024.0)
                lastDownloadStatusBanner = String(format: "✓ %@ Sûresi çevrimdışı indirildi (%.1f MB)", surahName, mb)
            } else {
                activeDownloads.removeValue(forKey: fname)
                lastDownloadStatusBanner = "İndirme tamamlanamadı, lütfen tekrar deneyin."
            }
        } catch {
            activeDownloads.removeValue(forKey: fname)
            lastDownloadStatusBanner = "İndirme hatası: \(error.localizedDescription)"
        }
    }

    func deleteOfflineFile(surahId: Int) {
        let fname = offlineFileName(
            surahId: surahId,
            mode: playbackMode,
            artistId: selectedTurkishArtistId,
            reciterId: selectedArabicReciterId
        )
        let destURL = offlineDirectory.appendingPathComponent(fname)
        try? FileManager.default.removeItem(at: destURL)
        refreshDownloadedFilesList()
    }

    var totalOfflineStorageString: String {
        guard let files = try? FileManager.default.contentsOfDirectory(at: offlineDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "7 Yerleşik Sûre Hazır"
        }
        var totalBytes: Int64 = 0
        for f in files {
            if let sz = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += Int64(sz)
            }
        }
        let mb = Double(totalBytes) / (1024.0 * 1024.0)
        return String(format: "%d İndirilen + 11 Yerleşik Ses (%.1f MB)", files.count, mb + 7.8)
    }
}
