import Foundation
import Testing
@testable import Asistan

/// K4 ikinci tur: dış/iç soru sırasının kararı (sessizlik, müdahale, ömür), eğik çizgi komutlarının dış kaynakta
/// etkisizleştirilmesi, MCP yetkisinin göçte korunması, paylaşım kutusunun hata yolunda dosyaları geri koyması.
@MainActor
@Suite("K4-app-paylasim-mcp düzeltmeleri")
struct Duzeltme2K4apppaylasimmcpTestleri {

    // MARK: DisSoruKuyrugu.karar

    @Test func kurulustaBostaysaHemenGonderir() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: Duration.zero - DisSoruKuyrugu.sessizlik, nesil: 5)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .zero, bosta: true, nesil: 5, disKaynak: true) == .gonder)
    }

    @Test func kesintisizSessizlikBeklenir() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: 1)
        // Meşgul: bekle.
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(0), bosta: false, nesil: 1, disKaynak: false) == .bekle)
        // İlk boşta görülüş: sayaç başlar, hemen gönderilmez (kullanıcının hazırladığı mesaj önce gitsin).
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(1), bosta: true, nesil: 1, disKaynak: false) == .bekle)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .milliseconds(1_500), bosta: true, nesil: 1, disKaynak: false) == .bekle)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .milliseconds(2_500), bosta: true, nesil: 1, disKaynak: false) == .gonder)
    }

    @Test func aradaMesgulGorulurseSayacSifirlanir() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: 1)
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(0), bosta: true, nesil: 1, disKaynak: true)
        // Kullanıcının mesajı başladı: nesil arttı, Asistan meşgul.
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(1), bosta: false, nesil: 2, disKaynak: true) == .bekle)
        #expect(g.bostaBaslangic == nil)
        // Olağan bitiş nesli artırmaz: dış istek yine sessizlikten sonra gider, bırakılmaz.
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(5), bosta: true, nesil: 2, disKaynak: true) == .bekle)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(7), bosta: true, nesil: 2, disKaynak: true) == .gonder)
    }

    @Test func durdurSonrasiDisIstekBirakilir() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: 3)
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(0), bosta: false, nesil: 3, disKaynak: true)
        // iptal / yeniSohbet nesli artırıp Asistan'ı boşa çeker.
        #expect(DisSoruKuyrugu.karar(&g, simdi: .milliseconds(500), bosta: true, nesil: 4, disKaynak: true) == .disIstekleriBirak)
    }

    @Test func durdurSonrasiIcIstekDahaUzunBekler() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: 3)
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(0), bosta: false, nesil: 3, disKaynak: false)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(1), bosta: true, nesil: 4, disKaynak: false) == .bekle)
        #expect(g.mudahaleSonrasi)
        // Kısa sessizlik yetmez: söz kesen sesli komutun dökümü önce gelsin.
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(3), bosta: true, nesil: 4, disKaynak: false) == .bekle)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(1) + DisSoruKuyrugu.mudahaleSessizligi, bosta: true, nesil: 4, disKaynak: false) == .gonder)
        #expect(!g.mudahaleSonrasi)
    }

    @Test func mudahaleSonrasiYeniTurBaslarsaOlaganSessizligeDoner() {
        var g = DisSoruKuyrugu.Gozlem(bostaBaslangic: nil, nesil: 3)
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(0), bosta: true, nesil: 4, disKaynak: false)
        #expect(g.mudahaleSonrasi)
        // Sesli komut geldi (yeni tur): müdahale bekleyişi biter.
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(1), bosta: false, nesil: 5, disKaynak: false)
        #expect(!g.mudahaleSonrasi)
        _ = DisSoruKuyrugu.karar(&g, simdi: .seconds(10), bosta: true, nesil: 5, disKaynak: false)
        #expect(DisSoruKuyrugu.karar(&g, simdi: .seconds(12), bosta: true, nesil: 5, disKaynak: false) == .gonder)
    }

    // MARK: Ömür ve bildirim

    @Test func suresiDolanlarYalnizOmruAsanlar() {
        let yaslar: [String: Duration] = ["a": .seconds(30), "b": .seconds(130), "c": .seconds(700)]
        #expect(DisSoruKuyrugu.suresiDolanlar(["a", "b", "c"], yaslar: yaslar, omur: DisSoruKuyrugu.disEnUzunBekleme) == ["b", "c"])
        #expect(DisSoruKuyrugu.suresiDolanlar(["a", "b", "c"], yaslar: yaslar, omur: DisSoruKuyrugu.enUzunBekleme) == ["c"])
        // Yaşı bilinmeyen istek dolmuş sayılmaz.
        #expect(DisSoruKuyrugu.suresiDolanlar(["x"], yaslar: [:], omur: .seconds(1)).isEmpty)
        #expect(DisSoruKuyrugu.disEnUzunBekleme < DisSoruKuyrugu.enUzunBekleme)
    }

    @Test func dusenIcIstekSessizKalmaz() {
        #expect(DisSoruKuyrugu.dusmeNotu([]) == nil)
        let tek = DisSoruKuyrugu.dusmeNotu(["yarın 8'de uyandır"])
        #expect(tek?.contains("yarın 8'de uyandır") == true)
        let cok = DisSoruKuyrugu.dusmeNotu(["a", "b"])
        #expect(cok?.contains("2 isteğin") == true)
    }

    // MARK: Eğik çizgi komutları

    @Test func disKaynakKomutuYerelKomutOlmaz() {
        for k in ["/yeni", "/model opus", " /nabiz ", "/sikistir"] {
            #expect(SlashKomutlari.coz(k) != nil)
            let e = DisSoruKuyrugu.komutuEtkisizlestir(k)
            #expect(SlashKomutlari.coz(e) == nil)
            #expect(e.contains(k.trimmingCharacters(in: .whitespaces)))
        }
        #expect(DisSoruKuyrugu.komutuEtkisizlestir("saat kaç") == "saat kaç")
        #expect(DisSoruKuyrugu.komutuEtkisizlestir("/Users/mehmet/a.pdf aç") == "/Users/mehmet/a.pdf aç")
        // Paylaşım metni: yönerge "/yeni" olsa bile komut yoluna girmez (kutudan silinmeyip yinelenmesin).
        let p = PaylasimKutusu.istemMetni(.init(istem: "/yeni", baglanti: "https://a.com"))
        #expect(SlashKomutlari.coz(p) != nil)
        #expect(SlashKomutlari.coz(DisSoruKuyrugu.komutuEtkisizlestir(p)) == nil)
    }

    // MARK: MCP kayıt biçimi

    @Test func tasinamayanYetkiPlisteKorunur() throws {
        let a = McpSunucu(ad: "notlar", url: "https://a.com/mcp", yetki: "Bearer tasindi")
        let b = McpSunucu(ad: "eski", url: "https://b.com/mcp", yetki: "Bearer kaldi")
        let temiz = String(decoding: try #require(McpKaydi.kayitVerisi([a, b], duzMetinKorunan: [])), as: UTF8.self)
        #expect(!temiz.contains("Bearer"))
        let veri = try #require(McpKaydi.kayitVerisi([a, b], duzMetinKorunan: [b.id]))
        let ham = String(decoding: veri, as: UTF8.self)
        #expect(ham.contains("Bearer kaldi"))
        #expect(!ham.contains("Bearer tasindi"))
        // Yeni biçimle de okunur (yetki alanı yok sayılır).
        let l = try JSONDecoder().decode([McpSunucu].self, from: veri)
        #expect(l.map(\.ad) == ["notlar", "eski"])
        #expect(l.allSatisfy { $0.yetki.isEmpty })
    }

    // MARK: Paylaşım kutusu

    @Test func hataYolundaTasinanlarGeriKonur() throws {
        let fm = FileManager.default
        let kok = fm.temporaryDirectory.appendingPathComponent("k4-paylasim-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: kok) }
        let gecici = kok.appendingPathComponent("gecici", isDirectory: true)
        let kutu = kok.appendingPathComponent("kutu", isDirectory: true)
        try fm.createDirectory(at: gecici, withIntermediateDirectories: true)
        try fm.createDirectory(at: kutu, withIntermediateDirectories: true)
        let k1 = gecici.appendingPathComponent("a.pdf"), k2 = gecici.appendingPathComponent("b.jpg")
        try Data("bir".utf8).write(to: k1); try Data("iki".utf8).write(to: k2)
        let h1 = kutu.appendingPathComponent("0-a.pdf"), h2 = kutu.appendingPathComponent("1-b.jpg")
        try fm.moveItem(at: k1, to: h1); try fm.moveItem(at: k2, to: h2)
        PaylasimKutusu.geriTasi([(k1, h1), (k2, h2)])
        #expect(fm.fileExists(atPath: k1.path) && fm.fileExists(atPath: k2.path))
        #expect(!fm.fileExists(atPath: h1.path) && !fm.fileExists(atPath: h2.path))
        #expect(try Data(contentsOf: k2) == Data("iki".utf8))
    }
}
