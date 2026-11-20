import Foundation
import AVFoundation

/// Toplantı kaydının dökümü (P4.6): ses 5 dakikalık parçalara bölünür, her parça vekildeki Whisper aktarıcısına
/// (`WhisperIstemcisi.cozumle`, 180 sn zaman aşımı) gider. Parça başına WAV ≈ 5 dk × 16 kHz × 2 bayt ≈ 9,6 MB
/// (aktarıcının 25 MB sınırının altında). Yeni paket ya da model yoktur.
nonisolated enum ToplantiDokumu {
    static let parcaSuresi: TimeInterval = 300
    /// Bundan kısa son parça öncekine katılır (birkaç saniyelik parçaya ayrı istek gitmesin).
    static let enKisaSonParca: TimeInterval = 20
    /// Sohbete belge olarak giden metin sınırı (BelgeOkuyucu ile aynı: 50.000 karakter).
    static let belgeSiniri = 50_000

    enum Hata: LocalizedError {
        case okunamadi, bos
        var errorDescription: String? {
            switch self {
            case .okunamadi: "Kayıt dosyası okunamadı."
            case .bos: "Kayıtta çözülecek ses yok."
            }
        }
    }

    /// Saf: süreyi `parca` uzunluğunda aralıklara böler; son parça `enKisaSonParca`'dan kısaysa öncekine katılır.
    static func parcaAraliklari(sure: TimeInterval, parca: TimeInterval = parcaSuresi) -> [Range<TimeInterval>] {
        guard sure > 0, parca > 0 else { return [] }
        var l: [Range<TimeInterval>] = []
        var bas: TimeInterval = 0
        while bas < sure {
            l.append(bas..<min(bas + parca, sure))
            bas += parca
        }
        if l.count > 1, let son = l.last, son.upperBound - son.lowerBound < min(enKisaSonParca, parca) {
            l.removeLast()
            l[l.count - 1] = l[l.count - 1].lowerBound..<son.upperBound
        }
        return l
    }

    /// "00:05:00" biçimi.
    static func zamanDamgasi(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Çözülemeyen bölümün yer tutucusu: "[65:00 bölümü çözülemedi]" (dakika:saniye).
    static func cozulemedi(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "[%02d:%02d bölümü çözülemedi]", s / 60, s % 60)
    }

    /// Saf: "[00:05:00] metin" satırları; boş (sessiz) parçalar atlanır.
    static func birlestir(_ parcalar: [(baslangic: TimeInterval, metin: String)]) -> String {
        parcalar.compactMap { p -> String? in
            let m = p.metin.trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : "[\(zamanDamgasi(p.baslangic))] \(m)"
        }.joined(separator: "\n\n")
    }

    /// Sohbete giden belge: sınırı aşarsa kesilir ve tam dökümün yeri not edilir.
    static func belgeMetni(_ dokum: String, dosyaAdi: String, sinir: Int = belgeSiniri) -> String {
        guard dokum.count > sinir else { return dokum }
        return String(dokum.prefix(sinir)) + "\n\n(Döküm \(sinir.formatted()) karakterle sınırlandı; tamamı telefonda \(dosyaAdi) dosyasında.)"
    }

    /// Ses dosyasını parça parça çözer, dökümü sesin yanına .txt olarak yazar ve döndürür.
    /// `ilerleme(biten, toplam)` her parça sonunda çağrılır. Parça başına bir yeniden deneme; olmazsa yer tutucu yazılır.
    /// `cozucu` testte sahtelenir (ağsız). Ana aktör dışında koşar (dosya okuma ve WAV kodlama ağır).
    @concurrent static func cozumle(
        _ url: URL,
        parca: TimeInterval = parcaSuresi,
        ilerleme: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        cozucu: @escaping @Sendable ([Float], Double, String?) async throws -> String = { o, oran, ipucu in
            try await WhisperIstemcisi.cozumle(ornekler: o, oran: oran, ipucu: ipucu, zamanAsimi: 180)
        }
    ) async throws -> String {
        guard let dosya = try? AVAudioFile(forReading: url) else { throw Hata.okunamadi }
        let bicim = dosya.processingFormat
        let oran = bicim.sampleRate
        guard oran > 0, dosya.length > 0 else { throw Hata.bos }
        let araliklar = parcaAraliklari(sure: Double(dosya.length) / oran, parca: parca)
        var sonuclar: [(baslangic: TimeInterval, metin: String)] = []
        var oncekiSon: String?
        for (i, a) in araliklar.enumerated() {
            try Task.checkCancellation()
            let bas = AVAudioFramePosition(a.lowerBound * oran)
            let adet = AVAudioFrameCount(min(Double(dosya.length - bas), (a.upperBound - a.lowerBound) * oran))
            var metin: String?
            if adet > 0, let tampon = AVAudioPCMBuffer(pcmFormat: bicim, frameCapacity: adet) {
                dosya.framePosition = bas
                if (try? dosya.read(into: tampon, frameCount: adet)) != nil, let k = tampon.floatChannelData?[0] {
                    let ornekler = Array(UnsafeBufferPointer(start: k, count: Int(tampon.frameLength)))
                    for _ in 0..<2 where metin == nil {
                        try Task.checkCancellation()
                        metin = try? await cozucu(ornekler, oran, oncekiSon)
                    }
                }
            }
            if let m = metin {
                sonuclar.append((a.lowerBound, m))
                let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
                oncekiSon = t.isEmpty ? oncekiSon : String(t.suffix(200))
            } else {
                sonuclar.append((a.lowerBound, cozulemedi(a.lowerBound)))
            }
            ilerleme(i + 1, araliklar.count)
        }
        let dokum = birlestir(sonuclar)
        try? dokum.write(to: SesKaydedici.dokumYolu(url), atomically: true, encoding: .utf8)
        return dokum
    }
}
