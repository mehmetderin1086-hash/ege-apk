import Foundation
import onnxruntime

/// Madde 50: CTC akustik modeli (wav2vec2, ONNX) için küçük onnxruntime sarmalayıcısı. Paketin zaten bağladığı onnxruntime'ın
/// C API'sini kullanır (sherpa-onnx ham logit vermez). Tek iş: 16 kHz tek kanal örnekler → kare × simge logit matrisi.
/// Erişimi sahibi sıraya koyar (uygulamada bir actor içinde durur).
public final class CTCAcousticModel {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var session: OpaquePointer?
    private var memory: OpaquePointer?
    private let inputName: String
    private let outputName: String

    /// `threads`: işlem içi iş parçacığı sayısı. Bellek ayarları ölçümle seçildi (13 Eki 2026, 356 MB int8 model, Mac'te Python
    /// onnxruntime 1.28): ağırlıkların ön paketlenmesi kapalı (açıkken yükleme sonrası 1058 MB, kapalıyken 525 MB) ve bellek deseni
    /// kapalı (eşit boylu girdilerde açıkken ikinci çalıştırmada ≈ 130 MB büyüyor, kapalıyken ilk çalıştırmadan sonra sabit).
    /// Bu sarmalayıcıyla benzeticide (uygulamanın bağladığı derleme): yükleme sonrası 360 MB, 10,64 sn'lik girdilerde tepe 0,61 GB.
    public init(modelPath: String, threads: Int = 1, inputName: String = "input_values", outputName: String = "logits") throws {
        guard let base = OrtGetApiBase(), let api = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            throw Failure(message: "onnxruntime sürümü uyumsuz")
        }
        self.api = api
        self.inputName = inputName
        self.outputName = outputName
        var options: OpaquePointer?
        defer { if let options { api.pointee.ReleaseSessionOptions(options) } }
        do {
            try check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_ERROR, "ctc", &env))
            try check(api.pointee.CreateSessionOptions(&options))
            try check(api.pointee.SetIntraOpNumThreads(options, Int32(max(1, threads))))
            try check(api.pointee.SetInterOpNumThreads(options, 1))
            try check(api.pointee.SetSessionExecutionMode(options, ORT_SEQUENTIAL))
            // Sleeping between windows must also stop ORT's worker pools from consuming CPU.
            try check(api.pointee.AddSessionConfigEntry(options, "session.intra_op.allow_spinning", "0"))
            try check(api.pointee.AddSessionConfigEntry(options, "session.inter_op.allow_spinning", "0"))
            try check(api.pointee.SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL))
            try check(api.pointee.DisableMemPattern(options))
            try check(api.pointee.AddSessionConfigEntry(options, "session.disable_prepacking", "1"))
            try check(api.pointee.CreateSession(env, modelPath, options, &session))
            try check(api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory))
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    private func close() {
        if let memory { api.pointee.ReleaseMemoryInfo(memory) }
        if let session { api.pointee.ReleaseSession(session) }
        if let env { api.pointee.ReleaseEnv(env) }
        memory = nil; session = nil; env = nil
    }

    private func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        defer { api.pointee.ReleaseStatus(status) }
        throw Failure(message: api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "onnxruntime hatası")
    }

    /// ORT documents RunOptionsSetTerminate as callable from another thread. Each inference owns its
    /// run options; locking prevents a late timer callback from touching options that have been released.
    private final class RunControl: @unchecked Sendable {
        private let api: UnsafePointer<OrtApi>
        private let lock = NSLock()
        private var options: OpaquePointer?
        private let timer: DispatchSourceTimer

        init(api: UnsafePointer<OrtApi>, options: OpaquePointer, maximumSeconds: Double,
             shouldStop: @escaping @Sendable () -> Bool) {
            self.api = api; self.options = options
            let deadline = ProcessInfo.processInfo.systemUptime + max(0.05, maximumSeconds)
            timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                if shouldStop() || ProcessInfo.processInfo.systemUptime >= deadline { self?.terminate() }
            }
            timer.resume()
            if shouldStop() { terminate() }
        }

        private func terminate() {
            lock.lock(); defer { lock.unlock() }
            guard let options else { return }
            if let status = api.pointee.RunOptionsSetTerminate(options) { api.pointee.ReleaseStatus(status) }
        }

        func finish() {
            timer.cancel()
            lock.lock(); defer { lock.unlock() }
            if let options { api.pointee.ReleaseRunOptions(options) }
            options = nil
        }
    }

    /// Örnekler → logitler. İptal/ön plan kaybı ve süre sınırı, pencerenin bitmesini beklemeden ORT'ye iletilir.
    /// ORT iptali operatör sınırlarında işler; tek bir native operatör için kesin süre garantisi değildir.
    public func logits(_ samples: [Float], maximumSeconds: Double = 4,
                       shouldStop: @escaping @Sendable () -> Bool = { false }) throws -> (values: [Float], frames: Int, vocab: Int) {
        guard let session, let memory, !samples.isEmpty else { throw Failure(message: "model yüklü değil ya da ses boş") }
        guard !shouldStop() else { throw CancellationError() }
        var runOptions: OpaquePointer?
        try check(api.pointee.CreateRunOptions(&runOptions))
        guard let runOptions else { throw Failure(message: "çalıştırma seçenekleri oluşturulamadı") }
        let control = RunControl(api: api, options: runOptions, maximumSeconds: maximumSeconds, shouldStop: shouldStop)
        defer { control.finish() }
        var input = samples
        let shape: [Int64] = [1, Int64(samples.count)]
        return try input.withUnsafeMutableBytes { bytes in
            var tensor: OpaquePointer?
            try check(api.pointee.CreateTensorWithDataAsOrtValue(memory, bytes.baseAddress, bytes.count, shape, shape.count,
                                                                 ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &tensor))
            defer { if let tensor { api.pointee.ReleaseValue(tensor) } }
            var output: OpaquePointer?
            defer { if let output { api.pointee.ReleaseValue(output) } }
            try inputName.withCString { inName in
                try outputName.withCString { outName in
                    let inNames: [UnsafePointer<CChar>?] = [inName], outNames: [UnsafePointer<CChar>?] = [outName]
                    let inputs: [OpaquePointer?] = [tensor]
                    try check(api.pointee.Run(session, runOptions, inNames, inputs, 1, outNames, 1, &output))
                }
            }
            var info: OpaquePointer?
            try check(api.pointee.GetTensorTypeAndShape(output, &info))
            defer { if let info { api.pointee.ReleaseTensorTypeAndShapeInfo(info) } }
            var kind = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
            try check(api.pointee.GetTensorElementType(info, &kind))
            var rank = 0
            try check(api.pointee.GetDimensionsCount(info, &rank))
            var dims = [Int64](repeating: 0, count: rank)
            try check(api.pointee.GetDimensions(info, &dims, rank))
            guard kind == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, rank == 3, dims[0] == 1, dims[1] > 0, dims[2] > 0 else {
                throw Failure(message: "beklenmeyen çıktı biçimi: \(dims)")
            }
            var raw: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData(output, &raw))
            guard let raw else { throw Failure(message: "çıktı okunamadı") }
            let frames = Int(dims[1]), vocab = Int(dims[2])
            return (Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: Float.self), count: frames * vocab)), frames, vocab)
        }
    }
}
