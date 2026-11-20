import Testing
import Foundation
@testable import Asistan

/// O2: Motorlu indirme kendi sürdürülen işlem görevini (BGContinuedProcessingTask) ister. Ağ, izin ve gerçek model
/// gerekmez; simülatörde gönderim hata atabilir, yakalanıp günlüğe yazılır (çökmemesi sınanır).
@Suite("O2-motorlu indirme sürdürme", .serialized)
@MainActor
struct AcikIsO2IndirmeSurdurmeTestleri {
    /// Etiketli demeti #expect içinde karşılaştırmak için diziye çevirir: [tamamlanan, toplam].
    func birim(_ alinan: Int64, _ toplam: Int64) -> [Int64] {
        let b = IndirmeSurdurucu.birimler(alinan: alinan, toplam: toplam)
        return [b.tamamlanan, b.toplam]
    }

    @Test func kimlikJokerKapsamindaVeHerIstekteYeni() {
        let a = IndirmeSurdurucu.yeniKimlik(), b = IndirmeSurdurucu.yeniKimlik()
        // Info.plist: com.mehmetderin.asistan.gorev.* joker kimliği kapsamalı.
        #expect(a.hasPrefix(ArkaPlanSurdurucu.onek + "."))
        // Aynı kayıt yeniden başlatılınca aynı kimlik ikinci kez kaydedilmemeli (yeniden kayıt çöker).
        #expect(a != b)
        // Tek parça: önekten sonra başka nokta yok.
        #expect(!a.dropFirst(ArkaPlanSurdurucu.onek.count + 1).contains("."))
    }

    @Test func birimlerBilinenToplamda() {
        #expect(birim(50, 100) == [50, 100])
        #expect(birim(500, 100) == [100, 100])
        #expect(IndirmeSurdurucu.birimler(alinan: -1, toplam: 100).tamamlanan == 0)
    }

    @Test func birimlerBilinmeyenToplamda() {
        #expect(birim(0, 0) == [1, 100])
        #expect(birim(10_000_000, 0) == [3, 100])
        #expect(birim(50_000_000_000, -1) == [90, 100])
        #expect(birim(-5, 0) == [1, 100])
    }

    @Test func gorevIstemekVeKapatmakCokertmez() {
        let s = IndirmeSurdurucu.ortak
        let id = UUID()
        s.baslat(id, ad: "test")
        s.ilerle(id, alinan: 10, toplam: 100)
        s.adiGuncelle(id, "Test videosu")
        s.asama(id, "Birleştiriliyor…")
        s.bitir(id, basarili: true)
        #expect(s.etkinSayisi == 0)
    }

    @Test func ayniKaydiYenidenBaslatmakCokertmez() {
        // motorluTekrar aynı kayıt id'siyle yeniden başlar: her istek yeni sistem kimliği almalı.
        let s = IndirmeSurdurucu.ortak
        let id = UUID()
        s.baslat(id, ad: "ilk")
        s.bitir(id, basarili: false)
        s.baslat(id, ad: "yeniden")
        s.bitir(id, basarili: true)
        #expect(s.etkinSayisi == 0)
    }

    @Test func bitmedenYenidenBaslatmakEskiIstegiUnutur() {
        let s = IndirmeSurdurucu.ortak
        let id = UUID()
        s.baslat(id, ad: "bir")
        s.baslat(id, ad: "iki")
        #expect(s.etkinSayisi <= 1)
        s.bitir(id, basarili: false)
        #expect(s.etkinSayisi == 0)
    }

    @Test func bilinmeyenKayitIcinCagrilarEtkisiz() {
        let s = IndirmeSurdurucu.ortak
        let id = UUID()
        s.ilerle(id, alinan: 1, toplam: 2)
        s.asama(id, "Birleştiriliyor…")
        s.birlestirmeIlerle(id, oran: 0.5)
        s.adiGuncelle(id, "x")
        s.bitir(id, basarili: true)
        #expect(s.etkinSayisi == 0)
    }
}
