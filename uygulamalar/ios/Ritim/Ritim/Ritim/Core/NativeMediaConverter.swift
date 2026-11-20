import AVFoundation
import CLame
import Foundation
import UIKit

/// Native downloads may run in parallel, but CPU-heavy encoders share one permit.
/// A cancelled waiter never starts encoding and never releases another job's slot.
private actor NativeConversionGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var owner: UUID?
    private var waiters: [Waiter] = []

    func acquire() async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if owner == nil { owner = id; continuation.resume(returning: id) }
                else { waiters.append(Waiter(id: id, continuation: continuation)) }
            }
        } onCancel: {
            Task { await self.cancelWaiting(id) }
        }
    }

    func release(_ id: UUID) {
        guard owner == id else { return }
        guard !waiters.isEmpty else { owner = nil; return }
        let next = waiters.removeFirst()
        owner = next.id
        next.continuation.resume(returning: next.id)
    }

    private func cancelWaiting(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Converts already downloaded files entirely on this device. It never opens a
/// remote URL and never changes the source resolution or invents source detail.
enum NativeMediaConverter {
    private static let conversionGate = NativeConversionGate()

    static func convert(
        audio: URL,
        video: URL?,
        format: DownloadFormat,
        quality: DownloadQuality,
        outputDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let work = Task.detached(priority: .utility) {
            let permit = try await conversionGate.acquire()
            do {
                let output = try await performConversion(audio: audio, video: video, format: format,
                                                         quality: quality, outputDirectory: outputDirectory,
                                                         progress: progress)
                await conversionGate.release(permit)
                return output
            } catch {
                await conversionGate.release(permit)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func performConversion(audio: URL, video: URL?, format: DownloadFormat,
                                          quality: DownloadQuality, outputDirectory: URL,
                                          progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        guard audio.isFileURL, video?.isFileURL != false else {
            throw RitimError.message("Dönüştürmek için dosyanın önce iPhone'a indirilmesi gerekiyor.")
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.rawValue)
        do {
            progress(0)
            try Task.checkCancellation()
            switch format {
            case .mp3:
                try await encodeMP3(input: audio, output: output, quality: quality, progress: progress)
            case .mp4:
                try await muxMP4(audio: audio, video: video ?? audio, output: output, quality: quality, progress: progress)
            }
            try Task.checkCancellation()
            try await validate(output, format: format)
            try Task.checkCancellation()
            progress(1)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func encodeMP3(
        input: URL,
        output: URL,
        quality: DownloadQuality,
        progress: @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw RitimError.message("İndirilen kaynakta dönüştürülebilir ses bulunamadı.")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RitimError.message("Ses dosyasının süresi okunamadı.") }
        let descriptions = try await track.load(.formatDescriptions)
        let sourceFormat = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sourceRate = sourceFormat?.mSampleRate ?? 44_100
        let rate = [32_000.0, 44_100.0, 48_000.0].contains(sourceRate) ? sourceRate : 48_000
        let channels = max(1, min(2, Int(sourceFormat?.mChannelsPerFrame ?? 2)))
        let reader = try AVAssetReader(asset: asset)
        let pcm = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        pcm.alwaysCopiesSampleData = false
        guard reader.canAdd(pcm) else { throw RitimError.message("Bu ses biçimi iPhone'da çözülemiyor.") }
        reader.add(pcm)
        guard let encoder = lame_init() else { throw RitimError.message("MP3 kodlayıcı başlatılamadı.") }
        defer { lame_close(encoder); reader.cancelReading() }
        let bitrate: Int32 = quality == .highest ? 320 : 192
        guard lame_set_in_samplerate(encoder, Int32(rate)) == 0,
              lame_set_out_samplerate(encoder, Int32(rate)) == 0,
              lame_set_num_channels(encoder, Int32(channels)) == 0,
              lame_set_brate(encoder, bitrate) == 0,
              lame_set_VBR(encoder, vbr_off) == 0,
              lame_set_quality(encoder, 2) == 0,
              lame_set_bWriteVbrTag(encoder, 1) == 0,
              lame_init_params(encoder) == 0 else {
            throw RitimError.message("MP3 kalite ayarları uygulanamadı.")
        }
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw RitimError.message("MP3 dosyası oluşturulamadı. Boş alanı kontrol et.")
        }
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }
        guard reader.startReading() else {
            throw reader.error ?? RitimError.message("Ses dosyası okunamadı.")
        }
        var frameCount: Int64 = 0
        var lastProgress = 0.0
        // LAME emits a small block for each frame; batching writes avoids
        // thousands of filesystem operations without changing encoded bytes.
        var outputBuffer = Data()
        outputBuffer.reserveCapacity(64 * 1_024)
        var workWindowStart = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            guard let sample = pcm.copyNextSampleBuffer() else { break }
            try autoreleasepool {
                guard let block = CMSampleBufferGetDataBuffer(sample) else {
                    throw RitimError.message("Ses örneği çözülemedi.")
                }
                let frames = CMSampleBufferGetNumSamples(sample)
                guard frames > 0 else { return }
                let samples = frames * channels
                let bytes = samples * MemoryLayout<Float>.size
                guard bytes <= CMBlockBufferGetDataLength(block) else {
                    throw RitimError.message("Ses örneği eksik indirildi.")
                }
                var buffer = [Float](repeating: 0, count: samples)
                let copyStatus = buffer.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!)
                }
                guard copyStatus == noErr else { throw RitimError.message("Ses verisi okunamadı.") }
                // AVAssetReader may return a large PCM sample. Bound each
                // synchronous LAME call so cancellation is observed promptly,
                // even for an hour-long source or a slow/debug device encoder.
                let chunkFrames = 1_152
                var encoded = [UInt8](repeating: 0, count: Int(Double(chunkFrames) * 1.25) + 7_200)
                for offset in stride(from: 0, to: frames, by: chunkFrames) {
                    try Task.checkCancellation()
                    let countFrames = min(chunkFrames, frames - offset)
                    let count = buffer.withUnsafeBufferPointer { source in
                        encoded.withUnsafeMutableBufferPointer { destination in
                            let start = source.baseAddress!.advanced(by: offset * channels)
                            if channels == 2 {
                                return lame_encode_buffer_interleaved_ieee_float(encoder, start, Int32(countFrames), destination.baseAddress, Int32(destination.count))
                            }
                            return lame_encode_buffer_ieee_float(encoder, start, start, Int32(countFrames), destination.baseAddress, Int32(destination.count))
                        }
                    }
                    try Task.checkCancellation()
                    guard count >= 0 else { throw RitimError.message("MP3 kodlama başarısız oldu (\(count)).") }
                    if count > 0 {
                        outputBuffer.append(contentsOf: encoded.prefix(Int(count)))
                        if outputBuffer.count >= 64 * 1_024 {
                            try file.write(contentsOf: outputBuffer)
                            outputBuffer.removeAll(keepingCapacity: true)
                        }
                    }
                    frameCount += Int64(countFrames)
                    let fraction = min(0.98, Double(frameCount) / rate / duration)
                    if fraction - lastProgress >= 0.005 {
                        progress(fraction)
                        lastProgress = fraction
                    }
                }
            }
            // iOS kills background audio apps that sustain excessive CPU.
            // Leave time for playback and the system between encoding bursts.
            let workTime = ProcessInfo.processInfo.systemUptime - workWindowStart
            if workTime >= 0.08 {
                let inBackground = await MainActor.run { UIApplication.shared.applicationState != .active }
                let thermal = ProcessInfo.processInfo.thermalState
                while ProcessInfo.processInfo.thermalState == .critical {
                    try await Task.sleep(for: .seconds(2))
                }
                let factor: Double = thermal == .serious ? 4 : (inBackground ? 2 : 0.25)
                try await Task.sleep(for: .seconds(min(workTime * factor, 2)))
                workWindowStart = ProcessInfo.processInfo.systemUptime
            }
        }
        try Task.checkCancellation()
        guard reader.status == .completed, frameCount > 0 else {
            throw reader.error ?? RitimError.message("Ses dosyası tamamen çözülemedi.")
        }
        var tail = [UInt8](repeating: 0, count: 7_200)
        let tailCount = tail.withUnsafeMutableBufferPointer {
            lame_encode_flush(encoder, $0.baseAddress, Int32($0.count))
        }
        guard tailCount >= 0 else { throw RitimError.message("MP3 dosyası tamamlanamadı.") }
        if tailCount > 0 { outputBuffer.append(contentsOf: tail.prefix(Int(tailCount))) }
        if !outputBuffer.isEmpty { try file.write(contentsOf: outputBuffer) }
        // Replace the reserved Xing/LAME header with its final duration and
        // encoder-delay values, so seeking and duration remain accurate.
        var tag = [UInt8](repeating: 0, count: 7_200)
        let tagCount = tag.withUnsafeMutableBufferPointer { lame_get_lametag_frame(encoder, $0.baseAddress, $0.count) }
        guard tagCount <= tag.count else { throw RitimError.message("MP3 süre bilgisi yazılamadı.") }
        if tagCount > 0 {
            try file.seek(toOffset: 0)
            try file.write(contentsOf: Data(tag.prefix(tagCount)))
        }
        try file.synchronize()
    }

    private static func muxMP4(
        audio: URL,
        video: URL,
        output: URL,
        quality: DownloadQuality,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Fragmented DASH sources may carry durations in both moov and moof.
        // Repair disposable copies so AVFoundation does not prepend empty time;
        // the downloaded checkpoints remain untouched for retries.
        let repairedVideo = try FragmentedMP4Repair.copyIfNeeded(video, in: output.deletingLastPathComponent())
        defer { if let repairedVideo { try? FileManager.default.removeItem(at: repairedVideo) } }
        let repairedAudio = audio == video ? nil : try FragmentedMP4Repair.copyIfNeeded(audio, in: output.deletingLastPathComponent())
        defer { if let repairedAudio { try? FileManager.default.removeItem(at: repairedAudio) } }
        try Task.checkCancellation()
        let videoAsset = AVURLAsset(url: repairedVideo ?? video)
        let audioAsset = audio == video ? videoAsset : AVURLAsset(url: repairedAudio ?? audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw RitimError.message("MP4 için hem video hem ses gerekli. Kaynak biçimi iPhone ile uyumlu değil.")
        }
        let size = try await videoTrack.load(.naturalSize)
        let maximum = quality == .highest ? 3_840.0 : 1_920.0
        let maximumShort = quality == .highest ? 2_160.0 : 1_080.0
        guard max(abs(size.width), abs(size.height)) <= maximum,
              min(abs(size.width), abs(size.height)) <= maximumShort else {
            throw RitimError.message("Kaynak video seçilen kalite sınırını aşıyor.")
        }
        let videoRange = try await videoTrack.load(.timeRange)
        let audioRange = try await audioTrack.load(.timeRange)
        guard videoRange.duration.seconds.isFinite, videoRange.duration.seconds > 0,
              audioRange.duration.seconds.isFinite, audioRange.duration.seconds > 0 else {
            throw RitimError.message("Kaynak video veya sesin süresi okunamadı.")
        }
        let composition = AVMutableComposition()
        guard let image = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sound = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RitimError.message("Video birleştirme başlatılamadı.")
        }
        try image.insertTimeRange(videoRange, of: videoTrack, at: .zero)
        image.preferredTransform = try await videoTrack.load(.preferredTransform)
        let audioDuration = CMTimeMinimum(audioRange.duration, videoRange.duration)
        try sound.insertTimeRange(CMTimeRange(start: audioRange.start, duration: audioDuration), of: audioTrack, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough),
              exporter.supportedFileTypes.contains(.mp4) else {
            throw RitimError.message("Bu kaynak iPhone'da MP4 olarak birleştirilemiyor.")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        try await withTaskCancellationHandler {
            let reporting = Task {
                while !Task.isCancelled {
                    progress(min(0.98, Double(exporter.progress)))
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            defer { reporting.cancel() }
            try Task.checkCancellation()
            await exporter.export()
            try Task.checkCancellation()
            guard exporter.status == .completed else {
                throw exporter.error ?? RitimError.message("MP4 birleştirme tamamlanamadı.")
            }
        } onCancel: {
            exporter.cancelExport()
        }
    }

    private static func validate(_ file: URL, format: DownloadFormat) async throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw RitimError.message("Oluşturulan dosya boş.") }
        let asset = AVURLAsset(url: file)
        guard try await asset.load(.isPlayable),
              try await asset.load(.duration).seconds > 0,
              !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw RitimError.message("Oluşturulan dosya bu iPhone'da oynatılamıyor.")
        }
        if format == .mp4, try await asset.loadTracks(withMediaType: .video).isEmpty {
            throw RitimError.message("Oluşturulan MP4 dosyasında görüntü yok.")
        }
    }
}

/// Repairs only fragmented MP4 initialization durations, on a temporary copy.
/// Based on the independent Kepçe motor's MP4Onarici implementation.
enum FragmentedMP4Repair {
    static func copyIfNeeded(_ source: URL, in directory: URL) throws -> URL? {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        var offset: UInt64 = 0
        var moov: (offset: UInt64, size: Int, header: Int)?
        var fragmented = false
        for _ in 0..<64 {
            try reader.seek(toOffset: offset)
            guard let bytes = try reader.read(upToCount: 16), bytes.count >= 8 else { break }
            let shortSize = bytes.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let kind = String(decoding: bytes[4..<8], as: UTF8.self)
            let header = shortSize == 1 ? 16 : 8
            let size: UInt64
            if shortSize == 1 {
                guard bytes.count >= 16 else { break }
                size = bytes[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            } else { size = shortSize }
            if kind == "moov", size >= UInt64(header), size < 50_000_000 { moov = (offset, Int(size), header) }
            if kind == "moof" { fragmented = true; break }
            guard size >= UInt64(header), offset <= UInt64.max - size else { break }
            offset += size
        }
        guard fragmented, let moov else { return nil }
        try Task.checkCancellation()
        try reader.seek(toOffset: moov.offset)
        guard var bytes = try reader.read(upToCount: moov.size), bytes.count == moov.size else {
            throw RitimError.message("Parçalı video başlığı okunamadı.")
        }
        zeroDurations(&bytes, from: moov.header, to: bytes.count)
        let copy = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            try Task.checkCancellation()
            let writer = try FileHandle(forUpdating: copy)
            defer { try? writer.close() }
            try writer.seek(toOffset: moov.offset)
            try writer.write(contentsOf: bytes)
            return copy
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    static func zeroDurations(_ bytes: inout Data, from start: Int, to end: Int) {
        guard start >= 0, end <= bytes.count, start <= end else { return }
        var position = start
        func number(_ offset: Int) -> Int? {
            guard offset >= 0, offset + 4 <= end else { return nil }
            return bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        func clear(_ offset: Int, _ count: Int, limit: Int) {
            guard offset >= 0, offset + count <= limit else { return }
            bytes.replaceSubrange(offset..<(offset + count), with: Data(count: count))
        }
        while position + 8 <= end {
            guard let size = number(position), size >= 8, size <= end - position else { return }
            let boxEnd = position + size
            let kind = String(decoding: bytes[(position + 4)..<(position + 8)], as: UTF8.self)
            let content = position + 8
            switch kind {
            case "mvhd", "mdhd", "tkhd", "elst":
                guard content < boxEnd else { return }
                let version = bytes[content]
                if kind == "mvhd" || kind == "mdhd" {
                    version == 0 ? clear(content + 16, 4, limit: boxEnd) : clear(content + 24, 8, limit: boxEnd)
                } else if kind == "tkhd" {
                    version == 0 ? clear(content + 20, 4, limit: boxEnd) : clear(content + 28, 8, limit: boxEnd)
                } else if let count = number(content + 4) {
                    var item = content + 8
                    for _ in 0..<min(count, 64) {
                        let length = version == 0 ? 12 : 20
                        guard item + length <= boxEnd else { break }
                        clear(item, version == 0 ? 4 : 8, limit: boxEnd)
                        item += length
                    }
                }
            case "moov", "trak", "mdia", "edts": zeroDurations(&bytes, from: content, to: boxEnd)
            default: break
            }
            position = boxEnd
        }
    }
}
