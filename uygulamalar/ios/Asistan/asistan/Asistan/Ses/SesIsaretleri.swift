import Foundation
import AVFoundation

/// Sesli kipteki kısa işaret tonları. "dinliyorum": mikrofon açıldı; "aldım": söz alındı, yanıt hazırlanıyor;
/// "kapandı": dinleme penceresi kapandı; "hata": mikrofon/dinleme hatası.
nonisolated enum IsaretTuru: CaseIterable, Hashable, Sendable {
    case dinliyorum, aldim, kapandi, hata
}

/// İşaret tonlarını kodda üretip (varlık dosyası yok) `AVAudioPlayer` ile çalar. Ayarlar → "İşaret sesleri" kapalıysa susar.
@MainActor
final class SesIsaretleri {
    static let ortak = SesIsaretleri()

    /// Ayar okuyucusu; `SesOturumu` init'te `Ayarlar.isaretSesleri`'ne bağlar.
    var acik: () -> Bool = { true }
    private var oynaticilar: [IsaretTuru: AVAudioPlayer] = [:]

    /// Tonun bir bölümü: frekans (Hz; 0 = sessizlik) ve süre (sn).
    nonisolated struct Bolum: Equatable, Sendable {
        let frekans: Double
        let sure: Double
    }

    nonisolated static let genlik: Float = 0.25
    nonisolated static let sonumSuresi = 0.005

    nonisolated static func bolumler(_ t: IsaretTuru) -> [Bolum] {
        switch t {
        case .dinliyorum: [Bolum(frekans: 880, sure: 0.07), Bolum(frekans: 1320, sure: 0.07)]
        case .aldim: [Bolum(frekans: 1320, sure: 0.06)]
        case .kapandi: [Bolum(frekans: 1320, sure: 0.07), Bolum(frekans: 880, sure: 0.07)]
        case .hata: [Bolum(frekans: 440, sure: 0.06), Bolum(frekans: 0, sure: 0.04), Bolum(frekans: 440, sure: 0.06)]
        }
    }

    /// Tonun toplam süresi (sn).
    nonisolated static func sure(_ t: IsaretTuru) -> TimeInterval {
        bolumler(t).reduce(0) { $0 + $1.sure }
    }

    /// Tek kanallı PCM örnekleri (saf): her ton bölümü 5 ms giriş/çıkış sönümüyle başlar ve biter (tık sesi olmaz).
    nonisolated static func ornekler(_ t: IsaretTuru, oran: Double = 44_100) -> [Float] {
        let sonum = max(1, Int(oran * sonumSuresi))
        var sonuc: [Float] = []
        for b in bolumler(t) {
            let n = max(1, Int((oran * b.sure).rounded()))
            guard b.frekans > 0 else {
                sonuc.append(contentsOf: [Float](repeating: 0, count: n))
                continue
            }
            let adim = 2 * Double.pi * b.frekans / oran
            sonuc.reserveCapacity(sonuc.count + n)
            for i in 0..<n {
                let giris = min(1, Double(i) / Double(sonum))
                let cikis = min(1, Double(n - 1 - i) / Double(sonum))
                sonuc.append(Float(sin(adim * Double(i)) * min(giris, cikis)) * genlik)
            }
        }
        return sonuc
    }

    /// Tonu çalar ve bitmesini bekler (ör. mikrofon motoru başlamadan önce, oturum bırakılmadan önce).
    func cal(_ t: IsaretTuru) async {
        guard baslat(t) else { return }
        try? await Task.sleep(for: .seconds(Self.sure(t) + 0.03))
    }

    /// Tonu çalar, beklemez (mikrofon zaten açıkken ya da akışı bloklamaması gerekirken).
    func calBeklemeden(_ t: IsaretTuru) {
        _ = baslat(t)
    }

    private func baslat(_ t: IsaretTuru) -> Bool {
        guard acik(), let o = oynatici(t) else { return false }
        // Daha önce sıraya girmiş bir ses oturumu bırakma kararı tonu yarıda kesmesin.
        SesOturumuKapisi.istek.artir()
        o.currentTime = 0
        return o.play()
    }

    /// Oynatıcılar ilk kullanımda üretilir ve saklanır.
    private func oynatici(_ t: IsaretTuru) -> AVAudioPlayer? {
        if let o = oynaticilar[t] { return o }
        let oran = 44_100.0
        let veri = WhisperIstemcisi.wav(Self.ornekler(t, oran: oran), oran: oran)
        guard let o = try? AVAudioPlayer(data: veri, fileTypeHint: AVFileType.wav.rawValue) else { return nil }
        o.prepareToPlay()
        oynaticilar[t] = o
        return o
    }
}
