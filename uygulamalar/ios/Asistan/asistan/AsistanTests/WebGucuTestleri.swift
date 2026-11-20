import Foundation
import PDFKit
import Testing
@testable import Asistan

/// 29 Ekim: güçlü web okuma (kodlama, ana içerik, yapısal veri, gömülü veri, ilgili bölümler, PDF, engel),
/// derin araştırma kaynak seçimi, yedek arama motoru ve site taraması (robots.txt).
@MainActor
@Suite struct WebGucuTestleri {
    // MARK: Kodlama ve varlıklar

    @Test func turkce_kod_sayfasi_dogru_cozulur() throws {
        let k1254 = try #require(WebOkuma.kodlama("windows-1254"))
        let html = "<html><head><meta charset=\"windows-1254\"></head><body><p>Öğretmen şube ığdır çiçek</p></body></html>"
        let veri = try #require(html.data(using: k1254))
        #expect(String(data: veri, encoding: .utf8) == nil, "örnek gerçekten UTF-8 dışı olmalı")
        #expect(WebOkuma.coz(veri).contains("Öğretmen şube ığdır çiçek"))
        // Başlıktaki charset (ISO-8859-9) meta'dan önce gelir.
        let k5 = try #require(WebOkuma.kodlama("iso-8859-9"))
        let v2 = try #require("<p>Şeker ağacı</p>".data(using: k5))
        #expect(WebOkuma.coz(v2, icerikTuru: "text/html; charset=ISO-8859-9").contains("Şeker ağacı"))
        // Bildirimsiz ve UTF-8 olmayan bayt: Türkçe varsayılan (1254).
        #expect(WebOkuma.coz(try #require("ılık".data(using: k1254))) == "ılık")
        // Yarım kesilmiş UTF-8 son karakteri bütün sayfayı bozmaz.
        var kesik = Data("Merhaba dünya ş".utf8); kesik.removeLast()
        #expect(WebOkuma.coz(kesik).hasPrefix("Merhaba dünya"))
    }

    @Test func satir_ici_etiketler_bosluk_birakmaz() {
        #expect(WebOkuma.duz("<p><b>Mitoz</b> ya da <a href='x'>mitoz bölünme</a>, ana&nbsp;hücrenin\u{2009}bölünmesi</p>") == "Mitoz ya da mitoz bölünme, ana hücrenin bölünmesi")
        #expect(WebOkuma.duz("<td>a</td><td>b</td>") == "a b")
    }

    @Test func html_varliklari_cozulur() {
        #expect(WebOkuma.varlikCoz("&#305;&#x131; &scedil;&ouml; &amp;&lt;b&gt; &bilinmez; &#8217;") == "ıı şö &<b> &bilinmez; ’")
        #expect(WebOkuma.varlikCoz("varlıksız metin") == "varlıksız metin")
    }

    // MARK: Ana içerik

    static let haberSayfasi = """
    <html lang="tr"><head><title>Site | Haber</title>
    <meta property="og:title" content="Mitoz ile Mayoz Farkı">
    <meta name="description" content="Hücre bölünmesi türleri">
    <meta property="article:published_time" content="2026-10-20T09:00:00+03:00">
    <meta name="author" content="Ayşe Yılmaz">
    <script>var x = "<p>betik içi</p>";</script><style>p{color:red}</style></head>
    <body>
    <header><nav><ul><li><a href="/a">Anasayfa</a></li><li><a href="/b">Gündem</a></li><li><a href="/c">Spor</a></li></ul></nav></header>
    <div class="cookie-banner"><p>Sitemizde çerez kullanılmaktadır. Kabul et</p></div>
    <article><h1>Mitoz ile Mayoz Farkı</h1>
    <p>Mitoz bölünmede kromozom sayısı değişmez ve iki özdeş hücre oluşur. Bu süreç büyüme ve onarımda görev alır.</p>
    <h2>Temel farklar</h2>
    <ul><li>Mitozda iki hücre oluşur</li><li>Mayozda dört hücre oluşur</li></ul>
    <table><tr><th>Özellik</th><th>Mitoz</th><th>Mayoz</th></tr><tr><td>Hücre sayısı</td><td>2</td><td>4</td></tr></table>
    <p>Mayoz bölünme eşey hücrelerinde görülür ve kromozom sayısını yarıya indirir; bu sayede türün kromozom sayısı nesiller boyu sabit kalır.</p>
    </article>
    <aside><a href="/x">Popüler haberler</a></aside>
    <footer><p>© 2026 Tüm hakları saklıdır.</p></footer>
    </body></html>
    """

    @Test func ana_icerik_gurultusuz_markdown() {
        let p = WebOkuma.ayristir(Self.haberSayfasi, adres: URL(string: "https://ornek.com.tr/haber"))
        #expect(p.baslik == "Mitoz ile Mayoz Farkı")
        #expect(p.yazar == "Ayşe Yılmaz")
        #expect(p.tarih.hasPrefix("2026-10-20"))
        #expect(p.dil == "tr")
        let m = p.metin
        #expect(m.contains("# Mitoz ile Mayoz Farkı"))
        #expect(m.contains("## Temel farklar"))
        #expect(m.contains("- Mayozda dört hücre oluşur"))
        #expect(m.contains("| Özellik | Mitoz | Mayoz |"))
        #expect(m.contains("| Hücre sayısı | 2 | 4 |"))
        #expect(m.contains("yarıya indirir"))
        for gurultu in ["Anasayfa", "Gündem", "çerez", "Popüler", "hakları saklıdır", "betik içi", "color:red"] {
            #expect(!m.contains(gurultu), "gürültü kaldı: \(gurultu)")
        }
    }

    @Test func duzen_tablosu_akista_kalir_ve_menu_atilir() {
        // Eski site düzeni: sayfa iskeleti tablo, solda bağlantı menüsü, sağda uzun içerik.
        let uzun = String(repeating: "Okulumuzda 2026-2027 eğitim yılı kayıtları başlamıştır ve veliler belgeleriyle başvurabilir. ", count: 5)
        let html = "<body><table><tr><td><a href='/1'>Ana</a> <a href='/2'>Duyuru</a> <a href='/3'>İletişim</a></td><td><p>\(uzun)</p></td></tr></table></body>"
        let m = WebOkuma.anaIcerik(html)
        #expect(m.contains("kayıtları başlamıştır"))
        #expect(!m.contains("|"), "düzen tablosu Markdown tabloya çevrilmemeli")
        #expect(!m.contains("İletişim"))
    }

    // MARK: İnceleme gerilemeleri

    @Test func asp_net_form_icindeki_icerik_korunur() {
        let uzun = String(repeating: "2026 yılı LGS tercih kılavuzu yayımlanmıştır ve öğrenciler e-Okul üzerinden tercih yapabilir. ", count: 4)
        let html = "<html><body><form id='form1' method='post' action='./Default.aspx'><input type='hidden' name='__VIEWSTATE' value='x'><div><h1>Duyuru</h1><p>\(uzun)</p></div></form></body></html>"
        let m = WebOkuma.anaIcerik(html)
        #expect(m.contains("# Duyuru"))
        #expect(m.contains("tercih kılavuzu yayımlanmıştır"))
    }

    @Test func cloudflare_betikli_normal_sayfa_engel_sayilmaz() {
        let html = Self.haberSayfasi.replacingOccurrences(of: "</body>", with: "<script src='/cdn-cgi/challenge-platform/scripts/jsd/main.js'></script><div class='g-recaptcha'></div></body>")
        #expect(!WebOkuma.engelMi(kod: 200, html: html))
        #expect(WebOkuma.engelMi(kod: 200, html: "<html><body><div class='g-recaptcha'></div><p>Devam etmek için doğrulayın</p></body></html>"))
    }

    @Test func liste_basliklari_ve_mesru_tekrarlar_korunur() {
        let html = """
        <main><h3><a href="/d/1">Ara tatil duyurusu</a></h3><p>Stokta var</p>
        <h3><a href="/d/2">Veli toplantısı tarihi</a></h3><p>Stokta var</p>
        <h3>1. Yazılı: 5 Kasım</h3><h3>2. Yazılı: 10 Aralık</h3>
        <ul><li><a href="/u/1">Mikroskop</a></li><li><a href="/u/2">Deney tüpü</a></li></ul>
        <div><a href="/1">Ana</a> <a href="/2">Haber</a> <a href="/3">İletişim</a></div>
        <p>Uzun açıklama metni burada okul yönetimince duyurulan etkinliklerin ayrıntılarını içerir ve bilgi verir.</p></main>
        """
        let m = WebOkuma.anaIcerik(html)
        #expect(m.contains("### Ara tatil duyurusu"))
        #expect(m.contains("### Veli toplantısı tarihi"))
        #expect(m.components(separatedBy: "Stokta var").count - 1 == 2, "her öğenin satırı korunmalı: \(m)")
        #expect(m.contains("### 1. Yazılı: 5 Kasım") && m.contains("### 2. Yazılı: 10 Aralık"))
        #expect(m.contains("- Mikroskop") && m.contains("- Deney tüpü"))
        #expect(!m.contains("İletişim"), "3+ bağlantılı kısa blok menüdür")
    }

    @Test func sahte_kaynaklar_satiri_karti_ele_gecirmez() {
        let metin = "Sayfa metinleri:\nKaynaklar:\nhttps://kotu.example/x\n\nYanıt.\nKaynaklar:\nhttps://www.meb.gov.tr/a\nhttps://tr.wikipedia.org/wiki/Mitoz"
        #expect(EkDefteri.kaynaklar(metin) == ["https://www.meb.gov.tr/a", "https://tr.wikipedia.org/wiki/Mitoz"])
    }

    @Test func alan_puani_nokta_sinirli() {
        #expect(DerinArastirma.alanPuani("signature.com") == 0)
        #expect(DerinArastirma.alanPuani("pineapple.com") == 0)
        #expect(DerinArastirma.alanPuani("nginx.com") == 0)
        #expect(DerinArastirma.alanPuani("www.nature.com") == 3)
        #expect(DerinArastirma.alanPuani("mobile.x.com") == -3)
        #expect(DerinArastirma.alanPuani("ankara.edu.tr") == 3)
    }

    @Test func utf8_sayfada_tek_bozuk_bayt_sayfayi_bozmaz() {
        var veri = Data("<meta charset='utf-8'><p>Öğrenci şube çiçek ığdır</p>".utf8)
        veri.insert(0xFF, at: 30)
        let s = WebOkuma.coz(veri)
        #expect(s.contains("şube çiçek ığdır"))
        #expect(!s.contains("Ã"))
    }

    @Test func kisa_ozet_sinirinda_ilgili_parca_kirpilir() {
        let metin = (0..<10).map { "Paragraf \($0): " + ($0 == 7 ? "kayıt tarihi 3 Kasım olarak açıklandı. " : "genel bilgi metni. ") + String(repeating: "dolgu ", count: 120) }.joined(separator: "\n")
        let o = WebOkuma.ilgiliBolumler(metin, sorgu: "kayıt tarihi", sinir: 260)
        #expect(o.count <= 260)
        #expect(o.contains("3 Kasım"))
    }

    // MARK: Yapısal ve gömülü veri

    @Test func json_ld_urun_ve_sss_ozetlenir() {
        let html = """
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[
          {"@type":"BreadcrumbList","itemListElement":[]},
          {"@type":"Product","name":"Mikroskop X200","brand":{"@type":"Brand","name":"Optik"},"sku":"X200",
           "offers":{"@type":"Offer","price":"4599.90","priceCurrency":"TRY","availability":"https://schema.org/InStock"},
           "aggregateRating":{"ratingValue":4.6,"reviewCount":128}}]}</script>
        <script type="application/ld+json">{"@type":"FAQPage","mainEntity":[{"@type":"Question","name":"Garanti süresi?","acceptedAnswer":{"text":"<p>2 yıl</p>"}}]}</script>
        """
        let satirlar = WebOkuma.jsonLD(html).compactMap(WebOkuma.ozetle)
        #expect(satirlar.count == 2, "\(satirlar)")
        let urun = satirlar.first { $0.hasPrefix("Product") } ?? ""
        #expect(urun.contains("Mikroskop X200"))
        #expect(urun.contains("fiyat 4599.90 TRY"))
        #expect(urun.contains("stok: InStock"))
        #expect(urun.contains("puan 4.6 (128 değerlendirme)"))
        #expect(urun.contains("marka: Optik"))
        #expect(satirlar.contains { $0.contains("S: Garanti süresi? Y: 2 yıl") })
        let tablo = VeriKaziAraci.yapisalSatirlar(html, adres: URL(string: "https://dukkan.com/x")!)
        #expect(tablo.first?[1] == "Mikroskop X200")
        #expect(tablo.first?[2] == "4599.90")
        #expect(tablo.first?[4] == "InStock")
    }

    @Test func spa_gomulu_veriden_metin_cikar() {
        let html = """
        <html><body><div id="__next"></div>
        <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"yazi":{"baslik":"Kısa","govde":"Fotosentez bitkilerin ışık enerjisini kimyasal enerjiye dönüştürdüğü süreçtir ve kloroplastta gerçekleşir.","link":"https://x.com/uzun/bir/adres/ki/metin/sayilmamali/cunku/bosluk/yok"}}}}</script>
        </body></html>
        """
        let p = WebOkuma.ayristir(html, adres: nil)
        #expect(p.metin.isEmpty)
        #expect(p.gomulu.contains("kloroplastta gerçekleşir"))
        #expect(!p.gomulu.contains("https://"))
        #expect(WebOkuma.bicimle(p, odak: nil, sinir: 5000).contains("[Sayfaya gömülü uygulama verisi]"))
    }

    // MARK: İlgili bölümler, engel, PDF

    @Test func uzun_sayfada_soruyla_ilgili_bolum_secilir() {
        var satirlar = ["# Okul rehberi"]
        for i in 0..<40 { satirlar.append("Genel bilgi paragrafı \(i): okulun tarihçesi, kantin, servis ve kulüpler hakkında açıklamalar burada yer alır.") }
        satirlar.append("## Kayıt takvimi")
        satirlar.append("Ön kayıt başvuruları 3 Kasım 2026 tarihinde başlar ve 14 Kasım 2026'da sona erer; başvuru e-Okul üzerinden yapılır.")
        for i in 0..<40 { satirlar.append("Ek bilgi \(i): spor salonu, kütüphane ve laboratuvar kullanımı kuralları anlatılır.") }
        let metin = satirlar.joined(separator: "\n")
        let secim = WebOkuma.ilgiliBolumler(metin, sorgu: "ön kayıt başvuru tarihleri ne zaman", sinir: 1200)
        #expect(secim.count <= 1400)
        #expect(secim.contains("3 Kasım 2026"))
        #expect(secim.contains("## Kayıt takvimi"))
        #expect(secim.contains("[…]"))
        // Kısa metin olduğu gibi döner.
        #expect(WebOkuma.ilgiliBolumler("kısa metin", sorgu: "x", sinir: 100) == "kısa metin")
    }

    @Test func bot_engeli_taninir() {
        #expect(WebOkuma.engelMi(kod: 403, html: ""))
        #expect(WebOkuma.engelMi(kod: 200, html: "<title>Just a moment...</title><div id='challenge-platform'></div>"))
        #expect(!WebOkuma.engelMi(kod: 200, html: Self.haberSayfasi))
        #expect(!WebOkuma.engelMi(kod: 404, html: "<p>Bulunamadı</p>"))
    }

    @Test func pdf_baglantisi_metin_olarak_okunur() throws {
        let veri = try #require(PdfOcrTestleri.metinliPdf("Resmi yazi 2026 kayit duyurusu").dataRepresentation())
        #expect(WebOkuma.pdfMi(veri, icerikTuru: "application/octet-stream"))
        let p = try #require(WebOkuma.pdfMetni(veri))
        #expect(p.metin.contains("[Sayfa 1]"))
        #expect(p.metin.contains("kayit duyurusu"))
        #expect(!WebOkuma.pdfMi(Data("<html>".utf8), icerikTuru: "text/html"))
    }

    // MARK: Arama motoru ve derin araştırma

    @Test func bing_sonuclari_ve_yonlendirme_cozulur() {
        let hedef = "https://www.meb.gov.tr/duyuru/2026"
        let kodlu = "a1" + Data(hedef.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let html = """
        <ol id="b_results"><li class="b_algo"><h2><a href="https://www.bing.com/ck/a?!&amp;&amp;p=abc&amp;u=\(kodlu)&amp;ntb=1">MEB &amp; Duyuru</a></h2><p>Kayıt takvimi açıklandı.</p></li>
        <li class="b_algo"><h2><a href="https://tr.wikipedia.org/wiki/Mitoz">Mitoz - Vikipedi</a></h2><div class="b_caption"><p>Hücre bölünmesi</p></div></li>
        <li class="b_algo"><h2><a href="http://guvensiz.com">HTTP</a></h2></li></ol>
        """
        let r = YedekArama.bingAyristir(html)
        #expect(r.map(\.url.absoluteString) == [hedef, "https://tr.wikipedia.org/wiki/Mitoz"])
        #expect(r.first?.baslik == "MEB & Duyuru")
        #expect(r.first?.ozet == "Kayıt takvimi açıklandı.")
    }

    @Test func derin_arastirma_kaynak_secimi() throws {
        func u(_ s: String) throws -> URL { try #require(URL(string: s)) }
        #expect(DerinArastirma.normalAdres(try u("https://www.Ornek.com/a/?utm_source=x&id=3#bolum")) == "https://ornek.com/a?id=3")
        #expect(DerinArastirma.alanPuani("www.meb.gov.tr") == 3)
        #expect(DerinArastirma.alanPuani("tr.wikipedia.org") == 3)
        #expect(DerinArastirma.alanPuani("www.pinterest.com") == -3)
        #expect(DerinArastirma.alanPuani("ornekblog.net") == 0)
        let birlesik = DerinArastirma.birlestir([
            [.init(adres: try u("https://blog.net/a")), .init(adres: try u("https://www.meb.gov.tr/x?utm_source=1"), saglayiciAtfi: true)],
            [.init(adres: try u("https://meb.gov.tr/x")), .init(adres: try u("https://blog.net/b")), .init(adres: try u("https://blog.net/c"))],
        ])
        #expect(birlesik.count == 4)
        let meb = try #require(birlesik.first { $0.adres.host?.contains("meb") == true })
        #expect(meb.gorulme == 2 && meb.saglayiciAtfi)
        let secilen = DerinArastirma.sec(birlesik, adet: 8)
        #expect(secilen.first?.adres.host?.contains("meb") == true, "çok görülen + atıflı + resmî kaynak önde")
        #expect(secilen.filter { $0.adres.host == "blog.net" }.count == 2, "aynı alandan en çok 2 sayfa")
        #expect(DerinArastirma.sorgular("1. Mitoz evreleri nelerdir\n- mitosis phases 2026\n\nkısa\n1. Mitoz evreleri nelerdir") == ["Mitoz evreleri nelerdir", "mitosis phases 2026"])
    }

    // MARK: Site taraması

    @Test func robots_kurallari_ayristirilir() {
        let r = VeriKaziAraci.robotsAyristir("""
        User-agent: Googlebot
        Disallow: /yalniz-google

        User-agent: *
        User-agent: Bingbot
        Disallow: /admin/ # yönetim
        Disallow: /ara*
        Disallow:
        Sitemap: https://okul.meb.k12.tr/sitemap.xml
        Sitemap: http://guvensiz/sitemap.xml
        """)
        #expect(r.kurallar.map(\.desen) == ["/admin/", "/ara*"])
        #expect(r.sitemaplar.map(\.absoluteString) == ["https://okul.meb.k12.tr/sitemap.xml"])
        #expect(!r.izinli("/admin/panel"))
        #expect(!r.izinli("/arama?q=x"))
        #expect(r.izinli("/duyurular"))
        #expect(r.izinli("/yalniz-google"))
        // WordPress/Shopify varsayılanları: joker kuralı bütün siteyi kapatmaz; Allow daha uzunsa kazanır; $ sona bağlar.
        let wp = VeriKaziAraci.robotsAyristir("User-agent: *\nDisallow: /*?\nDisallow: /*.pdf$\nDisallow: /wp-admin/\nAllow: /wp-admin/admin-ajax.php")
        #expect(wp.izinli("/2026/10/duyuru/"))
        #expect(!wp.izinli("/ara?s=mitoz"))
        #expect(!wp.izinli("/belge.pdf"))
        #expect(wp.izinli("/belge.pdf.html"))
        #expect(!wp.izinli("/wp-admin/edit.php"))
        #expect(wp.izinli("/wp-admin/admin-ajax.php"))
        #expect(VeriKaziAraci.siteAdi(URL(string: "https://www.Okul.k12.tr/a")!) == VeriKaziAraci.siteAdi(URL(string: "https://okul.k12.tr/b")!))
        #expect(VeriKaziAraci.dosyaUzantisi(URL(string: "https://x.com/a/belge.PDF")!))
        #expect(!VeriKaziAraci.dosyaUzantisi(URL(string: "https://x.com/a/sayfa")!))
    }

    @Test func web_araclari_semasi_duz_ve_yeni_islemler_tanimli() {
        #expect(VeriKaziAraci().description.contains("'tara'"))
        #expect(VeriKaziAraci().description.contains("'yapisal'"))
        #expect(WebSayfaAraci().description.contains("PDF"))
        #expect(WebAraci.derinSinir >= DerinArastirma.toplamSinir)
    }
}
