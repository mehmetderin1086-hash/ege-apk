import Foundation
import AVFoundation
import Testing
@testable import Asistan

/// P4.7: Sürüş kipi — CarPlay yolu tanıma, kip kuralı (otomatik/elle/bu sürüşte kapat), sesli ret sözlüğü,
/// seslendirme kırpması (akış önek kararlılığı dahil), talimat eki, erteleme ve hatırlatma, onay kapısının sesli yolu.
/// Ağ, izin, mikrofon ve gerçek model gerektirmez; her test kendi UserDefaults alanını ve SurusKipi örneğini kullanır.
@Suite("Gelistirme P4.7 · Sürüş kipi") @MainActor
struct Gelistirme_P4_7_SurusKipiTestleri {

    /// Temiz ayar alanı + o alana bağlı kip (ses yolu gözlemcisi kurulmaz).
    static func kur() -> (SurusKipi, Ayarlar, UserDefaults) {
        let ad = "p47-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: ad)!
        d.removePersistentDomain(forName: ad)
        let a = Ayarlar(defaults: d)
        let k = SurusKipi(defaults: d)
        k.ayarlar = a
        k.hatirlatici = { _ in true }
        return (k, a, d)
    }

    func bekle(_ kosul: () -> Bool, sinir: Int = 60) async {
        for _ in 0..<sinir where !kosul() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    // MARK: Ses yolu ve kip kuralı

    @Test func carPlayYoluTaninir() {
        #expect(SurusKipi.arabaMi([.carAudio]))
        #expect(SurusKipi.arabaMi([.builtInSpeaker, .carAudio]))
        #expect(!SurusKipi.arabaMi([.bluetoothA2DP]))
        #expect(!SurusKipi.arabaMi([.bluetoothHFP]))
        #expect(!SurusKipi.arabaMi([.builtInSpeaker]))
        #expect(!SurusKipi.arabaMi([]))
    }

    @Test func kipKurali() {
        #expect(SurusKipi.karar(elle: false, otomatik: true, arabada: true, elleKapali: false))
        #expect(!SurusKipi.karar(elle: false, otomatik: false, arabada: true, elleKapali: false))
        #expect(!SurusKipi.karar(elle: false, otomatik: true, arabada: false, elleKapali: false))
        #expect(SurusKipi.karar(elle: true, otomatik: false, arabada: false, elleKapali: false))
        #expect(!SurusKipi.karar(elle: true, otomatik: true, arabada: true, elleKapali: true))
    }

    @Test func ayarVarsayilanlari() {
        let (_, a, _) = Self.kur()
        #expect(a.surusKipiOtomatik)
        #expect(!a.surusKipiElle)
    }

    @Test func otomatikKipCarPlaydeAcilirAyrilincaKapanir() {
        let (k, _, _) = Self.kur()
        k.guncelle(cikislar: [.builtInSpeaker])
        #expect(!k.aktif)
        k.guncelle(cikislar: [.carAudio])
        #expect(k.aktif && k.arabada)
        k.guncelle(cikislar: [.bluetoothA2DP])
        #expect(!k.aktif)
    }

    @Test func otomatikKapaliykenCarPlayAcmaz() {
        let (k, a, _) = Self.kur()
        a.surusKipiOtomatik = false
        k.guncelle(cikislar: [.carAudio])
        #expect(!k.aktif)
    }

    @Test func elleAcikkenHoparlordeDeAktif() {
        let (k, a, _) = Self.kur()
        a.surusKipiElle = true
        k.guncelle(cikislar: [.builtInSpeaker])
        #expect(k.aktif)
    }

    @Test func buSurusteKapatAyrilincaSifirlanir() {
        let (k, _, _) = Self.kur()
        k.guncelle(cikislar: [.carAudio])
        #expect(k.aktif)
        k.buSurusteKapat()   // geçerli yol hâlâ CarPlay sayılsın diye yeniden aynı çıkışla değerlendirilir
        k.guncelle(cikislar: [.carAudio])
        #expect(!k.aktif)
        #expect(k.elleKapali)
        k.guncelle(cikislar: [.builtInSpeaker])   // araba bağlantısı kesildi
        #expect(!k.elleKapali)
        k.guncelle(cikislar: [.carAudio])          // sonraki sürüş
        #expect(k.aktif)
    }

    @Test func buSurusteKapatElleAciligiDaKapatir() {
        let (k, a, _) = Self.kur()
        a.surusKipiElle = true
        k.guncelle(cikislar: [.builtInSpeaker])
        #expect(k.aktif)
        k.buSurusteKapat()
        k.guncelle(cikislar: [.builtInSpeaker])
        #expect(!a.surusKipiElle)
        #expect(!k.aktif)
    }

    @Test func carPlaySahnesiKipiZorunluAcar() {
        let (k, a, _) = Self.kur()
        a.surusKipiOtomatik = false
        k.carPlayBagli = true
        #expect(k.aktif)
        k.carPlayBagli = false
        #expect(!k.aktif)
    }

    // MARK: Sesli ret sözlüğü

    @Test func evetHayirTablosu() {
        #expect(SurusKipi.evetHayir("evet gönder") == true)
        #expect(SurusKipi.evetHayir("Tamam.") == true)
        #expect(SurusKipi.evetHayir("hayır") == false)
        #expect(SurusKipi.evetHayir("yapma") == false)
        #expect(SurusKipi.evetHayir("yok, yapma!") == false)
        #expect(SurusKipi.evetHayir("I\u{0307}ptal") == false)   // NFD büyük İ
        #expect(SurusKipi.evetHayir("bilmiyorum") == nil)
        #expect(SurusKipi.evetHayir("evet hayır") == nil)
        #expect(SurusKipi.evetHayir("") == nil)
    }

    // MARK: Seslendirme kırpması

    @Test func kisaltDortCumleyiIkiyeIndirir() {
        let m = "Yarın hava güneşli. Sıcaklık 24 derece. Rüzgâr hafif. Akşam serinler."
        #expect(SurusKipi.kisalt(m) == "Yarın hava güneşli. Sıcaklık 24 derece.")
        #expect(SurusKipi.kisalt(m, cumle: 1) == "Yarın hava güneşli.")
    }

    @Test func kisaltKisaMetneDokunmaz() {
        #expect(SurusKipi.kisalt("Tamam, kurdum.") == "Tamam, kurdum.")
        #expect(SurusKipi.kisalt("Saat 14.30'da toplantın var. Hazırlan!") == "Saat 14.30'da toplantın var. Hazırlan!")
        #expect(SurusKipi.kisalt("") == "")
    }

    @Test func kisaltSatirlariCumleSayar() {
        let m = "Birinci madde oldukça uzun bir satır\nİkinci madde de oldukça uzun bir satır\nÜçüncü madde"
        #expect(SurusKipi.kisalt(m) == "Birinci madde oldukça uzun bir satır\nİkinci madde de oldukça uzun bir satır")
    }

    /// Akan metne her adımda uygulanınca sonuç büyüyen metnin öneki kalır ve 2 cümleden sonra değişmez:
    /// Konusmaci'nın bölücüsü 3. cümleyi hiç görmez.
    @Test func kisaltAkistaOnekKararli() {
        let tam = "Bir. İki cümle. Üç cümle burada. Dört."
        var onceki = ""
        var bolucu = CumleBolucu()
        bolucu.ilkVirgul = false
        var okunan: [String] = []
        for n in 1...tam.count {
            let parca = String(tam.prefix(n))
            let k = SurusKipi.kisalt(parca)
            #expect(parca.hasPrefix(k))
            #expect(k.hasPrefix(onceki) || onceki.hasPrefix(k))
            okunan += bolucu.yeniCumleler(k)
            onceki = k
        }
        if let kalan = bolucu.kalan(SurusKipi.kisalt(tam)) { okunan.append(kalan) }
        #expect(okunan == ["Bir.", "İki cümle."])
    }

    // MARK: Talimat

    @Test func surusTalimati() {
        #expect(Beyin.surusTalimati(aktif: false).isEmpty)
        let t = Beyin.surusTalimati(aktif: true)
        #expect(t.contains("Sürüş kipi"))
        #expect(t.contains("2 kısa cümle"))
        #expect(t.contains("ertele"))
    }

    // MARK: Erteleme ve hatırlatma

    @Test func pasifkenBelgeErtelenmez() {
        let (k, _, _) = Self.kur()
        k.guncelle(cikislar: [.builtInSpeaker])
        #expect(k.belgeyiErtele(ozet: "rapor.docx") == nil)
        #expect(k.ertelenenler.isEmpty)
    }

    @Test func aktifkenAsilIstekErtelenir() {
        let (k, _, d) = Self.kur()
        k.guncelle(cikislar: [.carAudio])
        k.sonIstek = "9A için yazılı sınavı Word olarak hazırla"
        #expect(k.belgeyiErtele(ozet: "sinav adlı DOCX belgesini hazırla") == SurusKipi.ertelemeYaniti)
        #expect(k.ertelenenler == ["9A için yazılı sınavı Word olarak hazırla"])
        // Aynı turda ikinci araç çağrısı aynı isteği yinelemez; kalıcıdır.
        _ = k.belgeyiErtele(ozet: "anahtar adlı PDF belgesini hazırla")
        #expect(k.ertelenenler.count == 1)
        #expect(d.stringArray(forKey: SurusKipi.ertelenenAnahtari) == k.ertelenenler)
        #expect(SurusKipi(defaults: d).ertelenenler == k.ertelenenler)
    }

    @Test func istekYoksaAracOzetiErtelenir() {
        let (k, _, _) = Self.kur()
        k.guncelle(cikislar: [.carAudio])
        k.sonIstek = nil
        _ = k.belgeyiErtele(ozet: "notlar adlı Excel tablosunu hazırla")
        #expect(k.ertelenenler == ["notlar adlı Excel tablosunu hazırla"])
    }

    @Test func ertelenenlerEnCokBes() {
        var l: [String] = []
        for i in 1...8 { l = SurusKipi.ekle("istek \(i)", l) }
        #expect(l.count == SurusKipi.enFazlaErtelenen)
        #expect(l.first == "istek 4")
        #expect(l.last == "istek 8")
        #expect(SurusKipi.ekle("istek 5", l).last == "istek 5")   // yinelenen öne (sona) alınır, sayı değişmez
        #expect(SurusKipi.ekle("istek 5", l).count == 5)
    }

    @Test(.timeLimit(.minutes(1))) func kipKapanincaHatirlatilirVeListeBosalir() async {
        let (k, _, _) = Self.kur()
        var gonderilen: [String] = []
        k.hatirlatici = { l in gonderilen = l; return true }
        k.guncelle(cikislar: [.carAudio])
        k.sonIstek = "Haftalık planı PDF yap"
        _ = k.belgeyiErtele(ozet: "plan")
        k.guncelle(cikislar: [.builtInSpeaker])
        await bekle { k.ertelenenler.isEmpty }
        #expect(gonderilen == ["Haftalık planı PDF yap"])
        #expect(k.ertelenenler.isEmpty)
        #expect(k.sonIstek == nil)
    }

    @Test(.timeLimit(.minutes(1))) func bildirimIzniYoksaListeKalir() async {
        let (k, _, _) = Self.kur()
        var cagrildi = false
        k.hatirlatici = { _ in cagrildi = true; return false }
        k.guncelle(cikislar: [.carAudio])
        k.sonIstek = "Tabloyu Excel'e dök"
        _ = k.belgeyiErtele(ozet: "tablo")
        k.guncelle(cikislar: [.builtInSpeaker])
        await bekle { cagrildi }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(cagrildi)
        #expect(k.ertelenenler == ["Tabloyu Excel'e dök"])
    }

    @Test func bildirimIcerigiIstegiTasir() {
        let c = SurusKipi.bildirimIcerigi("Sınavı hazırla")
        #expect(c.title == "Sürüşte ertelenen istek")
        #expect(c.body == "Sınavı hazırla")
        #expect(c.userInfo[TetikDeposu.istemAnahtari] as? String == "Sınavı hazırla")
        #expect(SurusKipi.bildirimOnek.hasPrefix("surus"))
    }

    // MARK: Onay kapısının sesli yolu (sürüşte SesOturumu sesli kip kapalıyken de sorucuyu çalıştırır)

    @Test(.timeLimit(.minutes(1))) func sesliEvetDiyaloguKapatir() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        k.sesliSorucu = { _ in true }
        #expect(await k.iste(baslik: "Mesaj gönderilsin mi?", ayrinti: "Alıcı: Ayşe") == true)
        #expect(k.bekleyen == nil)
    }

    @Test(.timeLimit(.minutes(1))) func sesliBelirsizdeDiyalogKalir() async {
        let k = OnayKapisi(zorunluOtomatikKararaUyar: false)
        var soruldu = false
        k.sesliSorucu = { _ in soruldu = true; return nil }
        let t = Task { await k.iste(baslik: "Ara", ayrinti: "Ayşe") }
        await bekle { soruldu && k.bekleyen != nil }
        #expect(k.bekleyen != nil)
        k.yanitla(false, id: k.bekleyen?.id)
        #expect(await t.value == false)
    }
}
