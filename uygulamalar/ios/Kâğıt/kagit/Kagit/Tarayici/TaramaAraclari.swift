import KagitKit
import PDFKit
import SwiftUI

/// OCR dil seçenekleri.
enum OCRDili: String, CaseIterable, Identifiable {
    case trEn, tr, en, deEn, frEn
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .trEn: "Türkçe + İngilizce"
        case .tr: "Yalnız Türkçe"
        case .en: "Yalnız İngilizce"
        case .deEn: "Almanca + İngilizce"
        case .frEn: "Fransızca + İngilizce"
        }
    }
    var kodlar: [String] {
        switch self {
        case .trEn: ["tr-TR", "en-US"]
        case .tr: ["tr-TR"]
        case .en: ["en-US"]
        case .deEn: ["de-DE", "en-US"]
        case .frEn: ["fr-FR", "en-US"]
        }
    }
}

// MARK: - Tara (tarayıcıyı açar)

struct TaraBaslatici: View {
    static let arac = Arac(id: "tara", ad: "Belge tara",
                           aciklama: "Kamerayla tara, düzenle, aranabilir PDF olarak kaydet.",
                           simge: "doc.viewfinder", kategori: .tarama, girdi: .yok) { _ in TaraBaslatici() }

    @Environment(Yonlendirici.self) private var yon
    @Environment(\.dismiss) private var kapat

    var body: some View {
        ProgressView()
            .task {
                let y = yon
                kapat()
                try? await Task.sleep(for: .milliseconds(450))
                y.taramaAcik = true
            }
    }
}

// MARK: - OCR

struct OCREkrani: View {
    static let arac = Arac(id: "ocr", ad: "Aranabilir yap (OCR)",
                           aciklama: "Taranmış sayfalara görünmez metin katmanı ekle; arama ve kopyalama çalışır.",
                           simge: "text.viewfinder", kategori: .tarama, girdi: .birVeyaCokPDF, topluUygun: true) {
        OCREkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var dil: OCRDili = .trEn
    @State private var aralik = ""
    @State private var metinliyiAtla = true
    @State private var parola = ""

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler) {
            Section {
                Picker("Dil", selection: $dil) { ForEach(OCRDili.allCases) { Text($0.ad).tag($0) } }
                SayfaAraligiAlani(metin: $aralik)
                Toggle("Metni olan sayfalara dokunma", isOn: $metinliyiAtla)
                SecureField("Parola (dosya parolalıysa)", text: $parola)
            } footer: {
                Text("Yalnız metni olmayan (taranmış) sayfalar işlenir. Sayfanın görünümü değişmez.")
            }
        } calistir: { girdiler, ilerleme in
            var sec = AranabilirSecenekleri()
            sec.diller = dil.kodlar
            sec.metniOlanlariAtla = metinliyiAtla
            let secenek = sec
            let p = parola.isEmpty ? nil : parola
            let ar = aralik
            var cikti: [URL] = []
            let n = Double(girdiler.count)
            for (i, u) in girdiler.enumerated() {
                let taban = Double(i)
                let (veri, sayfalar) = try await arkaplandaCalistir { () -> (Data, [Int]?) in
                    let v = try Data(contentsOf: u)
                    guard !ar.trimmingCharacters(in: .whitespaces).isEmpty else { return (v, nil) }
                    let adet = try Belge.ac(veri: v, parola: p).pageCount
                    return (v, try SayfaAraligi.coz(ar, sayfaSayisi: adet))
                }
                let (sonuc, rapor) = try await AranabilirPDF.yap(veri: veri, parola: p, sayfalar: sayfalar, secenekler: secenek) { o in
                    ilerleme((taban + o) / n)
                }
                guard rapor.islenen > 0 else { continue }
                let h = Gecici.dosya("\(u.adSiz) (aranabilir).pdf")
                try Belge.yaz(sonuc, h, beklenenSayfa: rapor.toplamSayfa, parola: p)
                cikti.append(h)
            }
            guard !cikti.isEmpty else {
                throw KagitHata.genel("İşlenecek sayfa yok: bütün sayfalarda zaten metin var ya da seçilen aralık boş.")
            }
            return cikti
        }
    }
}

// MARK: - Metni çıkar

nonisolated enum MetinCikarici {
    enum Mod: String, CaseIterable, Identifiable, Sendable {
        case otomatik, gomulu, hepsiOCR
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .otomatik: "Otomatik (metni olmayana OCR)"
            case .gomulu: "Yalnız gömülü metin"
            case .hepsiOCR: "Bütün sayfalarda OCR"
            }
        }
    }

    struct Sonuc: Sendable {
        var metin: String
        var tablolar: [String]
    }

    static func calistir(url: URL, parola: String?, mod: Mod, diller: [String], sayfaBasligi: Bool, tablo: Bool,
                         ilerleme: Ilerleme) async throws -> Sonuc {
        let belge = try Belge.ac(url, parola: parola)
        var parcalar: [String] = []
        var tablolar: [String] = []
        for i in 0..<belge.pageCount {
            try iptalDenetle()
            guard let s = belge.page(at: i) else { continue }
            var metin = ""
            let ocrGerek = mod == .hepsiOCR || (mod == .otomatik && !AranabilirPDF.metniVarMi(s))
            if ocrGerek, let g = PDFCizim.goruntu(s, dpi: 200) {
                metin = MetinTanima.metin(try await MetinTanima.tani(g, diller: diller))
                if tablo, let yapi = try? await BelgeYapisi.cikar(g) {
                    tablolar += yapi.tablolar.map(\.csv)
                }
            } else {
                metin = s.string ?? ""
            }
            parcalar.append(sayfaBasligi ? "--- Sayfa \(i + 1) ---\n\(metin)" : metin)
            ilerleme(Double(i + 1) / Double(belge.pageCount))
        }
        return Sonuc(metin: parcalar.joined(separator: "\n\n"), tablolar: tablolar)
    }
}

struct MetinCikarEkrani: View {
    static let arac = Arac(id: "metniCikar", ad: "Metni çıkar",
                           aciklama: "PDF'in metnini (gerekirse OCR ile) TXT dosyasına çıkar, panoya kopyala.",
                           simge: "doc.plaintext", kategori: .tarama, girdi: .birVeyaCokPDF, topluUygun: true) {
        MetinCikarEkrani(baglam: $0)
    }

    let baglam: AracBaglami
    @State private var mod: MetinCikarici.Mod = .otomatik
    @State private var dil: OCRDili = .trEn
    @State private var panoya = true
    @State private var baslik = false
    @State private var tablolar = false
    @State private var parola = ""

    var body: some View {
        AracSablonu(arac: Self.arac, girdiler: baglam.girdiler) {
            Section {
                Picker("Kaynak", selection: $mod) { ForEach(MetinCikarici.Mod.allCases) { Text($0.ad).tag($0) } }
                if mod != .gomulu { Picker("OCR dili", selection: $dil) { ForEach(OCRDili.allCases) { Text($0.ad).tag($0) } } }
                Toggle("Sayfa başlıkları ekle", isOn: $baslik)
                if mod != .gomulu { Toggle("Tabloları ayrı CSV dosyası yap", isOn: $tablolar) }
                Toggle("Panoya kopyala", isOn: $panoya)
                SecureField("Parola (dosya parolalıysa)", text: $parola)
            }
        } calistir: { girdiler, ilerleme in
            let p = parola.isEmpty ? nil : parola
            let n = Double(girdiler.count)
            var cikti: [URL] = []
            var tum: [String] = []
            for (i, u) in girdiler.enumerated() {
                let taban = Double(i)
                let s = try await MetinCikarici.calistir(url: u, parola: p, mod: mod, diller: dil.kodlar,
                                                         sayfaBasligi: baslik, tablo: tablolar && mod != .gomulu) { o in
                    ilerleme((taban + o) / n)
                }
                guard !s.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !s.tablolar.isEmpty else { continue }
                let h = Gecici.dosya("\(u.adSiz).txt")
                try s.metin.write(to: h, atomically: true, encoding: .utf8)
                cikti.append(h)
                for (j, csv) in s.tablolar.enumerated() {
                    let c = Gecici.dosya("\(u.adSiz) - tablo \(j + 1).csv")
                    try ("\u{FEFF}" + csv).write(to: c, atomically: true, encoding: .utf8)
                    cikti.append(c)
                }
                tum.append(s.metin)
            }
            guard !cikti.isEmpty else { throw KagitHata.genel("Çıkarılacak metin bulunamadı.") }
            if panoya { UIPasteboard.general.string = tum.joined(separator: "\n\n") }
            return cikti
        }
    }
}
