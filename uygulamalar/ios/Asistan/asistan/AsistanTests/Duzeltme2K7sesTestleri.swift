import Foundation
import Testing
@testable import Asistan

/// İkinci düzeltme turu, ses katmanı: uygulama içi medya çalarken oturum bırakılmaz, durmuş Live motorunda
/// oynatıcı başlatılmaz, goAway planlı ayrılmadır, yeniden bağlanma sıralı dinlemeyle çakışmaz,
/// kamera ve uyandırma onarımı kararları (ağsız, mikrofonsuz, saf mantık).
@Suite("K7-ses düzeltmeleri") @MainActor
struct Duzeltme2K7sesTestleri {

    // MARK: Uygulama içi medya (bulgu 30, 31, 33)

    @Test func sesKartiCalarkenOturumBirakilmaz() {
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                            medyaCaliyor: true))
        // Varsayılan (medya yok) davranış değişmez.
        #expect(SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                           gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false))
        #expect(SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                           gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                           medyaCaliyor: false))
    }

    // MARK: Durmuş motorda play() çökmesi (bulgu 32, 87)

    @Test func motorDurmuskenOynaticiBaslatilmaz() {
        #expect(CanliSesIO.oynatmaKarari(motorCalisiyor: true, askida: false, durduruldu: false) == .cal)
        // Ses yolu değişiminde motor durdu, kesinti yok: yeniden kurulum denenir (play doğrudan çağrılmaz).
        #expect(CanliSesIO.oynatmaKarari(motorCalisiyor: false, askida: false, durduruldu: false) == .yenidenBaslat)
        // Kesinti sürüyor: sessizce vazgeçilir, bitişte gözlemci devam ettirir.
        #expect(CanliSesIO.oynatmaKarari(motorCalisiyor: false, askida: true, durduruldu: false) == .vazgec)
        // Kapatıldı: hiçbir şey yapılmaz.
        #expect(CanliSesIO.oynatmaKarari(motorCalisiyor: false, askida: false, durduruldu: true) == .vazgec)
        #expect(CanliSesIO.oynatmaKarari(motorCalisiyor: true, askida: false, durduruldu: true) == .vazgec)
    }

    // MARK: Gemini goAway (bulgu 89)

    @Test func goAwayPlanliAyrilmaHataHemenKapanir() {
        #expect(GercekZamanliLive.kapanisTuru(["goAway": ["timeLeft": "10s"]]) == .ayrilma)
        #expect(GercekZamanliLive.kapanisTuru(["error": ["message": "x"]]) == .hata)
        // İkisi birden gelirse hata öncelikli.
        #expect(GercekZamanliLive.kapanisTuru(["error": [:] as [String: Any], "goAway": [:] as [String: Any]]) == .hata)
        #expect(GercekZamanliLive.kapanisTuru(["serverContent": ["turnComplete": true]]) == nil)
        #expect(GercekZamanliLive.kapanisTuru([:]) == nil)
    }

    // MARK: Kopan Live'ın yeniden bağlanması (bulgu 88)

    @Test func siraliDinlemeAcildiysaYenidenBaglanilmaz() {
        #expect(SesOturumu.canliYenidenBaglanir(mod: .live, canliMod: true, onPlanda: true, gercekZamanliEtkin: false, sesliKip: false))
        #expect(!SesOturumu.canliYenidenBaglanir(mod: .live, canliMod: true, onPlanda: true, gercekZamanliEtkin: false, sesliKip: true))
        #expect(!SesOturumu.canliYenidenBaglanir(mod: .live, canliMod: true, onPlanda: false, gercekZamanliEtkin: false, sesliKip: false))
        #expect(!SesOturumu.canliYenidenBaglanir(mod: .live, canliMod: true, onPlanda: true, gercekZamanliEtkin: true, sesliKip: false))
        #expect(!SesOturumu.canliYenidenBaglanir(mod: .normal, canliMod: true, onPlanda: true, gercekZamanliEtkin: false, sesliKip: false))
        #expect(!SesOturumu.canliYenidenBaglanir(mod: .live, canliMod: false, onPlanda: true, gercekZamanliEtkin: false, sesliKip: false))
    }

    // MARK: Kamera (bulgu 90)

    @Test func geminiBaglandiysaKameraAcikKalmaz() {
        #expect(SesOturumu.kameraAcikKalir(mod: .live, kullanilabilir: true))
        #expect(!SesOturumu.kameraAcikKalir(mod: .live, kullanilabilir: false))
        #expect(!SesOturumu.kameraAcikKalir(mod: .normal, kullanilabilir: true))
    }

    // MARK: Ses yolu bekçisi sonrası onarım (bulgu 92)

    @Test func uyandirmaKomutPenceresiDeKendiniOnarir() {
        let yol = "Ses yolu değişti; dinleme durdu. Yuvarlağa dokunarak yeniden başlat."
        #expect(SesOturumu.uyandirmaOnarilir(bekliyor: true, uyandirmaKomutunda: false, hata: yol))
        #expect(SesOturumu.uyandirmaOnarilir(bekliyor: false, uyandirmaKomutunda: true, hata: yol))
        // Elle açılan dinleme (Live dahil) kendiliğinden yeniden başlatılmaz.
        #expect(!SesOturumu.uyandirmaOnarilir(bekliyor: false, uyandirmaKomutunda: false, hata: yol))
        // İzin hatası kullanıcı düzeltmeli: onarılmaz.
        #expect(!SesOturumu.uyandirmaOnarilir(bekliyor: false, uyandirmaKomutunda: true, hata: "Mikrofon izni verilmedi."))
        #expect(!SesOturumu.uyandirmaOnarilir(bekliyor: true, uyandirmaKomutunda: false, hata: "Konuşma tanıma kullanılamıyor."))
    }

    @Test func liveEkraniBekciMetniniGosterir() {
        let yol = "Ses yolu değişti; dinleme durdu. Yuvarlağa dokunarak yeniden başlat."
        #expect(SesOturumu.mikrofonHataMetni(yol, live: true) == yol)
        #expect(SesOturumu.mikrofonHataMetni(yol, live: false) == "Mikrofon kullanılamıyor")
        #expect(SesOturumu.mikrofonHataMetni("", live: true) == "Mikrofon kullanılamıyor")
    }
}
