import Foundation
import Testing
@testable import Asistan

/// Geliştirme O6: video oynarken ses oturumu bırakılmaz (SesCalar.acikVideo sayacı + medyaCaliyor);
/// medya bitince oturum bırakma kararı yeniden verilir (SesCalar.bitti). Ağsız, oynatıcısız, saf mantık.
@Suite("O6 medya ve ses oturumu") @MainActor
struct Gelistirme_O6_Testleri {

    @Test func medyaCaliyorKarari() {
        #expect(SesCalar.medyaCaliyor(oynuyor: false, acikVideo: 1))
        #expect(SesCalar.medyaCaliyor(oynuyor: true, acikVideo: 0))
        #expect(SesCalar.medyaCaliyor(oynuyor: true, acikVideo: 2))
        #expect(!SesCalar.medyaCaliyor(oynuyor: false, acikVideo: 0))
    }

    @Test func videoSayaciEksiyeDusmez() {
        let cal = SesCalar()
        cal.videoAcildi(); cal.videoAcildi()
        #expect(cal.acikVideo == 2)
        #expect(cal.medyaCaliyor)
        cal.videoKapandi(); cal.videoKapandi(); cal.videoKapandi()
        #expect(cal.acikVideo == 0)
        #expect(!cal.medyaCaliyor)
    }

    @Test func bittiYalnizSonVideoKapanincaCagrilir() {
        let cal = SesCalar()
        var sayac = 0
        cal.bitti = { sayac += 1 }
        cal.videoAcildi(); cal.videoAcildi()
        cal.videoKapandi()          // bir video hâlâ açık: oturum bırakılmamalı, bildirim yok
        #expect(sayac == 0)
        cal.videoKapandi()          // son video kapandı: karar yeniden verilsin
        #expect(sayac == 1)
    }

    @Test func videoAcikkenOturumBirakilmaz() {
        let videoAcik = SesCalar.medyaCaliyor(oynuyor: false, acikVideo: 1)
        #expect(!SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                            gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                            medyaCaliyor: videoAcik))
        let videoKapali = SesCalar.medyaCaliyor(oynuyor: false, acikVideo: 0)
        #expect(SesOturumu.oturumBirakilir(dinleyiciCalisiyor: false, konusuyor: false, sozKesmeCalisiyor: false,
                                           gercekZamanli: false, beyinBosta: true, uyandirmaBekliyor: false,
                                           medyaCaliyor: videoKapali))
    }
}
