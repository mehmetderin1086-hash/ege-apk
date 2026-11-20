import Foundation
import onnxruntime

/// EMA-TTS (canberkkkkkk/ema-tts, Apache-2.0) cihaz içi çalışma zamanı. 65M parametreli, tek sesli Türkçe akış eşleme (flow matching)
/// modeli; VoxCPM2'nin dondurulmuş AudioVAE'siyle 48 kHz üretir. Model dört ONNX parçaya aktarılmıştır (sunucudaki `ema_export.py`):
///   ema_text  : karakter kimlikleri → karakter gösterimi `h` + karakter süreleri (kare)
///   ema_align : kelime/kare zaman çizelgesi → kare koşulu `cond`
///   ema_dit   : akış alanı (bir Euler adımı); 32 adımlık döngü burada koşar
///   ema_vae   : gizli diziyi 48 kHz sese çözer
/// Paketin zaten bağladığı onnxruntime'ın C API'si kullanılır. Erişimi sahibi sıraya koyar (uygulamada bir actor içinde durur).
public final class EmaTTS {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// `ema.json`: dışa aktarımın yazdığı model sabitleri (sözlük, kare hızı, adım sayısı).
    public struct Config: Decodable, Sendable {
        public var sampleRate: Int
        public var frameRate: Double
        public var latentDim: Int
        public var steps: Int
        public var lead: String
        public var vocab: [String]
        public var maxWordFrames: Int
        public var minWordFrames: Int
        public var maxFrames: Int
        enum CodingKeys: String, CodingKey {
            case sampleRate = "sample_rate", frameRate = "frame_rate", latentDim = "latent_dim", steps, lead, vocab
            case maxWordFrames = "max_word_frames", minWordFrames = "min_word_frames", maxFrames = "max_frames"
        }
    }
    public static let files = ["ema.json", "ema_text.onnx", "ema_align.onnx", "ema_dit.onnx", "ema_vae.onnx"]

    public let config: Config
    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    /// onnxruntime'ın paylaşılan varsayılan ayırıcısı (serbest bırakılmaz).
    private var allocator: UnsafeMutablePointer<OrtAllocator>?
    private var text: OpaquePointer?
    private var align: OpaquePointer?
    private var dit: OpaquePointer?
    private var vae: OpaquePointer?
    private let stoi: [Character: Int64]

    /// `threads`: işlem içi iş parçacığı. Ağırlık ön paketlemesi ve bellek deseni kapalı (bkz. `CTCAcousticModel` ölçümü): DiT 254 MB'lık
    /// ağırlıklarıyla telefonda tek kopya kalır.
    /// `voice`: "tr" (taban EMA) ya da "coskulu" (Biyoizm CC BY verisiyle ince ayarlanmış; metin kodlayıcı, hizalayıcı ve DiT `directory/coskulu` altında,
    /// ses çözücü (AudioVAE) ve `ema.json` her iki sesle ortak olduğundan `directory` içinde)
    public init(directory: URL, voice: String = "tr", threads: Int = 4) throws {
        guard let base = OrtGetApiBase(), let api = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            throw Failure(message: "onnxruntime sürümü uyumsuz")
        }
        self.api = api
        let data = try Data(contentsOf: directory.appendingPathComponent("ema.json"))
        config = try JSONDecoder().decode(Config.self, from: data)
        var table: [Character: Int64] = [:]
        for (index, entry) in config.vocab.enumerated() where entry.count == 1 { table[entry.first!] = Int64(index) }
        stoi = table
        var options: OpaquePointer?
        defer { if let options { api.pointee.ReleaseSessionOptions(options) } }
        do {
            try check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_ERROR, "ema", &env))
            try check(api.pointee.CreateSessionOptions(&options))
            try check(api.pointee.SetIntraOpNumThreads(options, Int32(max(1, threads))))
            try check(api.pointee.SetInterOpNumThreads(options, 1))
            try check(api.pointee.SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL))
            try check(api.pointee.DisableMemPattern(options))
            try check(api.pointee.AddSessionConfigEntry(options, "session.disable_prepacking", "1"))
            let voiceDirectory = voice == "coskulu" ? directory.appendingPathComponent("coskulu", isDirectory: true) : directory
            for (name, slot) in [("ema_text.onnx", \EmaTTS.text), ("ema_align.onnx", \EmaTTS.align), ("ema_dit.onnx", \EmaTTS.dit), ("ema_vae.onnx", \EmaTTS.vae)] {
                var session: OpaquePointer?
                let base = name == "ema_vae.onnx" ? directory : voiceDirectory
                try check(api.pointee.CreateSession(env, base.appendingPathComponent(name).path, options, &session))
                self[keyPath: slot] = session
            }
            try check(api.pointee.GetAllocatorWithDefaultOptions(&allocator))
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    private func close() {
        for session in [text, align, dit, vae] { if let session { api.pointee.ReleaseSession(session) } }
        if let env { api.pointee.ReleaseEnv(env) }
        allocator = nil; text = nil; align = nil; dit = nil; vae = nil; env = nil
    }

    private func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        defer { api.pointee.ReleaseStatus(status) }
        throw Failure(message: api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "onnxruntime hatası")
    }

    // MARK: - Tensörler

    /// Modele giden tensör: Float32 ya da Int64; `shape` satır öncelikli.
    enum Tensor {
        case float([Float], [Int])
        case int64([Int64], [Int])
    }
    struct Output { var values: [Float]; var dims: [Int] }

    private func run(_ session: OpaquePointer?, stage: String, inputs: [(String, Tensor)], outputs: [String]) throws -> [Output] {
        guard let session, let allocator else { throw Failure(message: "model yüklü değil") }
        var values: [OpaquePointer?] = []
        defer { for value in values { if let value { api.pointee.ReleaseValue(value) } } }
        // Girdi tensörleri onnxruntime'ın kendi ayırıcısıyla ayrılır ve veri içine kopyalanır: Swift dizisinin tamponuna Run sırasında
        // bağımlılık kalmaz (withUnsafeBytes işaretçisi closure dışında geçerli değildir).
        for (_, tensor) in inputs {
            var value: OpaquePointer?
            let dims: [Int64], kind: ONNXTensorElementDataType, bytes: Int
            switch tensor {
            case .float(let floats, let shape): dims = shape.map(Int64.init); kind = ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT; bytes = floats.count * 4
            case .int64(let ints, let shape): dims = shape.map(Int64.init); kind = ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64; bytes = ints.count * 8
            }
            guard dims.reduce(1, *) * (kind == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT ? 4 : 8) == Int64(bytes) else { throw Failure(message: "\(stage): tensör boyu şekle uymuyor") }
            try check(api.pointee.CreateTensorAsOrtValue(allocator, dims, dims.count, kind, &value))
            values.append(value)
            var raw: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData(value, &raw))
            guard let raw else { throw Failure(message: "\(stage): tensör belleği alınamadı") }
            switch tensor {
            case .float(let floats, _): floats.withUnsafeBytes { raw.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            case .int64(let ints, _): ints.withUnsafeBytes { raw.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
            }
        }
        let inNames = inputs.map { strdup($0.0) }, outNames = outputs.map { strdup($0) }
        defer { (inNames + outNames).forEach { free($0) } }
        var results = [OpaquePointer?](repeating: nil, count: outputs.count)
        defer { for result in results { if let result { api.pointee.ReleaseValue(result) } } }
        let inPointers = inNames.map { UnsafePointer<CChar>($0) }, outPointers = outNames.map { UnsafePointer<CChar>($0) }
        do {
            try check(api.pointee.Run(session, nil, inPointers, values, inputs.count, outPointers, outputs.count, &results))
        } catch {
            throw Failure(message: "\(stage): \(error.localizedDescription)")
        }
        return try results.map { result in
            var info: OpaquePointer?
            try check(api.pointee.GetTensorTypeAndShape(result, &info))
            defer { if let info { api.pointee.ReleaseTensorTypeAndShapeInfo(info) } }
            var kind = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
            try check(api.pointee.GetTensorElementType(info, &kind))
            var rank = 0
            try check(api.pointee.GetDimensionsCount(info, &rank))
            var dims = [Int64](repeating: 0, count: rank)
            try check(api.pointee.GetDimensions(info, &dims, rank))
            guard kind == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT else { throw Failure(message: "\(stage): beklenmeyen çıktı türü") }
            var raw: UnsafeMutableRawPointer?
            try check(api.pointee.GetTensorMutableData(result, &raw))
            let count = dims.reduce(1) { $0 * Int($1) }
            guard let raw, count >= 0 else { throw Failure(message: "\(stage): çıktı okunamadı") }
            return Output(values: Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: Float.self), count: count)), dims: dims.map(Int.init))
        }
    }

    // MARK: - Sentez

    /// Karakter kimlikleri ve kelime aralıkları (`prepare_text`): metin baş öneki (`lead`) dahil, normalize edilmiş hâliyle verilir.
    /// Her kelime ve ardındaki boşluk bir birimdir; sözlükte olmayan karakter `<unk>` (1) olur.
    public func encode(_ text: String) -> (ids: [Int64], spans: [(Int, Int)]) {
        // Sözlük dışı karakter (emoji, madde imi, yıldız) <unk> olarak modele gitmez; atılır (model <unk>'u neredeyse hiç görmedi).
        let chars = Array(text).filter { stoi[$0] != nil }
        guard !chars.isEmpty else { return ([], []) }
        let ids = chars.map { stoi[$0]! }
        var starts = chars.indices.filter { chars[$0] != " " && ($0 == 0 || chars[$0 - 1] == " ") }
        if starts.isEmpty { starts = [0] }
        var spans = starts.indices.map { (starts[$0], $0 + 1 < starts.count ? starts[$0 + 1] : chars.count) }
        spans[0].0 = 0
        return (ids, spans)
    }

    /// Normalize edilmiş Türkçe satırı seslendirir; `config.sampleRate` hızında Float32 örnekler. `speed` > 1 hızlandırır (süre tahmini
    /// ona bölünür; model sözcükleri daha sık karelere yerleştirir). `noise`: [0,1) tekdüze üretici (test için sabitlenebilir).
    public func synthesize(_ text: String, steps: Int? = nil, speed: Float = 1, noise: () -> Float = { Float.random(in: 0..<1) }) throws -> (samples: [Float], sampleRate: Int) {
        let (ids, spans) = encode(text)
        let L = ids.count
        guard L > 0 else { throw Failure(message: "metin boş") }
        let textOut = try run(text_, stage: "ema_text", inputs: [("ids", .int64(ids, [1, L]))], outputs: ["h", "frames"])
        let h = textOut[0], frames = textOut[1].values
        let d = L == 0 ? 512 : h.values.count / L
        // Kelime başına kare: karakter sürelerinin toplamı (hıza bölünür), yuvarlanır, [0, 250]; boş olmayan kelime en az 1 kare.
        var durations = spans.map { span -> Int in
            let sum = frames[span.0..<span.1].reduce(0, +) / max(speed, 0.5)
            // Yarıda çifte yuvarlama (NumPy `round` ile aynı): PyTorch yoluyla kare sayısı birebir tutar.
            return min(max(Int(sum.rounded(.toNearestOrEven)), 0), config.maxWordFrames)
        }
        for index in spans.indices where spans[index].1 > spans[index].0 && durations[index] < config.minWordFrames { durations[index] = config.minWordFrames }
        let T = min(durations.reduce(0, +), config.maxFrames)
        guard T > 0 else { throw Failure(message: "süre tahmini sıfır") }
        var charWord = [Int64](repeating: -1, count: L), charPos = [Float](repeating: 0, count: L)
        for (word, span) in spans.enumerated() {
            let n = span.1 - span.0
            for j in 0..<n { charWord[span.0 + j] = Int64(word); charPos[span.0 + j] = (Float(j) + 0.5) / Float(n) }
        }
        var frameWord = [Int64](repeating: 0, count: T), framePos = [Float](repeating: 0, count: T)
        var f = 0
        outer: for (word, n) in durations.enumerated() {
            for j in 0..<n {
                if f >= T { break outer }
                frameWord[f] = Int64(word); framePos[f] = (Float(j) + 0.5) / Float(max(1, n)); f += 1
            }
        }
        let cond = try run(align, stage: "ema_align", inputs: [
            ("h", .float(h.values, [1, L, d])), ("ids", .int64(ids, [1, L])), ("char_word", .int64(charWord, [1, L])), ("char_pos", .float(charPos, [1, L])),
            ("frame_word", .int64(frameWord, [1, T])), ("frame_pos", .float(framePos, [1, T])),
        ], outputs: ["cond"])[0].values
        // Başlangıç gürültüsü (Box-Muller) ve Euler döngüsü: x ← x + dt · v(x, t).
        let latent = config.latentDim
        var x = [Float](repeating: 0, count: T * latent)
        for index in x.indices {
            let u1 = max(noise(), 1e-7), u2 = noise()
            x[index] = sqrt(-2 * log(u1)) * cos(2 * Float.pi * u2)
        }
        let count = max(1, steps ?? config.steps)
        let dt = 1 / Float(count)
        let pos = (0..<T).map(Float.init)
        for step in 0..<count {
            let v = try run(dit, stage: "ema_dit", inputs: [
                ("xt", .float(x, [1, T, latent])), ("cond", .float(cond, [1, T, cond.count / T])), ("t", .float([Float(step) * dt], [1])), ("pos", .float(pos, [T])),
            ], outputs: ["v"])[0].values
            guard v.count == x.count else { throw Failure(message: "ema_dit: beklenmeyen çıktı boyu") }
            for index in x.indices { x[index] += dt * v[index] }
        }
        // [1, T, 64] → [1, 64, T]
        var transposed = [Float](repeating: 0, count: x.count)
        for t in 0..<T { for c in 0..<latent { transposed[c * T + t] = x[t * latent + c] } }
        let wav = try run(vae, stage: "ema_vae", inputs: [("latent", .float(transposed, [1, latent, T]))], outputs: ["wav"])[0].values
        guard !wav.isEmpty, wav.allSatisfy(\.isFinite) else { throw Failure(message: "ema_vae: geçersiz ses") }
        return (wav.map { min(1, max(-1, $0)) }, config.sampleRate)
    }
    private var text_: OpaquePointer? { text }
}
