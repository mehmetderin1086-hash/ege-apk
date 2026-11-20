import KagitKit
import SwiftUI

/// Tarama kalitesi: görüntü boyutu ve JPEG sıkıştırması.
nonisolated enum TaramaKalitesi: String, CaseIterable, Identifiable {
    case dusuk, orta, yuksek
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .dusuk: "Küçük dosya"
        case .orta: "Dengeli"
        case .yuksek: "En iyi"
        }
    }
    var enBuyukKenar: CGFloat {
        switch self {
        case .dusuk: 1500
        case .orta: 2100
        case .yuksek: 3000
        }
    }
    var jpeg: Double {
        switch self {
        case .dusuk: 0.55
        case .orta: 0.72
        case .yuksek: 0.88
        }
    }
}

/// Düzenleme ekranındaki tek sayfa. Görüntü işlemleri sırası: döndür → kırp (perspektif) → filtre.
struct TaramaSayfasi: Identifiable, Sendable {
    let id = UUID()
    /// Tam çözünürlüklü kaynak (en uzun kenar ≤ 3200 px).
    var ozgun: CGImage
    /// Önizleme için küçültülmüş kaynak.
    var kucuk: CGImage
    /// Saat yönünde derece (90'ın katı).
    var dondurme = 0
    /// Döndürülmüş görüntüye göre kırpma dörtgeni.
    var dortgen = Dortgen.tam
    var filtre: TaramaFiltresi = .ozgun
    var golgeTemizle = false
    var onizleme: CGImage?
    fileprivate var surum = 0
}

/// Tarama oturumunun durumu.
@Observable
final class TaramaModeli {
    var sayfalar: [TaramaSayfasi] = []
    var secili: UUID?

    var seciliIndeks: Int? { sayfalar.firstIndex { $0.id == secili } }

    // MARK: - Ekleme

    /// Yeni görüntüleri sona ekler. `otomatikKose` (fotoğraflar): belge köşeleri algılanırsa kırpar.
    func ekle(_ goruntuler: [CGImage], otomatikKose: Bool = false, filtre: TaramaFiltresi = .ozgun) {
        var yeniler: [TaramaSayfasi] = []
        for g in goruntuler {
            let ozgun = TaramaIslemleri.kucult(g, enBuyukKenar: 3200)
            let kucuk = TaramaIslemleri.kucult(ozgun, enBuyukKenar: 1400)
            var s = TaramaSayfasi(ozgun: ozgun, kucuk: kucuk)
            s.filtre = filtre
            yeniler.append(s)
        }
        sayfalar += yeniler
        if secili == nil { secili = yeniler.first?.id }
        for s in yeniler {
            yenile(s.id)
            if otomatikKose { koseleriAlgila(s.id) }
        }
    }

    /// Bir sayfanın yerine yeniden taranan görüntüyü koyar (filtre ayarları korunur).
    func degistir(_ id: UUID, goruntu: CGImage) {
        guard let i = sayfalar.firstIndex(where: { $0.id == id }) else { return }
        let ozgun = TaramaIslemleri.kucult(goruntu, enBuyukKenar: 3200)
        sayfalar[i].ozgun = ozgun
        sayfalar[i].kucuk = TaramaIslemleri.kucult(ozgun, enBuyukKenar: 1400)
        sayfalar[i].dondurme = 0
        sayfalar[i].dortgen = .tam
        yenile(id)
    }

    func koseleriAlgila(_ id: UUID) {
        guard let s = sayfalar.first(where: { $0.id == id }) else { return }
        let kaynak = TaramaIslemleri.dondur(s.kucuk, derece: s.dondurme)
        Task {
            guard let d = await TaramaIslemleri.kenarlariBul(kaynak),
                  d.alan > 0.25, d.alan < 0.97,
                  let i = sayfalar.firstIndex(where: { $0.id == id }), sayfalar[i].dondurme == s.dondurme else { return }
            sayfalar[i].dortgen = d
            yenile(id)
        }
    }

    // MARK: - Düzenleme

    func guncelle(_ id: UUID, _ yap: (inout TaramaSayfasi) -> Void) {
        guard let i = sayfalar.firstIndex(where: { $0.id == id }) else { return }
        yap(&sayfalar[i])
        yenile(id)
    }

    /// 90° döndürür; kırpma dörtgenini de birlikte döndürür.
    func dondur(_ id: UUID, saatYonunde: Bool = true) {
        guncelle(id) { s in
            s.dondurme = ((s.dondurme + (saatYonunde ? 90 : 270)) % 360)
            s.dortgen = s.dortgen.dondurulmus(saatYonunde: saatYonunde)
        }
    }

    func sil(_ id: UUID) {
        guard let i = sayfalar.firstIndex(where: { $0.id == id }) else { return }
        sayfalar.remove(at: i)
        if secili == id { secili = sayfalar.indices.contains(i) ? sayfalar[i].id : sayfalar.last?.id }
    }

    func tasi(_ id: UUID, hedef: UUID) {
        guard id != hedef, let a = sayfalar.firstIndex(where: { $0.id == id }),
              let b = sayfalar.firstIndex(where: { $0.id == hedef }) else { return }
        let s = sayfalar.remove(at: a)
        sayfalar.insert(s, at: b)
    }

    func kaydir(_ id: UUID, adim: Int) {
        guard let a = sayfalar.firstIndex(where: { $0.id == id }) else { return }
        let b = a + adim
        guard sayfalar.indices.contains(b) else { return }
        sayfalar.swapAt(a, b)
    }

    func filtreyiHepsineUygula(_ id: UUID) {
        guard let kaynak = sayfalar.first(where: { $0.id == id }) else { return }
        for s in sayfalar where s.id != id {
            guncelle(s.id) { $0.filtre = kaynak.filtre; $0.golgeTemizle = kaynak.golgeTemizle }
        }
    }

    // MARK: - İşleme

    /// Önizlemeyi arka planda yeniden üretir; eski istekler (sürüm numarası) yok sayılır.
    func yenile(_ id: UUID) {
        guard let i = sayfalar.firstIndex(where: { $0.id == id }) else { return }
        sayfalar[i].surum += 1
        let surum = sayfalar[i].surum
        let s = sayfalar[i]
        Task {
            let sonuc = await Task.detached(priority: .userInitiated) {
                Self.isle(s.kucuk, dondurme: s.dondurme, dortgen: s.dortgen, filtre: s.filtre,
                          golgeTemizle: s.golgeTemizle, enBuyukKenar: nil)
            }.value
            if let j = sayfalar.firstIndex(where: { $0.id == id }), sayfalar[j].surum == surum {
                sayfalar[j].onizleme = sonuc
            }
        }
    }

    /// Döndür → kırp → filtre → (isteğe bağlı) küçült.
    nonisolated static func isle(_ kaynak: CGImage, dondurme: Int, dortgen: Dortgen, filtre: TaramaFiltresi,
                                 golgeTemizle: Bool, enBuyukKenar: CGFloat?) -> CGImage {
        var g = TaramaIslemleri.dondur(kaynak, derece: dondurme)
        g = TaramaIslemleri.perspektifDuzelt(g, dortgen: dortgen)
        if let enBuyukKenar { g = TaramaIslemleri.kucult(g, enBuyukKenar: enBuyukKenar) }
        return TaramaIslemleri.uygula(g, filtre: filtre, golgeTemizle: golgeTemizle)
    }

    /// Kaydederken: tam çözünürlüklü işlenmiş görüntüler.
    func sonGoruntuler(kalite: TaramaKalitesi) async -> [CGImage] {
        let kopya = sayfalar
        return await Task.detached(priority: .userInitiated) {
            kopya.map {
                Self.isle($0.ozgun, dondurme: $0.dondurme, dortgen: $0.dortgen, filtre: $0.filtre,
                          golgeTemizle: $0.golgeTemizle, enBuyukKenar: kalite.enBuyukKenar)
            }
        }.value
    }
}

extension Dortgen {
    /// Normalize görüntü (üst sol köken) 90° döndürülünce köşelerin yeni konumu ve adları.
    func dondurulmus(saatYonunde: Bool) -> Dortgen {
        func ileri(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.y, y: p.x) }      // saat yönü
        func geri(_ p: CGPoint) -> CGPoint { CGPoint(x: p.y, y: 1 - p.x) }       // saat yönünün tersi
        if saatYonunde {
            return Dortgen(ustSol: ileri(altSol), ustSag: ileri(ustSol), altSag: ileri(ustSag), altSol: ileri(altSag))
        }
        return Dortgen(ustSol: geri(ustSag), ustSag: geri(altSag), altSag: geri(altSol), altSol: geri(ustSol))
    }
}
