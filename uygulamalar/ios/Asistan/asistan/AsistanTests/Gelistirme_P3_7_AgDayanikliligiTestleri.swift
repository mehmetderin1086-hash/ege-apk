import Testing
import Foundation
import FoundationModels
import ClaudeForFoundationModels
@testable import Asistan

/// P3.7: ağ dayanıklılığı — türlü hata sınıflaması, askı kapsamı (istek / model|yol / rota), kalıcı rota askısı,
/// VPS erişilemezliği, bağlantı özeti ve yarış genişliği. Ağ, izin ya da gerçek model gerektirmez.
@Suite("P3.7 ağ dayanıklılığı", .serialized)
@MainActor
struct Gelistirme_P3_7_AgDayanikliligiTestleri {
    /// ClaudeAPI.APIError taklidi: Mirror yolu `kind` ve `message` alanlarını okur.
    struct SahteApi: Error {
        enum Kind { case notFound, invalidRequest, permission, api }
        let kind: Kind
        let message: String
    }
    struct MetinHatasi: Error, CustomStringConvertible { let description: String }

    func suit() -> (UserDefaults, String) {
        let ad = "p37.\(UUID().uuidString)"
        return (UserDefaults(suiteName: ad)!, ad)
    }

    // MARK: (1) sınıflama tablosu

    @Test func urlHatalariIstekVeRotaAyrimi() {
        #expect(ModelZinciri.sinifla(URLError(.notConnectedToInternet), yol: .telefon) == .init(gec: true, kapsam: .istek))
        #expect(ModelZinciri.sinifla(URLError(.networkConnectionLost), yol: .vekil).kapsam == .istek)
        #expect(ModelZinciri.sinifla(URLError(.timedOut), yol: .vekil).kapsam == .istek)
        #expect(ModelZinciri.sinifla(URLError(.cannotConnectToHost), yol: .telefon).kapsam == .rota(30))
        #expect(ModelZinciri.sinifla(URLError(.cannotConnectToHost), yol: .vekil).kapsam == .rota(120))
        // DNS çözümü geçici olabilir: rota değil yalnız bu istek.
        #expect(ModelZinciri.sinifla(URLError(.dnsLookupFailed), yol: .anahtar).kapsam == .istek)
        // NSError biçimi (URLError'a köprülenmemiş) de aynı yoldan sınıflanır.
        let ns = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        #expect(ModelZinciri.sinifla(ns, yol: .vekil).kapsam == .istek)
    }

    @Test func dilModeliVeKimlikHatalari() {
        let sinir = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "429"))
        #expect(ModelZinciri.sinifla(sinir, yol: .telefon) == .init(gec: true, kapsam: .modelYol(600)))
        let zaman = LanguageModelError.timeout(.init(debugDescription: "zaman aşımı"))
        #expect(ModelZinciri.sinifla(zaman, yol: .telefon).kapsam == .istek)
        let baglam = LanguageModelError.contextSizeExceeded(.init(contextSize: 0, tokenCount: 0, debugDescription: "büyük"))
        #expect(ModelZinciri.sinifla(baglam, yol: .telefon).gec == false)
        let kimlik = ModelZinciri.sinifla(ClaudeError.missingCredential, yol: .vekil)
        #expect(kimlik == .init(gec: true, kapsam: .modelYol(3600)), "401 yalnız o model|yol")
        if case .rota = kimlik.kapsam { Issue.record("kimlik hatası rota askısı olmamalı") }
        #expect(ModelZinciri.sinifla(ClaudeError.attestationFailed, yol: .telefon).kapsam == .modelYol(3600))
        #expect(ModelZinciri.sinifla(CancellationError(), yol: .telefon).gec == false)
    }

    @Test func apiTuruMirrorIleOkunur() {
        #expect(ModelZinciri.apiTuru(SahteApi(kind: .notFound, message: "yok")) == "notFound")
        #expect(ModelZinciri.apiTuru(MetinHatasi(description: "x")) == nil)
        let bulunamadi = ModelZinciri.sinifla(SahteApi(kind: .notFound, message: "model yok"), yol: .telefon)
        #expect(bulunamadi == .init(gec: true, kapsam: .modelYol(3600), hakDusmez: true))
        let izin = ModelZinciri.sinifla(SahteApi(kind: .permission, message: "izin yok"), yol: .vekil)
        #expect(izin.kapsam == .modelYol(3600) && !izin.hakDusmez)
        #expect(ModelZinciri.sinifla(SahteApi(kind: .api, message: "500"), yol: .vekil).kapsam == .modelYol(60))
        let arac = ModelZinciri.sinifla(SahteApi(kind: .invalidRequest, message: "This model does not support tools"), yol: .vekil)
        #expect(arac.hakDusmez && arac.kapsam == .modelYol(3600))
        let olagan = ModelZinciri.sinifla(SahteApi(kind: .invalidRequest, message: "bad image"), yol: .vekil)
        #expect(olagan.gec && olagan.kapsam == .istek && !olagan.hakDusmez)
    }

    @Test func yapilandirmaIletisiHakDusmez() {
        let k = ModelZinciri.sinifla(MetinHatasi(description: "sunucu hatası: 'gemini-pro-account' sağlayıcısı 'tools' yeteneğini desteklemiyor"), yol: .telefon)
        #expect(k.gec && k.hakDusmez && k.kapsam == .modelYol(3600))
        let bilinmeyen = ModelZinciri.sinifla(MetinHatasi(description: "beklenmeyen bir şey"), yol: .telefon)
        #expect(bilinmeyen == .init(gec: true, kapsam: .modelYol(60)))
        // Uyumluluk: eski dusmeKarari biçimi.
        #expect(ModelZinciri.dusmeKarari(URLError(.notConnectedToInternet)).askiSn <= 60)
        #expect(ModelZinciri.dusmeKarari(MetinHatasi(description: "rateLimited(resetDate: nil)")).askiSn >= 600)
    }

    // MARK: (2) model|yol askısı

    @Test func modelYolAskisiYalnizOYoluAtlar() {
        let (d, ad) = suit(); defer { d.removePersistentDomain(forName: ad) }
        let v = ModelVitesi(defaults: d)
        v.beklet("claude-haiku-4-5", yol: .telefon, saniye: 3600)
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false, telefonVar: true, modelAskilari: v.yolAskilari)
        #expect(z.adimlar(model: "claude-haiku-4-5").map(\.yol) == [.vekil, .anahtar])
        #expect(z.adimlar(model: "gpt-6.1-sol").map(\.yol) == [.telefon, .vekil, .anahtar], "başka model etkilenmez")
        #expect(v.askida("claude-haiku-4-5", yol: .telefon))
        #expect(!v.askida("claude-haiku-4-5", yol: .vekil))
        // Model geneli değil: sıra modeli hâlâ önerir, kota uyarısı yok.
        let s = v.sira(caba: .low, kip: .sohbet, metin: "Merhaba", gorsel: false,
                       modeller: ["claude-haiku-4-5", "gpt-6.1-sol"], elle: "claude-opus-5-5", otomatik: true)
        #expect(s.contains("claude-haiku-4-5"))
        #expect(v.modelGeneliAskilar.isEmpty)
        #expect(v.yolAskilari.keys.sorted() == ["claude-haiku-4-5|telefon"])
        // Gecikme anahtarları yol askısı sayılmaz; o yolda başarı askıyı kaldırır.
        v.basari("claude-haiku-4-5", caba: .low, ilkSn: 1, yol: .telefon)
        #expect(!v.askida("claude-haiku-4-5", yol: .telefon))
        #expect(v.yolAskilari.isEmpty)
    }

    @Test func yolAskisiKotaUyarisiUretmez() {
        let (d, ad) = suit(); defer { d.removePersistentDomain(forName: ad) }
        let k = OnayKapisi(); k.otomatikKarar = false
        let v = ModelVitesi(defaults: d)
        let b = Beyin(ayarlar: Ayarlar(defaults: d), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: v)
        v.beklet("claude-haiku-4-5", yol: .telefon, saniye: 3600)
        #expect(b.kotaUyarisi == nil)
        v.beklet("claude-haiku-4-5", saniye: 3600)
        #expect(b.kotaUyarisi != nil, "model geneli askı uyarı üretir")
    }

    @Test func hepsiModelYolAskisindaysaAskiYoksayHepsiniVerir() {
        let simdi = Date()
        let bitis = simdi.addingTimeInterval(600)
        let z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false, telefonVar: true,
                             modelAskilari: ["m|telefon": bitis, "m|vekil": bitis, "m|anahtar": bitis])
        #expect(z.adimlar(model: "m", simdi: simdi).isEmpty)
        #expect(z.adimlar(model: "m", simdi: simdi, askiYoksay: true).map(\.yol) == [.telefon, .vekil, .anahtar])
        #expect(z.adimlar(model: "m", simdi: simdi.addingTimeInterval(601)).count == 3, "askı bitince geri gelir")
    }

    // MARK: (3) rota askısı kalıcı

    @Test func rotaAskisiKaliciVeSuresiGecenYuklenmez() {
        let (d, ad) = suit(); defer { d.removePersistentDomain(forName: ad) }
        let v = ModelVitesi(defaults: d)
        v.rotaAskisiYaz(.vekil, bitis: Date().addingTimeInterval(120))
        #expect(ModelVitesi(defaults: d).rotaAskilari[.vekil] != nil, "yeni örnekte okunur")
        // Süresi geçmiş kayıt yüklenmez.
        d.set(["telefon": Date().addingTimeInterval(-5).timeIntervalSince1970,
               "vekil": Date().addingTimeInterval(300).timeIntervalSince1970], forKey: ModelVitesi.rotaAnahtari)
        let y = ModelVitesi(defaults: d)
        #expect(y.rotaAskilari[.telefon] == nil)
        #expect(y.rotaAskilari[.vekil] != nil)
        y.askiKaldir("vekil")
        #expect(y.rotaAskilari.isEmpty)
        #expect(ModelVitesi(defaults: d).rotaAskilari.isEmpty, "kaldırma da kalıcı")
    }

    @Test func beyinAskilariModelVitesineYonlenir() {
        let (d, ad) = suit(); defer { d.removePersistentDomain(forName: ad) }
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: Ayarlar(defaults: d), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: ModelVitesi(defaults: d))
        b.askilar[.telefon] = Date().addingTimeInterval(60)
        #expect(b.zincir.askiBitis[.telefon] != nil)
        let ikinci = Beyin(ayarlar: Ayarlar(defaults: d), depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k, modelVitesi: ModelVitesi(defaults: d))
        #expect(ikinci.askilar[.telefon] != nil, "yeni Beyin örneğinde okunur")
        b.modelVitesi.beklet("gpt-6.1-sol", yol: .vekil, saniye: 600)
        #expect(b.zincir.modelAskilari["gpt-6.1-sol|vekil"] != nil)
        b.askiKaldir("telefon")
        b.askiKaldir("gpt-6.1-sol|vekil")
        #expect(b.askilar.isEmpty)
        #expect(b.modelVitesi.yolAskilari.isEmpty)
        b.modelVitesi.beklet("claude-opus-5-5", saniye: 600)
        b.askilar[.anahtar] = Date().addingTimeInterval(60)
        b.modelVitesi.tumAskilariKaldir()
        #expect(b.askilar.isEmpty && b.modelVitesi.modelGeneliAskilar.isEmpty)
    }

    // MARK: (4) VPS erişilemez

    @Test func vekilErisilemezVekilAdiminiAtlar() {
        var z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false, telefonVar: true, vekilErisilemez: true)
        #expect(z.adimlar(model: "m").map(\.yol) == [.telefon, .anahtar])
        z = ModelZinciri(vekilVar: true, anahtarVar: false, yalnizAnahtar: false, telefonVar: false, vekilErisilemez: true)
        #expect(z.adimlar(model: "m").map(\.yol) == [.vekil], "tek yol .vekil ise kalır")
    }

    // MARK: (5) askiYoksay

    @Test func askiYoksayButunAdimlariVerir() {
        let simdi = Date()
        var z = ModelZinciri(vekilVar: true, anahtarVar: true, yalnizAnahtar: false, telefonVar: true,
                             modelAskilari: ["m|telefon": simdi.addingTimeInterval(600)], vekilErisilemez: true)
        z.askiBitis[.anahtar] = simdi.addingTimeInterval(600)
        #expect(z.adimlar(model: "m", simdi: simdi, askiYoksay: true).map(\.yol) == [.telefon, .vekil, .anahtar])
        // Rota askısı tek açık yolu bırakır; model|yol askısı onu da süzer → boş, çağıran askiYoksay ile kurar.
        #expect(z.adimlar(model: "m", simdi: simdi).isEmpty)
    }

    // MARK: (6) bağlantı özeti

    @Test func baglantiOzetiVeHapEki() {
        typealias B = BaglantiDurumu
        #expect(B.ozet([.yerelVekil: .iyi, .vps: .iyi, .internet: .iyi], cevrimici: true) == nil)
        #expect(B.ozet([:], cevrimici: true) == nil, "bilinmiyorken uyarı yok")
        #expect(B.ozet([.internet: .yok("oturum açma sayfası"), .vps: .yok("zaman aşımı")], cevrimici: true)?.contains("internete çıkılamıyor") == true)
        #expect(B.ozet([.internet: .yok("bağlantı yok")], cevrimici: false) == nil, "çevrimdışı durum kendi şeridinde")
        #expect(B.ozet([.internet: .iyi, .vps: .yok("zaman aşımı")], cevrimici: true)?.contains("VPS") == true)
        #expect(B.ozet([.internet: .iyi, .vps: .yapilandirilmamis, .yerelVekil: .yok("yanıt yok")], cevrimici: true)?.contains("CLIProxy") == true)
        #expect(B.hapEki([.internet: .iyi, .vps: .yok("x")]) == "VPS yok")
        #expect(B.hapEki([.internet: .yok("x"), .vps: .yok("x")]) == "İnternet yok")
        #expect(B.hapEki([.internet: .iyi, .vps: .iyi]) == nil)
        #expect(B.internetSonucu(govde: "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>") == .iyi)
        #expect(B.internetSonucu(govde: "<html>Okul ağına giriş</html>") == .yok("oturum açma sayfası"))
        #expect(B.neden(.serverCertificateUntrusted) == "oturum açma sayfası olabilir")
        #expect(B.neden(.timedOut) == "zaman aşımı")
    }

    @Test func vpsYapilandirilmamissaYoklanmaz() async {
        #expect(await BaglantiDurumu.vpsYokla(taban: nil, token: "x") == .yapilandirilmamis)
        #expect(await BaglantiDurumu.vpsYokla(taban: URL(string: "https://ornek.invalid"), token: nil) == .yapilandirilmamis)
    }

    // MARK: (7) yarış genişliği

    @Test func paralelYarisGenisligi() {
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: true) == 1)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false) == 3)
        #expect(ParalelYaris.genislik(ayar: 0, dusukVeri: false) == 1)
        #expect(ParalelYaris.genislik(ayar: 9, dusukVeri: false) == 3)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, termalAgir: true) == 1)
        #expect(ParalelYaris.genislik(ayar: 3, dusukVeri: false, dusukGuc: true) == 2)
        #expect(AgIzleyici.arayuzAdi(wifi: true, hucresel: true, kablolu: false) == "wifi")
        #expect(AgIzleyici.arayuzAdi(wifi: false, hucresel: true, kablolu: false) == "hucresel")
    }

    // MARK: Sağlık ekranı askı listesi

    @Test func askiSatirlariSureyeGoreVeSuresiGecenYok() {
        let simdi = Date()
        let s = SaglikEkrani.askiSatirlari(rota: [.vekil: simdi.addingTimeInterval(120), .telefon: simdi.addingTimeInterval(-1)],
                                           yol: ["claude-haiku-4-5|telefon": simdi.addingTimeInterval(3600)],
                                           genel: ["gpt-6.1-sol": simdi.addingTimeInterval(600)], simdi: simdi)
        #expect(s.map(\.id) == ["claude-haiku-4-5|telefon", "gpt-6.1-sol", "vekil"])
        #expect(s[0].baslik.contains("iPhone CLIProxy"))
        #expect(s[2].baslik.contains("bütün modeller"))
    }
}

/// Gerçek ağ: captive.apple.com yoklaması (yalnız ASISTAN_CANLI=1).
@Suite("P3.7 canlı bağlantı yoklaması", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct Gelistirme_P3_7_CanliBaglantiTestleri {
    @Test func internetHalkasiIyi() async {
        #expect(await BaglantiDurumu.internetYokla() == .iyi)
    }
}
