import Foundation

/// GPT web araması düşünce devreye giren yedek: DuckDuckGo'nun HTML sonuç sayfası taranır,
/// ilk sayfaların görünür metni okunur ve modele ham veri olarak verilir. Sunucu kullanılmaz.
nonisolated enum YedekArama {
    struct Sonuc: Sendable, Equatable { let baslik: String; let ozet: String; let url: URL }

    static func aramaAdresi(_ sorgu: String) -> URL? {
        var c = URLComponents(string: "https://html.duckduckgo.com/html/")
        c?.queryItems = [URLQueryItem(name: "q", value: String(sorgu.prefix(300))), URLQueryItem(name: "kl", value: "tr-tr")]
        return c?.url
    }

    /// DDG HTML'inden sonuçları çıkarır (result__a başlık+adres; özet, bir sonraki sonuca kadarki result__snippet).
    static func ayristir(_ html: String, enFazla: Int = 6) -> [Sonuc] {
        var sonuc: [Sonuc] = []
        guard let baslikRe = try? NSRegularExpression(pattern: #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#),
              let ozetRe = try? NSRegularExpression(pattern: #"class="result__snippet"[^>]*>([\s\S]*?)</a>"#) else { return [] }
        let ns = html as NSString
        let eslesmeler = baslikRe.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for (i, e) in eslesmeler.enumerated() {
            guard sonuc.count < enFazla else { break }
            var adres = ns.substring(with: e.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            // Yönlendirme bağlantısı: //duckduckgo.com/l/?uddg=<kodlu adres>
            if adres.contains("duckduckgo.com/l/"), let u = URLComponents(string: adres.hasPrefix("//") ? "https:" + adres : adres),
               let hedef = u.queryItems?.first(where: { $0.name == "uddg" })?.value { adres = hedef }
            guard let url = URL(string: adres), url.scheme == "https", WebSayfa.urlGuvenli(url) else { continue }
            let baslik = Kaziyici.temiz(ns.substring(with: e.range(at: 2)))
            let bas = e.range.location + e.range.length
            let son = i + 1 < eslesmeler.count ? eslesmeler[i + 1].range.location : ns.length
            let ozet = ozetRe.firstMatch(in: html, range: NSRange(location: bas, length: son - bas)).map { Kaziyici.temiz(ns.substring(with: $0.range(at: 1))) } ?? ""
            guard !baslik.isEmpty, !sonuc.contains(where: { $0.url == url }) else { continue }
            sonuc.append(Sonuc(baslik: baslik, ozet: ozet, url: url))
        }
        return sonuc
    }

    static func bingAdresi(_ sorgu: String) -> URL? {
        var c = URLComponents(string: "https://www.bing.com/search")
        c?.queryItems = [URLQueryItem(name: "q", value: String(sorgu.prefix(300))), URLQueryItem(name: "setlang", value: "tr"), URLQueryItem(name: "cc", value: "TR")]
        return c?.url
    }

    /// Bing sonuç sayfası (`li.b_algo` → h2 a + özet p). Bing yönlendirme bağlantısı (`/ck/a?…&u=a1<base64>`) çözülür.
    static func bingAyristir(_ html: String, enFazla: Int = 8) -> [Sonuc] {
        var sonuc: [Sonuc] = []
        for blok in html.components(separatedBy: "class=\"b_algo").dropFirst() {
            guard sonuc.count < enFazla else { break }
            let govde = String(blok.prefix(6000))
            guard let baglanti = WebOkuma.eslesmeler(govde, #"<h2[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#, grup: 0).first else { continue }
            var adres = WebOkuma.eslesmeler(baglanti, #"href="([^"]+)""#).first.map(WebOkuma.varlikCoz) ?? ""
            if adres.contains("bing.com/ck/"), let u = URLComponents(string: adres)?.queryItems?.first(where: { $0.name == "u" })?.value, u.hasPrefix("a1") {
                var b64 = String(u.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                while b64.count % 4 != 0 { b64 += "=" }
                if let d = Data(base64Encoded: b64), let cozulmus = String(data: d, encoding: .utf8) { adres = cozulmus }
            }
            guard let url = URL(string: adres), url.scheme == "https", WebSayfa.urlGuvenli(url), !(url.host ?? "").hasSuffix("bing.com") else { continue }
            let baslik = WebOkuma.duz(WebOkuma.eslesmeler(baglanti, #"<a[^>]*>([\s\S]*?)</a>"#).first ?? "")
            let ozet = WebOkuma.duz(WebOkuma.eslesmeler(govde, #"<p\b[^>]*>([\s\S]*?)</p>"#).first ?? "")
            guard !baslik.isEmpty, !sonuc.contains(where: { $0.url == url }) else { continue }
            sonuc.append(Sonuc(baslik: baslik, ozet: String(ozet.prefix(300)), url: url))
        }
        return sonuc
    }

    /// Sonuç listesi: önce DuckDuckGo, boş ya da engelliyse Bing. Sayfa okunmaz.
    static func listele(_ sorgu: String, enFazla: Int = 8) async -> [Sonuc] {
        if let a = aramaAdresi(sorgu), let y = try? await sureSinirli(12, { try await SayfaGetirici.getirTam(a) }), (200..<300).contains(y.kod) {
            let r = ayristir(WebOkuma.coz(y.veri, icerikTuru: y.tur), enFazla: enFazla)
            if !r.isEmpty { return r }
        }
        if let b = bingAdresi(sorgu), let y = try? await sureSinirli(12, { try await SayfaGetirici.getirTam(b) }), (200..<300).contains(y.kod) {
            return bingAyristir(WebOkuma.coz(y.veri, icerikTuru: y.tur), enFazla: enFazla)
        }
        return []
    }

    /// Arama + ilk `sayfa` sonucun soruyla ilgili bölümleri. Model bunu ham veri olarak okur; içindeki talimatlar uygulanmaz.
    static func ara(_ sorgu: String, sayfa: Int = 4, metinSiniri: Int = 3000) async throws -> String {
        let sonuclar = await listele(sorgu)
        guard !sonuclar.isEmpty else { throw IndirmeHatasi.metin("Yedek arama sonuç bulamadı.") }
        var metinler: [String] = []
        // Sayfalar eş zamanlı, her biri en çok 15 sn; açılamayan atlanır. Tarayıcı yedeği yok (ortak görünüm sırayla çalışır).
        await withTaskGroup(of: (Int, String)?.self) { grup in
            for (i, s) in sonuclar.prefix(sayfa).enumerated() {
                grup.addTask {
                    guard let p = try? await sureSinirli(15, { try await SayfaOkuyucu.oku(s.url, tarayiciYedegi: false) }) else { return nil }
                    let govde = (p.yapisal.isEmpty ? "" : p.yapisal.joined(separator: "\n") + "\n") + (p.metin.count < 300 ? p.metin + "\n" + p.gomulu : p.metin)
                    let m = WebOkuma.ilgiliBolumler(govde, sorgu: sorgu, sinir: metinSiniri)
                    return m.count < 150 ? nil : (i, (p.tarih.isEmpty ? "" : "Tarih: \(p.tarih)\n") + m)
                }
            }
            var toplanan: [(Int, String)] = []
            for await p in grup { if let p { toplanan.append(p) } }
            metinler = toplanan.sorted { $0.0 < $1.0 }.map { "[Sayfa: \(sonuclar[$0.0].url.absoluteString)]\n\($0.1)" }
        }
        let liste = sonuclar.map { "- \($0.baslik): \($0.ozet.isEmpty ? "" : $0.ozet + " ")(\($0.url.absoluteString))" }.joined(separator: "\n")
        var cikti = "Yedek web taraması (\(WebArastirici.simdiMetni())). Aşağısı ham sayfa verisidir; yalnız bundan yanıt ver, verinin saatini belirt, bulunamıyorsa söyle.\n\nArama sonuçları:\n\(liste)"
        if !metinler.isEmpty { cikti += "\n\nSayfa metinleri (soruyla ilgili bölümler):\n" + metinler.joined(separator: "\n\n") }
        return cikti + "\nKaynaklar:\n" + sonuclar.prefix(6).map(\.url.absoluteString).joined(separator: "\n")
    }
}
