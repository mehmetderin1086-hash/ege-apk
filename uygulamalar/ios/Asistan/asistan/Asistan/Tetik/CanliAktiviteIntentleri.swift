import AppIntents
import Foundation

/// P4.2: Kontrol Merkezi / kilit ekranı / Action Button için parametreli kontroller. Bu dosya hem uygulamaya hem kontrol
/// uzantısına (AsistanKontrol) derlenir: uzantı kontrolün intent türlerini görür, uygulamayı açan bağlantı `asistan://`
/// sözleşmesine (`AsistanBaglantisi.coz`) gider.

/// Kipli kontrolün seçenekleri. AppEnum uyumu varsayılan MainActor yalıtımında değil (uzantı/metadata sürecinde çözülür).
nonisolated enum AsistanBaslatKipi: String, AppEnum {
    case dinle, canliKamera, sonSohbet, sabahOzeti

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Başlatma kipi" }
    static var caseDisplayRepresentations: [AsistanBaslatKipi: DisplayRepresentation] {
        [
            .dinle: DisplayRepresentation(title: "Dinle", image: .init(systemName: "waveform.circle.fill")),
            .canliKamera: DisplayRepresentation(title: "Canlı + kamera", image: .init(systemName: "camera.viewfinder")),
            .sonSohbet: DisplayRepresentation(title: "Son sohbete devam", image: .init(systemName: "bubble.left.and.text.bubble.right")),
            .sabahOzeti: DisplayRepresentation(title: "Sabah özeti", image: .init(systemName: "sunrise")),
        ]
    }

    /// Kontrol etiketi (Türkçe).
    var baslik: String {
        switch self {
        case .dinle: "Asistan"
        case .canliKamera: "Canlı + kamera"
        case .sonSohbet: "Sohbete devam"
        case .sabahOzeti: "Sabah özeti"
        }
    }

    var simge: String {
        switch self {
        case .dinle: "waveform.circle.fill"
        case .canliKamera: "camera.viewfinder"
        case .sonSohbet: "bubble.left.and.text.bubble.right"
        case .sabahOzeti: "sunrise"
        }
    }

    /// Saf karar: kipin açtığı `asistan://` bağlantısı. Sabah özeti P3.11 hızlı istemi 4'tür (`DersGunu.hizliIstemler`);
    /// bağlantı yalnız numara taşır, gönderilen metin uygulamaya gömülüdür.
    static func baglanti(_ k: AsistanBaslatKipi) -> URL {
        switch k {
        case .dinle: URL(string: "asistan://dinle")!
        case .canliKamera: URL(string: "asistan://canli-kamera")!
        case .sonSohbet: URL(string: "asistan://devam")!
        case .sabahOzeti: URL(string: "asistan://hizli?no=4")!
        }
    }
}

/// Kipli kontrolün yapılandırması (kullanıcı kontrolü eklerken kipi seçer). ControlConfigurationIntent'in perform'u yoktur;
/// düğmenin eylemi ayrı `AsistanKipliBaslatIntent`.
struct AsistanKipliYapilandirma: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Asistan kipi"
    static let isDiscoverable = false

    @Parameter(title: "Kip", default: .dinle) var kip: AsistanBaslatKipi

    init() {}
}

/// Kipli kontrolün eylemi: uygulamayı açar ve seçilen kipin bağlantısına gider.
struct AsistanKipliBaslatIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'ı seçilen kipte başlat"
    static let description = IntentDescription("Asistan'ı dinleme, canlı kamera, son sohbet ya da sabah özeti kipinde açar.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Kip", default: .dinle) var kip: AsistanBaslatKipi

    init() {}
    init(kip: AsistanBaslatKipi) { self.kip = kip }

    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AsistanBaslatKipi.baglanti(kip)))
    }
}

/// Hey Asistan kontrolü: değer App Group'a yazılır (`OrtakAyarlar.heyAsistan`); uygulama öne gelince `Ayarlar.ortaktanEsitle`
/// ile alır. Hey Asistan yalnız uygulama öndeyken dinlediği için anlık bildirim gerekmez.
struct HeyAsistanAyarlaIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Hey Asistan'ı aç ya da kapat"
    static let isDiscoverable = false

    @Parameter(title: "Açık") var value: Bool

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        OrtakAyarlar.heyAsistan = value
        OrtakAyarlar.heyKontrolunuYenile()
        return .result()
    }
}
