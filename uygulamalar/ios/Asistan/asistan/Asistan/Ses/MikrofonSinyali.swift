import Foundation

/// Normal oda sessizliği sıfır değildir. Tam sıfır tamponları ve hiç örnek
/// gelmemesini, düşük sesle konuşmadan ayrı değerlendirir (250 ms aralık).
nonisolated struct MikrofonSinyali {
    private(set) var sifirPencere = 0
    mutating func engelli(tepe: Float) -> Bool {
        if tepe > 0 { sifirPencere = 0 } else { sifirPencere += 1 }
        return sifirPencere >= 16
    }
}
