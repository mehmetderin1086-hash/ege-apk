import Foundation
import Testing
@testable import _01

@MainActor @Suite(.serialized)
struct ScanPhotoRetentionTestleri {
    private struct Injected: Error { }
    private func isolated(_ action: () async throws -> Void) async throws {
        let previous = ScanSessionStore.directoryOverride
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photo-retention-" + UUID().uuidString)
        ScanSessionStore.directoryOverride = directory
        defer { ScanSessionStore.directoryOverride = previous; try? FileManager.default.removeItem(at: directory) }
        try await action()
    }

    @Test func partialPhotoSuccessAndFailedOCRPixelsRemainInRealSessionAfterReload() async throws {
        try await isolated {
            let good = ScanPhotoImportSource(selectionIndex: 0, pickerIdentifier: "local-good")
            let failed = ScanPhotoImportSource(selectionIndex: 1, pickerIdentifier: "local-failed")
            var session = ScanSession(kind: .photo, title: "Toplu fotoğraf okuma")
            session.separatePhotoSources = [good, failed]
            let success = await ScanPhotoImportWorker.read(good, cachedImage: nil, load: { Data([1, 2, 3]) },
                parse: { _ in Book(id: good.id, title: "Başarılı eser", author: "Y") })
            let failure = await ScanPhotoImportWorker.read(failed, cachedImage: nil, load: { Data([4, 5, 6]) },
                parse: { _ in throw Injected() })
            success.apply(to: &session); failure.apply(to: &session)
            try ScanSessionStore.save(session, updateTimestamp: false)
            let saved = try #require(try ScanSessionStore.allVerified().first)
            #expect(saved.pendingBooks.map(\.id) == [good.id])
            #expect(saved.sourceImages == [Data([1, 2, 3]), Data([4, 5, 6])])
            #expect(saved.separatePhotoSources?.first?.status == .parsed)
            #expect(saved.separatePhotoSources?.last?.status == .failed)
            #expect(saved.separatePhotoSources?.last?.errorMessage != nil)
            #expect(saved.separatePhotoSources?.last?.pickerIdentifier == "local-failed")
            #expect(saved.separatePhotoSources?.last?.imageIndex == 1)
        }
    }

    @Test func retryReadsRetainedImageWithoutPhotosReloadAndKeepsOneStableDraftAndPixelPayload() async throws {
        try await isolated {
            let source = ScanPhotoImportSource(selectionIndex: 0, pickerIdentifier: "local-retry")
            var session = ScanSession(kind: .photo, title: "Yeniden deneme")
            let failed = await ScanPhotoImportWorker.read(source, cachedImage: nil, load: { Data([7, 8]) }, parse: { _ in throw Injected() })
            failed.apply(to: &session)
            try ScanSessionStore.save(session, updateTimestamp: false)
            session = try #require(try ScanSessionStore.allVerified().first)
            let retained = try #require(session.separatePhotoSources?.first)
            let index = try #require(retained.imageIndex)
            var photosLoads = 0
            let retry = await ScanPhotoImportWorker.read(retained, cachedImage: session.sourceImages?[index], load: {
                photosLoads += 1; throw Injected()
            }, parse: { _ in Book(id: retained.id, title: "Yeniden okunan", author: "Y") })
            retry.apply(to: &session); retry.apply(to: &session)
            try ScanSessionStore.save(session, updateTimestamp: false)
            let final = try #require(try ScanSessionStore.allVerified().first)
            #expect(photosLoads == 0 && final.pendingBooks.map(\.id) == [retained.id])
            #expect(final.sourceImages == [Data([7, 8])])
            #expect(final.separatePhotoSources?.first?.status == .parsed)
            #expect(final.separatePhotoSources?.first?.needsRead == false)
            #expect(final.separatePhotoSources?.first?.errorMessage == nil)
        }
    }

    @Test func failedPhotosLoadRetainsReselectableIdentityAndDoesNotPretendPixelsExist() async throws {
        try await isolated {
            let source = ScanPhotoImportSource(selectionIndex: 2, pickerIdentifier: "cloud-asset-not-loaded")
            let result = await ScanPhotoImportWorker.read(source, cachedImage: nil, load: { throw ScanPhotoImportWorker.Failure.noData },
                parse: { _ in Issue.record("Load hatasında OCR çağrılmamalı"); throw Injected() })
            var session = ScanSession(kind: .photo, title: "Yüklenemeyen kaynak")
            result.apply(to: &session)
            try ScanSessionStore.save(session, updateTimestamp: false)
            let saved = try #require(try ScanSessionStore.allVerified().first)
            #expect(saved.pendingBooks.isEmpty && (saved.sourceImages ?? []).isEmpty)
            let retained = try #require(saved.separatePhotoSources?.first)
            #expect(retained.id == source.id && retained.pickerIdentifier == source.pickerIdentifier)
            #expect(retained.imageIndex == nil && retained.status == .failed && retained.errorMessage != nil)
        }
    }

    @Test func cancelledOCRAndChangedBookIdentityKeepSourceForRetryWithoutCreatingBook() async throws {
        let source = ScanPhotoImportSource(selectionIndex: 0)
        let cancelled = await ScanPhotoImportWorker.read(source, cachedImage: Data([9]), load: { throw Injected() }, parse: { _ in throw CancellationError() })
        #expect(cancelled.book == nil && cancelled.image == Data([9]) && cancelled.source.status == .pending)
        let wrong = await ScanPhotoImportWorker.read(source, cachedImage: Data([9]), load: { throw Injected() },
            parse: { _ in Book(title: "Yanlış yeni kimlik", author: "Y") })
        #expect(wrong.book == nil && wrong.source.status == .failed && wrong.source.id == source.id)
    }
}
