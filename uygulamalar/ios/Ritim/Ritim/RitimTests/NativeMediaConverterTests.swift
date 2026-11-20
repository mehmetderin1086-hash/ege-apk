import AVFoundation
import XCTest
@testable import Ritim

final class NativeMediaConverterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NativeMediaTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func fixture(_ name: String, extension suffix: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
    }

    func testFragmentedVideoDurationRepairPreservesOriginalAndNonFragmentedFiles() throws {
        func box(_ name: String, _ body: Data) -> Data {
            let size = UInt32(body.count + 8).bigEndian
            var data = withUnsafeBytes(of: size) { Data($0) }
            data.append(contentsOf: name.utf8)
            data.append(body)
            return data
        }
        var movieHeader = Data(repeating: 0, count: 20)
        movieHeader.replaceSubrange(16..<20, with: [UInt8](arrayLiteral: 0, 0, 0, 42))
        let moov = box("moov", box("mvhd", movieHeader))
        let fragmented = moov + box("moof", Data())
        let source = directory.appendingPathComponent("source.mp4")
        try fragmented.write(to: source)
        let repaired = try XCTUnwrap(FragmentedMP4Repair.copyIfNeeded(source, in: directory))
        let repairedBytes = try Data(contentsOf: repaired)
        XCTAssertEqual(try Data(contentsOf: source), fragmented)
        XCTAssertEqual(Array(repairedBytes[32..<36]), [0, 0, 0, 0])
        XCTAssertEqual(repairedBytes.count, fragmented.count)
        let regular = directory.appendingPathComponent("regular.mp4")
        try moov.write(to: regular)
        XCTAssertNil(try FragmentedMP4Repair.copyIfNeeded(regular, in: directory))
        XCTAssertEqual(try Data(contentsOf: regular), moov)
    }

    func testConcurrentMP3ConversionsProduceActual192And320KbpsFiles() async throws {
        let source = try fixture("native-audio", extension: "m4a")
        async let standard = NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                          quality: .standard, outputDirectory: directory)
        async let highest = NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                         quality: .highest, outputDirectory: directory)
        let (standardURL, highestURL) = try await (standard, highest)
        for (file, bitrateIndex) in [(standardURL, 11), (highestURL, 14)] {
            let bytes = try Data(contentsOf: file)
            XCTAssertEqual(bytes[0], 0xFF)
            XCTAssertEqual(bytes[1] & 0xFE, 0xFA, "MPEG-1 Layer III frame, not renamed AAC")
            XCTAssertEqual(Int(bytes[2] >> 4), bitrateIndex)
            let asset = AVURLAsset(url: file)
            let duration = try await asset.load(.duration).seconds
            XCTAssertEqual(duration, 4, accuracy: 0.08)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let track = try XCTUnwrap(tracks.first)
            let descriptions = try await track.load(.formatDescriptions)
            let description = try XCTUnwrap(descriptions.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), kAudioFormatMPEGLayer3)
            let playable = try await asset.load(.isPlayable)
            XCTAssertTrue(playable)
        }
        XCTAssertGreaterThan(try Data(contentsOf: highestURL).count, try Data(contentsOf: standardURL).count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testAdaptiveMP4MuxPreserves4KAndAddsAudio() async throws {
        let output = try await NativeMediaConverter.convert(
            audio: fixture("native-audio", extension: "m4a"),
            video: fixture("native-4k-video", extension: "mp4"),
            format: .mp4, quality: .highest, outputDirectory: directory
        )
        let asset = AVURLAsset(url: output)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videos.first)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 3840, height: 2160))
        XCTAssertEqual(audio.count, 1)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 4, accuracy: 0.08)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
    }

    func testStandardProfileRejectsOversizedSourceWithoutLeavingOutput() async throws {
        do {
            _ = try await NativeMediaConverter.convert(
                audio: fixture("native-audio", extension: "m4a"),
                video: fixture("native-4k-video", extension: "mp4"),
                format: .mp4, quality: .standard, outputDirectory: directory
            )
            XCTFail("A 4K source must not be accepted as the 1080p profile")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("kalite sınırını"))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testCancellationRemovesPartialMP3() async throws {
        let source = try fixture("native-audio", extension: "m4a")
        let cancellation = ConversionCancellation()
        let operation = Task {
            try await NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                   quality: .highest, outputDirectory: directory) { fraction in
                if fraction > 0 { cancellation.cancel() }
            }
        }
        cancellation.set(operation)
        do {
            _ = try await operation.value
            XCTFail("Conversion must stop after cancellation")
        } catch is CancellationError {
            // The completed cancellation also waits for encoder/file cleanup.
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testConvertersSerializeCPUWorkAndCancelledWaiterNeverStartsOrStrandsQueue() async throws {
        let source = try fixture("native-audio", extension: "m4a")
        let firstStarted = expectation(description: "First converter owns the CPU slot")
        let releaseFirst = DispatchSemaphore(value: 0)
        let waitingStarts = ConversionStarts()
        let first = Task {
            try await NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                   quality: .highest, outputDirectory: directory) { fraction in
                if fraction == 0 {
                    firstStarted.fulfill()
                    _ = releaseFirst.wait(timeout: .now() + 5)
                }
            }
        }
        defer { releaseFirst.signal(); first.cancel() }
        await fulfillment(of: [firstStarted], timeout: 3)
        let waiting = Task {
            try await NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                   quality: .standard, outputDirectory: directory) { fraction in
                if fraction == 0 { waitingStarts.increment() }
            }
        }
        defer { waiting.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(waitingStarts.value, 0, "A second encoder must not consume CPU while the first holds its slot.")
        let cancelledAt = Date()
        waiting.cancel()
        do {
            _ = try await waiting.value
            XCTFail("A queued converter must be cancellable without starting")
        } catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 0.5)
        XCTAssertEqual(waitingStarts.value, 0)

        releaseFirst.signal()
        let firstOutput = try await first.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstOutput.path))
        let nextOutput = try await NativeMediaConverter.convert(audio: source, video: nil, format: .mp3,
                                                                quality: .standard, outputDirectory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nextOutput.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2,
                       "The cancelled queued attempt must not leave an output or strand the conversion permit.")
    }

    func testRemoteURLsCannotReachTheConverter() async throws {
        do {
            _ = try await NativeMediaConverter.convert(audio: URL(string: "https://example.com/audio.m4a")!,
                                                       video: nil, format: .mp3, quality: .highest,
                                                       outputDirectory: directory)
            XCTFail("Converter must only use files downloaded onto the device")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("önce iPhone'a"))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

private final class ConversionStarts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class ConversionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<URL, Error>?
    private var cancelled = false
    func set(_ task: Task<URL, Error>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let operation = task
        lock.unlock()
        operation?.cancel()
    }
}
