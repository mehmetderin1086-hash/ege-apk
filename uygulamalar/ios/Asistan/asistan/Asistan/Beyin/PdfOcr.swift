import Foundation
import PDFKit
import Vision
import UIKit
import CoreML

/// Metin katmanı olmayan (taranmış) PDF sayfaları için cihaz içi OCR.
/// Sayfa başına render → Vision → bırak; bellek tek sayfa büyüklüğünde kalır.
nonisolated enum PdfOcr {
    struct Ayar: Sendable, Equatable {
        var dpi: Double = 250
        /// Toplam OCR'lanacak sayfa sınırı.
        var azamiSayfa = 60
        /// Bütün OCR işi için duvar saati bütçesi (sn); dolunca kalan sayfalar atlanır.
        var sureButcesi: TimeInterval = 240
        /// Render edilen görüntünün uzun kenarı (piksel) üst sınırı.
        var azamiKenarPiksel = 3600
        /// Bu değerin altındaki satır 'düşük güvenli' sayılır.
        var dusukGuvenEsigi: Float = 0.5
        /// Vision hatasında sayfa başına en çok deneme (son deneme yalnız CPU).
        var denemeSayisi = 3
        static let varsayilan = Ayar()
    }

    /// Vision koordinatları: 0...1, başlangıç sol alt.
    struct Satir: Sendable, Equatable {
        var metin: String
        var guven: Float
        var kutu: CGRect
    }

    struct SayfaSonucu: Sendable, Equatable {
        /// 0 tabanlı sayfa indeksi.
        var indeks: Int
        var metin: String
        var satirSayisi: Int
        var ortalamaGuven: Double?
        var dusukGuvenOrani: Double
        var hata: String?
    }

    struct Sonuc: Sendable, Equatable {
        var sayfalar: [SayfaSonucu]
        /// Sayfa sınırı yüzünden hiç denenmeyen sayfa sayısı.
        var sinirYuzundenAtlanan: Int
        /// Süre bütçesi yüzünden denenmeyen sayfa sayısı.
        var sureYuzundenAtlanan: Int

        var metinliSayfalar: [SayfaSonucu] { sayfalar.filter { $0.hata == nil && !$0.metin.isEmpty } }
        var hataliSayfalar: [SayfaSonucu] { sayfalar.filter { $0.hata != nil } }
        var sureAsildi: Bool { sureYuzundenAtlanan > 0 }

        /// Satır sayısıyla ağırlıklı ortalama güven (0...1); hiç satır yoksa nil.
        var ortalamaGuven: Double? {
            var toplam = 0.0, adet = 0
            for s in sayfalar { if let g = s.ortalamaGuven { toplam += g * Double(s.satirSayisi); adet += s.satirSayisi } }
            return adet > 0 ? toplam / Double(adet) : nil
        }
    }

    // MARK: Saf mantık

    /// Satırları okuma sırasına dizer: üstten alta, aynı satırdaki parçalar soldan sağa.
    /// Aynı hizadaki sayılma ölçütü: dikey merkez farkı, ortanca satır yüksekliğinin yarısından küçük.
    static func okumaSirasi(_ satirlar: [Satir]) -> [Satir] {
        guard satirlar.count > 1 else { return satirlar }
        let yukseklikler = satirlar.map { $0.kutu.height }.sorted()
        let tolerans = max(yukseklikler[yukseklikler.count / 2] * 0.5, 0.002)
        let ustten = satirlar.sorted { $0.kutu.midY > $1.kutu.midY }
        var gruplar: [[Satir]] = []
        var grupMerkezi = 0.0
        for s in ustten {
            if let son = gruplar.indices.last, abs(Double(s.kutu.midY) - grupMerkezi) < Double(tolerans) {
                gruplar[son].append(s)
                grupMerkezi = gruplar[son].map { Double($0.kutu.midY) }.reduce(0, +) / Double(gruplar[son].count)
            } else {
                gruplar.append([s])
                grupMerkezi = Double(s.kutu.midY)
            }
        }
        return gruplar.flatMap { $0.sorted { $0.kutu.minX < $1.kutu.minX } }
    }

    /// Okuma sırasındaki satırları metne çevirir: aynı hizadaki parçalar boşlukla, farklı hizalar satır sonuyla.
    static func sayfaMetni(_ satirlar: [Satir]) -> String {
        let sirali = okumaSirasi(satirlar)
        guard !sirali.isEmpty else { return "" }
        let tolerans = max(sirali.map { $0.kutu.height }.sorted()[sirali.count / 2] * 0.5, 0.002)
        var cikti = ""
        var oncekiMerkez: CGFloat?
        for s in sirali {
            let yazi = s.metin.trimmingCharacters(in: .whitespaces)
            if yazi.isEmpty { continue }
            if let o = oncekiMerkez {
                cikti += abs(o - s.kutu.midY) < tolerans ? " " : "\n"
            }
            cikti += yazi
            oncekiMerkez = s.kutu.midY
        }
        return cikti
    }

    /// (ortalama güven 0...1, eşiğin altındaki satır oranı 0...1); boş girdide (nil, 0).
    static func guvenOzeti(_ guvenler: [Float], esik: Float) -> (ortalama: Double?, dusukOran: Double) {
        let gecerli = guvenler.filter { $0.isFinite }.map { min(max($0, 0), 1) }
        guard !gecerli.isEmpty else { return (nil, 0) }
        let ort = gecerli.reduce(0.0) { $0 + Double($1) } / Double(gecerli.count)
        let dusuk = Double(gecerli.filter { $0 < esik }.count) / Double(gecerli.count)
        return (ort, dusuk)
    }

    /// Sayfa boyutunu (punto) dpi'ye göre piksele çevirir; uzun kenar `azami`yi aşarsa orantılı küçültür.
    static func pikselBoyutu(sayfa: CGSize, dpi: Double, azami: Int) -> CGSize {
        guard sayfa.width > 0, sayfa.height > 0, dpi > 0 else { return .zero }
        var olcek = dpi / 72
        let uzun = max(sayfa.width, sayfa.height) * olcek
        if uzun > Double(azami) { olcek *= Double(azami) / uzun }
        return CGSize(width: max(1, (sayfa.width * olcek).rounded()), height: max(1, (sayfa.height * olcek).rounded()))
    }

    /// Kullanıcıya/modele eklenecek tek satırlık not: OCR ibaresi, ortalama güven ve atlananlar.
    static func not(_ sonuc: Sonuc, okunanSayfa: Int? = nil) -> String {
        let okunan = okunanSayfa ?? sonuc.metinliSayfalar.count
        var parcalar = ["\(okunan) sayfa OCR ile okundu, hata olabilir."]
        if let g = sonuc.ortalamaGuven {
            let satirlar = sonuc.sayfalar.reduce(0) { $0 + $1.satirSayisi }
            let dusuk = satirlar > 0 ? sonuc.sayfalar.reduce(0.0) { $0 + $1.dusukGuvenOrani * Double($1.satirSayisi) } / Double(satirlar) : 0
            parcalar.append("Ortalama güven %\(Int((g * 100).rounded())), düşük güvenli satır oranı %\(Int((dusuk * 100).rounded())).")
        }
        if sonuc.sinirYuzundenAtlanan > 0 { parcalar.append("OCR sayfa sınırı yüzünden \(sonuc.sinirYuzundenAtlanan) sayfa atlandı.") }
        if sonuc.sureYuzundenAtlanan > 0 { parcalar.append("OCR süre bütçesi dolduğu için \(sonuc.sureYuzundenAtlanan) sayfa atlandı.") }
        let hatali = sonuc.hataliSayfalar
        if !hatali.isEmpty { parcalar.append("OCR hatası olan sayfa: \(hatali.map { String($0.indeks + 1) }.joined(separator: ", ")).") }
        return "[Not: " + parcalar.joined(separator: " ") + "]"
    }

    // MARK: Render + tanıma

    /// Tek sayfayı beyaz zeminli, dpi'ye göre ölçekli bir görüntüye çevirir. Çağıran işi bitince bırakır.
    /// Sayfa döndürmesi sonrası çizim alanı (90/270'de genişlik ↔ yükseklik).
    static func donmusBoyut(_ r: CGRect, rotation: Int) -> CGRect {
        let d = ((rotation % 360) + 360) % 360
        return d == 90 || d == 270 ? CGRect(x: 0, y: 0, width: r.height, height: r.width) : CGRect(origin: .zero, size: r.size)
    }

    static func goruntu(_ sayfa: PDFPage, ayar: Ayar) -> CGImage? {
        // `draw(with:to:)` sayfanın /Rotate değerini kendisi uygular: 90/270'de tuval en-boyu değişmeli,
        // yoksa tarayıcıdan gelen yatay sayfa dar tuvale sığmayıp kırpılır.
        let ham = sayfa.bounds(for: .mediaBox)
        let sinir = donmusBoyut(ham, rotation: sayfa.rotation)
        let boyut = pikselBoyutu(sayfa: sinir.size, dpi: ayar.dpi, azami: ayar.azamiKenarPiksel)
        guard boyut.width > 0 else { return nil }
        let bicim = UIGraphicsImageRendererFormat()
        bicim.scale = 1
        bicim.opaque = true
        let img = UIGraphicsImageRenderer(size: boyut, format: bicim).image { r in
            UIColor.white.setFill()
            r.fill(CGRect(origin: .zero, size: boyut))
            let cg = r.cgContext
            cg.translateBy(x: 0, y: boyut.height)
            cg.scaleBy(x: boyut.width / sinir.width, y: -boyut.height / sinir.height)
            sayfa.draw(with: .mediaBox, to: cg)
        }
        return img.cgImage
    }

    /// Vision ile tek görüntüyü okur. e5rtError gibi geçici hatalarda yeniden dener; son deneme yalnız CPU'dur.
    static func tani(_ cg: CGImage, ayar: Ayar) throws -> [Satir] {
        var sonHata: Error?
        for deneme in 0..<max(1, ayar.denemeSayisi) {
            try Task.checkCancellation()
            do {
                let istek = VNRecognizeTextRequest()
                istek.recognitionLevel = .accurate
                istek.usesLanguageCorrection = true
                let diller = (try? istek.supportedRecognitionLanguages()) ?? []
                let secili = ["tr-TR", "en-US"].filter(diller.contains)
                if !secili.isEmpty { istek.recognitionLanguages = secili }
                if deneme > 0, deneme == ayar.denemeSayisi - 1 { if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) { istek.setComputeDevice(cpu, for: .main) } }
                try VNImageRequestHandler(cgImage: cg).perform([istek])
                return (istek.results ?? []).compactMap { gozlem in
                    guard let aday = gozlem.topCandidates(1).first else { return nil }
                    return Satir(metin: aday.string, guven: aday.confidence, kutu: gozlem.boundingBox)
                }
            } catch {
                sonHata = error
                if deneme < ayar.denemeSayisi - 1 { Thread.sleep(forTimeInterval: 0.25 * Double(deneme + 1)) }
            }
        }
        throw sonHata ?? OcrHatasi.bilinmeyen
    }

    private enum OcrHatasi: Error { case bilinmeyen }

    /// `sayfalar` (0 tabanlı indeksler) için OCR yürütür. İptalde `CancellationError` fırlatır;
    /// sayfa başına hata yalıtılır (o sayfa `hata` ile döner, diğerleri sürer).
    /// `ilerleme(tamamlanan, toplam)` her denenen sayfadan sonra çağrılır.
    static func oku(_ belge: PDFDocument, sayfalar: [Int], ayar: Ayar = .varsayilan,
                    ilerleme: (@Sendable (Int, Int) -> Void)? = nil) throws -> Sonuc {
        let baslangic = Date()
        let sinirli = Array(sayfalar.prefix(max(0, ayar.azamiSayfa)))
        var sonuc = Sonuc(sayfalar: [], sinirYuzundenAtlanan: max(0, sayfalar.count - sinirli.count), sureYuzundenAtlanan: 0)
        for (sira, indeks) in sinirli.enumerated() {
            try Task.checkCancellation()
            if Date().timeIntervalSince(baslangic) >= ayar.sureButcesi {
                sonuc.sureYuzundenAtlanan = sinirli.count - sira
                break
            }
            sonuc.sayfalar.append(try sayfayiOku(belge, indeks: indeks, ayar: ayar))
            ilerleme?(sira + 1, sinirli.count)
        }
        return sonuc
    }

    private static func sayfayiOku(_ belge: PDFDocument, indeks: Int, ayar: Ayar) throws -> SayfaSonucu {
        func hata(_ m: String) -> SayfaSonucu {
            SayfaSonucu(indeks: indeks, metin: "", satirSayisi: 0, ortalamaGuven: nil, dusukGuvenOrani: 0, hata: m)
        }
        var satirlar: [Satir] = []
        var yakalanan: Error?
        autoreleasepool {
            guard let sayfa = belge.page(at: indeks) else { yakalanan = OcrHatasi.bilinmeyen; return }
            guard let cg = goruntu(sayfa, ayar: ayar) else { yakalanan = OcrHatasi.bilinmeyen; return }
            do { satirlar = try tani(cg, ayar: ayar) } catch { yakalanan = error }
        }
        if let e = yakalanan {
            if e is CancellationError { throw e }
            return hata(e is OcrHatasi ? "Sayfa görüntüye çevrilemedi." : e.localizedDescription)
        }
        let ozet = guvenOzeti(satirlar.map(\.guven), esik: ayar.dusukGuvenEsigi)
        return SayfaSonucu(indeks: indeks, metin: sayfaMetni(satirlar), satirSayisi: satirlar.count,
                           ortalamaGuven: ozet.ortalama, dusukGuvenOrani: ozet.dusukOran, hata: nil)
    }
}
