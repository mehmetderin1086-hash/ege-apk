import Foundation

/// Web sayfası okumanın tek kapısı: getirme (yeniden deneme, karakter kümesi), PDF metni, HTML ana içerik + yapısal veri;
/// metin zayıfsa (JavaScript ile dolan sayfa) ya da site bot koruması gösteriyorsa tarayıcıda (WKWebView) yeniden okuma.
/// Aynı adres 10 dakika bellekte tutulur (derin araştırmada ve art arda sorularda yeniden indirilmez).
enum SayfaOkuyucu {
    enum Hata: LocalizedError {
        case http(Int), engel(Int), bos, pdfMetinsiz
        var errorDescription: String? {
            switch self {
            case .http(let k): "Sayfa açılamadı (HTTP \(k))."
            case .engel(let k): "Site otomatik erişimi engelledi (HTTP \(k)); tarayıcıda da okunamadı."
            case .bos: "Sayfadan okunabilir metin çıkmadı."
            case .pdfMetinsiz: "PDF'in metin katmanı yok (taranmış belge olabilir); dosyayı indirip sohbete eklersen OCR ile okunur."
            }
        }
    }

    static func oku(_ url: URL, tarayiciYedegi: Bool = true) async throws -> WebOkuma.Sayfa {
        if let o = await SayfaOnbellegi.ortak.al(url) { return o }
        let y = try await SayfaGetirici.getirTam(url, enFazlaBayt: 25_000_000)
        var sayfa: WebOkuma.Sayfa
        if WebOkuma.pdfMi(y.veri, icerikTuru: y.tur) {
            guard (200..<300).contains(y.kod) else { throw Hata.http(y.kod) }
            guard let p = await Task.detached(priority: .userInitiated, operation: { WebOkuma.pdfMetni(y.veri) }).value else { throw Hata.pdfMetinsiz }
            sayfa = WebOkuma.Sayfa(adres: y.adres.absoluteString, baslik: p.baslik.isEmpty ? y.adres.lastPathComponent : p.baslik,
                                   site: y.adres.host ?? "", metin: p.metin, pdf: true)
        } else {
            // PDF için 25 MB indirilir; HTML 5 MB'ta kesilir (her regex geçişi metnin kopyasını üretir, bellek tepesi büyümesin).
            let veri = y.veri.count > 5_000_000 ? y.veri.prefix(5_000_000) : y.veri
            let (ayrik, engel) = await Task.detached(priority: .userInitiated) { () -> (WebOkuma.Sayfa, Bool) in
                let h = WebOkuma.coz(veri, icerikTuru: y.tur)
                return (WebOkuma.ayristir(h, adres: y.adres), WebOkuma.engelMi(kod: y.kod, html: h))
            }.value
            if !engel, !(200..<300).contains(y.kod) { throw Hata.http(y.kod) }
            sayfa = ayrik
            let zayif = sayfa.metin.count < 300 && sayfa.gomulu.count < 300
            if (engel || zayif), tarayiciYedegi, !TarayiciOturumu.ortak.gorunur,
               let (h, son) = try? await sureSinirli(25, { try await SayfaGetirici.html(url, tarayici: true) }) {
                let t = await Task.detached(priority: .userInitiated) { WebOkuma.ayristir(h, adres: son) }.value
                if t.metin.count > sayfa.metin.count, !WebOkuma.engelMi(kod: 200, html: h) { sayfa = t; sayfa.tarayicidan = true }
            }
            if engel, !sayfa.tarayicidan { throw Hata.engel(y.kod) }
        }
        guard !sayfa.metin.isEmpty || !sayfa.gomulu.isEmpty || !sayfa.yapisal.isEmpty else { throw Hata.bos }
        // Tarayıcısız okunmuş zayıf sonuç önbelleğe yazılmaz: sonraki tarayıcılı okuma (webSayfaOku) onu almasın.
        if tarayiciYedegi || sayfa.pdf || sayfa.metin.count >= 300 { await SayfaOnbellegi.ortak.koy(url, sayfa) }
        return sayfa
    }
}

/// Okunan sayfaların kısa süreli bellek önbelleği (en çok 40 sayfa, 10 dk).
actor SayfaOnbellegi {
    static let ortak = SayfaOnbellegi()
    private var kayitlar: [String: (zaman: Date, sayfa: WebOkuma.Sayfa)] = [:]
    let omur: TimeInterval = 600

    func al(_ url: URL) -> WebOkuma.Sayfa? {
        guard let k = kayitlar[url.absoluteString], Date().timeIntervalSince(k.zaman) < omur else { return nil }
        return k.sayfa
    }

    func koy(_ url: URL, _ s: WebOkuma.Sayfa) {
        kayitlar[url.absoluteString] = (Date(), s)
        if kayitlar.count > 40, let eski = kayitlar.min(by: { $0.value.zaman < $1.value.zaman })?.key { kayitlar[eski] = nil }
    }

    func temizle() { kayitlar = [:] }
}
