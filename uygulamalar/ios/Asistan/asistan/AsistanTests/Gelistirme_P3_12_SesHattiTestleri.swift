import AVFoundation
import Foundation
import Testing
@testable import Asistan

/// P3.12: ses hattı (yol seçimi, ilk ses hızı, bulut ses devre kesicisi, akıllı konuşma sonu, TTS önbelleği,
/// kumanda kararı, okuma kontrolleri). Ağ, izin ve gerçek ses gerektirmez.
@Suite("Gelistirme P3.12 · Ses hattı") @MainActor
struct Gelistirme_P3_12_SesHattiTestleri {

    // MARK: YolSecici

    @Test func varsayilanKulaklikTercihiKapaliDahiliKalir() {
        #expect(YolSecici.sec(cikislar: [.bluetoothA2DP], girisler: [.builtInMic], kulaklikTercih: false, hfpYasakli: false) == .dahili)
        #expect(YolSecici.sec(cikislar: [.builtInSpeaker], girisler: [.builtInMic], kulaklikTercih: false, hfpYasakli: false) == .dahili)
    }

    @Test func bluetoothCikisVeTercihKulaklikSecer() {
        #expect(YolSecici.sec(cikislar: [.bluetoothA2DP], girisler: [.builtInMic], kulaklikTercih: true, hfpYasakli: false) == .bluetooth)
        #expect(YolSecici.sec(cikislar: [.bluetoothHFP], girisler: [.bluetoothHFP, .builtInMic], kulaklikTercih: true, hfpYasakli: false) == .bluetooth)
        #expect(YolSecici.sec(cikislar: [.bluetoothLE], girisler: [], kulaklikTercih: true, hfpYasakli: false) == .bluetooth)
    }

    @Test func hfpYasakliysaDahili() {
        #expect(YolSecici.sec(cikislar: [.bluetoothA2DP], girisler: [.builtInMic], kulaklikTercih: true, hfpYasakli: true) == .dahili)
    }

    @Test func kabloluMikrofonOncelikli() {
        #expect(YolSecici.sec(cikislar: [.headphones], girisler: [.headsetMic, .builtInMic], kulaklikTercih: false, hfpYasakli: false) == .kablolu)
        #expect(YolSecici.sec(cikislar: [.bluetoothA2DP], girisler: [.headsetMic], kulaklikTercih: true, hfpYasakli: false) == .kablolu)
    }

    @Test func kategoriSecenekleri() {
        let bt = YolSecici.secenekler(.bluetooth, kumanda: false)
        #expect(bt.contains(.allowBluetoothHFP))
        #expect(bt.contains(.duckOthers))
        #expect(bt.contains(.allowBluetoothA2DP))
        #expect(bt.contains(.defaultToSpeaker))
        #expect(!YolSecici.secenekler(.bluetooth, kumanda: true).contains(.duckOthers))
        // Dahili (varsayılan) = bugünkü kategori: HFP yok, müzik kısılır.
        #expect(YolSecici.secenekler(.dahili, kumanda: false) == [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
        #expect(!YolSecici.secenekler(.kablolu, kumanda: false).contains(.allowBluetoothHFP))
    }

    @Test func hedefPortlar() {
        #expect(YolSecici.hedefPort(.bluetooth) == .bluetoothHFP)
        #expect(YolSecici.hedefPort(.kablolu) == .headsetMic)
        #expect(YolSecici.hedefPort(.dahili) == .builtInMic)
    }

    @Test func hfpYasagiSuresi() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(!YolSecici.yasakSurer(bitis: nil, simdi: t0))
        #expect(YolSecici.yasakSurer(bitis: t0.addingTimeInterval(300), simdi: t0.addingTimeInterval(299)))
        #expect(!YolSecici.yasakSurer(bitis: t0.addingTimeInterval(300), simdi: t0.addingTimeInterval(301)))
    }

    // MARK: CumleBolucu ilk ses hızı

    @Test func ilkUzunVirgulObegiAyriDoner() {
        var b = CumleBolucu()
        let ilk = "Bugün okulda biyoloji dersinde hücre bölünmesini anlattım, öğrenciler çok ilgiliydi"
        #expect(b.yeniCumleler(ilk) == ["Bugün okulda biyoloji dersinde hücre bölünmesini anlattım,"])
        #expect(b.ilkVerildi)
        // İkinci uzun virgül cümle sonunu bekler.
        let ikinci = ilk + " ve birçok soru sordular, bazıları da defterlerine not aldı. Son"
        #expect(b.yeniCumleler(ikinci) == ["öğrenciler çok ilgiliydi ve birçok soru sordular, bazıları da defterlerine not aldı."])
    }

    @Test func kisaVirgulBolunmez() {
        var b = CumleBolucu()
        #expect(b.yeniCumleler("Merhaba, bugün hava güzel ve sıcaklık oldukça yüksek olacak") == [])
    }

    @Test func ilkVirgulKapaliEskiDavranis() {
        var b = CumleBolucu()
        b.ilkVirgul = false
        #expect(b.yeniCumleler("Bugün okulda biyoloji dersinde hücre bölünmesini anlattım, öğrenciler çok ilgiliydi") == [])
        #expect(!b.ilkVerildi)
    }

    @Test func virgulSonrasiKarakterGelmedenBolunmez() {
        var b = CumleBolucu()
        // "1,5" ondalık olabilir: virgül akışın sonundaysa beklenir.
        #expect(b.yeniCumleler("Bu çözeltinin derişimi litrede tam olarak bir virgül 1,") == [])
        #expect(b.yeniCumleler("Bu çözeltinin derişimi litrede tam olarak bir virgül 1,5 mol") == [])
    }

    @Test func sifirlaIlkParcayiYenidenAcar() {
        var b = CumleBolucu()
        _ = b.yeniCumleler("Kısa cümle. ")
        #expect(b.ilkVerildi)
        b.sifirla()
        #expect(!b.ilkVerildi)
        #expect(b.islenen == 0)
    }

    // MARK: BulutSesDevresi

    @Test func devreIkiHatadaAcilirBesDakikaSurer() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var d = BulutSesDevresi()
        d.hata(simdi: t0)
        #expect(!d.yerelMi(simdi: t0), "tek hata devreyi açmaz")
        d.hata(simdi: t0.addingTimeInterval(1))
        #expect(d.yerelMi(simdi: t0.addingTimeInterval(2)))
        #expect(d.yerelMi(simdi: t0.addingTimeInterval(300)))
        #expect(!d.yerelMi(simdi: t0.addingTimeInterval(1 + 301)), "süre dolunca yarı açık: bulut yeniden denenir")
    }

    @Test func yariAcikDenemeHatasiYenidenAcar() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var d = BulutSesDevresi()
        d.hata(simdi: t0); d.hata(simdi: t0)
        let sonra = t0.addingTimeInterval(400)
        #expect(!d.yerelMi(simdi: sonra))
        d.hata(simdi: sonra)
        #expect(d.yerelMi(simdi: sonra.addingTimeInterval(10)), "yarı açık deneme düştü: yeniden 5 dk")
    }

    @Test func basariSifirlar() {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var d = BulutSesDevresi()
        d.hata(simdi: t0); d.hata(simdi: t0)
        d.basari()
        #expect(!d.yerelMi(simdi: t0))
        #expect(d.artArda == 0)
        #expect(d.acikBitis == nil)
        d.hata(simdi: t0)
        #expect(!d.yerelMi(simdi: t0), "başarıdan sonra tek hata yine açmaz")
    }

    // MARK: UcNoktasiKarari

    @Test func konusmaSonuBeklemeleri() {
        #expect(UcNoktasiKarari.bekleme(metin: "saat kaç", taban: 1200) == UcNoktasiKarari.kisaMs)
        #expect(UcNoktasiKarari.bekleme(metin: "yarın sabah ve", taban: 1200) == UcNoktasiKarari.uzunMs)
        #expect(UcNoktasiKarari.bekleme(metin: "annemi ara,", taban: 1200) == UcNoktasiKarari.uzunMs)
        #expect(UcNoktasiKarari.bekleme(metin: "İstanbul'da yarın hava nasıl olacak acaba", taban: 1200) == 1200)
        #expect(UcNoktasiKarari.kisaMs == 850 && UcNoktasiKarari.uzunMs == 1600)
        // Kısa ama soru biçimli olmayan metin yarım olabilir: kipin tabanı.
        #expect(UcNoktasiKarari.bekleme(metin: "annemi ara", taban: 1200) == 1200)
        #expect(UcNoktasiKarari.bekleme(metin: "fener", taban: 1200) == 1200)
        #expect(UcNoktasiKarari.bekleme(metin: "Saat kaç?", taban: 1200) == 850)
        #expect(UcNoktasiKarari.bekleme(metin: "yağmur yağıyor mu", taban: 1200) == 850)
        #expect(UcNoktasiKarari.bekleme(metin: "saat kaç", taban: 700) == 700, "kısa kural tabanı uzatmaz")
    }

    @Test func bagclarVeIkiNokta() {
        #expect(UcNoktasiKarari.bekleme(metin: "bugün markete gideceğim ya da", taban: 1200) == 1600)
        #expect(UcNoktasiKarari.bekleme(metin: "Listeye şunları ekle:", taban: 1200) == 1600)
        #expect(UcNoktasiKarari.bekleme(metin: "Yarın toplantı var ÇÜNKÜ", taban: 1200) == 1600, "Türkçe büyük harf")
        #expect(UcNoktasiKarari.bekleme(metin: "   ", taban: 1200) == 1200)
    }

    @Test func dinleyiciAkilliSonVarsayilanKapali() {
        #expect(SesDinleyici().akilliSon == false)
    }

    // MARK: TTSOnbellegi

    @Test func onbellekAnahtari() {
        let a = TTSOnbellegi.anahtar(metin: "  Tamam, hatırlatıcı kuruldu. ", kimlik: "azure:Elif")
        #expect(a == TTSOnbellegi.anahtar(metin: "TAMAM, HATIRLATICI KURULDU.", kimlik: "azure:Elif"))
        #expect(a != TTSOnbellegi.anahtar(metin: "Tamam, hatırlatıcı kuruldu.", kimlik: "openai:marin"))
        #expect(a.count == 64)
        #expect(TTSOnbellegi.enUzunMetin == 80 && TTSOnbellegi.enCokDosya == 300)
    }

    @Test func onbellekYazOkuVeSinir() throws {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "tts-onbellek-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: klasor) }
        let veri = Data(repeating: 7, count: 100)
        #expect(TTSOnbellegi.oku(metin: "a", kimlik: "azure:Elif", klasor: klasor) == nil)
        func yaz(_ m: String, yas: TimeInterval) throws {
            TTSOnbellegi.yaz(veri, metin: m, kimlik: "azure:Elif", klasor: klasor, sinir: 3)
            let yol = TTSOnbellegi.dosya(metin: m, kimlik: "azure:Elif", klasor: klasor).path(percentEncoded: false)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-yas)], ofItemAtPath: yol)
        }
        try yaz("bir", yas: 100)
        try yaz("iki", yas: 50)
        try yaz("üç", yas: 10)
        try yaz("dört", yas: 0)   // sınır aşıldı: en eski ("bir") silinir
        let dosyalar = try FileManager.default.contentsOfDirectory(atPath: klasor.path(percentEncoded: false))
        #expect(dosyalar.count == 3)
        #expect(!FileManager.default.fileExists(atPath: TTSOnbellegi.dosya(metin: "bir", kimlik: "azure:Elif", klasor: klasor).path(percentEncoded: false)))
        #expect(TTSOnbellegi.oku(metin: "DÖRT", kimlik: "azure:Elif", klasor: klasor) == veri)
        #expect(TTSOnbellegi.oku(metin: "dört", kimlik: "openai:marin", klasor: klasor) == nil)
    }

    @Test func kucukVeriOnbellegeYazilmaz() {
        let klasor = FileManager.default.temporaryDirectory.appending(path: "tts-onbellek-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: klasor) }
        TTSOnbellegi.yaz(Data(repeating: 1, count: 10), metin: "x", kimlik: "azure:Elif", klasor: klasor)
        #expect(TTSOnbellegi.oku(metin: "x", kimlik: "azure:Elif", klasor: klasor) == nil)
    }

    // MARK: Kumanda kararı

    @Test func kumandaEslemesi() {
        typealias K = KumandaKomutlari
        #expect(K.karar(.oynatDuraklat, konusuyor: true, duraklatildi: false, dinliyor: false) == .duraklat)
        #expect(K.karar(.oynatDuraklat, konusuyor: true, duraklatildi: true, dinliyor: false) == .devam)
        #expect(K.karar(.oynatDuraklat, konusuyor: false, duraklatildi: false, dinliyor: true) == .gonder)
        #expect(K.karar(.oynatDuraklat, konusuyor: false, duraklatildi: false, dinliyor: false) == .dokun)
        #expect(K.karar(.sonraki, konusuyor: true, duraklatildi: false, dinliyor: false) == .sozuAl)
        #expect(K.karar(.hiz(1.5), konusuyor: true, duraklatildi: false, dinliyor: false) == .hiz(1.5))
        #expect(K.karar(.duraklat, konusuyor: false, duraklatildi: false, dinliyor: false) == .hicbiri)
        #expect(K.karar(.oynat, konusuyor: true, duraklatildi: false, dinliyor: false) == .hicbiri)
    }

    @Test func kumandaBaglanmadanCozmekGuvenli() {
        let k = KumandaKomutlari()
        k.coz()
        #expect(!k.bagli)
        #expect(!YolSecici.bayraklar.kumandaEtkin)
    }

    // MARK: Okuma kontrolleri

    @Test func hizSiniriVeEtiket() {
        #expect(Konusmaci.hizSinirla(3) == 1.6)
        #expect(Konusmaci.hizSinirla(0.1) == 0.8)
        #expect(Konusmaci.hizSinirla(.nan) == 1)
        #expect(Konusmaci.sentezHizi(1.6) <= AVSpeechUtteranceMaximumSpeechRate)
        #expect(Konusmaci.sentezHizi(1.25) > Konusmaci.sentezHizi(1))
        #expect(OkumaCubugu.hizEtiketi(1) == "1×")
        #expect(OkumaCubugu.hizEtiketi(1.25) == "1,25×")
        #expect(OkumaCubugu.hizEtiketi(1.5) == "1,5×")
    }

    @Test func konusmuyorkenDuraklatEtkisiz() {
        let k = Konusmaci()
        k.duraklat()
        #expect(!k.duraklatildi)
        k.devamEt()
        #expect(!k.duraklatildi)
        k.hiziDegistir(9)
        #expect(k.hiz == 1.6)
    }

    @Test func ayarVarsayilanlari() throws {
        let ad = "p312-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: ad))
        defer { d.removePersistentDomain(forName: ad) }
        let a = Ayarlar(defaults: d)
        #expect(a.kulaklikMikrofonu == false, "HFP varsayılan kapalı (14 Eki kararı)")
        #expect(a.kumanda == false, "müzik varsayılan kısılır, durmaz")
        #expect(a.akilliKonusmaSonu)
        #expect(a.ilkSesHizli)
        #expect(a.okumaHizi == 1.0)
        // Varsayılan ses ve Live motoru değişmez.
        #expect(a.sesKimligi == "azure:Elif")
        #expect(a.canliMotor == "claude")
        let k = Konusmaci()
        a.okumaHizi = 1.25
        k.ayarlar = a
        #expect(k.hiz == 1.25)
        k.hiziDegistir(1.5)
        #expect(a.okumaHizi == 1.5)
    }
}
