import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Raf fotoğrafını dilimleme

/// Raf/dolap fotoğrafını Gemini'nin okuyabileceği parçalara böler.
///
/// Tek rafta 40–50, tam dolapta 100'den fazla sırt olur; fotoğraf bütün olarak 2400 px'e
/// küçültülünce sırt yazıları 20 px'in altına düşer ve çoğu kitap kaçırılır. Bu yüzden:
/// 1. Ucuz bir yerleşim sorgusu raf SATIRLARINI (dikey aralıklar) bulur; kaçırılan raf, komşu
///    satırlar arasındaki olağandışı boşluktan yakalanır.
/// 2. Her satır, sırtları kesmeyecek şekilde dikey ŞERİTLERE bölünür (kenarlarda bindirme
///    bırakılır; kesilen sırt komşu dilimde bütün görünür).
/// 3. Her dilim ayrı okunur, sonuçlar `ShelfScanEngine` içinde dilim komşuluğuna göre birleştirilir.
enum RafDilimleyici {
    /// Bir dilimin orijinal fotoğrafta kapladığı en fazla genişlik (px). Bunun üstünde
    /// yazılar Gemini'ye giden 2400 px'lik görüntüde okunmaz hâle gelir.
    nonisolated static let hedefGenislik = 2200
    /// Bir fotoğraf için en fazla dilim (maliyet ve süre sınırı): 5 raflı dolap × 2 şerit sığar.
    nonisolated static let enFazlaDilim = 10
    /// Yan yana dilimlerin bindirme oranı (kesilen sırt komşuda bütün çıkar).
    nonisolated static let yatayBindirme = 0.08
    /// Satırın üstüne/altına eklenen pay (raf tahtası ve yerleşim hatası için). Küçük tutulur:
    /// komşu rafın sırt uçları dilime girerse aynı kitap iki rafta sayılabilir.
    nonisolated static let dikeyPay = 0.02

    /// Bir dilim ve fotoğraftaki yeri (satır = raf, sütun = şerit). Birleştirmede komşuluk için.
    nonisolated struct Dilim: Sendable {
        var data: Data
        var satir: Int
        var sutun: Int
        /// Bu satırın kesiti bir üst satırın kesitiyle piksel paylaşıyor mu? (Birleştirmede
        /// alt/üst dilimde görülen aynı kitap yalnız o zaman bindirme sayılır.)
        var ustBindirmeli = false
    }

    /// Kırpma dikdörtgeni ve yeri (piksel).
    nonisolated struct DilimAlani: Sendable, Equatable {
        var alan: CGRect
        var satir: Int
        var sutun: Int
        var ustBindirmeli = false
    }

    nonisolated struct YerlesimYaniti: Codable, Sendable {
        nonisolated struct Satir: Codable, Sendable {
            var top: Double
            var bottom: Double
        }
        var rows: [Satir]
    }

    // MARK: Yerleşim

    /// Fotoğrafın piksel boyutu (EXIF yönü uygulanmış); görüntü çözülmeden başlıktan okunur.
    nonisolated static func boyut(_ data: Data) -> (genislik: Int, yukseklik: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let ozellikler = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let genislik = ozellikler[kCGImagePropertyPixelWidth] as? Int,
              let yukseklik = ozellikler[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let yon = ozellikler[kCGImagePropertyOrientation] as? UInt32 ?? 1
        // EXIF 5–8: görüntü 90° döndürülerek gösterilir, kenarlar yer değiştirir
        return yon >= 5 ? (yukseklik, genislik) : (genislik, yukseklik)
    }

    /// Fotoğraf tek dilime sığıyorsa dilimlemeye (ve yerleşim sorgusuna) gerek yoktur.
    nonisolated static func dilimlemeGerekli(genislik: Int, yukseklik: Int) -> Bool {
        genislik > hedefGenislik || yukseklik > hedefGenislik
    }

    /// Gemini'ye küçük görüntüyle raf satırlarını sorar (0–1 arası dikey oranlar).
    /// Küçük fotoğrafta sorgu atlanır; bulamazsa ya da hata olursa tüm fotoğraf tek satır sayılır.
    static func satirlar(_ data: Data) async -> [ClosedRange<Double>] {
        if let boyut = boyut(data), !dilimlemeGerekli(genislik: boyut.genislik, yukseklik: boyut.yukseklik) {
            return [0...1]
        }
        guard GeminiSettings.isActive,
              let kucuk = await Task.detached(priority: .userInitiated, operation: {
                  GeminiImagePreparer.jpegData(from: data, maxPixel: 1024, quality: 0.7)
              }).value else { return [0...1] }
        do {
            let yanit = try await GeminiClient.shared.generateJSON(
                YerlesimYaniti.self,
                prompt: "Bu fotoğrafta kitapların dizili olduğu raf satırlarını bul.",
                system: """
                Fotoğrafta bir kitaplık var. Kitapların yan yana dizili olduğu her raf SATIRI için, \
                kitap sırtlarının kapladığı dikey aralığı fotoğraf yüksekliğinin oranı olarak ver \
                (0 = üst kenar, 1 = alt kenar). Boş rafları ve sadece raf tahtasını yazma; dolu \
                hiçbir rafı atlama. Tek raf varsa tek satır döndür. \
                YALNIZCA JSON: {"rows": [{"top": 0.12, "bottom": 0.31}]}
                """,
                images: [kucuk],
                temperature: 0,
                timeout: 30,
                maxAttempts: 1
            )
            return bosluklariDoldur(duzelt(yanit.rows.map { $0.top...max($0.top, $0.bottom) }))
        } catch {
#if DEBUG
            print("🤖 Raf yerleşimi okunamadı, tek satır varsayıldı: \(error.localizedDescription)")
#endif
            return [0...1]
        }
    }

    /// Model yanıtını güvenli hâle getirir: 0–1'e kırpılır, çok ince (%4'ten kısa) satırlar
    /// atılır, BÜYÜK ÖLÇÜDE örtüşenler (kısa olanın yarısından fazlası) birleştirilir, yukarıdan
    /// aşağı sıralanır. Birbirine değen ya da hafif örtüşen satırlar ayrı kalır: bunlar gerçek
    /// komşu raflardır (boşluk doldurma da tam değen satırlar üretir); kesitler zaten bindirmelidir.
    /// Hiç kalmazsa tüm fotoğraf. Aynı girdiye ikinci kez uygulanınca sonuç değişmez.
    nonisolated static func duzelt(_ satirlar: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        let temiz = satirlar
            .filter { $0.lowerBound.isFinite && $0.upperBound.isFinite }
            .map { max(0, min(1, $0.lowerBound))...max(0, min(1, $0.upperBound)) }
            .filter { $0.upperBound - $0.lowerBound >= 0.04 }
            .sorted { $0.lowerBound < $1.lowerBound }
        var sonuc: [ClosedRange<Double>] = []
        for satir in temiz {
            if let son = sonuc.last {
                let ortak = son.upperBound - satir.lowerBound
                let kisa = min(son.upperBound - son.lowerBound, satir.upperBound - satir.lowerBound)
                if ortak > kisa * 0.5 {
                    sonuc[sonuc.count - 1] = son.lowerBound...max(son.upperBound, satir.upperBound)
                    continue
                }
            }
            sonuc.append(satir)
        }
        return sonuc.isEmpty ? [0...1] : satirlariSinirla(sonuc)
    }

    /// Satır sayısı dilim bütçesini aşarsa en ince komşu çift birleştirilir (kitap atlanmaz,
    /// yalnız o iki raf tek dilimde biraz daha küçük okunur).
    nonisolated static func satirlariSinirla(_ satirlar: [ClosedRange<Double>], enFazla: Int = enFazlaDilim) -> [ClosedRange<Double>] {
        var sonuc = satirlar
        while sonuc.count > max(1, enFazla) {
            var enInce = 0
            var enInceYukseklik = Double.infinity
            for index in 0..<(sonuc.count - 1) {
                let yukseklik = sonuc[index + 1].upperBound - sonuc[index].lowerBound
                if yukseklik < enInceYukseklik {
                    enInceYukseklik = yukseklik
                    enInce = index
                }
            }
            sonuc[enInce] = sonuc[enInce].lowerBound...sonuc[enInce + 1].upperBound
            sonuc.remove(at: enInce + 1)
        }
        return sonuc
    }

    /// Model bir rafı kaçırdıysa iki satır arasındaki boşluk olağandışı büyür (raf tahtası payı
    /// ~%5 iken kaçan raf ~%20). Ortanca satır yüksekliğinin %90'ından ve %8'den büyük İÇ
    /// boşluklar satır olarak eklenir; böylece o raftaki kitaplar da okunur. Kenar boşlukları
    /// (tavan, zemin, etiket alanı) eklenmez.
    nonisolated static func bosluklariDoldur(_ satirlar: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        guard satirlar.count >= 2 else { return satirlar }
        let yukseklikler = satirlar.map { $0.upperBound - $0.lowerBound }.sorted()
        let ortanca = yukseklikler[yukseklikler.count / 2]
        let esik = max(0.08, ortanca * 0.9)
        var sonuc: [ClosedRange<Double>] = []
        for (index, satir) in satirlar.enumerated() {
            if index > 0 {
                let oncekiAlt = satirlar[index - 1].upperBound
                if satir.lowerBound - oncekiAlt > esik {
                    sonuc.append(oncekiAlt...satir.lowerBound)
                }
            }
            sonuc.append(satir)
        }
        return sonuc
    }

    // MARK: Geometri

    /// Dilim dikdörtgenleri (piksel). Her satır, `hedefGenislik`i aşmayacak sayıda eşit şeride
    /// bölünür; şeritler `yatayBindirme` oranında bindirilir. Toplam dilim `enFazla`yı aşarsa
    /// şerit sayısı düşürülür (kalite yerine bütünlük korunur: hiçbir kitap dışarıda kalmaz).
    nonisolated static func dilimAlanlari(
        genislik: Int, yukseklik: Int, satirlar: [ClosedRange<Double>],
        hedefGenislik: Int = hedefGenislik, enFazla: Int = enFazlaDilim
    ) -> [DilimAlani] {
        guard genislik > 0, yukseklik > 0, hedefGenislik > 0 else { return [] }
        let satirlar = satirlariSinirla(duzelt(satirlar), enFazla: enFazla)
        // Şerit bütçesi satır sayısına bölünür; en az 1 şerit (tek satır tüm genişlik)
        let gereken = max(1, Int((Double(genislik) / Double(hedefGenislik)).rounded(.up)))
        let sutunSayisi = max(1, min(gereken, enFazla / max(1, satirlar.count)))

        var alanlar: [DilimAlani] = []
        var oncekiAlt: Int?
        for (satirIndex, satir) in satirlar.enumerated() {
            // Kenarlar dışa doğru tam piksele yuvarlanır: kenar sütunu/satırı kaybolmaz
            let ust = Int((max(0, satir.lowerBound - dikeyPay) * Double(yukseklik)).rounded(.down))
            let alt = min(yukseklik, Int((min(1, satir.upperBound + dikeyPay) * Double(yukseklik)).rounded(.up)))
            guard alt - ust >= 1 else { continue }
            let ustBindirmeli = oncekiAlt.map { ust < $0 } ?? false
            oncekiAlt = alt

            let temelGenislik = Double(genislik) / Double(sutunSayisi)
            let bindirme = sutunSayisi > 1 ? temelGenislik * yatayBindirme : 0
            for sutun in 0..<sutunSayisi {
                let sol = max(0, Int((Double(sutun) * temelGenislik - bindirme).rounded(.down)))
                let sag = min(genislik, Int((Double(sutun + 1) * temelGenislik + bindirme).rounded(.up)))
                alanlar.append(DilimAlani(
                    alan: CGRect(x: sol, y: ust, width: sag - sol, height: alt - ust),
                    satir: satirIndex, sutun: sutun, ustBindirmeli: ustBindirmeli
                ))
            }
        }
        return alanlar
    }

    /// Fotoğrafı satırlara göre dilimler ve her dilimi Gemini'ye uygun JPEG'e çevirir.
    /// Tek dilim çıkarsa (küçük fotoğraf, tek raf) fotoğraf bütün olarak gider.
    nonisolated static func dilimle(_ data: Data, satirlar: [ClosedRange<Double>], gidenMaxPixel: Int = 2400) -> [Dilim] {
        guard let tam = decodeImage(from: data, maxPixel: 6000) else { return [] }
        let alanlar = dilimAlanlari(genislik: tam.width, yukseklik: tam.height, satirlar: satirlar)
        if alanlar.count <= 1 {
            guard let butun = GeminiImagePreparer.jpegData(from: data, maxPixel: gidenMaxPixel, quality: 0.85) else { return [] }
            return [Dilim(data: butun, satir: 0, sutun: 0)]
        }
        return alanlar.compactMap { dilim in
            guard let kesit = tam.cropping(to: dilim.alan),
                  let jpeg = jpeg(kesit, maxPixel: gidenMaxPixel, quality: 0.85) else { return nil }
            return Dilim(data: jpeg, satir: dilim.satir, sutun: dilim.sutun, ustBindirmeli: dilim.ustBindirmeli)
        }
    }

    // MARK: Görüntü yardımcıları

    nonisolated private static func decodeImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// CGImage → küçültülmüş JPEG (uzun kenar `maxPixel`).
    nonisolated private static func jpeg(_ image: CGImage, maxPixel: Int, quality: Double) -> Data? {
        var cikti = image
        let uzunKenar = max(image.width, image.height)
        if uzunKenar > maxPixel {
            let oran = Double(maxPixel) / Double(uzunKenar)
            let boyut = CGSize(width: Double(image.width) * oran, height: Double(image.height) * oran)
            if let context = CGContext(
                data: nil, width: Int(boyut.width), height: Int(boyut.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(origin: .zero, size: boyut))
                if let kucuk = context.makeImage() { cikti = kucuk }
            }
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cikti, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
