import Foundation
import Testing
@testable import Asistan

/// O1: söz kesme motoru sessizlikte açılır, taban ölçümü ve karar yalnız oynatma başlayınca işler.
@MainActor
struct SozKesmeOlcumO1Testleri {
    /// `sure` saniye boyunca `db` düzeyinde 0,05 sn'lik adımlar besler; herhangi bir adım tetiklediyse true.
    private func besle(_ kapi: inout SozKesmeKapisi, db: Float, sure: Double, dt: Double = 0.05) -> Bool {
        var tetik = false
        for _ in 0..<Int((sure / dt).rounded()) {
            if kapi.adim(db: db, dt: dt) { tetik = true }
        }
        return tetik
    }

    @Test func olcumAcilmadanYuksekSesTetiklemez() {
        var kapi = SozKesmeKapisi()
        #expect(!kapi.olcumAcik)
        #expect(!besle(&kapi, db: -10, sure: 2))
    }

    @Test func olcumBasladiktanSonraTabanUstuSesTetikler() {
        var kapi = SozKesmeKapisi()
        kapi.olcumuBaslat()
        #expect(kapi.olcumAcik)
        #expect(!besle(&kapi, db: -45, sure: 0.6))
        #expect(besle(&kapi, db: -20, sure: 0.4))
    }

    @Test func olcumuBaslatTabanOrnekleriniSifirlar() {
        var kapi = SozKesmeKapisi()
        kapi.olcumuBaslat()
        // Önceki turdan kalan yüksek örnekler (taban penceresinin yarısı) yeni tabanı şişirmemeli.
        #expect(!besle(&kapi, db: -10, sure: 0.35))
        kapi.olcumuBaslat()
        #expect(!besle(&kapi, db: -45, sure: 0.6))
        #expect(besle(&kapi, db: -20, sure: 0.4))
    }

    @Test func sifirlaOlcumuKapatir() {
        var kapi = SozKesmeKapisi()
        kapi.olcumuBaslat()
        _ = besle(&kapi, db: -45, sure: 0.6)
        kapi.sifirla()
        #expect(!kapi.olcumAcik)
        #expect(!besle(&kapi, db: -10, sure: 2))
    }

    @Test func motorAcikDegilkenOlcumuBaslatEtkisiz() {
        let d = SozKesmeDinleyici()
        d.olcumuBaslat()
        #expect(!d.calisiyor)
    }
}
