import Foundation
import AVFoundation
import Testing
@testable import Asistan

/// P4.3: söz kesmede 1,5 sn ön ses tamponu ve 'Arka planda Hey Asistan' saf kararları. Ağsız, izinsiz, mikrofonsuz.
/// Ön sesin çözümleyiciye verilmesi ve arka planda yeniden dinleme yalnız cihazda doğrulanabilir.
@Suite("P4.3-Ses ön tamponu") @MainActor
struct Gelistirme_P4_3_SesOnTamponTestleri {
    private func suite(_ ad: String) -> UserDefaults {
        let n = "p43-\(ad)-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        d.removePersistentDomain(forName: n)
        return d
    }

    // MARK: (1) kırpma

    @Test func kirpUzunVeridenSonBirBucukSaniyeyiTutar() {
        let oran = 16000.0
        let o = (0..<Int(3 * oran)).map { Float($0) }
        let k = OnSes.kirp(o, oran: oran)
        #expect(k.count == Int(1.5 * oran))
        #expect(k.last == o.last)
        #expect(k.first == o[o.count - Int(1.5 * oran)])
    }

    @Test func kirpKisaVeriyiDegistirmez() {
        let o: [Float] = [0.1, -0.2, 0.3]
        #expect(OnSes.kirp(o, oran: 16000) == o)
        #expect(OnSes.kirp([], oran: 16000).isEmpty)
        #expect(OnSes.kirp(o, oran: 0) == o)
    }

    // MARK: (2) baştaki sessizlik

    @Test func basSessizligiAtSifirlariAtarKonusmayiKorur() {
        let konusma: [Float] = [0.2, -0.3, 0.001, 0.25]
        let o = [Float](repeating: 0, count: 100) + [0.002, -0.003] + konusma
        #expect(OnSes.basSessizligiAt(o) == konusma)
        #expect(OnSes.basSessizligiAt(konusma) == konusma)
    }

    @Test func basSessizligiAtTamamenSessizdeBosDoner() {
        #expect(OnSes.basSessizligiAt([Float](repeating: 0.001, count: 500)).isEmpty)
        #expect(OnSes.basSessizligiAt([]).isEmpty)
    }

    @Test func hazirlaOnceKirparSonraSessizligiAtar() {
        let oran = 1000.0
        // 2 sn: 0,2 sn eski ses (yankı), 1 sn sessizlik, 0,8 sn konuşma. Son 1,5 sn = 0,7 sn sessizlik + 0,8 sn konuşma.
        let o = [Float](repeating: 0.3, count: 200) + [Float](repeating: 0, count: 1000) + [Float](repeating: 0.4, count: 800)
        let h = OnSes.hazirla(o, oran: oran)
        #expect(h.count == 800)
        #expect(h.first == 0.4)
        #expect(h.last == 0.4)
        #expect(SozKesmeDinleyici.onSesSuresi == 1.5)
        #expect(SozKesmeDinleyici.onSesGeriSuresi == 0.5)
    }

    // MARK: (3) halka tampon

    @Test func sesTamponuHalkaBirBucukSaniyeyiAsmaz() {
        let t = SesTamponu()
        t.ayarla(oran: 16000, azamiSure: 1.5)
        let parca = [Float](repeating: 0.1, count: 1600)   // 0,1 sn
        for _ in 0..<20 { parca.withUnsafeBufferPointer { t.ekle($0) } }   // toplam 2 sn
        #expect(abs(t.sure - 1.5) < 0.001)
        #expect(t.al().count == 24000)
        #expect(t.sure == 0)
    }

    @Test func sozKesmeOnSesiBaslamadanBos() {
        let s = SozKesmeDinleyici()
        let on = s.onSesiAl()
        #expect(on.ornekler.isEmpty)
        #expect(on.oran > 0)
    }

    // MARK: ön sesin mikrofon biçimine çevrilmesi

    @Test func onSesTamponuMonoFloatBicimdeKurulur() throws {
        let bicim = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let o = (0..<1600).map { Float(sin(Double($0) * 0.1)) * 0.3 }
        let b = try #require(SesDinleyici.onSesTamponu(o, oran: 16000, bicim: bicim))
        #expect(b.frameLength == 1600)
        #expect(b.floatChannelData![0][10] == o[10])
    }

    @Test func onSesTamponuYenidenOrnekler() throws {
        let bicim = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false))
        let o = (0..<16000).map { Float(sin(Double($0) * 0.05)) * 0.3 }   // 1 sn @ 16 kHz
        let b = try #require(SesDinleyici.onSesTamponu(o, oran: 16000, bicim: bicim))
        #expect(abs(Double(b.frameLength) - 48000) < 600)
        #expect(b.floatChannelData![1][1000] == b.floatChannelData![0][1000])   // her kanala aynı ses
    }

    @Test func onSesTamponuDesteklenmeyenBicimdeAtlanir() throws {
        let i16 = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let icIce = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 2, interleaved: true))
        let mono = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        #expect(SesDinleyici.onSesTamponu([0.1, 0.2], oran: 16000, bicim: i16) == nil)
        #expect(SesDinleyici.onSesTamponu([0.1, 0.2], oran: 16000, bicim: icIce) == nil)
        #expect(SesDinleyici.onSesTamponu([], oran: 16000, bicim: mono) == nil)
    }

    // MARK: (4) arka planda bekleme kararı

    @Test func arkaPlandaBeklemeSurerKararTablosu() {
        #expect(!SesOturumu.arkaPlandaBeklemeSurer(ayar: false, bekliyor: true, canli: false))   // ayar kapalı
        #expect(!SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: true, canli: true))     // Live
        #expect(!SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: false, canli: false))   // bekleme yoktu
        #expect(SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: true, canli: false))
        // Arka planda başlatma hatası: o dönem için yeniden açılmaz; önde hata bayrağı kararı etkilemez.
        #expect(!SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: true, canli: false, onPlanda: false, sonHataArkaPlanda: true))
        #expect(SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: true, canli: false, onPlanda: true, sonHataArkaPlanda: true))
        #expect(SesOturumu.arkaPlandaBeklemeSurer(ayar: true, bekliyor: true, canli: false, onPlanda: false, sonHataArkaPlanda: false))
    }

    // MARK: (5) ayar

    @Test func arkaPlanUyandirmaVarsayilanKapaliVeKalici() {
        let d = suite("ayar")
        let a = Ayarlar(defaults: d)
        #expect(a.arkaPlanUyandirma == false)
        a.arkaPlanUyandirma = true
        #expect(d.bool(forKey: "ayar.arkaPlanUyandirmaV1"))
        #expect(Ayarlar(defaults: d).arkaPlanUyandirma)
    }
}
