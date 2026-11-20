import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// #44: bölüm kapağı (akış ve dışa aktarma için ≤1 MB JPEG).
enum CoverArt {
    static func jpeg(for episode: Episode, size: CGFloat = 600) -> Data? {
        let view = EpisodeArtwork(title: episode.title, size: size, cover: episode.visuals?.cover)
            .frame(width: size, height: size)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        for quality in [0.85, 0.7, 0.5, 0.35] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= 1_000_000 { return data }
        }
        return nil
    }
}

/// Bölüm işareti (sn).
nonisolated struct ChapterMark: Hashable, Sendable {
    var title: String
    var start: Double
}

/// #44: bölüm işaretli ve kapaklı `.m4a`. Ses yeniden kodlanmaz (AAC geçişi); işaretler QuickTime bölüm metin izidir
/// (`AVAsset.chapterMetadataGroups` ile geri okunur). Yazıcı metin izini reddederse işaretsiz dışa aktarılır.
enum ChapterAudioExport {
    /// Son dışa aktarmada bölüm işaretleri yazılabildi mi (paylaşım ekranı bilgi verir).
    private(set) static var lastExportHadChapters = false

    static func export(_ episode: Episode) async throws -> URL {
        guard let audio = episode.audioURL, FileManager.default.fileExists(atPath: audio.path) else {
            throw APIError(status: 0, code: "state", message: "Bölümün ses dosyası yok.")
        }
        let chapters = (episode.timeline?.chapters ?? []).map { ChapterMark(title: $0.title, start: $0.start) }
        let output = URL.temporaryDirectory.appending(path: "\(fileName(episode.title)).m4a")
        lastExportHadChapters = try await write(audio: audio, chapters: chapters, title: episode.title, artist: "Ders Podcast",
                                                cover: CoverArt.jpeg(for: episode), to: output)
        return output
    }

    nonisolated static func fileName(_ title: String) -> String {
        let cleaned = String(title.map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }.prefix(60)).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Bolum" : cleaned
    }

    /// İşaret aralıkları: sıralı, sürenin içinde; ilk işaret 0'dan başlar; süre = sonraki başlangıca kadar.
    nonisolated static func normalized(_ chapters: [ChapterMark], duration: Double) -> [(title: String, start: Double, duration: Double)] {
        var marks = chapters.filter { $0.start.isFinite && $0.start >= 0 && $0.start < duration - 0.05 }.sorted { $0.start < $1.start }
        var unique: [ChapterMark] = []
        for m in marks where unique.last.map({ m.start - $0.start >= 0.05 }) ?? true { unique.append(m) }
        marks = unique
        guard !marks.isEmpty else { return [] }
        marks[0].start = 0
        return marks.indices.map { i in
            let end = i + 1 < marks.count ? marks[i + 1].start : duration
            let title = marks[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "Bölüm \(i + 1)" : title, marks[i].start, max(0.05, end - marks[i].start))
        }
    }

    /// Dönüş: bölüm işaretleri yazıldı mı. İşaretli yazım başarısız olursa işaretsiz yeniden denenir.
    @concurrent
    nonisolated static func write(audio: URL, chapters: [ChapterMark], title: String, artist: String, cover: Data?, to output: URL) async throws -> Bool {
        if !chapters.isEmpty {
            do {
                if try await writeOnce(audio: audio, chapters: chapters, title: title, artist: artist, cover: cover, to: output) { return true }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // İşaretli yazım reddedildi: işaretsiz dene.
            }
        }
        _ = try await writeOnce(audio: audio, chapters: [], title: title, artist: artist, cover: cover, to: output)
        return false
    }

    nonisolated private static func writeOnce(audio: URL, chapters: [ChapterMark], title: String, artist: String, cover: Data?, to output: URL) async throws -> Bool {
        let asset = AVURLAsset(url: audio)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw APIError(status: 0, code: "audio", message: "Ses izi bulunamadı.")
        }
        let duration = try await asset.load(.duration)
        let formats = try await track.load(.formatDescriptions)
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw APIError(status: 0, code: "audio", message: "Ses okunamadı.") }
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        writer.metadata = metadata(title: title, artist: artist, cover: cover)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { throw APIError(status: 0, code: "audio", message: "Ses yazılamadı.") }
        writer.add(audioInput)

        var samples: [CMSampleBuffer] = []
        var textInput: AVAssetWriterInput?
        let marks = normalized(chapters, duration: duration.seconds)
        if !marks.isEmpty {
            guard let format = textFormat() else { return false }
            let input = AVAssetWriterInput(mediaType: .text, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            input.languageCode = "tur"
            input.extendedLanguageTag = "tr-TR"
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            guard audioInput.canAddTrackAssociation(withTrackOf: input, type: AVAssetTrack.AssociationType.chapterList.rawValue) else { return false }
            audioInput.addTrackAssociation(withTrackOf: input, type: AVAssetTrack.AssociationType.chapterList.rawValue)
            let scale: CMTimeScale = 1000
            for m in marks {
                guard let s = textSample(m.title, start: CMTime(seconds: m.start, preferredTimescale: scale),
                                         duration: CMTime(seconds: m.duration, preferredTimescale: scale), format: format) else { return false }
                samples.append(s)
            }
            textInput = input
        }

        guard writer.startWriting() else { throw writer.error ?? APIError(status: 0, code: "write", message: "Dosya yazılamadı.") }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { throw reader.error ?? APIError(status: 0, code: "read", message: "Ses okunamadı.") }

        var textIndex = 0
        var audioDone = false
        var textDone = textInput == nil
        while !audioDone || !textDone {
            try Task.checkCancellation()
            var progressed = false
            if !textDone, let input = textInput, input.isReadyForMoreMediaData {
                if textIndex < samples.count {
                    guard input.append(samples[textIndex]) else { throw writer.error ?? APIError(status: 0, code: "write", message: "Bölüm işareti yazılamadı.") }
                    textIndex += 1
                } else {
                    input.markAsFinished()
                    textDone = true
                }
                progressed = true
            }
            if !audioDone, audioInput.isReadyForMoreMediaData {
                if let buffer = readerOutput.copyNextSampleBuffer() {
                    guard audioInput.append(buffer) else { throw writer.error ?? APIError(status: 0, code: "write", message: "Ses yazılamadı.") }
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        if reader.status == .failed { writer.cancelWriting(); throw reader.error ?? APIError(status: 0, code: "read", message: "Ses okunamadı.") }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? APIError(status: 0, code: "write", message: "Dosya yazılamadı.") }
        return textInput != nil
    }

    nonisolated private static func metadata(title: String, artist: String, cover: Data?) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol, dataType: String? = nil) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value
            if let dataType { m.dataType = dataType }
            m.extendedLanguageTag = "tr"
            return m
        }
        var items = [item(.commonIdentifierTitle, title as NSString), item(.commonIdentifierArtist, artist as NSString)]
        if let cover { items.append(item(.commonIdentifierArtwork, cover as NSData, dataType: kCMMetadataBaseDataType_JPEG as String)) }
        return items
    }

    /// 3GPP zamanlı metin ('tx3g') örnek açıklaması: bölüm izi için AVAssetWriter'ın kabul ettiği en küçük biçim
    /// (QuickTime 'text' ham açıklaması ve uzantı sözlüğüyle kurulan biçim -11800 ile reddedildi).
    nonisolated private static func textFormat() -> CMFormatDescription? {
        var d: [UInt8] = [0, 0, 0, 0] + Array("tx3g".utf8) + [0, 0, 0, 0, 0, 0, 0, 1]
        // görüntü bayrakları, yatay/dikey hizalama, arka plan RGBA, metin kutusu, stil kaydı (12 bayt)
        d += [0, 0, 0, 0, 1, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 12, 0xFF, 0xFF, 0xFF, 0xFF]
        d += [0, 0, 0, 18] + Array("ftab".utf8) + [0, 1, 0, 1, 9] + Array("Helvetica".utf8)
        d[2] = UInt8(d.count >> 8)
        d[3] = UInt8(d.count & 0xFF)
        var desc: CMFormatDescription?
        let status = d.withUnsafeBufferPointer { buffer in
            CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(allocator: kCFAllocatorDefault, bigEndianTextDescriptionData: buffer.baseAddress!,
                                                                          size: buffer.count, flavor: nil, mediaType: kCMMediaType_Text,
                                                                          formatDescriptionOut: &desc)
        }
        return status == noErr ? desc : nil
    }

    /// Metin örneği: 16 bit büyük-uçlu uzunluk + UTF-8.
    nonisolated private static func textSample(_ text: String, start: CMTime, duration: CMTime, format: CMFormatDescription) -> CMSampleBuffer? {
        let utf8 = Array(text.utf8.prefix(1000))
        let bytes: [UInt8] = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return nil }
        guard bytes.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                                                    dataLength: bytes.count) }) == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: start, decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil,
                                   refcon: nil, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                   sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    /// Dosyadaki bölüm işaretlerini okur (test ve doğrulama için).
    nonisolated static func readChapters(_ url: URL) async throws -> [ChapterMark] {
        let asset = AVURLAsset(url: url)
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["tr", "tr-TR", "en", "und"])
        var out: [ChapterMark] = []
        for group in groups {
            let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first ?? group.items.first
            let title = (try? await titleItem?.load(.stringValue)) ?? nil
            out.append(ChapterMark(title: title ?? "", start: group.timeRange.start.seconds))
        }
        return out
    }
}
