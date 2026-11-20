import Foundation
import Testing
@testable import Asistan

/// P1.12: sesli kipte işaret tonları ve "söz bitti → ilk ses" ölçümü. Ağ, izin ve gerçek ses gerektirmez.
@Suite("Gelistirme P1.12 · İşaret sesleri ve sesli tur ölçümü") @MainActor
struct Gelistirme_P1_12_SesIsaretleriTestleri {
    // MARK: Ton üretimi

    @Test(arguments: IsaretTuru.allCases)
    func tonSuresiGenlikVeSonum(_ t: IsaretTuru) {
        let oran = 44_100.0
        let o = SesIsaretleri.ornekler(t, oran: oran)
        let sure = Double(o.count) / oran
        #expect(sure >= 0.04 && sure <= 0.25, "süre: \(sure)")
        #expect(abs(sure - SesIsaretleri.sure(t)) < 0.002)
        let tepe = o.map { abs($0) }.max() ?? 0
        #expect(tepe <= 0.3)
        #expect(tepe > 0.2)   // duyulur genlik (0,25)
        #expect(abs(o.first ?? 1) < 0.01)
        #expect(abs(o.last ?? 1) < 0.01)
    }

    @Test func turlerBirbirindenFarkli() {
        let hepsi = IsaretTuru.allCases.map { SesIsaretleri.ornekler($0) }
        for i in hepsi.indices {
            for j in hepsi.indices where j > i { #expect(hepsi[i] != hepsi[j]) }
        }
    }

    @Test func dusukOrandaDaSonumlu() {
        // 16 kHz gibi farklı örnekleme oranında da süre korunur ve uçlar sessizdir.
        let o = SesIsaretleri.ornekler(.dinliyorum, oran: 16_000)
        #expect(o.count == 2240)
        #expect(abs(o[0]) < 0.01 && abs(o[o.count - 1]) < 0.01)
    }

    @Test func wavVerisiUretilir() {
        let o = SesIsaretleri.ornekler(.aldim)
        let wav = WhisperIstemcisi.wav(o, oran: 44_100)
        #expect(wav.count == 44 + o.count * 2)
        #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
    }

    // MARK: Sesli tur ölçümü

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func dortAsamaDogru() throws {
        let olcum = SesTurOlcumu(sonSes: t0, kesinlesme: t0 + 0.8, gonderim: t0 + 1.0, ilkMetin: t0 + 1.7,
                                 ilkTTS: t0 + 1.8, ilkOynatma: t0 + 2.5, kip: "live")
        let a = try #require(olcum.asamalar())
        #expect(a.map(\.tur) == ["ses_tur", "ses_tur_bekleme", "ses_tur_model", "ses_tur_tts"])
        let s = Dictionary(uniqueKeysWithValues: a.map { ($0.tur, $0.sure) })
        #expect(abs(s["ses_tur"]! - 2.5) < 1e-6)
        #expect(abs(s["ses_tur_bekleme"]! - 0.8) < 1e-6)
        #expect(abs(s["ses_tur_model"]! - 0.7) < 1e-6)
        #expect(abs(s["ses_tur_tts"]! - 0.7) < 1e-6)
    }

    @Test func ilkOynatmaYoksaNil() {
        let olcum = SesTurOlcumu(sonSes: t0, kesinlesme: t0 + 0.5, gonderim: t0 + 0.6, ilkMetin: t0 + 1, kip: "normal")
        #expect(olcum.asamalar() == nil)
        #expect(SesTurOlcumu(sonSes: t0, ilkOynatma: t0 + 2, kip: "normal").asamalar() == nil)   // kesinleşme yok
    }

    @Test func sonSesYoksaKesinlesmeTabanAlinir() throws {
        for son in [Date.distantPast, nil] as [Date?] {
            let olcum = SesTurOlcumu(sonSes: son, kesinlesme: t0, ilkOynatma: t0 + 1.5, kip: "eller-serbest")
            let a = try #require(olcum.asamalar())
            #expect(a.count == 2)
            #expect(abs(a[0].sure - 1.5) < 1e-6)
            #expect(a[1] == .init(tur: "ses_tur_bekleme", sure: 0))
        }
    }

    @Test func bozukSiradakiAraAsamaAtlanir() throws {
        // Karar: ilk metin gönderimden önceyse yalnız ses_tur_model atlanır; ana süre yazılır.
        let olcum = SesTurOlcumu(sonSes: t0, kesinlesme: t0 + 0.5, gonderim: t0 + 1.2, ilkMetin: t0 + 1.0,
                                 ilkTTS: t0 + 1.4, ilkOynatma: t0 + 2, kip: "normal")
        let a = try #require(olcum.asamalar())
        #expect(a.map(\.tur) == ["ses_tur", "ses_tur_bekleme", "ses_tur_tts"])
    }

    @Test func anaSiraBozuksaNil() {
        // İlk ses kesinleşmeden önce: ölçüm geçersiz, hiç yazılmaz.
        let olcum = SesTurOlcumu(sonSes: t0, kesinlesme: t0 + 1, ilkOynatma: t0 + 0.5, kip: "normal")
        #expect(olcum.asamalar() == nil)
    }

    @Test func sonSesKesinlesmedenSonraysaKesinlesmeTaban() throws {
        let olcum = SesTurOlcumu(sonSes: t0 + 2, kesinlesme: t0, ilkOynatma: t0 + 1, kip: "normal")
        let a = try #require(olcum.asamalar())
        #expect(abs(a[0].sure - 1) < 1e-6)
        #expect(a[1].sure == 0)
    }

    // MARK: SaglikMerkezi yüzdelikleri

    @Test func medyanVeP90() throws {
        let ad = "saglik.p112.\(UUID())"
        let d = try #require(UserDefaults(suiteName: ad)); defer { d.removePersistentDomain(forName: ad) }
        let m = SaglikMerkezi(defaults: d)
        for s in 1...10 { m.kaydet("ses_tur", sure: Double(s), etiket: "live|azure") }
        let o = try #require(m.ozet("ses_tur"))
        #expect(o.adet == 10)
        #expect(o.medyanMs >= 5000 && o.medyanMs <= 5500)
        #expect(o.p90Ms == 9000)
        #expect(o.p95Ms == 10_000)
        #expect(o.ortalamaMs == 5500)
    }

    @Test func yuzdelikKenarDurumlari() {
        #expect(SaglikMerkezi.yuzdelik([42], 0.5) == 42)
        #expect(SaglikMerkezi.yuzdelik([42], 0.95) == 42)
        #expect(SaglikMerkezi.yuzdelik([], 0.5) == 0)
        #expect(SaglikMerkezi.yuzdelik([1, 2, 3, 4], 0) == 1)
        #expect(SaglikMerkezi.yuzdelik([1, 2, 3, 4], 1) == 4)
        #expect(SaglikMerkezi.sinir == 300)
    }

    // MARK: Ayar

    @Test func isaretSesleriVarsayilanAcikVeKalici() throws {
        let ad = "ayar.p112.\(UUID())"
        let d = try #require(UserDefaults(suiteName: ad)); defer { d.removePersistentDomain(forName: ad) }
        let a = Ayarlar(defaults: d)
        #expect(a.isaretSesleri == true)
        a.isaretSesleri = false
        #expect(Ayarlar(defaults: d).isaretSesleri == false)
    }

    @Test func kapaliykenCalinmaz() async {
        let isaret = SesIsaretleri()
        isaret.acik = { false }
        let bas = ContinuousClock.now
        await isaret.cal(.dinliyorum)
        // Kapalıyken beklemeden döner (ton süresi kadar uyumaz).
        #expect(ContinuousClock.now - bas < .milliseconds(160))
    }
}
