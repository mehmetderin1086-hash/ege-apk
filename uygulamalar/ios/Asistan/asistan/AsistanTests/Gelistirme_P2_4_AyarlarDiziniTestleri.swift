import Foundation
import Testing
@testable import Asistan

/// P2.4: Ayarlar dizini/araması ve Kurulum durumu hesabı. Saf işlevler; ağ, izin ya da model gerekmez.
@Suite("P2.4 ayarlar dizini ve kurulum")
struct Gelistirme_P2_4_AyarlarDiziniTestleri {

    // MARK: AyarDizini.ara

    @Test func buyukHarfVeTurkceHarfDuyarsizArar() {
        #expect(AyarDizini.ara("ELİF").contains { $0.id == "ses-kimligi" })
        #expect(AyarDizini.ara("elif").contains { $0.id == "ses-kimligi" })
    }

    @Test func cedillasizCerezBulunur() {
        #expect(AyarDizini.ara("cerez").contains { $0.id == "cerez" })
        #expect(AyarDizini.ara("Çerez").contains { $0.id == "cerez" })
    }

    @Test func beceriBecerileriBulur() {
        let sonuc = AyarDizini.ara("beceri")
        #expect(sonuc.first?.id == "beceriler", "başlıkta eşleşen önce gelmeli")
    }

    @Test func bosSorguBosDoner() {
        #expect(AyarDizini.ara("").isEmpty)
        #expect(AyarDizini.ara("   ").isEmpty)
    }

    @Test func anlamsizSorguSonucsuz() {
        #expect(AyarDizini.ara("zzqqxx").isEmpty)
    }

    @Test func cokSozcukluSorguHepsiniArar() {
        #expect(AyarDizini.ara("hey asistan").contains { $0.id == "uyandirma" })
        // İki sözcük ayrı ayrı geçmeli: "kota" + "sağlık" aynı öğede yok.
        #expect(!AyarDizini.ara("kota saglik").contains { $0.id == "kullanim" })
    }

    @Test func ytDlpIndirmeMotorunuGetirir() {
        let o = AyarDizini.ara("yt-dlp").first { $0.id == "yt-dlp" }
        #expect(o?.hedef == .indirmeMotoru)
        #expect(o?.bolum == .gelismis)
    }

    @Test func kimliklerBenzersiz() {
        let idler = AyarDizini.hepsi.map(\.id)
        #expect(Set(idler).count == idler.count)
    }

    @Test func herBolumdeEnAzBirOge() {
        for b in AyarBolumu.allCases {
            #expect(AyarDizini.hepsi.contains { $0.bolum == b }, "boş bölüm: \(b.rawValue)")
        }
    }

    @Test func anaBasliklarAltiTaneVeGelismisHaric() {
        #expect(AyarBolumu.anaBasliklar.map(\.baslik) == ["Asistan", "Model", "Ses ve Live", "Görünüm", "Hafıza", "Bağlantı ve kota"])
        #expect(!AyarBolumu.anaBasliklar.contains(.gelismis))
    }

    /// TumDugmelerUITesti'nin aradığı başlıklar dizinde birebir bulunmalı (ve her biri kendi ekranına gitmeli).
    @Test func arayuzTestininAradigiBasliklarDizinde() {
        let beklenen: [String: AyarHedefi] = [
            "Görünüm stüdyosu": .gorunum, "Komutlarım ve kaydedilenler": .komutlar, "Sağlık ve hız merkezi": .saglik,
            "Beceriler": .beceriler, "MCP sunucuları": .mcp, "Çalışma alanı (SOUL · USER · AGENTS)": .calismaAlani,
            "Nabız (proaktif kontrol)": .nabiz, "Hey Asistan ve diğer uygulamalardan erişim": .uyandirma,
            "Kullanım ve kota": .kullanim, "Çökme ve performans": .izleme, "Asistan seni böyle tanıyor": .hafiza, "İzinler": .izinler,
        ]
        for (baslik, hedef) in beklenen {
            let o = AyarDizini.hepsi.first { $0.baslik == baslik }
            #expect(o != nil, "dizinde yok: \(baslik)")
            #expect(o?.hedef == hedef, "yanlış hedef: \(baslik)")
        }
    }

    /// Arayüz testinin yazdığı ASCII terimler ilgili başlığı bulmalı.
    @Test func arayuzTestininTerimleriEslesir() {
        let terimler: [(String, String)] = [
            ("gorunum", "gorunum"), ("komut", "komutlar"), ("saglik", "saglik"), ("beceri", "beceriler"), ("mcp", "mcp"),
            ("soul", "calisma-alani"), ("nabiz", "nabiz"), ("hey asistan", "uyandirma"), ("izinler", "izinler"),
            ("kota", "kullanim"), ("cokme", "izleme"), ("taniyor", "hafiza"),
        ]
        for (terim, id) in terimler {
            #expect(AyarDizini.ara(terim).contains { $0.id == id }, "\(terim) → \(id) bulunamadı")
        }
    }

    // MARK: KurulumHesabi

    private func adimlar(proxyHazir: Bool = true, hesap: Int = 2, izinler: [IzinTuru: IzinDurumu] = [.mikrofon: .verildi, .konusma: .verildi],
                         sesHatasi: Bool = false, ses: String = "azure:Elif", kontrol: Bool? = true,
                         tetik: Bool = false, siri: Bool = true) -> [KurulumAdimi] {
        KurulumHesabi.adimlar(proxyHazir: proxyHazir, hesapSayisi: hesap, izinler: izinler, bulutSesHatasi: sesHatasi,
                              sesKimligi: ses, kontrolEklendi: kontrol, tetikKullanildi: tetik, siriKullanildi: siri)
    }

    private func durum(_ a: [KurulumAdimi], _ id: String) -> KurulumAdimi.Durum? { a.first { $0.id == id }?.durum }

    @Test func herSeyHazirkenEksikYok() {
        let a = adimlar()
        #expect(a.map(\.id) == ["baglanti", "izinler", "ses", "kontrol", "siri"])
        #expect(KurulumHesabi.eksikSayisi(a) == 0)
    }

    @Test func proxyYokkenBaglantiEksik() {
        #expect(durum(adimlar(proxyHazir: false), "baglanti") == .eksik)
        #expect(durum(adimlar(proxyHazir: true, hesap: 0), "baglanti") == .eksik)
        #expect(KurulumHesabi.eksikSayisi(adimlar(proxyHazir: false)) == 1)
    }

    @Test func mikrofonReddedildiyseIzinEksik() {
        #expect(durum(adimlar(izinler: [.mikrofon: .reddedildi, .konusma: .verildi]), "izinler") == .eksik)
        #expect(durum(adimlar(izinler: [:]), "izinler") == .eksik, "okunamayan zorunlu izin eksik sayılır")
    }

    @Test func takvimSorulmadiEksikSayilmaz() {
        let a = adimlar(izinler: [.mikrofon: .verildi, .konusma: .verildi, .takvim: .sorulmadi, .kisiler: .sorulmadi])
        #expect(durum(a, "izinler") == .tamam)
        // Reddedilmiş isteğe bağlı izin de eksik sayılmaz, yalnız ayrıntıda anılır.
        let b = adimlar(izinler: [.mikrofon: .verildi, .konusma: .verildi, .takvim: .reddedildi])
        #expect(durum(b, "izinler") == .tamam)
        #expect(b.first { $0.id == "izinler" }?.ayrinti.contains("Takvim") == true)
    }

    @Test func bulutSesHatasiYalnizBulutSesindeEksik() {
        #expect(durum(adimlar(sesHatasi: true, ses: "azure:Elif"), "ses") == .eksik)
        #expect(durum(adimlar(sesHatasi: true, ses: "apple"), "ses") == .tamam)
        #expect(durum(adimlar(sesHatasi: false, ses: "azure:Elif"), "ses") == .tamam)
    }

    @Test func kontrolBilinmiyorsaEksikSayilmaz() {
        let a = adimlar(kontrol: nil, tetik: false)
        #expect(durum(a, "kontrol") == .bilinmiyor)
        #expect(KurulumHesabi.eksikSayisi(a) == 0)
    }

    @Test func kontrolBilinmiyorAmaTetikKullanildiysaTamam() {
        #expect(durum(adimlar(kontrol: nil, tetik: true), "kontrol") == .tamam)
    }

    @Test func kontrolEkliDegilseEksik() {
        #expect(durum(adimlar(kontrol: false), "kontrol") == .eksik)
    }

    @Test func siriKullanilmadiysaBilinmiyorVeIpucuVerir() {
        let a = adimlar(siri: false)
        #expect(durum(a, "siri") == .bilinmiyor)
        #expect(a.first { $0.id == "siri" }?.ayrinti.contains("Asistan ile konuş") == true)
        #expect(KurulumHesabi.eksikSayisi(a) == 0)
    }

    // MARK: Yedek dışlama (Duzeltme2K9 ile aynı sözleşme: AyarlarEkrani'nda kaldı)

    @Test func yedektenDislaAyarlarEkranindaKaldi() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "p24-yedek-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(AyarlarEkrani.yedektenDisla(url))
    }
}
