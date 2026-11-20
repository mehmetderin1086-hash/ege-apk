import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import SwiftData
import UIKit
import Vision

/// Kaynak belgelerdeki şekil, grafik, tablo ve fotoğrafları bulur, yüksek kalitede kırpar ve iyileştirir.
///
/// Kalite yaklaşımı:
/// - PDF: bölge, sayfanın vektör verisinden 3–4× çözünürlükle yeniden çizilir (bulanık büyütme değil, gerçek keskinlik).
/// - Fotoğraf / taranmış görsel: yalnızca perspektif düzeltme ve kırpma; pikseller ve yazılar ORİJİNAL kalır
///   (gürültü azaltma/keskinleştirme küçük etiketleri bozuyordu — kullanıcı isteği).
/// - Tablo: içerik hücre hücre okunur; slaytta düzenlenebilir tablo olarak yeniden dizilir.
/// - Yapay zekâya şekil YENİDEN ÇİZDİRİLMEZ: bilimsel şekillerdeki veriler değişebilir.
enum FigureExtractor {
    static let maxPages = 40
    static let batchSize = 6
    static let maxFigures = 30

    struct Progress: Sendable { var done: Int; var total: Int }

    /// Bir çıkarımın sonucu. Kalıcı duruma (figures.json, eski şekil dosyaları) dokunulmamıştır: çağıran `commit` ile
    /// kalıcı yapar ya da `discard` ile bu çıkarımın dosyalarını siler.
    nonisolated struct Extraction: Sendable, Equatable {
        var figures: [SourceFigure]
        /// Sunucudan yanıt alınamayan parti sayısı ve toplam parti (0: taranacak sayfa bulunamadı).
        var failedBatches: Int
        var totalBatches: Int
        /// Bu çıkarımın kimlik öneki; şekil kimlikleri "<run>-<sıra>".
        var run: String
    }

    /// Bölümün kaynak belgelerinden şekilleri çıkarır ve görsellerini bölüm klasörüne yazar. Var olan şekillere ve
    /// figures.json'a dokunmaz: kimlikler çıkarıma özgüdür ("<run>-<sıra>"), eski dosyaların üstüne yazılmaz; böylece
    /// çıkarım yarıda kalırsa eski destenin şekilleri yerinde durur. İptalde bu çıkarımın yazdığı dosyalar silinir.
    static func extract(_ episode: Episode, context: ModelContext,
                        progress: @escaping (Progress) -> Void) async throws -> Extraction {
        let run = String(UUID().uuidString.prefix(6)).lowercased()
        let documents = (episode.sourceDocumentIDs ?? []).compactMap { DocumentLibrary.fetch($0, context: context) }
        guard !documents.isEmpty else { return Extraction(figures: [], failedBatches: 0, totalBatches: 0, run: run) }
        // Değerler baştan alınır: bölüm üretim sırasında silinirse modele bir daha dokunulmaz.
        let directory = episode.directory

        // Gönderilecek sayfa görüntüleri (belge, sayfa, JPEG) — en fazla 40 sayfa.
        // jpeg: sunucuya giden önizleme; full: fotoğraflarda kırpmanın yapıldığı tam çözünürlüklü düzleştirilmiş görüntü.
        var pages: [(doc: SourceDocument, page: Int, jpeg: Data, size: CGSize, full: Data?)] = []
        for doc in documents where pages.count < maxPages {
            switch doc.kindRaw {
            case "pdf":
                guard let pdf = PDFDocument(url: doc.url) else { continue }
                for index in 0..<min(pdf.pageCount, maxPages - pages.count) {
                    guard let rendered = await renderPreview(url: doc.url, pageIndex: index) else { continue }
                    pages.append((doc, index + 1, rendered.jpeg, rendered.size, nil))
                }
            case "image":
                guard let photo = await preparePhoto(doc.url) else { continue }
                pages.append((doc, 1, photo.jpeg, photo.size, photo.full))
            default: continue
            }
        }
        guard !pages.isEmpty else { return Extraction(figures: [], failedBatches: 0, totalBatches: 0, run: run) }

        var figures: [SourceFigure] = []
        var counter = 0
        var failedBatches = 0
        let total = Int((Double(pages.count) / Double(batchSize)).rounded(.up))
        do {
            for (batchIndex, start) in stride(from: 0, to: pages.count, by: batchSize).enumerated() where figures.count < maxFigures {
                try Task.checkCancellation()
                progress(Progress(done: batchIndex, total: total))
                let batch = Array(pages[start..<min(start + batchSize, pages.count)])
                // Sunucuya sayfa sırasını benzersiz numarayla gönder (birden çok belge olabilir).
                let request = FiguresRequest(pages: batch.enumerated().map { offset, item in
                    FigurePage(page: start + offset + 1, image: item.jpeg.base64EncodedString(), width: Int(item.size.width), height: Int(item.size.height))
                })
                let detected: [DetectedFigure]
                do {
                    detected = try await APIClient.shared.figures(request)
                } catch {
                    try Task.checkCancellation()
                    failedBatches += 1   // diğer sayfalarla devam; çağıran eksik taramayı kullanıcıya bildirir ve sonra yeniden dener
                    continue
                }
                for figure in detected where figures.count < maxFigures {
                    let local = figure.page - start - 1
                    guard batch.indices.contains(local), figure.box.count == 4 else { continue }
                    let item = batch[local]
                    // Çok küçük kutular (logo, ikon) payı eklenmeden önceki ham boyuta göre atlanır.
                    guard (figure.box[3] - figure.box[1]) > 50, (figure.box[2] - figure.box[0]) > 50 else { continue }
                    let box = normalizedRect(figure.box)
                    let id = "\(run)-\(counter + 1)"
                    let image: UIImage?
                    if item.doc.kindRaw == "pdf" {
                        image = await renderRegion(url: item.doc.url, pageIndex: item.page - 1, box: box, enhance: false)
                    } else {
                        image = await crop(item.full ?? item.jpeg, box: box)
                    }
                    guard let image, await write(image, to: figureFile(id, in: directory)) else { continue }
                    counter += 1
                    figures.append(SourceFigure(id: id, kind: figure.kind, caption: figure.caption, page: item.page,
                                                documentName: item.doc.name, table: figure.table))
                }
            }
            try Task.checkCancellation()
        } catch {
            discard(Extraction(figures: figures, failedBatches: failedBatches, totalBatches: total, run: run), in: directory)
            throw error
        }
        progress(Progress(done: total, total: total))
        return Extraction(figures: figures, failedBatches: failedBatches, totalBatches: total, run: run)
    }

    // MARK: - Kalıcılık (çıkarım sonucu ancak yeni deste kaydedilince eskilerin yerine geçer)

    /// Video dersinden türeyen bölümlerde şekiller video kareleridir (`TranscriptFormat.figureID`): belgeden yeniden
    /// çıkarılamaz, bu yüzden belge şekilleri yenilenirken korunur.
    nonisolated static let videoFramePrefix = "yt_"
    nonisolated static func isVideoFrame(_ id: String) -> Bool { id.hasPrefix(videoFramePrefix) }

    nonisolated static func figureFile(_ id: String, in directory: URL) -> URL { directory.appending(path: "figure_\(id).png") }

    /// "figure_<kimlik>.png" → kimlik; başka dosyada nil (figuremap.json, labels_*.json dışarıda kalır).
    nonisolated static func figureID(ofFile url: URL) -> String? {
        let name = url.lastPathComponent
        guard name.hasPrefix("figure_"), url.pathExtension == "png" else { return nil }
        return String(name.dropFirst("figure_".count).dropLast(".png".count))
    }

    /// Şekiller yeniden kesilmeli mi? Belge şekli hiç yoksa ya da liste eskimişse (yeni fotoğraf eklendi, önceki tarama eksik kaldı).
    nonisolated static func needsExtraction(existing: [SourceFigure], stale: Bool) -> Bool {
        stale || !existing.contains { !isVideoFrame($0.id) }
    }

    /// Yeni belge şekilleri eskilerinin yerine geçer; video kareleri korunur.
    nonisolated static func merged(existing: [SourceFigure], extracted: [SourceFigure]) -> [SourceFigure] {
        existing.filter { isVideoFrame($0.id) } + extracted
    }

    /// Çıkarımdan sonra kullanılacak liste. Hiç sayfa taranamadıysa (belge açılamadı ya da bütün partiler düştü) eldeki
    /// şekiller korunur: boş sonuç, çalışan şekillerin yerine geçmez.
    nonisolated static func figures(after r: Extraction, existing: [SourceFigure]) -> [SourceFigure] {
        guard r.totalBatches > 0, !(r.figures.isEmpty && r.failedBatches > 0) else { return existing }
        return merged(existing: existing, extracted: r.figures)
    }

    /// Eksik tarama için kullanıcıya gösterilecek not; tarama tamsa nil.
    nonisolated static func note(for r: Extraction) -> String? {
        guard r.failedBatches > 0 else { return nil }
        if r.figures.isEmpty {
            return "Kaynak sayfalar taranamadı (\(r.failedBatches)/\(r.totalBatches)); yeni kaynak görseli eklenmedi. Desteyi yeniden oluşturduğunda yeniden denenir."
        }
        return "Kaynak sayfaların bir bölümü taranamadı (\(r.failedBatches)/\(r.totalBatches)). Bulunan şekiller kullanıldı; desteyi yeniden oluşturduğunda eksikler yeniden denenir."
    }

    /// Çıkarım kalıcı yapılmadan bırakılınca (üretim hata verdi ya da durduruldu) kalacak not. Bulunan şekiller
    /// `discard` ile silindiği için "bulunan şekiller kullanıldı" notu eski destenin altında kalmaz; hiç şekil
    /// bulunamadıysa not ("yeni kaynak görseli eklenmedi") hâlâ doğrudur.
    nonisolated static func note(afterDiscarding r: Extraction) -> String? {
        r.figures.isEmpty ? note(for: r) : nil
    }

    /// Kurulum formundaki kaynak satırı (saf; test edilir). `warning`: ne belge ne şekil var, kullanıcı fotoğraf eklemeye yönlendirilir.
    nonisolated static func sourceSummary(documents: Int, figures: [SourceFigure]) -> (text: String, warning: Bool) {
        if documents == 0 {
            guard !figures.isEmpty else {
                return ("Bu bölümde kayıtlı kaynak belge yok. Kitap sayfasının fotoğrafını ekle; şekiller kesilip slaytlara konur.", true)
            }
            let frames = figures.allSatisfy { isVideoFrame($0.id) }
            return (frames ? "\(figures.count) kaynak görseli (video kareleri)" : "\(figures.count) kaynak görseli", false)
        }
        return (figures.isEmpty ? "\(documents) kaynak belge · şekiller deste oluşturulurken kesilir"
                                : "\(documents) kaynak belge · \(figures.count) şekil kesildi", false)
    }

    /// Etiket sınavının OCR önbelleği; ad `LabelCard.cacheURL` ile aynı olmalı (testte karşılaştırılır).
    nonisolated static func labelCacheFile(_ id: String, in directory: URL) -> URL { directory.appending(path: "labels_\(id).json") }

    /// Listede olmayan şekil dosyalarını siler. Video kareleri listede olmasa da silinmez (yeniden üretilemez;
    /// şekil kartları dosyayı doğrudan açar). Etiket önbelleği duran şekil de silinmez: etiket tekrar kartları
    /// (`ReviewCard.figureID`) şekli ve kutuları eski kimlikle açar, yeniden kesimde kimlikler değişir.
    nonisolated static func prune(in directory: URL, keeping ids: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let id = figureID(ofFile: file), !ids.contains(id), !isVideoFrame(id),
                  !FileManager.default.fileExists(atPath: labelCacheFile(id, in: directory).path) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// "Şekiller eskidi" işareti (figures.stale): sonraki deste üretimi belgeleri yeniden tarar. Şekilleri silmek yerine
    /// kullanılır; üretim başarısız olursa ya da durdurulursa eski şekiller ve deste yerinde kalır.
    nonisolated static func staleURL(_ directory: URL) -> URL { directory.appending(path: "figures.stale") }
    nonisolated static func markStale(_ directory: URL) { try? Data().write(to: staleURL(directory)) }
    nonisolated static func isStale(_ directory: URL) -> Bool { FileManager.default.fileExists(atPath: staleURL(directory).path) }
    nonisolated static func clearStale(_ directory: URL) { try? FileManager.default.removeItem(at: staleURL(directory)) }

    /// Çıkarımı kalıcı yapar: figures.json güncellenir, listeden düşen eski belge şekillerinin dosyaları silinir
    /// (etiket kartlarının kullandıkları dışında). Tarama eksikse işaret konur (sonraki üretim yeniden dener), tamsa kaldırılır.
    static func commit(_ r: Extraction, to episode: Episode) {
        guard r.totalBatches > 0, episode.modelContext != nil else { return }
        let directory = episode.directory
        let old = episode.sourceFigures
        let list = figures(after: r, existing: old)
        if list != old {
            episode.sourceFigures = list
            // Liste yazılamadıysa dosyalara dokunma (eski liste eski dosyaları göstermeye devam eder).
            guard episode.sourceFigures == list else { return }
            // Kimlikler değişti: dinlerken gösterilen şekil eşlemesi yeniden kurulsun.
            if Set(old.map(\.id)) != Set(list.map(\.id)) { episode.figureMap = nil }
        }
        prune(in: directory, keeping: Set(list.map(\.id)))
        if r.failedBatches > 0 { markStale(directory) } else { clearStale(directory) }
    }

    /// Kalıcı yapılmayan çıkarımın dosyalarını siler (üretim hata verdi ya da durduruldu).
    nonisolated static func discard(_ r: Extraction, in directory: URL) {
        for figure in r.figures { try? FileManager.default.removeItem(at: figureFile(figure.id, in: directory)) }
    }

    /// Fotoğraf belgesini sunucuya gidecek önizlemeye ve kırpmanın yapıldığı tam çözünürlüklü kopyaya çevirir.
    /// 4200 px'e yeniden çizim ve JPEG kodlama fotoğraf başına yarım saniyeyi bulur; ana iş parçacığı dışında yapılır.
    @concurrent
    static func preparePhoto(_ url: URL) async -> (jpeg: Data, size: CGSize, full: Data)? {
        // Yön (EXIF) düzeltilmiş hâli: sunucunun kutuları ile kırpma aynı koordinat uzayında olsun.
        // Kitap fotoğrafı: sayfa bulunup perspektifi düzeltilir (arka plan ve eğiklik gider).
        guard let original = UIImage(contentsOfFile: url.path)?.normalizedUp(maxSide: 4200),
              let image = await flattenPage(original),
              let full = image.jpegData(compressionQuality: 0.95),
              let jpeg = image.normalizedUp(maxSide: 1600).jpegData(compressionQuality: 0.8) else { return nil }
        return (jpeg, image.size, full)
    }

    /// PNG kodlama ve yazma ana iş parçacığı dışında; başarısızsa false.
    @concurrent
    static func write(_ image: UIImage, to url: URL) async -> Bool {
        guard let png = image.pngData() else { return false }
        return (try? png.write(to: url, options: .atomic)) != nil
    }

    /// [ymin, xmin, ymax, xmax] (0–1000) → 0…1 dikdörtgen (sol üst köken), %2 pay ile.
    static func normalizedRect(_ box: [Double]) -> CGRect {
        let ymin = max(0, min(1000, box[0])) / 1000, xmin = max(0, min(1000, box[1])) / 1000
        let ymax = max(0, min(1000, box[2])) / 1000, xmax = max(0, min(1000, box[3])) / 1000
        let pad = 0.02
        let x0 = max(0, xmin - pad), y0 = max(0, ymin - pad), x1 = min(1, xmax + pad), y1 = min(1, ymax + pad)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    // MARK: - Çizim

    /// Sayfa önizlemesi (en uzun kenar 1400 px, JPEG %75) — şekil tespiti için.
    @concurrent
    static func renderPreview(url: URL, pageIndex: Int) async -> (jpeg: Data, size: CGSize)? {
        guard let page = PDFDocument(url: url)?.page(at: pageIndex) else { return nil }
        let bounds = displaySize(page)
        let scale = 1400 / max(bounds.width, bounds.height)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        return image.jpegData(compressionQuality: 0.75).map { ($0, image.size) }
    }

    /// Sayfanın görünür boyutu (döndürme uygulanmış).
    nonisolated static func displaySize(_ page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        return abs(page.rotation) % 180 == 90 ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }

    /// Bölgeyi PDF'in vektör verisinden yüksek çözünürlükte çizer (uzun kenar ≈ 1800 px).
    @concurrent
    static func renderRegion(url: URL, pageIndex: Int, box: CGRect, enhance: Bool) async -> UIImage? {
        guard let page = PDFDocument(url: url)?.page(at: pageIndex) else { return nil }
        // page.draw(with:to:) kutu kökenini ve döndürmeyi kendisi uygular: çizim alanı (0,0)–görünür boyut.
        // Kutu sol üstten (0…1); PDF koordinatları sol alttan.
        let bounds = displaySize(page)
        let region = CGRect(x: box.minX * bounds.width, y: (1 - box.maxY) * bounds.height,
                            width: box.width * bounds.width, height: box.height * bounds.height)
        guard region.width > 1, region.height > 1 else { return nil }
        let scale = min(8, 1800 / max(region.width, region.height))
        let size = CGSize(width: (region.width * scale).rounded(), height: (region.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            // PDF koordinatları sol alttan başlar: çevir, bölgeye kaydır, ölçekle.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -region.minX, y: -region.minY)
            page.draw(with: .mediaBox, to: cg)
        }
        return enhance ? Enhancer.photo(image) : image   // vektör çizim zaten keskin; taranmış sayfada da orijinal kalsın
    }

    /// Fotoğraftaki belgeyi (sayfa/kitap açılımı) bulur ve dik açılı düz görüntüye çevirir.
    /// Belge bulunamazsa ya da çok küçükse görüntü olduğu gibi döner.
    @concurrent
    static func flattenPage(_ image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        guard let quad = request.results?.first, quad.confidence > 0.6,
              quad.boundingBox.width * quad.boundingBox.height > 0.35 else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // Vision: sol alt köken, 0…1 — Core Image ile aynı.
        func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cg)
        filter.topLeft = point(quad.topLeft).cgPointValue
        filter.topRight = point(quad.topRight).cgPointValue
        filter.bottomLeft = point(quad.bottomLeft).cgPointValue
        filter.bottomRight = point(quad.bottomRight).cgPointValue
        guard let output = filter.outputImage,
              let flat = CIContext().createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: flat)
    }

    /// Fotoğraftan kırpma: filtre yok, pikseller olduğu gibi (etiket yazıları orijinal).
    @concurrent
    static func crop(_ jpeg: Data, box: CGRect) async -> UIImage? {
        guard let cg = UIImage(data: jpeg)?.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard let cropped = cg.cropping(to: CGRect(x: box.minX * w, y: box.minY * h, width: box.width * w, height: box.height * h)) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

/// Core Image tabanlı görsel iyileştirme.
nonisolated enum Enhancer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Fotoğraf/taranmış görsel: kısa kenar 1200 px'e kadar Lanczos büyütme, gürültü azaltma, keskinleştirme, hafif kontrast.
    static func photo(_ image: UIImage) -> UIImage {
        guard var ci = CIImage(image: image) else { return image }
        let shortSide = min(ci.extent.width, ci.extent.height)
        if shortSide < 1200 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = ci
            lanczos.scale = Float(min(3, 1200 / max(shortSide, 1)))
            lanczos.aspectRatio = 1
            ci = lanczos.outputImage ?? ci
        }
        let noise = CIFilter.noiseReduction()
        noise.inputImage = ci
        noise.noiseLevel = 0.015
        noise.sharpness = 0.5
        ci = noise.outputImage ?? ci
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ci
        sharpen.sharpness = 0.45
        ci = sharpen.outputImage ?? ci
        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.contrast = 1.06
        color.saturation = 1.05
        ci = color.outputImage ?? ci
        guard let out = context.createCGImage(ci, from: ci.extent) else { return image }
        return UIImage(cgImage: out)
    }

    /// Vektörden çizilmiş şekil: yalnızca hafif keskinleştirme (taranmış PDF sayfalarına da yardımcı olur).
    static func crisp(_ image: UIImage) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ci
        sharpen.sharpness = 0.25
        guard let output = sharpen.outputImage, let out = context.createCGImage(output, from: ci.extent) else { return image }
        return UIImage(cgImage: out)
    }
}

extension UIImage {
    /// Yönü .up olan, en uzun kenarı en fazla maxSide piksel kopya.
    nonisolated func normalizedUp(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height) * scale
        let ratio = min(1, maxSide / max(longest, 1))
        let target = CGSize(width: (size.width * scale * ratio).rounded(), height: (size.height * scale * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
