import Testing

extension Tag {
    /// Büyük katalog ve süre ölçen testler; yalnız 'Performans' planında koşar.
    @Tag static var performans: Self
    /// Gerçek cihaz veya gerçek depo kopyası isteyen testler; 'Cihaz Kabul' planında koşar.
    @Tag static var cihaz: Self
}

/// Süre sınırlarını makineye göre ölçekler: sabit bir iş yükü (sıralama + metin üretimi) bu makinede
/// referans makineden yavaşsa sınırlar aynı oranda genişler; hızlıysa sınırlar referansta kalır.
enum PerformansTabani {
    /// Referans makinede (Debug, -Onone) ölçülen medyan süre, saniye.
    static let referansSaniye = 0.154

    static let olculen: Double = {
        var sonuclar: [Double] = []
        for _ in 0..<5 {
            var x: UInt64 = 0x9E37_79B9_7F4A_7C15
            var dizi = [Int](); dizi.reserveCapacity(200_000)
            let bas = ContinuousClock.now
            for _ in 0..<200_000 { x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407; dizi.append(Int(x >> 33)) }
            dizi.sort()
            _ = dizi.prefix(20_000).map(String.init).joined(separator: ",").count
            let gecen = ContinuousClock.now - bas
            sonuclar.append(Double(gecen.components.seconds) + Double(gecen.components.attoseconds) / 1e18)
        }
        return sonuclar.sorted()[2]
    }()

    static var olcek: Double { max(1, olculen / referansSaniye) }

    /// Referans makine için yazılmış sınırı bu makineye uyarlar (aynı birimde döner).
    static func sinir(_ referansSiniri: Double) -> Double { referansSiniri * olcek }
}
