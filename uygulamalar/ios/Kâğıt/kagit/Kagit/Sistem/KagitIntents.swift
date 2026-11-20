import AppIntents
import CoreGraphics
import KagitKit
import UniformTypeIdentifiers

/// Kısayollar eylemlerinde kullanılan dil seçeneği.
enum KisayolOCRDili: String, AppEnum {
    case trEn, tr, en
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "OCR dili"
    static let caseDisplayRepresentations: [KisayolOCRDili: DisplayRepresentation] = [
        .trEn: "Türkçe + İngilizce", .tr: "Türkçe", .en: "İngilizce",
    ]
    var kodlar: [String] {
        switch self {
        case .trEn: ["tr-TR", "en-US"]
        case .tr: ["tr-TR"]
        case .en: ["en-US"]
        }
    }
}

nonisolated private func pdfDosyasi(_ veri: Data, ad: String) -> IntentFile {
    IntentFile(data: veri, filename: TurkceMetin.dosyaAdi(ad) + ".pdf", type: .pdf)
}

nonisolated private func dosyaAdiSiz(_ f: IntentFile) async -> String {
    (await f.filename as NSString).deletingPathExtension
}

// MARK: - Kâğıt'ta aç

struct KagitdaAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Kâğıt'ta aç"
    static let description = IntentDescription("Bir PDF'i Kâğıt kitaplığına alıp açar.")
    static let openAppWhenRun = true

    @Parameter(title: "PDF", supportedContentTypes: [.pdf])
    var dosya: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        let gecici = Gecici.dosya(dosya.filename.isEmpty ? "Belge.pdf" : dosya.filename)
        try await dosya.data.write(to: gecici)
        let alinan = try await Kitaplik.paylasilan.iceAktar([gecici])
        if let o = alinan.first, o.pdfMi { SistemKurulumu.yonlendirici?.ac(o) }
        return .result()
    }
}

// MARK: - OCR

struct PDFAranabilirYapIntent: AppIntent {
    static let title: LocalizedStringResource = "PDF'i aranabilir yap (OCR)"
    static let description = IntentDescription("Taranmış PDF'e görünmez metin katmanı ekler.")

    @Parameter(title: "PDF", supportedContentTypes: [.pdf])
    var dosya: IntentFile

    @Parameter(title: "Dil", default: .trEn)
    var dil: KisayolOCRDili

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$dosya) dosyasını \(\.$dil) ile aranabilir yap")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        var sec = AranabilirSecenekleri()
        sec.diller = dil.kodlar
        let (veri, _) = try await AranabilirPDF.yap(veri: await dosya.data, secenekler: sec)
        return .result(value: pdfDosyasi(veri, ad: await dosyaAdiSiz(dosya) + " (aranabilir)"))
    }
}

// MARK: - Parola

struct PDFParolaKoyIntent: AppIntent {
    static let title: LocalizedStringResource = "PDF'e parola koy"
    static let description = IntentDescription("PDF'i açılış parolasıyla korur.")

    @Parameter(title: "PDF", supportedContentTypes: [.pdf])
    var dosya: IntentFile

    @Parameter(title: "Parola")
    var parola: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$dosya) dosyasına \(\.$parola) parolasını koy")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let veri = try Koruma.parolaKoy(veri: await dosya.data, kullaniciParolasi: parola, sahipParolasi: nil)
        return .result(value: pdfDosyasi(veri, ad: await dosyaAdiSiz(dosya) + " (korumalı)"))
    }
}

// MARK: - Görsellerden PDF

struct GorsellerdenPDFIntent: AppIntent {
    static let title: LocalizedStringResource = "Görsellerden PDF yap"
    static let description = IntentDescription("Görselleri sırayla tek bir PDF'te birleştirir.")

    @Parameter(title: "Görseller", supportedContentTypes: [.image])
    var gorseller: [IntentFile]

    @Parameter(title: "Aranabilir yap (OCR)", default: false)
    var ocr: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$gorseller) görsellerinden PDF yap") {
            \.$ocr
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        var goruntuler: [CGImage] = []
        for f in gorseller {
            if let g = PDFCizim.goruntuYukle(await f.data, enBuyukKenar: 3000) { goruntuler.append(g) }
        }
        guard !goruntuler.isEmpty else { throw KagitHata.bosGirdi }
        var sec = AranabilirSecenekleri()
        sec.ocr = ocr
        let veri = try await AranabilirPDF.gorsellerdenPDF(goruntuler, secenekler: sec)
        return .result(value: pdfDosyasi(veri, ad: "Görseller"))
    }
}

// MARK: - Kısayollar sağlayıcısı

struct KagitKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: KagitdaAcIntent(),
                    phrases: ["\(.applicationName) ile PDF aç", "\(.applicationName) uygulamasında PDF aç"],
                    shortTitle: "Kâğıt'ta aç", systemImageName: "doc.text")
        AppShortcut(intent: PDFAranabilirYapIntent(),
                    phrases: ["\(.applicationName) ile PDF'i aranabilir yap", "\(.applicationName) ile OCR yap"],
                    shortTitle: "Aranabilir yap (OCR)", systemImageName: "text.viewfinder")
        AppShortcut(intent: PDFParolaKoyIntent(),
                    phrases: ["\(.applicationName) ile PDF'e parola koy"],
                    shortTitle: "Parola koy", systemImageName: "lock.doc")
        AppShortcut(intent: GorsellerdenPDFIntent(),
                    phrases: ["\(.applicationName) ile görsellerden PDF yap"],
                    shortTitle: "Görsellerden PDF", systemImageName: "photo.on.rectangle")
    }
}
