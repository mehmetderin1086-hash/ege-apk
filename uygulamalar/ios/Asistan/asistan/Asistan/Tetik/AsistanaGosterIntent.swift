import AppIntents
import UniformTypeIdentifiers

/// "Asistan'a göster" (P1.11): Kestirmeler'de "Ekran Görüntüsü Al → Asistan'a göster" ya da Arkaya Dokun ile
/// ekran görüntüsünü / dosyayı isteğe bağlı soruyla Asistan'a verir. Siri sesle dosya veremediği için AppShortcut değildir;
/// `isDiscoverable` Kestirmeler eylem listesinde görünmesine yeter. İş Paylaş menüsünün kutusundan geçer
/// (kaynak: goster → dış kaynak sayılmaz) ve uygulama asistan://paylasim ile açılınca PaylasimAlici sıraya alır.
struct AsistanaGosterIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'a göster"
    static let description = IntentDescription("Ekran görüntüsünü ya da dosyayı (isteğe bağlı soruyla) Asistan'a gösterir. Kestirmeler'de Ekran Görüntüsü Al eyleminden sonra kullan; Arkaya Dokun'a bağlanabilir.")
    static let openAppWhenRun = true
    static let isDiscoverable = true

    @Parameter(title: "Dosyalar", supportedContentTypes: [.image, .pdf, .plainText, .item], requestValueDialog: IntentDialog("Hangi görüntü ya da dosya?"))
    var dosyalar: [IntentFile]

    @Parameter(title: "Soru")
    var soru: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$dosyalar) Asistan'a göster") { \.$soru }
    }

    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        guard !dosyalar.isEmpty else { throw $dosyalar.needsValueError() }
        let girdiler = dosyalar
        let istem = String((soru ?? "").prefix(4000))
        // Dosya verisi (40 MB'a kadar) ve kutuya yazma ana iş parçacığı dışında.
        try await Task.detached(priority: .userInitiated) {
            let ham = girdiler.map { f in (ad: f.filename, uzanti: f.type?.preferredFilenameExtension, veri: f.data) }
            let hazir = try GosterHazirlik.hazirla(ham).get()
            try PaylasimKutusu.yaz(PaylasimKutusu.Istek(istem: istem, kaynak: PaylasimKutusu.gosterKaynagi), dosyalar: hazir)
        }.value
        return .result(opensIntent: OpenURLIntent(URL(string: "asistan://paylasim")!))
    }
}

nonisolated enum GosterHatasi: LocalizedError, Equatable {
    case cokFazlaDosya
    case cokBuyuk

    var errorDescription: String? {
        switch self {
        case .cokFazlaDosya: "En çok \(PaylasimKutusu.gosterEnFazlaDosya) dosya gösterebilirsin."
        case .cokBuyuk: "Dosyalar \(PaylasimKutusu.gosterToplamSinir / (1024 * 1024)) MB'tan büyük."
        }
    }
}

/// Saf hazırlık: sınırları uygular ve kutuya yazılacak adları belirler (test edilebilir, ağsız).
nonisolated enum GosterHazirlik {
    static func hazirla(_ girdiler: [(ad: String, uzanti: String?, veri: Data)]) -> Result<[(ad: String, veri: Data)], GosterHatasi> {
        guard girdiler.count <= PaylasimKutusu.gosterEnFazlaDosya else { return .failure(.cokFazlaDosya) }
        guard girdiler.reduce(0, { $0 + $1.veri.count }) <= PaylasimKutusu.gosterToplamSinir else { return .failure(.cokBuyuk) }
        return .success(girdiler.enumerated().map { n, g in (ad: dosyaAdi(g.ad, uzanti: g.uzanti, sira: n + 1), veri: g.veri) })
    }

    /// Boş ad → "ekran-1.png" (uzantı türden, yoksa "dat"). Uzantısız ada türün uzantısı eklenir:
    /// PaylasimAlici görsel/belge ayrımını uzantıdan yapar.
    static func dosyaAdi(_ ad: String, uzanti: String?, sira: Int) -> String {
        let temiz = ad.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = (uzanti?.isEmpty == false) ? uzanti! : nil
        if temiz.isEmpty { return "ekran-\(sira).\(u ?? "dat")" }
        if (temiz as NSString).pathExtension.isEmpty, let u { return "\(temiz).\(u)" }
        return temiz
    }
}
