import Foundation
import Testing
@testable import Kagit

@MainActor
@Suite struct KitaplikTestleri {
    private func gecici() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("kagit-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func klasorVeBenzersizAd() async throws {
        let k = Kitaplik(kok: gecici())
        let klasor = try await k.yeniKlasor("Sınavlar")
        #expect(klasor.klasorMu)
        let a = k.benzersizURL(klasor: k.kok, ad: "Sınavlar", uzanti: "")
        #expect(a.lastPathComponent.hasPrefix("Sınavlar 2"))
    }

    @Test func iceAktarTasiCop() async throws {
        let k = Kitaplik(kok: gecici())
        let kaynak = FileManager.default.temporaryDirectory.appendingPathComponent("deneme-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: kaynak)
        let alinan = try await k.iceAktar([kaynak])
        #expect(alinan.count == 1)
        _ = try await k.yeniKlasor("A")
        try await k.tasi(alinan, klasor: "A")
        #expect(k.icerik("A").count == 1)
        try await k.copeAt(k.icerik("A"))
        #expect(k.icerik("A").isEmpty)
        #expect(k.copOgeleri.count == 1)
    }
}

@MainActor
@Suite struct KitaplikIncelemeTestleri {
    private func gecici() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("kagit-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func noktaliKlasorAdiKorunur() async throws {
        let k = Kitaplik(kok: gecici())
        let a = try await k.yeniKlasor("9.A")
        #expect(a.ad == "9.A")
        let b = try await k.yeniKlasor("9.B")
        #expect(b.ad == "9.B")
    }

    @Test func eskiDosyaCopteHemenSilinmez() async throws {
        let k = Kitaplik(kok: gecici())
        let kaynak = FileManager.default.temporaryDirectory.appendingPathComponent("eski-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: kaynak)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86_400)], ofItemAtPath: kaynak.path)
        let alinan = try await k.iceAktar([kaynak])
        // iceAktar kopyada eski tarihi korumayabilir; tarihi elle eskit
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86_400)], ofItemAtPath: alinan[0].url.path)
        await k.tara()
        try await k.copeAt(k.belgeler)
        await k.copuBosalt(gun: 30)
        #expect(k.copOgeleri.count == 1)
    }
}
