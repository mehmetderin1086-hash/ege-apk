// Fotoğraftan kitap okuma akışları: ayrı kitaplar, raf fotoğrafı, tek kitabın sayfaları, Gemini gruplama.
// ContentView'dan (P8) taşındı; davranış değişmedi.
import SwiftUI
import SwiftData
import PhotosUI
@preconcurrency import Vision
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
#if os(iOS)
import UIKit
import VisionKit
#endif

extension ContentView {
    /// Her fotoğrafı AYRI kitap olarak işler (farklı kitapların kapakları için).
    func processSeparateBooks(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, acceptsActiveCatalogResult() else { return }
        let sources = items.enumerated().map { index, item in
            ScanPhotoImportSource(selectionIndex: index, pickerIdentifier: item.itemIdentifier)
        }
        for (source, item) in zip(sources, items) { retainedPhotoSelections[source.id] = item }
        await processSeparatePhotoSources(sources)
    }

    /// Failed decoded images are retained locally and retried independently.
    /// A failed Photos load retains identity/error; after relaunch the user must
    /// reselect that source, rather than the app claiming inaccessible pixels exist.
    func processSeparatePhotoSources(_ sources: [ScanPhotoImportSource], resuming saved: ScanSession? = nil,
        only sourceIDs: Set<UUID>? = nil) async {
        guard !sources.isEmpty, acceptsActiveCatalogResult() else { return }
        isRecognizing = true; isCancelRequested = false
        defer { isRecognizing = false; scanProgress = 0; scanTotal = 0 }
        if let saved {
            do {
                let recovered = try ScanSessionStore.reconciled(saved, context: modelContext)
                scanSession = recovered; lastSessionInserted = recovered.insertedIDs; lastSessionMerged = recovered.mergedCopies
                bulkPendingBooks = recovered.pendingBooks
            } catch { recognitionError = "Fotoğraf oturumu açılamadı: \(error.localizedDescription)"; return }
        } else {
            beginAddSession()
            scanSession?.title = "Toplu fotoğraf okuma"
            scanSession?.separatePhotoSources = sources
        }
        let completed = Set(scanSession?.savedOperationIDs ?? [])
        let eligible = sources.filter { $0.needsRead && !completed.contains($0.id) && (sourceIDs?.contains($0.id) ?? true) }
        scanProgress = 0; scanTotal = eligible.count
        persistScanSession()
        var drafts: [BookDraft] = [], startIndex = 0
        while startIndex < eligible.count {
            guard !isCancelRequested, acceptsActiveCatalogResult() else { break }
            let chunk = Array(eligible[startIndex..<min(startIndex + 3, eligible.count)]); startIndex += chunk.count
            var loaded: [ScanPhotoImportSource] = []
            // Retain every loaded source BEFORE its provider/OCR suspension.
            for var source in chunk {
                guard !isCancelRequested, acceptsActiveCatalogResult() else { break }
                let cached = source.imageIndex.flatMap { index in
                    (scanSession?.sourceImages ?? []).indices.contains(index) ? scanSession?.sourceImages?[index] : nil
                }
                if cached == nil {
                    do {
                        guard let item = retainedPhotoSelections[source.id] else { throw ScanPhotoImportWorker.Failure.reselect }
                        guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else { throw ScanPhotoImportWorker.Failure.noData }
                        guard acceptsActiveCatalogResult() else { return }
                        var session = scanSession ?? ScanSession(kind: .photo, title: "Toplu fotoğraf okuma")
                        ScanPhotoImportOutcome(source: source, image: data, book: nil).apply(to: &session)
                        scanSession = session
                        source = session.separatePhotoSources?.first { $0.id == source.id } ?? source
                        persistScanSession()
                    } catch {
                        guard acceptsActiveCatalogResult() else { return }
                        source.status = .failed; source.errorMessage = error.localizedDescription
                        if var session = scanSession { ScanPhotoImportOutcome(source: source, image: nil, book: nil).apply(to: &session); scanSession = session }
                        persistScanSession(); scanProgress += 1
                        continue
                    }
                }
                loaded.append(source)
            }
            var originals: [UUID: BookDraft] = [:]
            await withTaskGroup(of: ScanPhotoImportOutcome.self) { group in
                for source in loaded {
                    let image = source.imageIndex.flatMap { index in
                        (scanSession?.sourceImages ?? []).indices.contains(index) ? scanSession?.sourceImages?[index] : nil
                    }
                    group.addTask { @MainActor in
                        await ScanPhotoImportWorker.read(source, cachedImage: image, load: { throw ScanPhotoImportWorker.Failure.reselect }, parse: { data in
                            var result = try await self.draftFromImageData(data)
                            guard self.acceptsActiveCatalogResult() else { throw CancellationError() }
                            result.id = source.id
                            originals[source.id] = result
                            return self.book(from: result)
                        })
                    }
                }
                for await generated in group {
                    guard acceptsActiveCatalogResult() else { group.cancelAll(); return }
                    var result = generated
                    if isCancelRequested {
                        group.cancelAll()
                        result.book = nil
                        result.source.status = .pending
                        result.source.errorMessage = "Okuma iptal edildi; kaynak fotoğraf korunuyor."
                    }
                    scanProgress += 1
                    if var session = scanSession {
                        result.apply(to: &session)
                        if let imageIndex = session.separatePhotoSources?.first(where: { $0.id == result.source.id })?.imageIndex,
                           let original = originals[result.source.id] {
                            session.bookSources = session.bookSources ?? [:]
                            session.bookSources?[result.source.id] = ScanBookSource(photoIndex: imageIndex,
                                box: [0, 0, 1000, 1000], method: original.recognizedByGemini ? "gemini" : "vision", confidence: nil)
                        }
                        scanSession = session
                    }
                    if let parsed = result.book, let original = originals[result.source.id] {
                        bulkPendingBooks.removeAll { $0.id == parsed.id }; bulkPendingBooks.append(parsed)
                        persistScanSession()
                        acceptOrQueue(original, reviewQueue: &drafts)
                    } else { persistScanSession() }
                }
            }
        }
        guard acceptsActiveCatalogResult() else { return }
        routeBatch(drafts)
        let failed = (scanSession?.separatePhotoSources ?? []).filter { $0.status == .failed }.count
        let pending = (scanSession?.separatePhotoSources ?? []).filter { $0.status == .pending }.count
        if failed > 0 || pending > 0 {
            bulkMessage = "Başarılı kayıtlar korundu. \(failed) fotoğraf okunamadı, \(pending) kaynak bekliyor; Ekle’deki Son Eklemeler bölümünden yeniden deneyin."
        }
        persistScanSession()
    }

    /// "Raf Karesi": tek fotoğrafta yan yana dizilmiş birçok kitap (ön ya da arka yüz).
    /// Her kitap ayrı bulunur (Vision barkod + Gemini, konumla eşlenir); ISBN'i olan Amazon'dan,
    /// olmayan ad + yazarla doldurulur. Adı, yazarı ve kapağı tam gelen ve güvenilir olanlar onay
    /// beklemeden kaydedilir; eksik ya da şüpheli kalanlar onay kuyruğuna düşer.
    func processShelfPhotos(_ items: [PhotosPickerItem]) async {
        guard acceptsActiveCatalogResult() else { return }
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
        }
        guard acceptsActiveCatalogResult() else { return }
        await processShelfImages(images)
    }

    func processShelfImages(_ photos: [Data], resuming saved: ScanSession? = nil) async {
        guard acceptsActiveCatalogResult() else { return }
        guard !photos.isEmpty else { return }
        isRecognizing = true
        isCancelRequested = false
        scanTotal = photos.count
        scanProgress = 0
        defer {
            isRecognizing = false
            scanTotal = 0
            scanProgress = 0
        }
        if let saved {
            let recovered = (try? ScanSessionStore.reconciled(saved, context: modelContext)) ?? saved
            scanSession = recovered
            lastSessionInserted = recovered.insertedIDs
            lastSessionMerged = recovered.mergedCopies
            shelfPhotoRelation = recovered.photoRelation ?? .overlapping
        } else { beginAddSession() }
        let restoredDrafts = Dictionary(uniqueKeysWithValues: (scanSession?.pendingBooks ?? []).map { ($0.id, $0) })
        scanSession?.sourceImages = photos
        scanSession?.photoRelation = shelfPhotoRelation
        if scanSession?.photoBookKeys == nil { scanSession?.photoBookKeys = [:] }
        if scanSession?.bookSources == nil { scanSession?.bookSources = [:] }
        persistScanSession()

        // 1) Her karedeki kitaplar (barkod ve Gemini birlikte); kareler kapak kesiti için saklanır
        var detected: [AlgilananKitap] = []
        var geminiFailures = 0
        for (photoIndex, data) in photos.enumerated() {
            if isCancelRequested { break }
            defer { scanProgress += 1 }
            let outcome = await CokluKitapAlgilayici.algila(data)
            guard acceptsActiveCatalogResult() else { return }
            if let error = outcome.geminiHatasi {
                geminiFailures += 1
                scanSession?.photoErrors?[photoIndex] = error
            } else { scanSession?.photoErrors?.removeValue(forKey: photoIndex) }
            persistScanSession()
            detected.append(contentsOf: outcome.kitaplar.map { found in
                var tagged = found
                tagged.photoIndex = photoIndex
                return tagged
            })
        }
        if shelfPhotoRelation == .overlapping { detected = CokluKitapAlgilayici.tekillestir(detected) }
        let geminiNote = geminiFailures > 0 ? " Gemini yanıt vermedi; yalnız barkodlar okundu, kapağı görünen kitaplar eklenmedi." : ""
        guard !detected.isEmpty else {
            if isCancelRequested { return }
            recognitionError = GeminiSettings.isOCREnabled
                ? "Fotoğraflarda kitap bulunamadı. Kitapları yan yana, barkodları ya da kapakları net görünecek şekilde çekin.\(geminiNote)"
                : "Fotoğraflarda okunabilir barkod bulunamadı. Ön yüzden tanıma için Ayarlar'dan Gemini'yi açın."
            return
        }

        // 2) Her kitap için ağdan bilgi; 3'erli paralel (Amazon engellemesin)
        scanTotal = detected.count
        scanProgress = 0
        var built: [(draft: BookDraft, found: AlgilananKitap)] = []
        var startIndex = 0
        while startIndex < detected.count {
            if isCancelRequested { break }
            let chunk = Array(detected[startIndex..<min(startIndex + 3, detected.count)])
            startIndex += chunk.count

            await withTaskGroup(of: (BookDraft, AlgilananKitap).self) { group in
                for found in chunk {
                    let photo = found.photoIndex.flatMap { photos.indices.contains($0) ? photos[$0] : nil }
                    group.addTask { @MainActor in
                        (await self.shelfDraft(from: found, photo: photo), found)
                    }
                }
                for await (shelfBookDraft, found) in group {
                    guard acceptsActiveCatalogResult() else { group.cancelAll(); return }
                    scanProgress += 1
                    built.append((shelfBookDraft, found))
                }
            }
        }

        guard acceptsActiveCatalogResult() else { return }
        // 3) Aynı kitabın iki okuması (barkod + metin) tek taslağa iner; sonra kaydet ya da kuyruğa al
        var savedCount = 0
        var queued: [BookDraft] = []
        // Sonuç anahtarı taslak kimliğini yeniden denemeler arasında korur.
        for index in built.indices {
            let found = built[index].found
            let key = photoBookKey(found)
            let id = scanSession?.photoBookKeys?[key] ?? UUID()
            scanSession?.photoBookKeys?[key] = id
            if let pending = restoredDrafts[id] { built[index].draft = BookDraft(book: pending) }
            else { built[index].draft.id = id }
            scanSession?.bookSources?[id] = ScanBookSource(photoIndex: found.photoIndex ?? 0,
                box: found.box, method: found.barkodlu ? "barcode" : "gemini", confidence: found.confidence)
        }
        for var shelfBookDraft in mergeShelfDrafts(built) {
            let operationID = shelfBookDraft.existingBookID ?? shelfBookDraft.id
            if (scanSession?.savedOperationIDs ?? []).contains(operationID) { continue }
            reconcileWithCatalog(&shelfBookDraft)
            let isComplete = shelfBookDraft.lowConfidenceFields.isEmpty
                && !shelfBookDraft.title.isEmpty
                && !shelfBookDraft.author.isEmpty
                && shelfBookDraft.coverData != nil
            if isComplete && GeminiSettings.isQuickSaveEnabled {
                let outcome = saveBook(book(from: shelfBookDraft))
                if outcome.succeeded {
                    recordSession(outcome)
                    savedCount += 1
                } else { queued.append(shelfBookDraft) }
            } else {
                queued.append(shelfBookDraft)
            }
        }

        guard acceptsActiveCatalogResult() else { return }
        if savedCount > 0 { CatalogBackup.saveLight(catalogBooks) }
        routeBatch(queued)
        let total = savedCount + queued.count
        let message: String
        if isCancelRequested {
            message = "Tarama durduruldu: \(savedCount) kitap kaydedildi, \(queued.count) tanesi onay bekliyor."
        } else if queued.isEmpty {
            message = "\(total) kitap bulundu, hepsi kataloğa eklendi.\(geminiNote)"
        } else {
            message = "\(total) kitap bulundu: \(savedCount) kaydedildi, \(queued.count) tanesi onay bekliyor.\(geminiNote)"
        }
        bulkMessage = message
        AccessibilityNotification.Announcement(message).post()
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(savedCount > 0 ? .success : .warning)
#endif
    }

    func photoBookKey(_ found: AlgilananKitap) -> String {
        let isbn = found.temizISBN
        let identity = isbn.isEmpty ? [found.temizAd, found.temizYazar, found.publisher ?? ""].map(CatalogMatcher.normalize).joined(separator: "|") : isbn
        return identity + (shelfPhotoRelation == .distinct ? "|photo:\(found.photoIndex ?? 0)" : "")
    }

    /// Raf karesinde bulunan tek kitabı ağdan doldurur.
    /// - ISBN barkoddan geldiyse doğrudan güvenilir. Metinden okunmuşsa (Gemini rakamları yanılabilir,
    ///   komşu kitabın numarasını kopyalayabilir) yalnız güven eşiğini aşınca onaysız kaydedilir.
    /// - ISBN yoksa ad + yazarla aranır; gelen sonucun adı fotoğraftaki adla benzer değilse ya da
    ///   fotoğrafta okunan yazarla uyuşmuyorsa ("Şiirler" gibi ortak adlar) GÜVENİLMEZ sayılır ve
    ///   Amazon verisi uygulanmaz — yanlış kitap kaydetmek yerine onay kuyruğuna düşer.
    /// - Amazon kapak vermediyse kitabın fotoğraftaki kendi kesiti kapak (ön yüz) ya da arka kapak olur.
    func shelfDraft(from found: AlgilananKitap, photo: Data?) async -> BookDraft {
        var result = BookDraft()
        result.recognitionSource = found.barkodlu ? "barcode" : "gemini"
        result.isbn = found.temizISBN
        result.title = found.temizAd
        result.author = found.temizYazar
        result.publisher = (found.publisher ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        result.quantity = found.nusha

        if !result.isbn.isEmpty {
            if let meta = await BookMetadataService.fetch(
                isbn: result.isbn, title: result.title, author: result.author, publisher: result.publisher
            ) {
                AmazonBookScraper.apply(metadata: meta, to: &result, overwrite: true)
                if !found.barkodlu, (found.confidence ?? 0) < CokluKitapAlgilayici.guvenEsigi {
                    result.lowConfidenceFields.formUnion(["title", "author", "isbn"])
                }
            } else {
                // Çevrimiçi kaynaklar bulamadı: Gemini'nin kendi bilgisi denenir (ad/yazar işaretli kalır)
                await GeminiBookRecognizer.lookupISBN(result.isbn, into: &result)
                result.lowConfidenceFields.formUnion(["title", "author"])
            }
        } else if let meta = await BookMetadataService.search(
            title: result.title, author: result.author, publisher: result.publisher
        ), CatalogMatcher.isSimilarTitle(meta.title, result.title) {
            let authorMismatch = !found.temizYazar.isEmpty && !meta.author.isEmpty
                && !CatalogMatcher.isSimilar(meta.author, found.temizYazar)
            if authorMismatch {
                result.lowConfidenceFields.formUnion(["title", "author"])
            } else {
                AmazonBookScraper.apply(metadata: meta, to: &result, overwrite: true)
                // Fotoğrafta yazar okunmadıysa yalnız adla eşleşme ("Şiirler", "Masallar") yanlış
                // kitap olabilir: onaya düşer
                if found.temizYazar.isEmpty { result.lowConfidenceFields.insert("author") }
            }
        } else {
            result.lowConfidenceFields.formUnion(["title", "author"])
        }

        // Kapak kesiti: kırpma ana iş parçacığında yapılmaz (3000 px çözme yüzlerce ms sürer)
        if let photo, let kutu = found.kutu, result.coverData == nil || result.backCoverData == nil {
            let kesit = await Task.detached(priority: .utility) {
                CokluKitapAlgilayici.kapakKesiti(photo, kutu: kutu)
            }.value
            if let kesit {
                if found.onYuz {
                    if result.coverData == nil { result.coverData = kesit }
                } else if result.backCoverData == nil {
                    result.backCoverData = kesit
                }
            }
        }

        if result.title.isEmpty { result.lowConfidenceFields.insert("title") }
        return result
    }

    /// Aynı kitabı temsil eden taslakları birleştirir: aynı ISBN ya da (ISBN çakışmıyorsa) benzer
    /// ad + uyumlu yazar. Daha dolu olan (ISBN, kapak, güven) tutulur. Adet: aynı karede KESİŞMEYEN
    /// iki kutudan geldilerse iki ayrı fiziksel kitaptır ve toplanır (biri arkadan barkodla, öteki
    /// önden adıyla okunmuş iki nüsha); aksi hâlde aynı kitabın iki okumasıdır, en yüksek alınır.
    func mergeShelfDrafts(_ items: [(draft: BookDraft, found: AlgilananKitap)]) -> [BookDraft] {
        func score(_ candidate: BookDraft) -> Int {
            (candidate.title.isEmpty ? 0 : 2)
                + (ISBNFormatter.normalize(candidate.isbn).isEmpty ? 0 : 2)
                + (candidate.coverData == nil ? 0 : 1)
                + (candidate.lowConfidenceFields.isEmpty ? 1 : 0)
        }
        func isSame(_ a: BookDraft, _ b: BookDraft) -> Bool {
            let isbnA = ISBNFormatter.normalize(a.isbn)
            let isbnB = ISBNFormatter.normalize(b.isbn)
            if !isbnA.isEmpty, !isbnB.isEmpty { return isbnA == isbnB }
            guard !a.title.isEmpty, !b.title.isEmpty, CatalogMatcher.isSimilarTitle(a.title, b.title) else { return false }
            return a.author.isEmpty || b.author.isEmpty || CatalogMatcher.isSimilar(a.author, b.author)
        }
        // Aynı karede iki kutu: komşu kitapların kutuları birkaç piksel çakışabilir, bu yüzden
        // "kesişmiyor" yerine "küçük kutunun %30'undan azı ortak" ölçütü kullanılır. Sanal barkod
        // kutusu (bağlanamayan barkod) öteki kutunun kenarına yakınsa aynı kitabın kaymış kutusudur.
        func separatePhysicalBooks(_ a: AlgilananKitap, _ b: AlgilananKitap) -> Bool {
            guard let photoA = a.photoIndex, let photoB = b.photoIndex else { return false }
            if photoA != photoB { return shelfPhotoRelation == .distinct }
            guard let boxA = a.kutu, let boxB = b.kutu else { return false }
            let sanalA = boxA.width < 0.05 && boxA.height < 0.05
            let sanalB = boxB.width < 0.05 && boxB.height < 0.05
            if sanalA != sanalB {
                let barkod = sanalA ? CGPoint(x: boxA.midX, y: boxA.midY) : CGPoint(x: boxB.midX, y: boxB.midY)
                let kutu = sanalA ? boxB : boxA
                return CokluKitapAlgilayici.kenaraUzaklik(barkod, kutu) > 0.1
            }
            let ortak = boxA.intersection(boxB)
            guard !ortak.isNull, ortak.width > 0, ortak.height > 0 else { return true }
            let kucukAlan = min(boxA.width * boxA.height, boxB.width * boxB.height)
            return (ortak.width * ortak.height) / kucukAlan < 0.3
        }

        var kept: [(draft: BookDraft, found: AlgilananKitap)] = []
        for item in items {
            if let index = kept.firstIndex(where: { isSame($0.draft, item.draft) }) {
                let quantity = min(AlgilananKitap.enFazlaNusha, separatePhysicalBooks(kept[index].found, item.found)
                    ? kept[index].draft.quantity + item.draft.quantity
                    : max(kept[index].draft.quantity, item.draft.quantity))
                if score(item.draft) > score(kept[index].draft) { kept[index] = item }
                kept[index].draft.quantity = quantity
            } else {
                kept.append(item)
            }
        }
        return kept.map(\.draft)
    }

    /// "Kitap Tara": aynı kitabın birden çok fotoğrafı (kapak + künye + son sayfa)
    /// PDF akışındaki gibi TEK kitapta birleştirilir.
    func processSingleBookPhotos() async {
        guard acceptsActiveCatalogResult() else { return }
        guard !singleBookPhotos.isEmpty else { return }
        let items = singleBookPhotos
        await mergePhotosIntoOneBook(items)
        guard acceptsActiveCatalogResult() else { return }
        if singleBookPhotos == items { singleBookPhotos = [] }
    }

    /// Karışık fotoğraflar: Gemini hangi fotoğrafların aynı kitaba ait olduğunu bulur, her grup
    /// tek kitap olarak okunur ve hepsi onay kuyruğuna gider.
    func groupPhotosWithGemini(_ items: [PhotosPickerItem]) async {
        guard acceptsActiveCatalogResult() else { return }
        isRecognizing = true
        var datas: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
        }
        guard acceptsActiveCatalogResult() else { return }
        guard datas.count == items.count,
              let groups = try? await GeminiFotoGruplayici.grupla(datas) else {
            isRecognizing = false
            // Gruplama yapılamadı (bağlantı/okuma): güvenli yol, her fotoğraf ayrı kitap
            guard acceptsActiveCatalogResult() else { return }
            await processSeparateBooks(items)
            return
        }
        isRecognizing = false
        var drafts: [BookDraft] = []
        for group in groups {
            if isCancelRequested { break }
            await mergePhotosIntoOneBook(group.map { items[$0] }) { drafts.append($0) }
        }
        guard acceptsActiveCatalogResult() else { return }
        routeBatch(drafts)
        bulkMessage = "\(items.count) fotoğraf \(groups.count) kitaba gruplandı; kontrol edip kaydedin."
    }

    func mergePhotosIntoOneBook(_ items: [PhotosPickerItem], deliver: ((BookDraft) -> Void)? = nil) async {
        guard acceptsActiveCatalogResult() else { return }
        guard !items.isEmpty else { return }

        isRecognizing = true
        scanTotal = items.count
        scanProgress = 0
        defer {
            isRecognizing = false
            scanTotal = 0
            scanProgress = 0
        }

        isCancelRequested = false
        var lines: [OCRLine] = []
        var barcodeISBN: String?
        var cover: Data?
        var extraImages: [Data] = []

        // Fotoğraflar önce yüklenir ki Gemini (ana OCR) tüm sayfaları görerek Vision
        // motorlarıyla AYNI ANDA çalışabilsin; toplam süre uzamaz.
        var loadedImages: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loadedImages.append(data)
            }
        }
        let geminiTask = Task { await GeminiBookRecognizer.fieldsIfEnabled(images: loadedImages) }

        for data in loadedImages {
            if isCancelRequested { break }
            defer { scanProgress += 1 }

            if cover != nil, extraImages.count < 2 {
                extraImages.append(data)
            }
            if cover == nil {
                let coverTask = Task.detached(priority: .userInitiated) { () -> Data? in
                    if let jpeg = BookOCREngine.coverData(from: data) { return jpeg }
                    guard let image = BookOCREngine.decodeImage(from: data) else { return nil }
                    return BookOCREngine.encodePNG(image)
                }
                cover = await coverTask.value
            }

            if let result = await BookOCREngine.recognize(imageData: data) {
                lines.append(contentsOf: result.lines)
                barcodeISBN = barcodeISBN ?? result.barcodeISBN
            }
        }

        let geminiFields = await geminiTask.value
        guard acceptsActiveCatalogResult() else { return }
        guard !lines.isEmpty || barcodeISBN != nil || geminiFields?.isBook == true else {
            recognitionError = "Fotoğraflarda okunabilir metin bulunamadı."
            return
        }

        var parsedDraft = BookOCRExtractor.draft(
            from: BookOCRResult(lines: lines, barcodeISBN: barcodeISBN)
        )
        parsedDraft.coverData = cover
        if extraImages.count > 0 { parsedDraft.backCoverData = extraImages[0] }
        if extraImages.count > 1 { parsedDraft.imprintData = extraImages[1] }
        // Gemini (ana OCR) görüntüleri bütün olarak okur; Vision'ın satır tahminlerini düzeltir
        if let geminiFields { GeminiBookRecognizer.merge(geminiFields, into: &parsedDraft) }
        reconcileWithCatalog(&parsedDraft)
        await replaceWithOfficialCover(&parsedDraft)
        guard acceptsActiveCatalogResult() else { return }
        if let deliver {
            deliver(parsedDraft)
        } else {
            presentOrQuickSave(parsedDraft)
        }
    }

    /// ISBN'i belli kitaplarda elle çekilmiş fotoğraf yerine resmi kapak görselini kullanır.
    func replaceWithOfficialCover(_ draft: inout BookDraft) async {
        let isbn = ISBNFormatter.normalize(draft.isbn)
        guard !isbn.isEmpty else { return }
        if let official = await BookMetadataService.officialCover(
            isbn: isbn,
            title: draft.title,
            author: draft.author,
            publisher: draft.publisher
        ) {
            draft.coverData = official
        }
    }
}
