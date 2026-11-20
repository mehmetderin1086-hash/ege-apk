import Foundation
import Testing
@testable import Asistan

/// 29 Ekim: Siri'nin sistem ayarları (Wi-Fi, Bluetooth, uçak modu, odak, görünüm, ses, ekran kilidi) Asistan Sistem Köprüsü ile.
@MainActor
@Suite struct SistemKoprusuTestleri {
    private var koprPlist: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "araclar/sistem-koprusu/asistan-sistem-koprusu.unsigned.shortcut")
    }

    @Test func kestirme_dallari_swift_komutlariyla_ayni() throws {
        let veri = try Data(contentsOf: koprPlist)
        let p = try #require(try PropertyListSerialization.propertyList(from: veri, format: nil) as? [String: Any])
        let eylemler = try #require(p["WFWorkflowActions"] as? [[String: Any]])
        let dallar = eylemler.compactMap { e -> String? in
            let a = e["WFWorkflowActionParameters"] as? [String: Any]
            guard e["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.conditional", a?["WFControlFlowMode"] as? Int == 0 else { return nil }
            return a?["WFConditionalActionString"] as? String
        }
        #expect(dallar.count == Set(dallar).count, "yinelenen dal")
        #expect(Set(dallar) == Set(SistemKomutu.tumu.map(\.kod)))
        #expect(p["WFWorkflowName"] as? String == SistemKoprusu.kestirmeAdi)
        // Güvenlik: girdi yalnız koşullarda okunur; hiçbir eylem girdiyi parametre (adres/betik/metin) olarak kullanmaz.
        let izinli: Set<String> = ["is.workflow.actions.conditional", "is.workflow.actions.lockscreen", "is.workflow.actions.setvolume",
                                   "is.workflow.actions.appearance", "is.workflow.actions.dnd.set"]
        for e in eylemler {
            let kimlik = try #require(e["WFWorkflowActionIdentifier"] as? String)
            #expect(izinli.contains(kimlik) || kimlik.hasSuffix(".set"), "beklenmeyen eylem: \(kimlik)")
            guard kimlik != "is.workflow.actions.conditional" else { continue }
            let ham = try PropertyListSerialization.data(fromPropertyList: e["WFWorkflowActionParameters"] ?? [:], format: .xml, options: 0)
            #expect(!String(decoding: ham, as: UTF8.self).contains("ExtensionInput"), "\(kimlik) girdiyi kullanıyor")
        }
    }

    @Test func model_argumanlari_cozulur() {
        #expect(SistemKomutu.coz(ayar: "wifi", deger: "kapat") == .anahtar(.wifi, false))
        #expect(SistemKomutu.coz(ayar: "Wi-Fi", deger: "aç") == .anahtar(.wifi, true))
        #expect(SistemKomutu.coz(ayar: "ucak", deger: "ac") == .anahtar(.ucak, true))
        #expect(SistemKomutu.coz(ayar: "uçak modu", deger: "kapalı") == .anahtar(.ucak, false))
        #expect(SistemKomutu.coz(ayar: "rahatsız etme", deger: "ac") == .anahtar(.odak, true))
        #expect(SistemKomutu.coz(ayar: "mobilveri", deger: "kapat") == .anahtar(.mobilveri, false))
        #expect(SistemKomutu.coz(ayar: "gorunum", deger: "karanlik") == .gorunum(karanlik: true))
        #expect(SistemKomutu.coz(ayar: "karanlık mod", deger: "kapat") == .gorunum(karanlik: false))
        #expect(SistemKomutu.coz(ayar: "aydınlık mod", deger: "ac") == .gorunum(karanlik: false))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "45") == .ses(50))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "%30") == .ses(30))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "150") == .ses(100))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "sustur") == .ses(0))
        #expect(SistemKomutu.coz(ayar: "kilitle", deger: nil) == .kilitle)
        #expect(SistemKomutu.coz(ayar: "wifi", deger: "belki") == nil)
        #expect(SistemKomutu.coz(ayar: "televizyon", deger: "ac") == nil)
        #expect(SistemKomutu.coz(ayar: "ses", deger: nil) == nil)
        // iOS'ta "Açık" tema aydınlıktır; "aç" anlamına alınıp koyu temaya geçilmemeli.
        #expect(SistemKomutu.coz(ayar: "gorunum", deger: "acik") == .gorunum(karanlik: false))
        #expect(SistemKomutu.coz(ayar: "tema", deger: "açık") == .gorunum(karanlik: false))
        #expect(SistemKomutu.coz(ayar: "karanlik mod", deger: "acik") == .gorunum(karanlik: true))
        // Göreli ses: şimdiki düzeyden ±20, sınırlar içinde; şimdiki düzey bilinmiyorsa çözülmez.
        #expect(SistemKomutu.coz(ayar: "ses", deger: "artir", mevcutSes: 0.42) == .ses(60))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "kis", mevcutSes: 0.1) == .ses(0))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "artir", mevcutSes: 0.95) == .ses(100))
        #expect(SistemKomutu.coz(ayar: "ses", deger: "artir") == nil)
        #expect(SistemKomutu.ayarAdi("kablosuz sarj") == nil)
    }

    @Test func yerel_komut_sistem_ayarlarini_tanir() {
        #expect(YerelKomut.coz("Wi-Fi'yi kapat") == .sistem(.anahtar(.wifi, false)))
        #expect(YerelKomut.coz("wifi aç") == .sistem(.anahtar(.wifi, true)))
        #expect(YerelKomut.coz("Bluetooth'u aç") == .sistem(.anahtar(.bluetooth, true)))
        #expect(YerelKomut.coz("Uçak moduna geç") == .sistem(.anahtar(.ucak, true)))
        #expect(YerelKomut.coz("uçak modundan çık") == .sistem(.anahtar(.ucak, false)))
        #expect(YerelKomut.coz("Rahatsız etmeyi aç") == .sistem(.anahtar(.odak, true)))
        #expect(YerelKomut.coz("mobil veriyi kapatır mısın") == .sistem(.anahtar(.mobilveri, false)))
        #expect(YerelKomut.coz("Düşük güç modunu aç") == .sistem(.anahtar(.dusukguc, true)))
        #expect(YerelKomut.coz("Karanlık moda geç") == .sistem(.gorunum(karanlik: true)))
        #expect(YerelKomut.coz("karanlık modu kapat") == .sistem(.gorunum(karanlik: false)))
        #expect(YerelKomut.coz("Sesi yüzde 40 yap") == .sistem(.ses(40)))
        #expect(YerelKomut.coz("sesi 75'e ayarla") == .sistem(.ses(80)))
        #expect(YerelKomut.coz("Ekranı kilitle") == .sistem(.kilitle))
        #expect(YerelKomut.coz("uçak modundan çıkar mısın") == .sistem(.anahtar(.ucak, false)))
        #expect(YerelKomut.coz("uçak modunu kaldır") == .sistem(.anahtar(.ucak, false)))
        #expect(YerelKomut.coz("mobil verileri aç") == .sistem(.anahtar(.mobilveri, true)))
        #expect(YerelKomut.coz("wifi'ye bağlan") == .sistem(.anahtar(.wifi, true)))
        // Medya ses düzeyi zili susturmaz; sesli kipte "sesi kapat" konuşmayı kes demektir.
        #expect(YerelKomut.coz("telefonu sessize al") == nil)
        #expect(YerelKomut.coz("sesi kapat") == nil)
        // Bileşik ya da soru biçimli istekler modele gider.
        #expect(YerelKomut.coz("Wi-Fi'yi kapat ve annemi ara") == nil)
        #expect(YerelKomut.coz("wifi şifresi ne") == nil)
        #expect(YerelKomut.coz("uçak modu nedir") == nil)
        let k = YerelKomut.Komut.sistem(.anahtar(.wifi, false))
        #expect(YerelKomut.aracAdi(k) == "cihaz")
        #expect(YerelKomut.yanEtkili(k))
    }

    @Test func sistem_istekleri_arac_yolundan_kacmaz() {
        #expect(!CanliHizliIstemci.uygun("Uçak moduna geçer misin"))
        #expect(!CanliHizliIstemci.uygun("Telefonu kilitler misin"))
        #expect(!CanliHizliIstemci.uygun("Wi-Fi'yi kapatabilir misin acaba"))
        #expect(!CanliHizliIstemci.uygun("hotspotu açar mısın"))
        #expect(!CanliHizliIstemci.uygun("Rahatsız Etme'yi etkinleştirir misin acaba"))
        #expect(!CanliHizliIstemci.uygun("ses düzeyini yüzde 30 yapar mısın acaba"))
        #expect(!CanliHizliIstemci.uygun("karanlık moda geçebilir misin acaba"))
    }

    @Test func ayar_iddialari_cihaz_aracina_baglanir() {
        // Araç gerçekten çalıştıysa "yapılmadı" notu düşmez; araçsız iddia yakalanır.
        for y in ["Wi-Fi'yi açtım.", "Ses düzeyini %40'a ayarladım.", "Bluetooth'u kapattım.", "Rahatsız Etme'yi etkinleştirdim.", "Ekranı kilitledim."] {
            #expect(EylemIddiasi.denetle(y, basariliAraclar: ["cihaz"]) == nil, "\(y)")
            #expect(EylemIddiasi.denetle(y, basariliAraclar: []) != nil, "\(y)")
        }
    }

    @Test func x_callback_adresi_donusu_bozmaz() throws {
        let url = try #require(SistemKoprusu.adres(.anahtar(.wifi, false), kimlik: "K-1"))
        #expect(url.absoluteString.hasPrefix("shortcuts://x-callback-url/run-shortcut?"))
        let q = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func deger(_ ad: String) -> String? { q.first { $0.name == ad }?.value }
        #expect(q.count == 6, "dönüş adresinin & işareti sorguyu bölmemeli")
        #expect(deger("name") == "Asistan Sistem Köprüsü")
        #expect(deger("input") == "text")
        #expect(deger("text") == "wifi_kapat")
        #expect(deger("x-success") == "asistan://sistem-koprusu?sonuc=tamam&k=K-1")
        #expect(deger("x-error") == "asistan://sistem-koprusu?sonuc=hata&k=K-1")
        #expect(deger("x-cancel") == "asistan://sistem-koprusu?sonuc=iptal&k=K-1")
    }

    @Test func donus_baglantisi_cozulur() throws {
        func url(_ s: String) throws -> URL { try #require(URL(string: s)) }
        let tamam = try #require(SistemKoprusu.donusCoz(try url("asistan://sistem-koprusu?sonuc=tamam&k=abc")))
        #expect(tamam.kimlik == "abc" && tamam.sonuc == .tamam)
        let hata = try #require(SistemKoprusu.donusCoz(try url("asistan://sistem-koprusu?sonuc=hata&k=abc&errorMessage=Kestirme%20bulunamad%C4%B1")))
        #expect(hata.sonuc == .hata("Kestirme bulunamadı"))
        #expect(SistemKoprusu.bulunamadiMi("Kestirme bulunamadı"))
        #expect(SistemKoprusu.bulunamadiMi("The shortcut couldn’t be found."))
        #expect(!SistemKoprusu.bulunamadiMi("İnternet bağlantısı yok"))
        #expect(SistemKoprusu.donusCoz(try #require(URL(string: "asistan://sistem-koprusu?sonuc=tamam"))) == nil)
        #expect(SistemKoprusu.donusCoz(try #require(URL(string: "asistan://tekrar"))) == nil)
        #expect(AsistanBaglantisi.coz(try #require(URL(string: "asistan://sistem-koprusu?sonuc=tamam&k=abc"))) == nil)
        // Bekleyen çağrısı olmayan dönüş sessizce yutulur (başka bağlantı dalına düşmez).
        #expect(SistemKoprusu(defaults: UserDefaults(suiteName: "sk-\(UUID())")!).geriDonus(try #require(URL(string: "asistan://sistem-koprusu?sonuc=tamam&k=yok"))))
    }

    @Test func interneti_kesen_komutlar_ertelenir() {
        #expect(SistemKomutu.anahtar(.ucak, true).agiKeser)
        #expect(!SistemKomutu.anahtar(.ucak, false).agiKeser)
        #expect(SistemKomutu.anahtar(.wifi, false).agiKeser)
        #expect(!SistemKomutu.anahtar(.wifi, true).agiKeser)
        #expect(SistemKomutu.anahtar(.mobilveri, false).agiKeser)
        #expect(!SistemKomutu.anahtar(.bluetooth, false).agiKeser)
        #expect(SistemKomutu.anahtar(.ucak, true).gelecek == "Uçak modu açılacak")
        let k = SistemKoprusu(defaults: UserDefaults(suiteName: "sk-\(UUID())")!)
        // Birden çok komut sırayla tutulur; aynı ayarın son isteği kalır; ekran kilidi en sonda.
        k.ertele(.kilitle)
        k.ertele(.anahtar(.wifi, false))
        k.ertele(.anahtar(.mobilveri, false))
        k.ertele(.anahtar(.wifi, true))
        #expect(k.ertelenenler == [.anahtar(.mobilveri, false), .anahtar(.wifi, true), .kilitle])
        k.ertelenenTemizle()
        #expect(k.ertelenenler.isEmpty)
        #expect(SistemKomutu.kilitle.yanittanSonra && !SistemKomutu.kilitle.agiKeser)
        #expect(!SistemKomutu.anahtar(.bluetooth, true).yanittanSonra)
    }

    @Test func kurulum_durumu_kalici() throws {
        let d = try #require(UserDefaults(suiteName: "sk-\(UUID())"))
        let k = SistemKoprusu(defaults: d)
        #expect(!k.kuruldu)
        k.kuruldu = true
        #expect(SistemKoprusu(defaults: d).kuruldu)
    }

    @Test func sonuc_metinleri_durustur() {
        let k = SistemKomutu.ses(40)
        #expect(SistemKoprusu.metin(k, .tamam, dogrulandi: true).contains("doğrulandı"))
        #expect(SistemKoprusu.metin(k, .tamam, dogrulandi: false).contains("doğrulanamadı"))
        #expect(SistemKoprusu.metin(k, .hata("Kestirme bulunamadı"), dogrulandi: nil).contains("Sistem ayarları"))
        #expect(SistemKoprusu.metin(k, .zamanAsimi, dogrulandi: nil).contains("doğrulanamadı"))
        #expect(SistemKoprusu.metin(k, .iptal, dogrulandi: nil).contains("değişmedi"))
        #expect(SistemKoprusu.metin(k, .durduruldu, dogrulandi: nil).contains("doğrulanamadı"))
        #expect(SistemKoprusu.metin(k, .arkaPlanda, dogrulandi: nil).contains("arka planda"))
    }

    @Test func kurulmamis_kopruda_kurulum_ekrani_acilir() async throws {
        let kopru = SistemKoprusu.ortak
        guard !kopru.kuruldu else { return }   // test aygıtında kurulu değil; kuruluysa bu dal sınanamaz
        let m = try await CihazAraci().call(arguments: .init(islem: "wifi", deger: "kapat"))
        #expect(m.contains("Asistan Sistem Köprüsü"))
        #expect(m.contains("henüz değişmedi"))
        #expect(kopru.ekranAcik)
        #expect(kopru.ertelenenler.isEmpty, "kurulmamışken ertelenen komut kalmamalı")
        kopru.ekranAcik = false
    }

    @Test func eski_cihaz_islemleri_bozulmadi() async throws {
        let m = try await CihazAraci().call(arguments: .init(islem: "yokboyle", deger: nil))
        #expect(m.hasPrefix("Bilinmeyen işlem"))
        #expect(try await CihazAraci().call(arguments: .init(islem: "depolama", deger: nil)).hasPrefix("Boş alan"))
    }
}
