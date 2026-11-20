import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Sıkıştırma ön ayarı.
public enum SikistirmaOnAyari: String, CaseIterable, Sendable, Identifiable {
    case az, orta, yuksek, epostayaSigdir
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .az: "Az sıkıştır (en iyi kalite)"
        case .orta: "Orta"
        case .yuksek: "Yüksek sıkıştırma"
        case .epostayaSigdir: "E-postaya sığdır (≤ 10 MB)"
        }
    }
}

public struct SikistirmaAyari: Sendable, Equatable {
    public enum Yol: String, Sendable, CaseIterable, Identifiable {
        /// PDFKit: metin vektör kalır, görseller JPEG/ekran çözünürlüğüne iner.
        case vektor
        /// Her sayfa görüntüye çevrilir (taranmış belgeler için); metin seçilemez olur.
        case rasterlestir
        public var id: String { rawValue }
    }

    public var yol: Yol
    /// Rasterleştirmede çözünürlük.
    public var dpi: Int
    /// JPEG kalitesi (0...1), rasterleştirmede.
    public var jpegKalite: Double
    /// Vektör yolunda görselleri ~144 dpi'ye indir.
    public var ekranIcin: Bool
    /// Doluysa hedef boyuta ulaşana kadar kademeli dener.
    public var hedefBayt: Int64?

    public init(yol: Yol, dpi: Int = 150, jpegKalite: Double = 0.7, ekranIcin: Bool = true, hedefBayt: Int64? = nil) {
        self.yol = yol
        self.dpi = dpi
        self.jpegKalite = jpegKalite
        self.ekranIcin = ekranIcin
        self.hedefBayt = hedefBayt
    }

    public static func onAyar(_ o: SikistirmaOnAyari) -> SikistirmaAyari {
        switch o {
        case .az: .init(yol: .vektor, ekranIcin: false)
        case .orta: .init(yol: .vektor, ekranIcin: true)
        case .yuksek: .init(yol: .rasterlestir, dpi: 110, jpegKalite: 0.55)
        case .epostayaSigdir: .init(yol: .vektor, ekranIcin: true, hedefBayt: 10_000_000)
        }
    }
}

public struct SikistirmaSonucu: Sendable {
    /// Küçüldüyse yeni dosya, aksi halde özgün girdi.
    public let cikti: URL
    public let girdiBoyu: Int64
    public let ciktiBoyu: Int64
    public let kuculdu: Bool
    public let kullanilanYol: SikistirmaAyari.Yol
    /// Hedef boyut istendiyse ulaşıldı mı.
    public let hedefeUlasti: Bool

    public var ileti: String {
        if !kuculdu { return "Dosya zaten en küçük hâlinde; özgün dosya korundu." }
        let oran = Int((1 - Double(ciktiBoyu) / Double(max(girdiBoyu, 1))) * 100)
        return "\(BicimYardimci.boyut(girdiBoyu)) → \(BicimYardimci.boyut(ciktiBoyu)) (%\(oran) küçüldü)"
    }
}

public enum Sikistirma {

    public static func sikistir(_ giris: URL, ayar: SikistirmaAyari, parola: String? = nil,
                                ilerleme: Ilerleme? = nil) throws -> SikistirmaSonucu {
        let girdiBoyu = IsYardimcisi.dosyaBoyutu(giris)
        let hedef = IsYardimcisi.cikti(giris, "küçültüldü")

        // Aday ayarlar: hedef boyut varsa kademeli sertleşir.
        var adaylar: [SikistirmaAyari] = [ayar]
        if ayar.hedefBayt != nil {
            adaylar += [
                .init(yol: .rasterlestir, dpi: 150, jpegKalite: 0.65),
                .init(yol: .rasterlestir, dpi: 110, jpegKalite: 0.5),
                .init(yol: .rasterlestir, dpi: 80, jpegKalite: 0.4),
            ]
        }

        var enIyi: (veri: Data, ayar: SikistirmaAyari, sayfa: Int)?
        for (k, a) in adaylar.enumerated() {
            try iptalDenetle()
            let (veri, sayfa) = try uret(giris, a, parola: parola) { o in
                ilerleme?((Double(k) + o) / Double(adaylar.count))
            }
            if enIyi == nil || veri.count < enIyi!.veri.count { enIyi = (veri, a, sayfa) }
            if let h = ayar.hedefBayt, Int64(veri.count) <= h { break }
            if ayar.hedefBayt == nil { break }
        }
        guard let en = enIyi else { throw KagitHata.bosGirdi }
        let hedefeUlasti = ayar.hedefBayt.map { Int64(en.veri.count) <= $0 } ?? true
        guard Int64(en.veri.count) < girdiBoyu else {
            return SikistirmaSonucu(cikti: giris, girdiBoyu: girdiBoyu, ciktiBoyu: girdiBoyu, kuculdu: false,
                                    kullanilanYol: en.ayar.yol, hedefeUlasti: ayar.hedefBayt.map { girdiBoyu <= $0 } ?? true)
        }
        try Belge.yaz(en.veri, hedef, beklenenSayfa: en.sayfa)
        ilerleme?(1)
        return SikistirmaSonucu(cikti: hedef, girdiBoyu: girdiBoyu, ciktiBoyu: Int64(en.veri.count), kuculdu: true,
                                kullanilanYol: en.ayar.yol, hedefeUlasti: hedefeUlasti)
    }

    private static func uret(_ giris: URL, _ a: SikistirmaAyari, parola: String?, _ ilerleme: (Double) -> Void) throws -> (Data, Int) {
        let b = try Belge.ac(giris, parola: parola)
        switch a.yol {
        case .vektor:
            let veri = try Belge.veri(b, secenekler: KayitSecenekleri(aciklamalariGom: true, gorselleriJPEG: true,
                                                                       ekranIcinOptimize: a.ekranIcin))
            return (veri, b.pageCount)
        case .rasterlestir:
            let y = PDFCizim.Yazici(baslik: giris.deletingPathExtension().lastPathComponent)
            let n = b.pageCount
            for i in 0..<n {
                try iptalDenetle()
                try autoreleasepool {
                    guard let s = b.page(at: i) else { return }
                    let g = IsYardimcisi.gorunenBoyut(s)
                    guard let img = PDFCizim.goruntu(s, dpi: CGFloat(a.dpi)),
                          let jpeg = PDFCizim.kodla(img, tur: .jpeg, kalite: a.jpegKalite),
                          let kaynak = CGImageSourceCreateWithData(jpeg as CFData, nil),
                          let gomulecek = CGImageSourceCreateImageAtIndex(kaynak, 0, nil) else {
                        throw KagitHata.genel("Sayfa \(i + 1) görüntüye çevrilemedi.")
                    }
                    y.sayfa(CGRect(origin: .zero, size: g)) { ctx in
                        ctx.draw(gomulecek, in: CGRect(origin: .zero, size: g))
                    }
                }
                ilerleme(Double(i + 1) / Double(n))
            }
            return (y.bitir(), n)
        }
    }
}
