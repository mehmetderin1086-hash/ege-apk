import Foundation
import SwiftData
import Testing
import UIKit
@testable import Ikra

/// Üretim ve içe aktarma iyileştirmeleri. Dalga 1: açılışta sürdürme, içe aktarma, önizleme metni, kaynak listesi,
/// sistem arka plan görevi, seri kuyruğu. Dalga 2: metin kodlamaları ve dosya hataları, yoklama ve model geçerliliği,
/// seslendirme beklemesi, ders kaydı, bölümlere ayrılmış kitabın tek belge olması.
@MainActor
@Suite struct ImproveUretimTests {
    // MARK: - 1 kullanıcının durdurduğu bölüm açılışta sürdürülmez

    @Test func launchPlanSkipsUserStoppedEpisodes() {
        let stopped = UUID(), stoppedBroken = UUID(), running = UUID(), broken = UUID(), approval = UUID()
        let episodes: [GenerationQueue.EpisodeState] = [
            .init(id: stopped, status: .generating, canResume: true, needsApproval: false),
            .init(id: stoppedBroken, status: .generating, canResume: false, needsApproval: false),
            .init(id: running, status: .generating, canResume: true, needsApproval: false),
            .init(id: broken, status: .generating, canResume: false, needsApproval: false),
            .init(id: approval, status: .generating, canResume: true, needsApproval: true),
        ]
        let plan = GenerationQueue.launchPlan(episodes: episodes, requests: [], scripting: [], stopped: [stopped, stoppedBroken])
        #expect(plan.resume == [running])
        #expect(plan.expire == [broken])
        #expect(plan.keepActivities == [running])
        // Durdurma kümesi verilmezse eski davranış sürer.
        let before = GenerationQueue.launchPlan(episodes: episodes, requests: [], scripting: [])
        #expect(before.resume == [stopped, running])
        #expect(before.expire == [stoppedBroken, broken])
    }

    @Test func userStoppedGenerationsRoundTrip() throws {
        let suite = "uretim-stopped-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = UUID(), b = UUID()
        #expect(UserStoppedGenerations.all(in: defaults).isEmpty)
        UserStoppedGenerations.insert(a, in: defaults)
        UserStoppedGenerations.insert(b, in: defaults)
        UserStoppedGenerations.insert(a, in: defaults)
        #expect(UserStoppedGenerations.all(in: defaults) == [a, b])
        #expect(UserStoppedGenerations.contains(a, in: defaults))
        UserStoppedGenerations.remove(a, in: defaults)
        #expect(!UserStoppedGenerations.contains(a, in: defaults))
        #expect(UserStoppedGenerations.all(in: defaults) == [b])
        UserStoppedGenerations.remove(b, in: defaults)
        #expect(defaults.object(forKey: UserStoppedGenerations.key) == nil)
        // UUID olmayan kayıt yok sayılır.
        defaults.set(["bozuk", b.uuidString], forKey: UserStoppedGenerations.key)
        #expect(UserStoppedGenerations.all(in: defaults) == [b])
    }

    // MARK: - 2 fotoğraf ve tarama içe aktarma

    @Test func importedNamesCountUpWithoutGaps() {
        var names: [String] = []
        for _ in 0..<3 { names.append(SourceNaming.next("Fotoğraf", existing: names)) }
        #expect(names == ["Fotoğraf 1", "Fotoğraf 2", "Fotoğraf 3"])
        #expect(SourceNaming.next("Fotoğraf", existing: ["Fotoğraf 1", "Fotoğraf 2"]) == "Fotoğraf 3")
        #expect(SourceNaming.next("Taranan sayfa", existing: ["Fotoğraf 1", "Notlar"]) == "Taranan sayfa 1")
        // Kaldırılan sayfanın numarası yeniden kullanılır (listede olmayan en küçük sayı).
        #expect(SourceNaming.next("Fotoğraf", existing: ["Fotoğraf 1", "Fotoğraf 3"]) == "Fotoğraf 2")
    }

    @Test func imageLimitsAreReportedBeforeGeneration() {
        let megabyte = 1024 * 1024
        #expect(SourceLimits.problem(imageCount: 21, imageBytes: 0) != nil)
        #expect(SourceLimits.problem(imageCount: 5, imageBytes: 14 * megabyte) != nil)
        #expect(SourceLimits.problem(imageCount: 20, imageBytes: 5 * megabyte) == nil)
        #expect(SourceLimits.problem(imageCount: Config.maxImages, imageBytes: Config.maxTotalPayloadBytes) == nil)
        #expect(SourceLimits.problem(imageCount: 0, imageBytes: 0) == nil)

        let photo = ImportedSource(name: "Fotoğraf 1", kind: .image(Data(count: 1024)))
        let text = ImportedSource(name: "Not", kind: .text("metin"))
        #expect(photo.isImage && !text.isImage)
        #expect(SourceLimits.problem(for: Array(repeating: photo, count: Config.maxImages) + [text]) == nil)
        #expect(SourceLimits.problem(for: Array(repeating: photo, count: Config.maxImages + 1)) != nil)

        #expect(SourceLimits.scanNote(total: 20, taken: 20, failed: 0) == nil)
        #expect(SourceLimits.scanNote(total: 25, taken: 20, failed: 0)?.contains("25 sayfadan") == true)
        #expect(SourceLimits.scanNote(total: 3, taken: 3, failed: 2) == "2 sayfa işlenemedi.")
    }

    @Test func photoDataIsDownscaledWithThumbnail() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let data = try #require(big.jpegData(compressionQuality: 0.8))
        let prepared = await DocumentLoader.jpeg(fromImageData: data)
        let jpeg = try #require(prepared)
        let image = try #require(UIImage(data: jpeg))
        #expect(max(image.size.width, image.size.height) * image.scale <= Config.maxImageDimension)
        #expect(abs(image.size.width / image.size.height - 4.0 / 3.0) < 0.01)
        // Görsel olmayan veri reddedilir.
        let garbage = await DocumentLoader.jpeg(fromImageData: Data("görsel değil".utf8))
        #expect(garbage == nil)

        let source = await DocumentLoader.imageSource(jpeg: jpeg, name: "Fotoğraf 1")
        #expect(source.isImage && source.name == "Fotoğraf 1")
        let thumbnail = try #require(source.thumbnailData.flatMap { UIImage(data: $0) })
        #expect(max(thumbnail.size.width, thumbnail.size.height) * thumbnail.scale <= 132)
        #expect(source.thumbnail != nil)
        // Küçük resmi olmayan (ör. belge kütüphanesinden gelen) görsel kaynağı eskisi gibi asıl veriden çizilir.
        #expect(ImportedSource(name: "Eski", kind: .image(jpeg)).thumbnail != nil)

        // Taranan sayfa yolu (bellekteki görsel) de aynı sınırı uygular.
        let scanned = await DocumentLoader.jpeg(from: big)
        let scannedImage = try #require(scanned.flatMap { UIImage(data: $0) })
        #expect(max(scannedImage.size.width, scannedImage.size.height) * scannedImage.scale <= Config.maxImageDimension)
    }

    // MARK: - 3 senaryo önizlemede konu metni

    @Test func previewTextKeepsTurnOrderAndSpeakerNames() {
        let chapter = ScriptChapter(title: "Mitoz", scenes: [
            ScriptScene(turns: [ScriptTurn(speaker: .a, text: "Bir", style: "", sourcePage: 4), ScriptTurn(speaker: .b, text: "İki", style: "")]),
            ScriptScene(turns: [ScriptTurn(speaker: .c, text: "Üç", style: ""), ScriptTurn(speaker: .a, text: "Dört", style: "")]),
        ])
        var settings = PodcastSettings()
        settings.hostA = Host(name: "Ayşe", voice: "Kore")
        settings.hostB = Host(name: "Mert", voice: "Puck")
        let lines = ScriptPreviewText.lines(for: chapter, settings: settings)
        #expect(lines.map(\.text) == ["Bir", "İki", "Üç", "Dört"])
        #expect(lines.map(\.sceneIndex) == [0, 0, 1, 1])
        #expect(lines.map(\.speaker) == ["Ayşe", "Mert", "Konuk", "Ayşe"])
        #expect(lines.map(\.id) == [0, 1, 2, 3])
        #expect(lines.map(\.page) == [4, nil, nil, nil])
        settings.guest = Host(name: "Deniz", voice: "Charon")
        #expect(ScriptPreviewText.lines(for: chapter, settings: settings)[2].speaker == "Deniz")
        #expect(ScriptPreviewText.lines(for: ScriptChapter(title: "Boş", scenes: []), settings: settings).isEmpty)
    }

    // MARK: - 4 kaynak listesi

    @Test func pageRangeInputClampsAndOrders() {
        #expect(PageRangeInput.resolve(start: 300, end: 250, pageCount: 600) == 250...300)
        #expect(PageRangeInput.resolve(start: 0, end: 9999, pageCount: 600) == nil)
        #expect(PageRangeInput.resolve(start: 5, end: 5, pageCount: 600) == 5...5)
        #expect(PageRangeInput.resolve(start: 1, end: 600, pageCount: 600) == nil)
        #expect(PageRangeInput.resolve(start: 700, end: 900, pageCount: 600) == 600...600)
        // Klavyeden girilen metin: boş ilk sayfa 1, boş son sayfa belgenin sonu.
        #expect(PageRangeInput.resolve(startText: "120", endText: " 180 ", pageCount: 600) == 120...180)
        #expect(PageRangeInput.resolve(startText: "", endText: "", pageCount: 600) == nil)
        #expect(PageRangeInput.resolve(startText: "abc", endText: "40", pageCount: 600) == 1...40)
        #expect(PageRangeInput.resolve(startText: "250", endText: "", pageCount: 600) == 250...600)
    }

    @Test func movingSourcesReordersWithinBounds() {
        let a = ImportedSource(name: "A", kind: .text("a"))
        let b = ImportedSource(name: "B", kind: .text("b"))
        let c = ImportedSource(name: "C", kind: .text("c"))
        let list = [a, b, c]
        #expect(list.moving(id: a.id, by: -1) == list)
        #expect(list.moving(id: c.id, by: 1) == list)
        #expect(list.moving(id: UUID(), by: 1) == list)
        #expect(list.moving(id: b.id, by: 1).map(\.name) == ["A", "C", "B"])
        #expect(list.moving(id: b.id, by: -1).map(\.name) == ["B", "A", "C"])
        // Kimlikler korunur (sıra bölüm sırasını belirler; kaynak yeniden oluşturulmaz).
        #expect(Set(list.moving(id: b.id, by: 1).map(\.id)) == Set(list.map(\.id)))
    }

    @Test func renamedSourceNameIsTrimmedAndCapped() {
        #expect(SourceNaming.cleaned("  Hücre zarı \n") == "Hücre zarı")
        #expect(SourceNaming.cleaned(" \n ") == nil)
        #expect(SourceNaming.cleaned(String(repeating: "a", count: 200))?.count == SourceNaming.maxLength)
    }

    // MARK: - 5 sistem arka plan görevi

    @Test func shortRetryWaitsKeepBackgroundTask() {
        #expect(RetryPolicy.keepsBackgroundTask(delay: 30))
        #expect(RetryPolicy.keepsBackgroundTask(delay: 120))
        for delay in [300.0, 900, 21_600] { #expect(!RetryPolicy.keepsBackgroundTask(delay: delay)) }
        // Üstel beklemenin ilk iki adımı görevi açık tutar.
        #expect((0..<4).map { RetryPolicy.keepsBackgroundTask(delay: RetryPolicy.delay(attempt: $0, retryAfter: nil)) } == [true, true, false, false])
    }

    @Test func backgroundAdoptionPicksWantedRunningInactive() {
        let wantedRunning = UUID(), wantedFinished = UUID(), wantedActive = UUID(), unwanted = UUID()
        let result = BackgroundAdoption.candidates(wanted: [wantedRunning, wantedFinished, wantedActive],
                                                   running: [wantedRunning, wantedActive, unwanted], active: [wantedActive])
        #expect(result == [wantedRunning])
        #expect(BackgroundAdoption.candidates(wanted: [], running: [unwanted], active: []).isEmpty)
    }

    @Test func heldTaskKeepsReportingProgressForLongestWait() {
        // Açık tutulan en uzun bekleme 2 dk; kalp atışı 8 sn'de bir → 15 tur. Her turda ilerleme artmalı.
        var level = 0.4
        let ceiling = level + GenerationBackground.holdHeadroom
        for _ in 0..<15 {
            let next = PulseMath.next(level, toward: ceiling)
            #expect(next > level)
            level = next
        }
        #expect(level < ceiling)
    }

    // MARK: - 6 seri baştan kuyruğa yazılır

    @Test func seriesPlanNumbersEveryChapter() {
        let seriesID = UUID()
        var base = PodcastSettings()
        base.durationMin = 20
        let plan = NewPodcastView.seriesPlan(base, count: 3, seriesID: seriesID, name: "Biyoloji")
        #expect(plan.map { $0.series?.index } == [1, 2, 3])
        #expect(plan.allSatisfy { $0.series?.total == 3 && $0.series?.id == seriesID && $0.series?.name == "Biyoloji" })
        #expect(plan.allSatisfy { $0.series?.previousTitles.isEmpty == true && $0.series?.previousKeyPoints.isEmpty == true })
        #expect(plan.allSatisfy { $0.durationMin == 20 })
        #expect(NewPodcastView.seriesPlan(base, count: 0, seriesID: seriesID, name: "Biyoloji").isEmpty)
    }

    @Test func interruptedSeriesResumesOnlyWithSameSources() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(NewPodcastView.resumesSeries(runSources: [a, b, c], current: [a, b, c], wantsSeries: true))
        // Sıra değişti, kaynak çıktı ya da seri kapatıldı: eski seri sürdürülmez (kuyrukta kalan bölümleri silinir).
        #expect(!NewPodcastView.resumesSeries(runSources: [a, b, c], current: [a, c, b], wantsSeries: true))
        #expect(!NewPodcastView.resumesSeries(runSources: [a, b, c], current: [a, c], wantsSeries: true))
        #expect(!NewPodcastView.resumesSeries(runSources: [a, b, c], current: [a, b, c], wantsSeries: false))
    }

    @Test func queuedSourceNamesFollowRequestNotLibrary() {
        let a = ImportedSource(name: "Kütüphanedeki ad", kind: .text("a"))
        let b = ImportedSource(name: "B", kind: .text("b"))
        #expect(QueuedSourceNames.apply(["Yeni ad", "B"], to: [a, b]).map(\.name) == ["Yeni ad", "B"])
        // Sayı tutmuyorsa (silinmiş belge) ya da ad boşsa dokunulmaz.
        #expect(QueuedSourceNames.apply(["Yeni ad"], to: [a, b]).map(\.name) == ["Kütüphanedeki ad", "B"])
        #expect(QueuedSourceNames.apply(["", "B"], to: [a, b]).map(\.name) == ["Kütüphanedeki ad", "B"])
        #expect(QueuedSourceNames.apply([], to: []).isEmpty)
    }

    @Test func wholeSeriesIsQueuedUpFrontAndKeptInOrder() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let seriesID = UUID()
        let sources = ["Hücre", "Doku", "Organ"].map { ImportedSource(name: $0, kind: .text(String(repeating: "\($0) notları. ", count: 5))) }
        let plan = NewPodcastView.seriesPlan(PodcastSettings(), count: sources.count, seriesID: seriesID, name: "Biyoloji")
        defer {
            for doc in (try? context.fetch(FetchDescriptor<SourceDocument>())) ?? [] { DocumentLibrary.delete(doc, context: context) }
        }
        // Üretimdeki kuyruğa yazma işlevi (`generateSeries` bunu çağırır): hiçbir bölüm başlamadan hepsi kuyruktadır.
        let queued = NewPodcastView.enqueueSeries(sources, plan: plan, context: context)
        let ids = queued.requestIDs
        try #require(ids.count == 3 && Set(ids).count == 3)
        #expect(queued.sources.map(\.id) == sources.map(\.id))
        let requests = try context.fetch(FetchDescriptor<QueuedRequest>())
        #expect(requests.count == 3)
        #expect(Set(requests.map(\.id)) == Set(ids))
        #expect(requests.allSatisfy { $0.stateRaw == QueueState.waiting && $0.settings?.series?.id == seriesID })
        // Dönen kimlikler bölüm sırasıyladır (ekran bölümleri bu sırayla başlatır ve izler).
        let inOrder = ids.compactMap { id in requests.first { $0.id == id } }
        #expect(inOrder.map(\.title) == ["Biyoloji · 1/3 · Hücre", "Biyoloji · 2/3 · Doku", "Biyoloji · 3/3 · Organ"])
        // Kalıcılaşan belge kimlikleri kaynaklara geri yazılır (yeniden denemede belge yeniden kopyalanmaz).
        #expect(queued.sources.map(\.documentID) == inOrder.map(\.documentIDs.first))
        let first = try #require(inOrder.first)
        // Seri sırası: ilk bölüm kuyruktayken sonrakiler bekler.
        #expect(OfflineQueue.blockedBySeries(OfflineQueue.seriesItems(requests)) == [ids[1], ids[2]])

        // Uygulama ilk senaryo yazılırken kapandı: yeniden açılışta yalnız o istek yeniden sıraya girer, bekleyenler durur.
        first.stateRaw = QueueState.scripting
        let launch = GenerationQueue.launchPlan(episodes: [], requests: requests.map { .init(id: $0.id, state: $0.stateRaw) }, scripting: [])
        #expect(launch.requeue == [ids[0]])

        // İlk bölüm oluşunca (isteği silinince) sıradaki açılır.
        context.delete(first)
        try context.save()
        let rest = try context.fetch(FetchDescriptor<QueuedRequest>())
        #expect(rest.count == 2)
        #expect(OfflineQueue.blockedBySeries(OfflineQueue.seriesItems(rest)) == [ids[2]])
    }

    @Test func cancellingSeriesPicksOnlyItsRemainingQueuedRequests() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        defer {
            for doc in (try? context.fetch(FetchDescriptor<SourceDocument>())) ?? [] { DocumentLibrary.delete(doc, context: context) }
        }
        let sources = ["Hücre", "Doku", "Organ"].map { ImportedSource(name: $0, kind: .text(String(repeating: "\($0) notları. ", count: 5))) }
        let plan = NewPodcastView.seriesPlan(PodcastSettings(), count: sources.count, seriesID: UUID(), name: "Biyoloji")
        let ids = NewPodcastView.enqueueSeries(sources, plan: plan, context: context).requestIDs
        try #require(ids.count == 3)
        // Seriyle ilgisi olmayan, kuyrukta bekleyen başka bir istek.
        let other = OfflineQueue.insert(sources: [ImportedSource(name: "Ayrı not", kind: .text(String(repeating: "Ayrı not. ", count: 5)))],
                                        settings: PodcastSettings(), context: context, state: QueueState.waiting)
        // İlk bölüm oluştu (isteği kuyruktan çıktı); ikinci yazılırken "Vazgeç".
        let before = try context.fetch(FetchDescriptor<QueuedRequest>())
        let first = try #require(before.first { $0.id == ids[0] })
        context.delete(first)
        try context.save()
        let queue = try context.fetch(FetchDescriptor<QueuedRequest>())
        let picked = NewPodcastView.queuedSeriesRequests(queue, requestIDs: ids).map(\.id)
        #expect(Set(picked) == [ids[1], ids[2]])
        #expect(!picked.contains(other.id))
        #expect(NewPodcastView.queuedSeriesRequests(queue, requestIDs: []).isEmpty)

        // "Vazgeç" kuyruktaki bölümleri yalnız seri yazılırken siler.
        #expect(NewPodcastView.cancelsQueuedSeries(generating: true, failed: false, queued: false, inProgress: true))
        // Kalıcı hata ya da kuyruğa düşme ekranı: kalan bölümler kuyrukta sürer.
        #expect(!NewPodcastView.cancelsQueuedSeries(generating: true, failed: true, queued: false, inProgress: true))
        #expect(!NewPodcastView.cancelsQueuedSeries(generating: true, failed: false, queued: true, inProgress: true))
        // Seri değil (tek bölüm) ya da üretim başlamadı.
        #expect(!NewPodcastView.cancelsQueuedSeries(generating: true, failed: false, queued: false, inProgress: false))
        #expect(!NewPodcastView.cancelsQueuedSeries(generating: false, failed: false, queued: false, inProgress: true))
    }

    // MARK: - 7 düz metin kodlamaları ve dosya başına hata

    @Test func plainTextDecodingHandlesTurkishEncodings() throws {
        let text = "Öğrenci çalışması: ığüşöç İĞÜŞÖÇ"
        let cp1254 = try #require(text.data(using: .windowsCP1254))
        #expect(String(data: cp1254, encoding: .utf8) == nil)
        #expect(DocumentLoader.decodeText(cp1254) == text)
        #expect(DocumentLoader.decodeText(Data(text.utf8)) == text)
        #expect(DocumentLoader.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)) == text)
        let little = try #require(text.data(using: .utf16LittleEndian)), big = try #require(text.data(using: .utf16BigEndian))
        #expect(DocumentLoader.decodeText(Data([0xFF, 0xFE]) + little) == text)
        #expect(DocumentLoader.decodeText(Data([0xFE, 0xFF]) + big) == text)
        // BOM'suz UTF-16 ve ikili veri (NUL içerir) metin sayılmaz; boş dosya boş metindir ("içinde metin yok" hatasına düşer).
        #expect(DocumentLoader.decodeText(little) == nil)
        #expect(DocumentLoader.decodeText(Data([0x00, 0x01, 0x02, 0xFF])) == nil)
        #expect(DocumentLoader.decodeText(Data()) == "")

        // Geçerli UTF-8 içindeki gerçek "�" metnin parçasıdır: 1254'e düşüp bütün metin bozuk harflerle yüklenmez.
        let marked = "Öğrenci notu \u{FFFD} işaretli"
        #expect(DocumentLoader.decodeText(Data(marked.utf8)) == marked)
        #expect(DocumentLoader.decodeText(Data([0xEF, 0xBB, 0xBF]) + Data(marked.utf8)) == marked)
        // Son baytı kesik UTF-8: kalan metin korunur, yalnız kesik harf "�" olur.
        var cut = Data("Hücre bölünmesi ş".utf8)
        cut.removeLast()
        #expect(DocumentLoader.decodeText(cut) == "Hücre bölünmesi \u{FFFD}")
        // 1254 metinde rastlantıyla geçerli bir UTF-8 dizisi (Ç + kapanış tırnağı = C7 94) metni UTF-8 saydırmaz.
        let quoted = "“GÜÇ” ve öğrenci çalışması"
        let quoted1254 = try #require(quoted.data(using: .windowsCP1254))
        #expect(String(data: quoted1254, encoding: .utf8) == nil)
        #expect(DocumentLoader.decodeText(quoted1254) == quoted)
    }

    @Test func loadAllKeepsGoodFilesAndReportsEachFailure() throws {
        let dir = URL.temporaryDirectory.appending(path: "uretim-loadall-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Uzantı bilerek uydurma: sistemde tanımlı bir türle çakışmasın.
        let good = dir.appending(path: "Hucre notlari.txt"), unknown = dir.appending(path: "veri.bilinmez"), emptyRTF = dir.appending(path: "bos.rtf")
        let text = "Öğrenci çalışması: ığüşöç İĞÜŞÖÇ ve hücre bölünmesi."
        try #require(text.data(using: .windowsCP1254)).write(to: good)
        try Data("x".utf8).write(to: unknown)
        try Data(#"{\rtf1\ansi }"#.utf8).write(to: emptyRTF)

        let loaded = DocumentLoader.loadAll([good, unknown])
        #expect(loaded.sources.count == 1)
        #expect(loaded.sources.first?.name == "Hucre notlari")
        #expect(loaded.sources.first?.kind == .text(text))
        #expect(loaded.errors.count == 1)
        #expect(loaded.errors.first?.contains("veri.bilinmez") == true)

        // Boş RTF kaynak olarak eklenmez (hata üretim adımına kalmaz).
        do {
            _ = try DocumentLoader.load(url: emptyRTF)
            Issue.record("hata bekleniyordu")
        } catch DocumentLoaderError.empty {
        } catch {
            Issue.record("beklenmeyen hata: \(error)")
        }
        let both = DocumentLoader.loadAll([unknown, emptyRTF])
        #expect(both.sources.isEmpty && both.errors.count == 2)

        // Dosya adını taşımayan hata metninin başına ad eklenir; taşıyana dokunulmaz.
        #expect(DocumentLoader.message(for: DocumentLoaderError.unreadable("Not"), fileName: "Not.txt") == "\"Not\" açılamadı.")
        #expect(DocumentLoader.message(for: DocxTextExtractor.DocxError.notZip, fileName: "Odev.docx").hasPrefix("\"Odev.docx\": "))
    }

    // MARK: - 8 sonuç ucu hatası ve model geçerliliği

    @Test func failingResultEndpointStopsPolling() async throws {
        let done = try JSONDecoder().decode(ScriptJobStatus.self, from: Data(#"{"jobId":"j","state":"done"}"#.utf8))
        var statusCalls = 0, resultCalls = 0
        let api = ScriptJobAPI(start: { _ in "j" },
                               status: { _ in
                                   statusCalls += 1
                                   return done
                               },
                               result: { _ in
                                   resultCalls += 1
                                   // Emniyet: sayaç her durum yoklamasında sıfırlanırsa (eski davranış) test sonsuza dek dönmesin.
                                   if resultCalls >= 30 { throw APIError(status: 400, code: "invalid_request", message: "emniyet") }
                                   throw APIError(status: 500, code: "internal", message: "Sunucu hatası")
                               })
        let start = ScriptStartRequest(clientRequestId: "c", settings: PodcastSettings(), sources: [.text("x", name: "n")], prerender: nil)
        var waits: [Duration] = []
        do {
            _ = try await ScriptJobClient.run(existingJobID: "j", api: api, makeStart: { start }, onJob: { _ in }, onProgress: { _ in },
                                              sleep: { waits.append($0) })
            Issue.record("hata bekleniyordu")
        } catch {
            #expect((error as? APIError)?.code == "internal")
        }
        #expect(resultCalls == 9)
        #expect(statusCalls == 9)
        #expect(waits.count == 8)
        #expect(waits.last == .seconds(24))
    }

    @Test func scriptModelSelectionLocksOnlyWhenCatalogRejectsIt() {
        // Katalog yokken (yükleniyor, gelmedi, istek iptal oldu) "Oluştur" kilitlenmez.
        #expect(ScriptModelValidity.isValid(catalog: nil, selection: nil, loading: true))
        #expect(ScriptModelValidity.isValid(catalog: nil, selection: ScriptAISettings(provider: "baska", model: "yok"), loading: false))
        let catalog = ScriptModelCatalog(providers: [], models: [
            .init(id: "claude-sonnet-5-5", provider: "claude", title: "Sonnet", detail: "", efforts: ["auto", "low"]),
        ], defaultSelection: .init(provider: "claude", model: "claude-sonnet-5-5"))
        #expect(ScriptModelValidity.isValid(catalog: catalog, selection: catalog.defaultSelection, loading: false))
        // Liste yenilenirken eldeki katalog esastır.
        #expect(ScriptModelValidity.isValid(catalog: catalog, selection: catalog.defaultSelection, loading: true))
        #expect(!ScriptModelValidity.isValid(catalog: catalog, selection: .init(provider: "claude", model: "claude-sonnet-5-5", effort: "max"), loading: false))
        #expect(!ScriptModelValidity.isValid(catalog: catalog, selection: .init(provider: "baska", model: "yok"), loading: false))
        #expect(!ScriptModelValidity.isValid(catalog: catalog, selection: nil, loading: false))
    }

    // MARK: - 10 seslendirme beklemesi ve taslak satırı

    @Test func retryWaitIsSlicedSoItCanBeCutShort() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(RetryWait.next(until: now.addingTimeInterval(10), now: now) == 1)
        let short = try #require(RetryWait.next(until: now.addingTimeInterval(0.4), now: now))
        #expect(abs(short - 0.4) < 0.000_1)
        #expect(RetryWait.next(until: now, now: now) == nil)
        #expect(RetryWait.next(until: now.addingTimeInterval(-5), now: now) == nil)
    }

    @Test func draftRowShowsRequestTitleAndProgress() {
        #expect(DraftBanner.title("Biyoloji · 2/5 · Doku") == "Biyoloji · 2/5 · Doku")
        #expect(DraftBanner.title(nil) == "Podcast")
        #expect(DraftBanner.title("  ") == "Podcast")
        #expect(DraftBanner.subtitle(.preparing) == "Belgeler hazırlanıyor")
        #expect(DraftBanner.subtitle(.writingScript(ScriptProgress(stage: "chapters", chaptersDone: 4, chaptersTotal: 12))) == "Plan çıkarıldı · Konu 4/12")
    }

    // MARK: - 11 ders kaydı

    @Test func lectureSegmentStaysUnderServerLimit() {
        let seconds = LectureLimit.segmentSeconds(maxBytes: LectureRecordSheet.maxRawBytes)
        #expect((3000.0...3400.0).contains(seconds))
        #expect(seconds * 32_000 / 8 <= Double(LectureRecordSheet.maxRawBytes))
        #expect(LectureLimit.segmentSeconds(maxBytes: 0) == 0)
        #expect(LectureLimit.isNegligible(bytes: 4_000) && !LectureLimit.isNegligible(bytes: 40_000))
        // "Vazgeç": yalnız süren ve birkaç saniyeyi aşmış kayıt onay ister.
        #expect(!LectureLimit.needsDiscardConfirmation(isRecording: true, elapsed: 3))
        #expect(LectureLimit.needsDiscardConfirmation(isRecording: true, elapsed: 40 * 60))
        #expect(!LectureLimit.needsDiscardConfirmation(isRecording: false, elapsed: 40 * 60))
        // İçe aktarılan dosyada süre söylenmez (süre bit hızına bağlıdır).
        let imported = LectureLimit.tooLargeMessage(bytes: 20_000_000, maxBytes: LectureRecordSheet.maxRawBytes, recorded: false)
        #expect(!imported.contains("dakika") && imported.contains("Ses dosyası"))
        #expect(LectureLimit.tooLargeMessage(bytes: 20_000_000, maxBytes: LectureRecordSheet.maxRawBytes, recorded: true).hasPrefix("Kayıt"))
    }

    @Test func lectureRecordingsAreListedNewestFirstAndGroupedByPart() throws {
        let dir = URL.temporaryDirectory.appending(path: "uretim-kayit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let oldStem = "ders-kaydi-2026-10-01T09-00-00", newStem = "ders-kaydi-2026-10-05T14-30-00"
        #expect(LectureRecordings.fileName(stem: oldStem, part: 1) == "\(oldStem).m4a")
        #expect(LectureRecordings.fileName(stem: newStem, part: 2) == "\(newStem)-p2.m4a")
        let old = dir.appending(path: LectureRecordings.fileName(stem: oldStem, part: 1))
        let new = dir.appending(path: LectureRecordings.fileName(stem: newStem, part: 1))
        let newSecond = dir.appending(path: LectureRecordings.fileName(stem: newStem, part: 2))
        let note = dir.appending(path: "not.txt")
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for (url, bytes, offset) in [(old, 10, 0.0), (new, 20, 3_600), (newSecond, 5, 7_200), (note, 3, 9_000)] {
            try Data(count: bytes).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(offset)], ofItemAtPath: url.path)
        }
        // Yalnız kayıt dosyaları, en yeni önce.
        #expect(LectureRecordings.pending(in: dir).map(\.lastPathComponent) == [newSecond, new, old].map(\.lastPathComponent))

        #expect(LectureRecordings.parse(newSecond).stem == newStem && LectureRecordings.parse(newSecond).part == 2)
        #expect(LectureRecordings.parse(old).stem == oldStem && LectureRecordings.parse(old).part == 1)
        let sessions = LectureRecordings.sessions(LectureRecordings.files(in: dir))
        #expect(sessions.map(\.stem) == [newStem, oldStem])
        #expect(sessions.first?.parts.map(\.lastPathComponent) == [new, newSecond].map(\.lastPathComponent))
        #expect(sessions.first?.bytes == 25)
        // Gönderilmemiş kayıt, yazıya dökülmüş olandan önce gösterilir.
        #expect(LectureRecordings.ordered(sessions, sent: [newStem]).map(\.stem) == [oldStem, newStem])
        #expect(LectureRecordings.ordered(sessions, sent: []).map(\.stem) == [newStem, oldStem])

        let stem = LectureRecordings.stem(now: base)
        #expect(stem.hasPrefix("ders-kaydi-") && !stem.contains(":"))
        #expect(LectureRecordings.parse(URL(fileURLWithPath: "/tmp/\(stem).m4a")).part == 1)
    }

    @Test func sentLectureRecordingsRoundTrip() throws {
        let suite = "uretim-kayit-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LectureRecordings.sent(in: defaults).isEmpty)
        LectureRecordings.markSent("a", in: defaults)
        LectureRecordings.markSent("b", in: defaults)
        LectureRecordings.markSent("a", in: defaults)
        #expect(LectureRecordings.sent(in: defaults) == ["a", "b"])
        LectureRecordings.forget("a", in: defaults)
        #expect(LectureRecordings.sent(in: defaults) == ["b"])
        LectureRecordings.forget("b", in: defaults)
        #expect(defaults.object(forKey: LectureRecordings.sentKey) == nil)
    }

    @Test func recordingsFromBeforeSendTrackingAreNotCalledUnsent() throws {
        let suite = "uretim-kayit-onceki-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Güncellemeden sonraki ilk açılış: klasörde duran kayıtların gönderilip gönderilmediği bilinmez (önceki sürüm
        // yazıya dökülen kaydı da klasörde bırakırdı); "gönderilmemiş" diye gösterilmezler.
        let legacy = LectureRecordings.legacy(existing: ["eski-1", "eski-2"], in: defaults)
        #expect(legacy == ["eski-1", "eski-2"])
        #expect(LectureRecordings.status("eski-1", sent: [], legacy: legacy) == .legacy)
        #expect(LectureRecordings.Status.legacy.title == "Önceki kayıt")
        #expect(LectureRecordings.Status.legacy.note != nil)
        // Sonradan yapılan kayıt bu kümeye girmez: yazıya dökülene dek gönderilmemiştir.
        let later = LectureRecordings.legacy(existing: ["eski-1", "eski-2", "yeni"], in: defaults)
        #expect(later == legacy)
        #expect(LectureRecordings.status("yeni", sent: [], legacy: later) == .unsent)
        #expect(LectureRecordings.Status.unsent.title == "Gönderilmemiş kayıt" && LectureRecordings.Status.unsent.note == nil)
        // Önceki kayıt yeniden gönderilip yazıya dökülünce durumu kesinleşir.
        LectureRecordings.markSent("eski-2", in: defaults)
        #expect(LectureRecordings.status("eski-2", sent: LectureRecordings.sent(in: defaults), legacy: later) == .sent)
        #expect(LectureRecordings.Status.sent.title == "Yazıya dökülmüş kayıt" && LectureRecordings.Status.sent.note == nil)

        // Temiz kurulum: boş klasör de "bakıldı" diye yazılır; sonraki ilk kayıt "önceki" sayılmaz.
        let freshSuite = "uretim-kayit-temiz-\(UUID().uuidString)"
        let fresh = try #require(UserDefaults(suiteName: freshSuite))
        defer { fresh.removePersistentDomain(forName: freshSuite) }
        #expect(LectureRecordings.legacy(existing: [], in: fresh).isEmpty)
        #expect(LectureRecordings.legacy(existing: ["ilk"], in: fresh).isEmpty)
        // İlk bakışta durumu zaten bilinen (yazıya dökülmüş) kayıt kümeye girmez.
        let trackedSuite = "uretim-kayit-izlenen-\(UUID().uuidString)"
        let tracked = try #require(UserDefaults(suiteName: trackedSuite))
        defer { tracked.removePersistentDomain(forName: trackedSuite) }
        LectureRecordings.markSent("gonderildi", in: tracked)
        #expect(LectureRecordings.legacy(existing: ["gonderildi", "belirsiz"], in: tracked) == ["belirsiz"])
    }

    // MARK: - 12 bölümlere ayrılmış kitap tek belge

    private func bookPieces(_ url: URL, name: String, count: Int) -> [ImportedSource] {
        (0..<count).map { i in
            var piece = ImportedSource(name: "\(name) · Bölüm \(i + 1)", kind: .pdf(url, pageCount: count))
            piece.pageRange = (i + 1)...(i + 1)
            piece.libraryName = name
            return piece
        }
    }

    @Test func adoptedDocumentIsSharedByPiecesOfTheSamePDF() {
        let pieces = bookPieces(URL(fileURLWithPath: "/tmp/kitap.pdf"), name: "Kitap", count: 3)
        let other = ImportedSource(name: "Başka", kind: .pdf(URL(fileURLWithPath: "/tmp/baska.pdf"), pageCount: 9))
        let note = ImportedSource(name: "Not", kind: .text("x"))
        let all = pieces + [other, note]
        let id = UUID()
        let adopted = NewPodcastView.adoptingDocumentIDs([id], for: [pieces[1]], in: all)
        #expect(adopted.map(\.documentID) == [id, id, id, nil, nil])
        #expect(adopted.map(\.id) == all.map(\.id))
        // Kimliği olan parça ezilmez.
        var known = all
        let own = UUID()
        known[0].documentID = own
        #expect(NewPodcastView.adoptingDocumentIDs([id], for: [pieces[1]], in: known).map(\.documentID) == [own, id, id, nil, nil])
        // Metin kaynağının kimliği başka kaynağa yayılmaz.
        #expect(NewPodcastView.adoptingDocumentIDs([id], for: [note], in: all).map(\.documentID) == [nil, nil, nil, nil, id])
    }

    @Test func queuedPageRangesKeepTwoRangesOfTheSameDocument() {
        let requestID = UUID(), doc = UUID()
        var first = ImportedSource(name: "Kitap · 1", kind: .text("x"))
        first.pageRange = 1...10
        var lost = ImportedSource(name: "Kopyalanamadı", kind: .text("z"))
        lost.pageRange = 3...4
        let whole = ImportedSource(name: "Tümü", kind: .text("w"))
        var later = ImportedSource(name: "Kitap · 5", kind: .text("y"))
        later.pageRange = 40...50
        // Kopyalanamayan kaynak (nil) isteğin belge listesinde yoktur: sıra kalanlarla hizalanır.
        QueuedPageRanges.save([first, lost, whole, later], documentIDs: [doc, nil, doc, doc], for: requestID)
        defer { QueuedPageRanges.clear(requestID) }
        #expect(QueuedPageRanges.range(at: 0, document: doc, for: requestID) == 1...10)
        #expect(QueuedPageRanges.range(at: 1, document: doc, for: requestID) == nil)
        #expect(QueuedPageRanges.range(at: 2, document: doc, for: requestID) == 40...50)

        // Eski biçim (belge kimliği → aralık) hâlâ okunur.
        let legacyID = UUID()
        UserDefaults.standard.set([doc.uuidString: [5, 9]], forKey: "queue.ranges.\(legacyID.uuidString)")
        defer { QueuedPageRanges.clear(legacyID) }
        #expect(QueuedPageRanges.range(at: 0, document: doc, for: legacyID) == 5...9)
        #expect(QueuedPageRanges.range(at: 0, document: UUID(), for: legacyID) == nil)
        var loaded = ImportedSource(name: "Kitap", kind: .text("x"))
        loaded.documentID = doc
        #expect(QueuedPageRanges.apply(to: [loaded], for: legacyID).first?.pageRange == 5...9)
        // Kayıt yoksa aralık yok.
        #expect(QueuedPageRanges.range(at: 0, document: doc, for: UUID()) == nil)
    }

    @Test func splitBookIsCopiedOnceIntoTheLibrary() throws {
        let container = try ModelContainer(for: QueuedRequest.self, SourceDocument.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        func writeBook() throws -> URL {
            let url = URL.temporaryDirectory.appending(path: "uretim-kitap-\(UUID().uuidString).pdf")
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).writePDF(to: url) { renderer in
                for _ in 0..<3 { renderer.beginPage() }
            }
            return url
        }
        let book = try writeBook(), second = try writeBook()
        var requestIDs: [UUID] = []
        defer {
            for url in [book, second] { try? FileManager.default.removeItem(at: url) }
            for id in requestIDs { QueuedPageRanges.clear(id) }
            for doc in (try? context.fetch(FetchDescriptor<SourceDocument>())) ?? [] { DocumentLibrary.delete(doc, context: context) }
        }

        // Tek istek (tek bölüm): üç parça için kitap bir kez kopyalanır; aralıklar sırayla durur.
        let pieces = bookPieces(book, name: "Biyoloji kitabı", count: 3)
        var adopted: [UUID?] = []
        let request = OfflineQueue.insert(sources: pieces, settings: PodcastSettings(), context: context, state: QueueState.waiting,
                                          onDocuments: { adopted = $0 })
        requestIDs.append(request.id)
        let documents = try context.fetch(FetchDescriptor<SourceDocument>())
        #expect(documents.count == 1)
        #expect(documents.first?.name == "Biyoloji kitabı")
        #expect(request.documentIDs.count == 3 && Set(request.documentIDs).count == 1)
        #expect(adopted == request.documentIDs.map { Optional($0) })
        #expect(request.sourceNames == pieces.map(\.name))
        let document = try #require(request.documentIDs.first)
        #expect((0..<3).map { QueuedPageRanges.range(at: $0, document: document, for: request.id) } == [1...1, 2...2, 3...3])

        // Seri (parça başına ayrı istek), üretimdeki kuyruğa yazma işleviyle: ilk parçanın belgesi sonraki parçalara
        // yazılır, kitap yeniden kopyalanmaz.
        let parts = bookPieces(second, name: "Kimya kitabı", count: 3)
        let plan = NewPodcastView.seriesPlan(PodcastSettings(), count: parts.count, seriesID: UUID(), name: "Kimya")
        let series = NewPodcastView.enqueueSeries(parts, plan: plan, context: context)
        requestIDs += series.requestIDs
        #expect(series.requestIDs.count == 3)
        let queue = try context.fetch(FetchDescriptor<QueuedRequest>())
        var seriesDocuments: [UUID] = []
        for (j, id) in series.requestIDs.enumerated() {
            let queued = try #require(queue.first { $0.id == id })
            seriesDocuments += queued.documentIDs
            #expect(QueuedPageRanges.range(at: 0, document: queued.documentIDs.first ?? UUID(), for: id) == (j + 1)...(j + 1))
        }
        #expect(seriesDocuments.count == 3 && Set(seriesDocuments).count == 1)
        #expect(series.sources.map(\.documentID) == seriesDocuments.map { Optional($0) })
        let all = try context.fetch(FetchDescriptor<SourceDocument>())
        #expect(all.count == 2)
        #expect(Set(all.map(\.name)) == ["Biyoloji kitabı", "Kimya kitabı"])
    }
}
