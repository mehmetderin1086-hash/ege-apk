import Foundation
import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CoreTransferable
import UniformTypeIdentifiers
import VisionKit

// MARK: - ISBN onarım önerileri

/// Kontrol basamağı tutmayan ISBN için olası doğru yazımlar: bitişik iki rakamın yer
/// değiştirmesi, OCR'ın sık karıştırdığı rakamlar (0↔8, 1↔7, 5↔6, 3↔8…), eksik kontrol
/// basamağı. Her öneri kontrol basamağından geçer; en olası olanlar önce gelir.
nonisolated enum ISBNOnarici {
    private static let karisanlar: [Character: [Character]] = [
        "0": ["8", "6", "9"], "8": ["0", "3", "6", "9"], "1": ["7", "4"], "7": ["1"],
        "5": ["6", "3"], "6": ["5", "8", "0"], "3": ["8", "5"], "9": ["0", "8"], "4": ["1"], "2": ["7"]
    ]

    static func oneriler(_ girdi: String, enFazla: Int = 4) -> [String] {
        let rakamlar = girdi.filter(\.isNumber)
        var sonuc: [String] = []
        func ekle(_ aday: String) {
            guard aday.count == 13, aday.hasPrefix("978") || aday.hasPrefix("979"),
                  ISBNFormatter.isValidISBN13(aday), aday != rakamlar, !sonuc.contains(aday) else { return }
            sonuc.append(aday)
        }

        if rakamlar.count == 12 {
            // Kontrol basamağı eksik: tamamla
            for son in 0...9 { ekle(rakamlar + String(son)) }
            return Array(sonuc.prefix(enFazla))
        }
        if rakamlar.count == 10, let donusen = Optional(ISBNFormatter.normalize(girdi)), !donusen.isEmpty {
            ekle(donusen)
        }
        guard rakamlar.count == 13 else { return Array(sonuc.prefix(enFazla)) }
        let dizi = Array(rakamlar)

        // 1) Bitişik yer değiştirme (en sık el yazımı hatası)
        for i in 3..<(dizi.count - 1) where dizi[i] != dizi[i + 1] {
            var aday = dizi
            aday.swapAt(i, i + 1)
            ekle(String(aday))
        }
        // 2) OCR'ın karıştırdığı rakamlar
        for i in 3..<dizi.count {
            for yerine in karisanlar[dizi[i]] ?? [] {
                var aday = dizi
                aday[i] = yerine
                ekle(String(aday))
            }
        }
        // 3) Yalnız kontrol basamağı yanlış okunmuş olabilir
        for son in 0...9 {
            ekle(String(dizi.prefix(12)) + String(son))
        }
        return Array(sonuc.prefix(enFazla))
    }
}

// MARK: - Kapak perspektif düzeltme

/// Eğik çekilmiş kapak fotoğrafında kitabın dikdörtgenini bulup düz (karşıdan çekilmiş gibi)
/// hale getirir. Dikdörtgen bulunamazsa `nil` döner, çağıran özgün fotoğrafı kullanır.
nonisolated enum KapakDuzeltici {
    @concurrent static func duzelt(_ data: Data) async -> Data? {
        guard !Task.isCancelled, let girdi = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let istek = VNDetectRectanglesRequest()
        istek.minimumConfidence = 0.7
        istek.minimumAspectRatio = 0.4
        istek.maximumAspectRatio = 1.0
        istek.minimumSize = 0.3
        istek.maximumObservations = 1
        let isleyici = VNImageRequestHandler(ciImage: girdi)
        guard (try? isleyici.perform([istek])) != nil,
              let dortgen = istek.results?.first else { return nil }

        let boyut = girdi.extent.size
        func nokta(_ p: CGPoint) -> CIVector { CIVector(x: p.x * boyut.width, y: p.y * boyut.height) }
        guard let filtre = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filtre.setValue(girdi, forKey: kCIInputImageKey)
        filtre.setValue(nokta(dortgen.topLeft), forKey: "inputTopLeft")
        filtre.setValue(nokta(dortgen.topRight), forKey: "inputTopRight")
        filtre.setValue(nokta(dortgen.bottomLeft), forKey: "inputBottomLeft")
        filtre.setValue(nokta(dortgen.bottomRight), forKey: "inputBottomRight")
        guard let cikti = filtre.outputImage else { return nil }
        // Hafif kontrast/netlik: kapak yazıları OCR'da daha iyi okunur
        let netlesmis = cikti
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.08])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.4])
        let baglam = CIContext()
        guard let cg = baglam.createCGImage(netlesmis, from: netlesmis.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
    }
}

// MARK: - Seri taramada sesli sayaç

/// Seri taramada her 10 kitapta bir "10 kitap" gibi kısa sesli bildirim (ekrana bakmadan çalışmak için).
enum SeriTaramaSesi {
    static let ayarAnahtari = "serialScanSpokenCounter"
    static let aralik = 10
    private static let konusucu = AVSpeechSynthesizer()

    static var acik: Bool {
        UserDefaults.standard.object(forKey: ayarAnahtari) as? Bool ?? true
    }

    static func duyurulmali(_ sayi: Int) -> Bool {
        sayi > 0 && sayi % aralik == 0
    }

    static func bildir(_ sayi: Int) {
        guard acik, duyurulmali(sayi) else { return }
        let soz = AVSpeechUtterance(string: "\(sayi) kitap")
        soz.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        soz.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        konusucu.speak(soz)
    }
}

// MARK: - Videodan kare çıkarma (raf taraması)

/// Galeriden seçilen video dosyası (geçici klasöre kopyalanır).
struct VideoDosyasi: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { alinan in
            let hedef = FileManager.default.temporaryDirectory
                .appendingPathComponent("raf-\(UUID().uuidString).\(alinan.file.pathExtension.isEmpty ? "mov" : alinan.file.pathExtension)")
            try FileManager.default.copyItem(at: alinan.file, to: hedef)
            return VideoDosyasi(url: hedef)
        }
    }
}

nonisolated enum VideoKareCikarici {
    /// Raf boyunca yavaşça çekilmiş videodan eşit aralıklı `adet` kare (JPEG).
    static func kareler(url: URL, adet: Int = 4) async -> [Data] {
        guard adet > 0 else { return [] }
        let varlik = AVURLAsset(url: url)
        guard let sure = try? await varlik.load(.duration), sure.seconds.isFinite, sure.seconds > 0 else { return [] }
        let uretici = AVAssetImageGenerator(asset: varlik)
        uretici.appliesPreferredTrackTransform = true
        uretici.maximumSize = CGSize(width: 2400, height: 2400)
        uretici.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        uretici.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)

        var sonuc: [Data] = []
        let adet = min(10, adet)
        for i in 0..<adet {
            guard !Task.isCancelled else { break }
            // Uçlardaki bulanık kareleri atlamak için %10–%90 aralığı
            let oran = adet == 1 ? 0.5 : 0.1 + 0.8 * Double(i) / Double(adet - 1)
            let zaman = CMTime(seconds: sure.seconds * oran, preferredTimescale: 600)
            if let kare = try? await uretici.image(at: zaman).image,
               let jpeg = UIImage(cgImage: kare).jpegData(compressionQuality: 0.85) {
                sonuc.append(jpeg)
            }
        }
        return sonuc
    }
}

// MARK: - Gemini ile fotoğraf gruplama

/// Toplu fotoğraf eklemede hangi fotoğrafların aynı kitaba ait olduğunu (kapak + arka kapak +
/// künye) Gemini'ye sorar. Sonuç: her grup bir kitap, fotoğraf sıraları.
enum GeminiFotoGruplayici {
    static let ayarAnahtari = "aiPhotoGrouping"

    static var acik: Bool {
        UserDefaults.standard.bool(forKey: ayarAnahtari) && GeminiSettings.isActive
    }

    nonisolated struct Yanit: Codable, Sendable {
        var groups: [[Int]]
    }

    @concurrent private static func kucult(_ kaynak: [Data]) async -> [Data] {
        kaynak.compactMap { GeminiImagePreparer.jpegData(from: $0, maxPixel: 768, quality: 0.6) }
    }

    static func grupla(_ fotograflar: [Data]) async throws -> [[Int]] {
        let kaynak = Array(fotograflar.prefix(16))
        let hazir = await kucult(kaynak)
        try Task.checkCancellation()
        guard hazir.count == kaynak.count, hazir.count > 1 else { return fotograflar.indices.map { [$0] } }
        let yanit = try await GeminiClient.shared.generateJSON(
            Yanit.self,
            prompt: "Fotoğraflar 0'dan \(hazir.count - 1)'e numaralı sırayla verildi. Aynı kitaba ait olanları (kapak, arka kapak, künye sayfası) grupla.",
            system: """
            Kitap fotoğraflarını kitaplara göre grupla. Her fotoğraf tam olarak bir grupta olmalı. \
            Emin değilsen fotoğrafı tek başına grup yap. YALNIZCA JSON: {"groups": [[0, 1], [2]]}
            """,
            images: hazir,
            temperature: 0,
            timeout: 60
        )
        return duzelt(yanit.groups, adet: hazir.count) + (hazir.count..<fotograflar.count).map { [$0] }
    }

    /// Modelin yanıtını güvenli hale getirir: sınır dışı/yinelenen sıralar atılır, unutulan
    /// fotoğraflar tek başına grup olur.
    nonisolated static func duzelt(_ gruplar: [[Int]], adet: Int) -> [[Int]] {
        var gorulen = Set<Int>()
        var sonuc: [[Int]] = []
        for grup in gruplar {
            let temiz = grup.filter { (0..<adet).contains($0) && gorulen.insert($0).inserted }
            if !temiz.isEmpty { sonuc.append(temiz) }
        }
        for i in 0..<adet where !gorulen.contains(i) { sonuc.append([i]) }
        return sonuc
    }
}

// MARK: - Taslak deposu

/// Kaydedilmemiş taslaklar (toplu tarama kuyruğu, yarım kalan düzenleme) diske yazılır;
/// uygulama kapanır ya da çökerse bir sonraki açılışta geri yüklenebilir.
enum TaslakDeposu {
    static var dosyaOverride: URL?

    private static var dosya: URL? {
        if let dosyaOverride { return dosyaOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Taslaklar.json")
    }

    static func kaydet(_ taslaklar: [Book]) {
        guard let dosya else { return }
        if taslaklar.isEmpty {
            try? FileManager.default.removeItem(at: dosya)
            return
        }
        try? FileManager.default.createDirectory(at: dosya.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(taslaklar) else { return }
        try? data.write(to: dosya, options: .atomic)
    }

    static func yukle() -> [Book] {
        guard let dosya, let data = try? Data(contentsOf: dosya) else { return [] }
        return CatalogBackup.decode(data)
    }

    static var sayi: Int { yukle().count }

    static func temizle() { kaydet([]) }
}

// MARK: - Canlı kapak tanıma

/// Kamerayı kapağa tutun: canlı metin algılanır (okunabilirliği anlık görürsünüz), kapak kadraja
/// oturunca "Yakala" ile fotoğraf çekilir ve perspektifi düzeltilerek geri verilir.
struct CanliKapakTaramaSayfasi: View {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var algilananSatirlar: [String] = []
    @State private var yakalaniyor = false
    @State private var hata: String?
    @State private var tetik = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                CanliMetinTarayici(tetik: tetik, onText: { algilananSatirlar = $0 }, onPhoto: isle)
                    .ignoresSafeArea()
            } else {
                // Desteklenen cihazda "kullanılamıyor" çoğunlukla reddedilmiş kamera iznidir
                if DataScannerViewController.isSupported {
                    ContentUnavailableView("Kamera kullanılamıyor", systemImage: "camera.fill",
                                           description: Text("Canlı tarama için Ayarlar > Kitap Bul > Kamera iznini açın."))
                } else {
                    ContentUnavailableView("Canlı tarama bu cihazda yok", systemImage: "text.viewfinder")
                }
            }

            VStack(spacing: 12) {
                if !algilananSatirlar.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(algilananSatirlar.prefix(4), id: \.self) { Text($0).lineLimit(1) }
                    }
                    .font(.callout.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Algılanan yazı: " + algilananSatirlar.prefix(3).joined(separator: ", "))
                }
                if let hata {
                    Text(hata).font(.footnote).foregroundStyle(.white)
                        .padding(8).background(.red.opacity(0.8), in: .rect(cornerRadius: 8))
                }
                HStack {
                    Button("Kapat") { dismiss() }
                        .buttonStyle(.kitapTonlu(.white))
                    Spacer()
                    Button {
                        yakalaniyor = true
                        hata = nil
                        tetik += 1
                    } label: {
                        Label(yakalaniyor ? "Hazırlanıyor…" : "Yakala", systemImage: "camera.aperture")
                            .font(.title3.weight(.bold))
                    }
                    .buttonStyle(.kitapDolu(KitapTema.foto))
                    .disabled(yakalaniyor)
                }
            }
            .padding()
        }
        .background(.black)
    }

    private func isle(_ foto: Data?) {
        guard let foto else {
            yakalaniyor = false
            hata = "Fotoğraf çekilemedi, yeniden deneyin."
            return
        }
        Task { @MainActor in
            // Eğik çekimde kapak düz hale getirilir; bulunamazsa özgün fotoğraf gider
            let duz = await KapakDuzeltici.duzelt(foto) ?? foto
            yakalaniyor = false
            onPhoto(duz)
            dismiss()
        }
    }
}

/// DataScanner'ın metin modu: satırları canlı bildirir, `tetik` değişince fotoğraf çeker.
private struct CanliMetinTarayici: UIViewControllerRepresentable {
    let tetik: Int
    let onText: ([String]) -> Void
    let onPhoto: (Data?) -> Void

    func makeCoordinator() -> Koordinator { Koordinator(onText: onText) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let tarayici = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        tarayici.delegate = context.coordinator
        return tarayici
    }

    func updateUIViewController(_ tarayici: DataScannerViewController, context: Context) {
        // Görünüm ekrana girdikten sonra başlatılır (oluştururken başlatmak sessizce başarısız olabiliyordu)
        if !tarayici.isScanning {
            Task { @MainActor in try? tarayici.startScanning() }
        }
        guard tetik != context.coordinator.sonTetik else { return }
        context.coordinator.sonTetik = tetik
        Task { @MainActor in
            let foto = try? await tarayici.capturePhoto()
            onPhoto(foto?.jpegData(compressionQuality: 0.9))
        }
    }

    static func dismantleUIViewController(_ tarayici: DataScannerViewController, coordinator: Koordinator) {
        tarayici.stopScanning()
    }

    final class Koordinator: NSObject, DataScannerViewControllerDelegate {
        var sonTetik = 0
        private let onText: ([String]) -> Void

        init(onText: @escaping ([String]) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            yay(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            yay(allItems)
        }

        private func yay(_ ogeler: [RecognizedItem]) {
            let satirlar = ogeler.compactMap { oge -> String? in
                if case .text(let metin) = oge { return metin.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
                return nil
            }
            .filter { $0.count >= 2 }
            onText(satirlar)
        }
    }
}
