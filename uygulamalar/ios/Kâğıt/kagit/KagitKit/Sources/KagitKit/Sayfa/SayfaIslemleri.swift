import CoreGraphics
import Foundation
import PDFKit

/// Bölme biçimi.
public enum BolmeKipi: Sendable, Equatable {
    /// Her aralık ayrı dosya: ["1-3", "4-6", "7-"].
    case araliklar([String])
    /// Her N sayfada bir dosya.
    case herNSayfada(Int)
    /// Her sayfa ayrı dosya.
    case tekTek
    /// Her parça verilen bayt sınırını aşmayacak biçimde.
    case boyutSiniri(Int64)
}

/// Sıralama işlemleri.
public enum SiralamaKipi: Sendable, Equatable {
    case tersCevir
    case yalnizTekler
    case yalnizCiftler
    /// İki dosya: tekler ve çiftler.
    case tekVeCiftAyir
}

/// Sayfa düzeyindeki işlemler: birleştir, böl, çıkar, sil, döndür, sırala, boş sayfa, yeniden boyutlandır.
public enum SayfaIslemleri {

    // MARK: Birleştir

    /// Birden çok PDF'i sırayla birleştirir. `yerImi`: her dosyanın adı ilk sayfasına yer imi olur.
    /// `parolalar`: dosya adı → parola.
    public static func birlestir(_ girdiler: [URL], yerImi: Bool = true, parolalar: [String: String] = [:],
                                 ilerleme: Ilerleme? = nil) throws -> URL {
        guard !girdiler.isEmpty else { throw KagitHata.bosGirdi }
        let cikis = PDFDocument()
        let kok = PDFOutline()
        var kaynaklar: [PDFDocument] = []
        for (i, u) in girdiler.enumerated() {
            try iptalDenetle()
            let b = try Belge.ac(u, parola: parolalar[u.lastPathComponent])
            kaynaklar.append(b)
            let bas = cikis.pageCount
            var k = 0
            while k < b.pageCount {
                try iptalDenetle()
                autoreleasepool {
                    let son = min(b.pageCount, k + 50)
                    for j in k..<son {
                        if let s = b.page(at: j) { cikis.insert(Belge.sayfaKopyasi(s), at: cikis.pageCount) }
                    }
                    k = son
                }
            }
            if yerImi, let ilk = cikis.page(at: bas) {
                let o = PDFOutline()
                o.label = u.deletingPathExtension().lastPathComponent
                o.destination = PDFDestination(page: ilk, at: CGPoint(x: 0, y: ilk.bounds(for: .cropBox).maxY))
                kok.insertChild(o, at: kok.numberOfChildren)
            }
            ilerleme?(Double(i + 1) / Double(girdiler.count))
        }
        guard cikis.pageCount > 0 else { throw KagitHata.bosGirdi }
        if yerImi { cikis.outlineRoot = kok }
        let ad = girdiler.count == 1 ? girdiler[0].deletingPathExtension().lastPathComponent : "Birleştirilmiş"
        let hedef = Gecici.dosya("\(ad).pdf")
        try IsYardimcisi.yaz(cikis, hedef)
        withExtendedLifetime(kaynaklar) {}
        return hedef
    }

    // MARK: Böl

    public static func bol(_ giris: URL, kip: BolmeKipi, parola: String? = nil, ilerleme: Ilerleme? = nil) throws -> [URL] {
        let kaynak = try Belge.ac(giris, parola: parola)
        let n = kaynak.pageCount
        guard n > 0 else { throw KagitHata.bosGirdi }
        let ad = giris.deletingPathExtension().lastPathComponent
        let klasor = Gecici.klasor()
        var sonuc: [URL] = []

        func yaz(_ idx: [Int], _ etiket: String, veri: Data? = nil) throws {
            try iptalDenetle()
            let v = try veri ?? Belge.veri(IsYardimcisi.belge(kaynak, indeksler: idx))
            let hedef = klasor.appendingPathComponent(TurkceMetin.dosyaAdi("\(ad) (\(etiket))") + ".pdf")
            try Belge.yaz(v, hedef, beklenenSayfa: idx.count)
            sonuc.append(hedef)
        }

        switch kip {
        case .araliklar(let liste):
            let temiz = liste.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !temiz.isEmpty else { throw KagitHata.gecersizAralik("") }
            for (i, a) in temiz.enumerated() {
                let idx = try SayfaAraligi.coz(a, sayfaSayisi: n)
                try yaz(idx, "Sayfa \(SayfaAraligi.metin(idx))")
                ilerleme?(Double(i + 1) / Double(temiz.count))
            }
        case .herNSayfada(let m):
            guard m >= 1 else { throw KagitHata.gecersizAralik("\(m)") }
            let parcaSayisi = (n + m - 1) / m
            for p in 0..<parcaSayisi {
                let idx = Array((p * m)..<min(n, (p + 1) * m))
                try yaz(idx, "Sayfa \(SayfaAraligi.metin(idx))")
                ilerleme?(Double(p + 1) / Double(parcaSayisi))
            }
        case .tekTek:
            for i in 0..<n {
                try yaz([i], "Sayfa \(i + 1)")
                ilerleme?(Double(i + 1) / Double(n))
            }
        case .boyutSiniri(let sinir):
            guard sinir > 10_000 else { throw KagitHata.gecersizAralik("boyut sınırı çok küçük") }
            var kalan = Array(0..<n)
            var tahmin = n
            var parca = 1
            while !kalan.isEmpty {
                try iptalDenetle()
                var adet = min(kalan.count, tahmin)
                var veri: Data
                while true {
                    veri = try Belge.veri(IsYardimcisi.belge(kaynak, indeksler: Array(kalan.prefix(adet))))
                    if Int64(veri.count) <= sinir || adet == 1 { break }
                    let oran = Double(sinir) / Double(veri.count) * 0.97
                    adet = max(1, min(adet - 1, Int(Double(adet) * oran)))
                }
                let idx = Array(kalan.prefix(adet))
                try yaz(idx, "Parça \(parca)", veri: veri)
                kalan.removeFirst(adet)
                tahmin = adet
                parca += 1
                ilerleme?(Double(n - kalan.count) / Double(n))
            }
        }
        return sonuc
    }

    // MARK: Çıkar / sil

    /// Aralıktaki sayfaları yeni PDF'e çıkarır.
    public static func sayfaCikar(_ giris: URL, aralik: String, parola: String? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        let yeni = IsYardimcisi.belge(b, indeksler: idx)
        return try IsYardimcisi.yaz(yeni, IsYardimcisi.cikti(giris, "Sayfa \(SayfaAraligi.metin(idx))"))
    }

    /// Aralıktaki sayfaları siler. Hepsi silinemez.
    public static func sayfaSil(_ giris: URL, aralik: String, parola: String? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let silinecek = Set(try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount))
        let kalan = (0..<b.pageCount).filter { !silinecek.contains($0) }
        guard !kalan.isEmpty else { throw KagitHata.genel("Bütün sayfalar silinemez. En az bir sayfa kalmalı.") }
        let yeni = IsYardimcisi.belge(b, indeksler: kalan)
        return try IsYardimcisi.yaz(yeni, IsYardimcisi.cikti(giris, "sayfa silindi"))
    }

    // MARK: Döndür

    /// Aralıktaki sayfaları döndürür (90, 180, 270; negatif = sola).
    public static func dondur(_ giris: URL, aralik: String = "", derece: Int, parola: String? = nil) throws -> URL {
        guard derece % 90 == 0, derece != 0 else { throw KagitHata.genel("Döndürme 90, 180 veya 270 derece olmalı.") }
        let b = try Belge.ac(giris, parola: parola)
        let idx = try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount)
        for i in idx {
            guard let s = b.page(at: i) else { continue }
            s.rotation = ((s.rotation + derece) % 360 + 360) % 360
        }
        return try IsYardimcisi.yaz(b, IsYardimcisi.cikti(giris, "döndürüldü"))
    }

    // MARK: Sırala

    /// Sıralama işlemi. `tekVeCiftAyir` iki dosya (tekler, çiftler) döndürür.
    public static func sirala(_ giris: URL, kip: SiralamaKipi, parola: String? = nil) throws -> [URL] {
        let b = try Belge.ac(giris, parola: parola)
        let n = b.pageCount
        guard n > 0 else { throw KagitHata.bosGirdi }
        let tekler = Array(stride(from: 0, to: n, by: 2)), ciftler = Array(stride(from: 1, to: n, by: 2))
        func yap(_ idx: [Int], _ ek: String) throws -> URL {
            guard !idx.isEmpty else { throw KagitHata.genel("Bu belgede ayrılacak sayfa yok.") }
            return try IsYardimcisi.yaz(IsYardimcisi.belge(b, indeksler: idx), IsYardimcisi.cikti(giris, ek))
        }
        switch kip {
        case .tersCevir: return [try yap(Array((0..<n).reversed()), "ters sıra")]
        case .yalnizTekler: return [try yap(tekler, "tek sayfalar")]
        case .yalnizCiftler: return [try yap(ciftler, "çift sayfalar")]
        case .tekVeCiftAyir: return [try yap(tekler, "tek sayfalar"), try yap(ciftler, "çift sayfalar")]
        }
    }

    /// Çift taraflı taramayı birleştirir: ön yüzler (1, 3, 5…) ile arka yüzler (2, 4, 6…) harmanlanır.
    /// `arkaTers`: arka yüzler, desteyi çevirince ters sırada taranmıştır.
    public static func harmanla(onYuzler: URL, arkaYuzler: URL, arkaTers: Bool = true) throws -> URL {
        let o = try Belge.ac(onYuzler), a = try Belge.ac(arkaYuzler)
        guard o.pageCount > 0, a.pageCount > 0 else { throw KagitHata.bosGirdi }
        let arka = arkaTers ? Array((0..<a.pageCount).reversed()) : Array(0..<a.pageCount)
        let cikis = PDFDocument()
        for i in 0..<max(o.pageCount, arka.count) {
            if i < o.pageCount, let s = o.page(at: i) { cikis.insert(Belge.sayfaKopyasi(s), at: cikis.pageCount) }
            if i < arka.count, let s = a.page(at: arka[i]) { cikis.insert(Belge.sayfaKopyasi(s), at: cikis.pageCount) }
        }
        return try IsYardimcisi.yaz(cikis, IsYardimcisi.cikti(onYuzler, "harmanlandı"))
    }

    /// Tek dosyada: ilk yarı ön yüzler, ikinci yarı (ters sırada) arka yüzler.
    public static func harmanlaTekDosya(_ giris: URL, arkaTers: Bool = true) throws -> URL {
        let b = try Belge.ac(giris)
        let n = b.pageCount
        guard n >= 2, n % 2 == 0 else {
            throw KagitHata.genel("Tek dosyada harmanlamak için sayfa sayısı çift olmalı (ön yüzler, sonra arka yüzler).")
        }
        let yarim = n / 2
        var sira: [Int] = []
        for i in 0..<yarim {
            sira.append(i)
            sira.append(arkaTers ? n - 1 - i : yarim + i)
        }
        return try IsYardimcisi.yaz(IsYardimcisi.belge(b, indeksler: sira), IsYardimcisi.cikti(giris, "harmanlandı"))
    }

    // MARK: Boş sayfa

    public enum BosSayfaKonumu: Sendable, Equatable {
        case basa
        case sona
        case herSayfadanSonra
        /// Aralıktaki her sayfanın ardına.
        case aralikSonrasi(String)
    }

    public static func bosSayfaEkle(_ giris: URL, konum: BosSayfaKonumu, sayi: Int = 1, parola: String? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let n = b.pageCount
        guard n > 0, sayi >= 1, sayi <= 20 else { throw KagitHata.bosGirdi }
        // -1: en başa
        var sonrasi: [Int]
        switch konum {
        case .basa: sonrasi = [-1]
        case .sona: sonrasi = [n - 1]
        case .herSayfadanSonra: sonrasi = Array(0..<n)
        case .aralikSonrasi(let a): sonrasi = try SayfaAraligi.coz(a, sayfaSayisi: n)
        }
        let kume = Set(sonrasi)
        let cikis = PDFDocument()
        func bos(_ ornek: PDFPage) {
            guard let p = IsYardimcisi.bosSayfa(IsYardimcisi.gorunenBoyut(ornek, kutu: .mediaBox)) else { return }
            for _ in 0..<sayi { cikis.insert(Belge.sayfaKopyasi(p), at: cikis.pageCount) }
        }
        if kume.contains(-1), let ilk = b.page(at: 0) { bos(ilk) }
        for i in 0..<n {
            guard let s = b.page(at: i) else { continue }
            cikis.insert(Belge.sayfaKopyasi(s), at: cikis.pageCount)
            if kume.contains(i) { bos(s) }
        }
        return try IsYardimcisi.yaz(cikis, IsYardimcisi.cikti(giris, "boş sayfalı"))
    }

    // MARK: Yeniden boyutlandır

    public static func boyutlandir(_ giris: URL, hedef: PDFCizim.Boyut, aralik: String = "", parola: String? = nil,
                                   ilerleme: Ilerleme? = nil) throws -> URL {
        let b = try Belge.ac(giris, parola: parola)
        let secili = Set(try SayfaAraligi.coz(aralik, sayfaSayisi: b.pageCount))
        let y = PDFCizim.Yazici(baslik: giris.deletingPathExtension().lastPathComponent)
        for i in 0..<b.pageCount {
            try iptalDenetle()
            try autoreleasepool {
                guard let s = b.page(at: i) else { return }
                if secili.contains(i) {
                    let g = IsYardimcisi.gorunenBoyut(s)
                    let kutu = CGRect(origin: .zero, size: hedef.yonlu(yatay: g.width > g.height))
                    y.sayfa(kutu) { ctx in IsYardimcisi.sigdirCiz(s, ctx, hedef: kutu) }
                } else {
                    y.sayfaKopyala(s)
                }
            }
            ilerleme?(Double(i + 1) / Double(b.pageCount))
        }
        return try yazVeri(y.bitir(), IsYardimcisi.cikti(giris, "\(hedef.ad)"), sayfa: b.pageCount)
    }

    static func yazVeri(_ veri: Data, _ hedef: URL, sayfa: Int?) throws -> URL {
        try Belge.yaz(veri, hedef, beklenenSayfa: sayfa)
        return hedef
    }
}
