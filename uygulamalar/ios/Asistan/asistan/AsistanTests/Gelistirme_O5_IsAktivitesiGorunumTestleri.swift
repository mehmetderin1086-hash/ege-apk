import Foundation
import Testing
@testable import Asistan

/// O5: Live Activity "Durduruldu" ve "Bağlantı koptu" görünümleri, geriye uyumlu durum çözücü, bayatlık tarihi.
@Suite("O5-Live Activity görünümü") @MainActor
struct Gelistirme_O5_IsAktivitesiGorunumTestleri {
    private typealias Durum = AsistanIsNitelikleri.ContentState

    private func durum(bitti: Bool = false, hata: Bool = false, durduruldu: Bool = false) -> Durum {
        var s = Durum(adim: "Düşünüyor")
        s.bitti = bitti; s.hata = hata; s.durduruldu = durduruldu
        return s
    }

    // MARK: (a) hal() öncelik sırası

    @Test func halBirlesimleri() {
        // Durdurulan iş hata bayrağı taşısa da (bitisMetni) "Durduruldu" görünür; bayatlık bitmiş işi etkilemez.
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true, hata: true, durduruldu: true), bayat: false) == .durduruldu)
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true, hata: true, durduruldu: true), bayat: true) == .durduruldu)
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true, hata: true), bayat: false) == .hata)
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true, hata: true), bayat: true) == .hata)
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true), bayat: false) == .hazir)
        #expect(IsAktivitesiGorunum.hal(durum(bitti: true), bayat: true) == .hazir)
        #expect(IsAktivitesiGorunum.hal(durum(), bayat: true) == .koptu)
        #expect(IsAktivitesiGorunum.hal(durum(), bayat: false) == .calisiyor)
    }

    @Test func baslikSimgeVeAdimMetni() {
        #expect(IsAktivitesiGorunum.baslik(.durduruldu) == "Durduruldu")
        #expect(IsAktivitesiGorunum.simge(.durduruldu) == "stop.circle.fill")
        #expect(IsAktivitesiGorunum.baslik(.hata) == "Tamamlanamadı")
        #expect(IsAktivitesiGorunum.baslik(.hazir) == "Hazır")
        #expect(IsAktivitesiGorunum.baslik(.koptu) == "Bağlantı koptu")
        #expect(IsAktivitesiGorunum.simge(.koptu) == "exclamationmark.arrow.circlepath")
        #expect(IsAktivitesiGorunum.baslik(.calisiyor) == "Asistan çalışıyor")
        let s = durum()
        #expect(IsAktivitesiGorunum.adimMetni(s, .koptu) == "Durumu görmek için uygulamayı aç")
        #expect(IsAktivitesiGorunum.adimMetni(s, .calisiyor) == "Düşünüyor")
    }

    // MARK: (b) Geriye uyumlu çözücü

    @Test func eskiDurumCozulur() throws {
        let eski = Data(#"{"adim":"x"}"#.utf8)
        let s = try JSONDecoder().decode(Durum.self, from: eski)
        #expect(s.adim == "x" && !s.durduruldu && s.tamamlanan == 0 && s.toplam == 0 && !s.bitti && !s.hata && s.sureSn == 0)
        // Yeni alan gidiş-dönüşte korunur; adim yoksa çözme başarısız olur.
        var yeni = durum(bitti: true, hata: true, durduruldu: true); yeni.sureSn = 12
        #expect(try JSONDecoder().decode(Durum.self, from: JSONEncoder().encode(yeni)) == yeni)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Durum.self, from: Data("{}".utf8)) }
    }

    /// ActivityKit durumu uzantı sürecinde ve `Task.detached` içinde çözer: uyum yalıtımsız derlenmeli.
    @Test func yalitimsizBaglamdaCozulur() async throws {
        let s = try await Task.detached {
            try JSONDecoder().decode(AsistanIsNitelikleri.ContentState.self, from: Data(#"{"adim":"y","bitti":true}"#.utf8))
        }.value
        #expect(s.adim == "y" && s.bitti && !s.durduruldu)
    }

    // MARK: (c) Bayatlık

    @Test func bayatlikTarihiDoksanSaniyeSonra() {
        let simdi = Date(timeIntervalSince1970: 1_000_000)
        #expect(IsAktivitesi.bayatlikTarihi(simdi) == simdi.addingTimeInterval(90))
        #expect(IsAktivitesi.bayatlikSn == 90)
    }

    @Test func ayniDurumOtuzSaniyedeBirYenilenir() {
        let simdi = Date(timeIntervalSince1970: 1_000_000), s = durum()
        #expect(!IsAktivitesi.yenilenmeli(durum: s, son: s, sonYenileme: simdi.addingTimeInterval(-10), simdi: simdi))
        #expect(IsAktivitesi.yenilenmeli(durum: s, son: s, sonYenileme: simdi.addingTimeInterval(-31), simdi: simdi))
        var farkli = s; farkli.adim = "Yanıt yazılıyor"
        #expect(IsAktivitesi.yenilenmeli(durum: farkli, son: s, sonYenileme: simdi, simdi: simdi))
        #expect(IsAktivitesi.yenilenmeli(durum: s, son: nil, sonYenileme: simdi, simdi: simdi))
    }

    // MARK: (d) bitisMetni sözleşmesi değişmedi (DuzeltmeA2BeyinZincirTestleri.durdurulanIsYanitHazirGostermez)

    @Test func bitisMetniDegismedi() {
        let durdu = IsAktivitesi.bitisMetni(hata: false, durduruldu: true)
        #expect(durdu.adim == "Durduruldu" && durdu.hata)
    }
}
