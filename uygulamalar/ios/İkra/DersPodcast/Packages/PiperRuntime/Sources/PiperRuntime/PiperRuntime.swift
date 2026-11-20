import Foundation
import SherpaOnnxC

/// A deliberately small wrapper around the upstream C TTS API. The owner must
/// serialize access (Ders Podcast keeps this object inside an actor).
public final class PiperRuntime {
    public enum Failure: Error { case modelLoad, synthesis }
    private var handle: OpaquePointer?

    public init(directory: URL) throws {
        var strings: [UnsafeMutablePointer<CChar>] = []
        func cString(_ value: String) -> UnsafePointer<CChar> {
            let pointer = strdup(value)!
            strings.append(pointer)
            return UnsafePointer(pointer)
        }
        defer { strings.forEach { free($0) } }
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.vits.model = cString(directory.appendingPathComponent("tr_TR-dfki-medium.onnx").path)
        config.model.vits.tokens = cString(directory.appendingPathComponent("tokens.txt").path)
        config.model.vits.data_dir = cString(directory.appendingPathComponent("espeak-ng-data").path)
        config.model.vits.lexicon = cString("")
        config.model.vits.noise_scale = 0.667
        config.model.vits.noise_scale_w = 0.8
        config.model.vits.length_scale = 1
        config.model.num_threads = 2
        config.model.provider = cString("cpu")
        config.max_num_sentences = 1
        config.silence_scale = 0.2
        handle = SherpaOnnxCreateOfflineTts(&config)
        guard handle != nil else { throw Failure.modelLoad }
    }

    deinit { if let handle { SherpaOnnxDestroyOfflineTts(handle) } }

    public func synthesize(_ text: String, speed: Float) throws -> (samples: [Float], sampleRate: Int) {
        guard let handle else { throw Failure.modelLoad }
        let audio = text.withCString { SherpaOnnxOfflineTtsGenerate(handle, $0, 0, speed) }
        guard let audio else { throw Failure.synthesis }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        guard audio.pointee.n > 0, let samples = audio.pointee.samples,
              audio.pointee.sample_rate > 0 else { throw Failure.synthesis }
        return (Array(UnsafeBufferPointer(start: samples, count: Int(audio.pointee.n))), Int(audio.pointee.sample_rate))
    }
}
