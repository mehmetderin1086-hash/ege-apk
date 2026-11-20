import Foundation
import Testing
@testable import Asistan

@Suite("Sağlık ve hız merkezi") @MainActor
struct SaglikMerkeziTestleri {
    @Test func ozetVeGizlilikSiniri() throws {
        let ad = "saglik.test.\(UUID())"
        let d = try #require(UserDefaults(suiteName: ad)); defer { d.removePersistentDomain(forName: ad) }
        let m = SaglikMerkezi(defaults: d)
        m.kaydet("model_ilk_metin", sure: 1, etiket: String(repeating: "x", count: 200))
        m.kaydet("model_ilk_metin", sure: 2, basarili: false, etiket: "gpt")
        let o = try #require(m.ozet("model_ilk_metin"))
        #expect(o.adet == 2)
        #expect(o.ortalamaMs == 1500)
        #expect(o.p95Ms == 2000)
        #expect(o.medyanMs == 1000)
        #expect(o.p90Ms == 2000)
        #expect(o.basariOrani == 0.5)
        #expect(m.olcumler.first?.etiket?.count == 80)
        #expect(SaglikMerkezi(defaults: d).olcumler.count == 2)
    }

    @Test func kayitSiniriVeTemizleme() throws {
        let ad = "saglik.test.\(UUID())"
        let d = try #require(UserDefaults(suiteName: ad)); defer { d.removePersistentDomain(forName: ad) }
        let m = SaglikMerkezi(defaults: d)
        for i in 0..<320 { m.kaydet("tts", sure: Double(i) / 1000) }
        #expect(m.olcumler.count == 300)
        m.temizle()
        #expect(m.olcumler.isEmpty)
    }
}
