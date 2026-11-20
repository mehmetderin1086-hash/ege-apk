import Foundation
import ImageIO
import JavaScriptCore
@preconcurrency import PDFKit
import Synchronization
import UniformTypeIdentifiers

/// Sunucu mantığını uygulamanın içinde çalıştıran gömülü motor. Sunucu (VPS) ve vekil yoktur: istemler, şemalar ve doğrulama
/// `engine.js` paketinde (sunucuyla aynı kod) JavaScriptCore'da çalışır; Claude doğrudan Anthropic API'sinden çağrılır.
///
/// Motorun dış dünyayla tek bağı buradaki köprüdür: ağ istekleri `URLSession` ile yapılır ve Claude API anahtarı yalnız burada,
/// Anthropic'e giden istekte başlığa konur (motorun içine hiç girmez). JavaScript bağlamı tek bir seri kuyrukta yaşar.
nonisolated final class EmbeddedEngine: @unchecked Sendable {
    struct Reply: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    enum Failure: LocalizedError {
        /// Motor başlatılamadı ya da istek motorda işlenemedi.
        case unavailable(String)
        /// Motor isteği süre sınırı içinde yanıtlamadı.
        case timedOut
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): "Uygulama içi motor çalışmıyor: \(reason)"
            case .timedOut: "Uygulama içi motor zamanında yanıt vermedi."
            }
        }
    }

    /// Motorun yaptığı ağ isteği (`engine.js` → `__host.fetch`).
    private struct Outgoing: Decodable {
        var url: String
        var method: String
        var headers: [String: String]
        var body: String?
        var bodyBase64: String?
    }

    static let anthropicHost = "api.anthropic.com"
    /// Motorun anahtar yerine kullandığı yer tutucu; gerçek anahtarla yalnız Anthropic'e giden istekte değiştirilir.
    static let keyPlaceholder = "native"
    /// Motorun VPS'teki Claude vekiline giden istekte anahtar yerine kullandığı yer tutucu; sunucu erişim anahtarına (`X-Personal-Token`)
    /// dönüşür, yalnız vekilin kendi adresinde.
    static let proxyPlaceholder = "native-proxy"
    /// Adım başına model seçimlerinin (uygulamadaki "Modeller" ekranı) saklandığı ayar anahtarı; değer JSON nesnesidir.
    static let stepModelsKey = "questions.stepModels"
    /// Matematik sorularında önce sunucudaki yerel modelin (Qwen + SymPy sağlaması) denenmesi; yoksa açık.
    static let mathLocalFirstKey = "questions.mathLocalFirst"
    /// Altı derste (fizik, kimya, biyoloji, edebiyat, tarih, coğrafya) önce sunucudaki yerel modelin (Gemma + ders kitabı bağlamı) denenmesi; yoksa açık.
    static let dersLocalFirstKey = "questions.dersLocalFirst"
    /// Claude hesabı isteği kabul etmediğinde motorun yanıta eklediği başlık; değeri yedek yolun kullanılacağı süredir (sn).
    static let unavailableHeader = "X-Claude-Unavailable"

    private let queue = DispatchQueue(label: "com.mehmetderin.ders.engine")
    /// Sayfa görüntüleri motor kuyruğunu tutmadan, ama PDF kitaplığına tek iş parçacığından erişerek üretilir.
    private let renderQueue = DispatchQueue(label: "com.mehmetderin.ders.engine.pdf", qos: .userInitiated)
    private let source: @Sendable () throws -> String
    private let key: @Sendable () -> String?
    private let model: @Sendable () -> String?
    private let proxy: @Sendable () -> URL?
    private let token: @Sendable () -> String?
    private let steps: @Sendable () -> Data?
    private let unavailable: @Sendable (TimeInterval) -> Void
    /// Vekil isteklerinin telefondaki CLI Proxy hesaplarıyla karşılanması; yalnız uygulamanın motorunda açık (testlerde kapalı).
    private let phoneProxy: Bool
    private let session: URLSession
    /// Bir isteğin motorda en çok sürebileceği süre; aşılırsa çağıran hatayla serbest bırakılır (uzun senaryo birkaç dakika sürer).
    private let callTimeout: TimeInterval = 1800

    // Aşağıdaki durum yalnız `queue` üzerinde okunur ve değiştirilir.
    private var context: JSContext?
    private var engine: JSValue?
    private var startupError: String?
    private var calls: [Int32: CheckedContinuation<Reply, any Error>] = [:]
    private var watchdogs: [Int32: DispatchWorkItem] = [:]
    private var timers: [Int32: DispatchWorkItem] = [:]
    /// Süren ağ isteklerinin iptal işlevleri (URLSession görevi ya da telefondaki vekil görevi).
    private var tasks: [Int32: () -> Void] = [:]
    /// Motor çağrısı sırasında yakalanmayan JavaScript istisnası (çağrıdan hemen sonra denetlenir).
    private var thrown: String?
    private var documents: [Int32: PDFDocument] = [:]
    private var nextDocument: Int32 = 0

    /// - Parameters:
    ///   - source: `engine.js` paketinin metni (ilk istekte bir kez okunur).
    ///   - key: Claude API anahtarı; yoksa `nil` (istek anlaşılır bir hatayla döner).
    ///   - model: varsayılan Claude modeli; `nil` ise motorun varsayılanı.
    ///   - proxy: VPS'teki Claude vekilinin Anthropic uyumlu ucu (motorun birinci yolu); `nil` ise yalnız API anahtarı denenir.
    ///   - token: vekile giden isteğe konan sunucu erişim anahtarı.
    ///   - steps: adım başına model seçimleri (uygulamadaki "Modeller" ekranı), JSON nesnesi olarak: `{ "read": { "model": … }, … }`.
    ///     Her istekte okunur; seçim hemen geçerli olur.
    ///   - unavailable: Claude hesabı isteği kabul etmediğinde (kredi, anahtar, kullanım sınırı; arka plandaki işte de) ya da motor
    ///     çalışmadığında, yedek yolun kullanılması gereken süreyle çağrılır.
    init(source: @escaping @Sendable () throws -> String, key: @escaping @Sendable () -> String?, model: @escaping @Sendable () -> String? = { nil },
         proxy: @escaping @Sendable () -> URL? = { nil }, token: @escaping @Sendable () -> String? = { nil },
         steps: @escaping @Sendable () -> Data? = { nil },
         unavailable: @escaping @Sendable (TimeInterval) -> Void = { _ in },
         phoneProxy: Bool = false) {
        self.source = source
        self.key = key
        self.model = model
        self.proxy = proxy
        self.token = token
        self.steps = steps
        self.unavailable = unavailable
        self.phoneProxy = phoneProxy
        let configuration = URLSessionConfiguration.ephemeral
        // Uzun senaryo çağrıları dakikalarca sürer; yanıt akış olarak gelir ama motor bitmiş gövdeyi alır.
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1800
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }

    /// Anahtar taşıyan istek başka bir adrese yönlendirilirse izlenmez: `URLSession` özel başlıkları (anahtarı) hedefe taşırdı.
    private nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            let carriesKey = task.originalRequest?.value(forHTTPHeaderField: "x-api-key") != nil
                || task.originalRequest?.value(forHTTPHeaderField: "X-Personal-Token") != nil
            completionHandler(carriesKey ? nil : request)
        }
    }

    /// Sunucudaki `POST <path>` çağrısının karşılığı: gövde JSON'dur, yanıt durum kodu ve JSON gövdedir.
    /// Görev iptal edilirse çağıran hemen serbest kalır (motordaki iş kendi sonuna dek sürebilir; sonucu atılır).
    func request(_ path: String, body: Data) async throws -> Reply {
        let call = Self.callIDs.withLock { id -> Int32 in
            id &+= 1
            return id
        }
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.begin(call, path, body, cancellation, continuation) }
            }
        } onCancel: {
            cancellation.set()
            queue.async { self.finish(call, with: .failure(CancellationError())) }
        }
    }

    private static let callIDs = Mutex<Int32>(0)

    /// İstek motor kuyruğuna ulaşmadan iptal edildiyse motor hiç çalıştırılmaz (kuyrukta görev bağlamı yoktur; bayrak elle taşınır).
    private nonisolated final class Cancellation: Sendable {
        private let flag = Mutex(false)
        var isSet: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }

    // MARK: - Motor

    private func begin(_ call: Int32, _ path: String, _ body: Data, _ cancellation: Cancellation, _ continuation: CheckedContinuation<Reply, any Error>) {
        guard !cancellation.isSet else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let engine = started() else {
            continuation.resume(throwing: Failure.unavailable(startupError ?? "bilinmeyen hata"))
            return
        }
        calls[call] = continuation
        let watchdog = DispatchWorkItem { [weak self] in self?.finish(call, with: .failure(Failure.timedOut)) }
        watchdogs[call] = watchdog
        queue.asyncAfter(deadline: .now() + callTimeout, execute: watchdog)
        thrown = nil
        engine.invokeMethod("handle", withArguments: [call, path, String(decoding: body, as: UTF8.self)])
        // `handle` eşzamanlı hata fırlattıysa yanıt hiç gelmez: çağıran asılı kalmasın.
        if let thrown {
            self.thrown = nil
            finish(call, with: .failure(Failure.unavailable(thrown)))
        }
    }

    /// Çağrıyı bir kez sonuçlandırır (yanıt, iptal, süre aşımı ya da motor hatası; hangisi önce gelirse).
    private func finish(_ call: Int32, with result: Result<Reply, any Error>) {
        watchdogs.removeValue(forKey: call)?.cancel()
        calls.removeValue(forKey: call)?.resume(with: result)
    }

    private func started() -> JSValue? {
        if let engine { return engine }
        if startupError != nil { return nil }
        guard let context = JSContext() else {
            startupError = "JavaScript bağlamı oluşturulamadı"
            return nil
        }
        context.exceptionHandler = { [weak self] _, exception in
            let text = exception?.toString() ?? "?"
            self?.thrown = text
            self?.note("error", "Motor istisnası: \(text)")
        }
        context.setObject(hostObject(in: context), forKeyedSubscript: "__host" as NSString)
        do {
            context.evaluateScript(try source(), withSourceURL: URL(string: "engine.js"))
        } catch {
            startupError = "motor paketi okunamadı"
            return nil
        }
        thrown = nil
        guard let engine = context.objectForKeyedSubscript("__engine"), engine.hasProperty("handle") else {
            startupError = "motor paketi yüklenemedi"
            return nil
        }
        self.context = context
        self.engine = engine
        return engine
    }

    /// Motorun çağırdığı köprü işlevleri. Hepsi JavaScript çalışırken, yani `queue` üzerinde çağrılır.
    private func hostObject(in context: JSContext) -> JSValue {
        let host = JSValue(newObjectIn: context)!
        let log: @convention(block) (String, String) -> Void = { [weak self] level, message in self?.note(level, message) }
        let timer: @convention(block) (Int32, Double) -> Void = { [weak self] id, milliseconds in self?.schedule(id, milliseconds) }
        let cancelTimer: @convention(block) (Int32) -> Void = { [weak self] id in self?.timers.removeValue(forKey: id)?.cancel() }
        let fetch: @convention(block) (Int32, String) -> Void = { [weak self] id, request in self?.send(id, request) }
        let abort: @convention(block) (Int32) -> Void = { [weak self] id in self?.tasks.removeValue(forKey: id)?() }
        let random: @convention(block) (Int32) -> String = { count in
            // Sistem üreteci kriptografik olarak güvenlidir ve başarısız olmaz.
            var generator = SystemRandomNumberGenerator()
            let bytes = (0..<max(0, Int(count))).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            return Data(bytes).base64EncodedString()
        }
        let config: @convention(block) () -> String = { [weak self] in
            // Anahtar motora girmez; vekilin adresi her istekte buradan okunur.
            var payload: [String: Any] = ["claudeModel": self?.model() ?? "", "claudeProxy": self?.proxy()?.absoluteString ?? ""]
            if QSModelPlan.astraOnly { payload["modelPolicy"] = "astra-only" }
            // Adım başına model seçimleri: bozuk ya da boş kayıt motoru etkilemez (adımlar kendi modelleriyle çalışır).
            if let data = self?.steps(), let table = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], !table.isEmpty { payload["stepModels"] = table }
            // Matematikte yerel ilk geçiş (sunucudaki Qwen + SymPy; 13 Eki 2026): ayar yoksa KAPALI (17 Eki 2026: bütün çözümler Claude, ChatGPT ve Gemini'den).
            payload["mathLocalFirst"] = UserDefaults.standard.object(forKey: EmbeddedEngine.mathLocalFirstKey) as? Bool ?? false
            // Altı derste yerel ilk geçiş (sunucudaki Gemma + kaynak deposu; 14 Eki 2026): ayar yoksa KAPALI (17 Eki 2026).
            payload["dersLocalFirst"] = UserDefaults.standard.object(forKey: EmbeddedEngine.dersLocalFirstKey) as? Bool ?? false
            return (try? JSONSerialization.data(withJSONObject: payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        }
        let done: @convention(block) (Int32, Int32, String, String) -> Void = { [weak self] call, status, body, headers in
            guard let self else { return }
            let parsed = (try? JSONSerialization.jsonObject(with: Data(headers.utf8))) as? [String: String] ?? [:]
            // Çağıran vazgeçmiş olsa da bildirim işlenir: süren bir işin hatası yalnız bu başlıkla öğrenilir.
            if let wait = parsed[Self.unavailableHeader].flatMap(Double.init), wait > 0 { self.unavailable(wait) }
            self.finish(call, with: .success(Reply(status: Int(status), body: Data(body.utf8), headers: parsed)))
        }
        // Kalıcı dosya köprüsü (madde 13): motorun `/data` ağacı Application Support/EngineData altına yansıtılır ve açılışta geri yüklenir.
        let fsLoad: @convention(block) () -> String = { EngineData.snapshot() }
        let fsSync: @convention(block) (String, String, JSValue, JSValue) -> Void = { op, path, data, to in
            EngineData.apply(op, path: path, data: data.isNull || data.isUndefined ? nil : data.toString(), to: to.isNull || to.isUndefined ? nil : to.toString())
        }
        // Uygulama kaynağı köprüsü (madde 30): motorun isteğe bağlı ikili dosyası (vtracer wasm) motor paketine gömülmez, yanında
        // durur ve yalnız istendiğinde okunur. base64 döner; dosya yoksa boş.
        let asset: @convention(block) (String) -> String = { name in Self.asset(named: name)?.base64EncodedString() ?? "" }
        let pdfOpen: @convention(block) (String, Bool) -> String = { [weak self] data, text in self?.openDocument(data, withText: text) ?? "{}" }
        let pdfRender: @convention(block) (Int32, Int32, Int32) -> Void = { [weak self] id, page, call in self?.renderPage(id, page, call) }
        let pdfClose: @convention(block) (Int32) -> Void = { [weak self] id in
            // Süren görüntü işleri belgeyi kendi başvurusuyla tutar; kapatma onları beklemez.
            self?.documents.removeValue(forKey: id)
        }
        for (name, block) in [("log", log as Any), ("timer", timer), ("cancelTimer", cancelTimer), ("fetch", fetch), ("abort", abort),
                              ("random", random), ("config", config), ("done", done), ("pdfOpen", pdfOpen), ("pdfRender", pdfRender), ("pdfClose", pdfClose),
                              ("fsLoad", fsLoad), ("fsSync", fsSync), ("asset", asset)] {
            host.setObject(block, forKeyedSubscript: name as NSString)
        }
        return host
    }

    /// Motorun uygulama paketindeki ikili kaynağı. Ad yalın bir `.wasm` dosya adı olmalıdır: motor başka dosya ya da yol isteyemez.
    static func asset(named name: String, in bundle: Bundle = .main) -> Data? {
        guard name.hasSuffix(".wasm"), !name.contains("/"), !name.contains(".."), let url = bundle.url(forResource: name, withExtension: nil) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func note(_ level: String, _ message: String) {
        #if DEBUG
        print("[motor \(level)] \(message)")
        #else
        if level == "error" || level == "warn" { NSLog("[motor %@] %@", level, message) }
        #endif
    }

    private func schedule(_ id: Int32, _ milliseconds: Double) {
        timers.removeValue(forKey: id)?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timers.removeValue(forKey: id)
            self.engine?.invokeMethod("fire", withArguments: [id])
        }
        timers[id] = item
        queue.asyncAfter(deadline: .now() + max(0, milliseconds) / 1000, execute: item)
    }

    // MARK: - PDF

    /// base64 PDF'i açar; sayfa sayısını ve (istenirse) sayfaların gömülü metnini döndürür. Açılamayan (bozuk, şifreli, boş)
    /// belgede `{}`. Metin çıkarmak büyük belgede saniyeler sürer; yalnız sayfa görüntüsü gerekiyorsa atlanır.
    private func openDocument(_ base64: String, withText: Bool) -> String {
        guard let data = Data(base64Encoded: base64), let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else { return "{}" }
        nextDocument &+= 1
        documents[nextDocument] = document
        var payload: [String: Any] = ["id": Int(nextDocument), "count": document.pageCount]
        if withText { payload["pages"] = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" } }
        return (try? JSONSerialization.data(withJSONObject: payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func renderPage(_ id: Int32, _ number: Int32, _ call: Int32) {
        // Belgeye yalnız `renderQueue` üzerinden dokunulur (PDF kitaplığı eşzamanlı erişime dayanıklı değildir).
        nonisolated(unsafe) let document = documents[id]
        renderQueue.async { [weak self] in
            let image = document?.page(at: Int(number) - 1).flatMap { Self.jpeg(of: $0, longSide: 2000) }?.base64EncodedString()
            guard let self else { return }
            self.queue.async { self.engine?.invokeMethod("rendered", withArguments: [call, image ?? NSNull()]) }
        }
    }

    /// Sayfayı (dönüşü uygulanmış hâliyle) beyaz zemine çizip JPEG'e çevirir; uzun kenar `longSide` piksel olur.
    private static func jpeg(of page: PDFPage, longSide: CGFloat) -> Data? {
        let box = page.bounds(for: .mediaBox)
        let turned = page.rotation % 180 != 0
        let size = turned ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = longSide / max(size.width, size.height)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // `draw` sayfanın dönüşünü ve kutu ötelemesini kendisi uygular.
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // MARK: - Ağ

    private func send(_ id: Int32, _ requestJSON: String) {
        guard let outgoing = try? JSONDecoder().decode(Outgoing.self, from: Data(requestJSON.utf8)),
              let url = URL(string: outgoing.url), let scheme = url.scheme?.lowercased(), scheme == "https" else {
            queue.async { self.settle(id, failure: "Geçersiz ağ isteği.") }
            return
        }
        let body = outgoing.body.map { Data($0.utf8) } ?? outgoing.bodyBase64.flatMap { Data(base64Encoded: $0) }
        // Telefondaki CLI Proxy hesapları (17 Eki 2026): vekile giden model istekleri ağa çıkmadan uygulama içinde karşılanır.
        // Kasa boşsa ya da ayar kapalıysa istek aşağıdaki eski yoldan VPS'e gider.
        if phoneProxy, outgoing.headers["x-api-key"] == Self.proxyPlaceholder, let proxy = proxy(), Self.belongs(url, to: proxy),
           let local = PhoneProxy.localPath(for: url, proxy: proxy) {
            let method = outgoing.method, headers = outgoing.headers
            let job = Task { [weak self] in
                let reply = await PhoneProxy.handle(method: method, path: local, headers: headers, body: body ?? Data())
                guard let self else { return }
                self.queue.async { self.deliver(id, status: reply.status, headers: reply.headers, body: reply.body) }
            }
            tasks[id] = { job.cancel() }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = outgoing.method
        for (name, value) in outgoing.headers { request.setValue(value, forHTTPHeaderField: name) }
        if outgoing.headers["x-api-key"] == Self.keyPlaceholder {
            // Yer tutucu yalnız Anthropic için geçerlidir: anahtar başka hiçbir adrese gönderilmez.
            guard url.host()?.lowercased() == Self.anthropicHost, let secret = key(), !secret.isEmpty else {
                let missing = url.host()?.lowercased() == Self.anthropicHost
                queue.async { self.settle(id, failure: missing ? "Claude API anahtarı girilmemiş." : "Anahtar bu adrese gönderilemez.") }
                return
            }
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
        } else if outgoing.headers["x-api-key"] == Self.proxyPlaceholder {
            // Vekil yer tutucusu yalnız vekilin kendi adresinde sunucu erişim anahtarına dönüşür; API anahtarı oraya hiç gitmez.
            request.setValue(nil, forHTTPHeaderField: "x-api-key")
            guard let proxy = proxy(), Self.belongs(url, to: proxy) else {
                queue.async { self.settle(id, failure: "Erişim anahtarı bu adrese gönderilemez.") }
                return
            }
            guard let token = token(), !token.isEmpty else {
                queue.async { self.settle(id, failure: "Sunucu erişim anahtarı girilmemiş.") }
                return
            }
            request.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        }
        request.httpBody = body
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async { self.received(id, data, response, error) }
        }
        tasks[id] = { task.cancel() }
        task.resume()
    }

    private func received(_ id: Int32, _ data: Data?, _ response: URLResponse?, _ error: (any Error)?) {
        guard tasks.removeValue(forKey: id) != nil else { return } // motor isteği iptal etti
        guard let http = response as? HTTPURLResponse, error == nil else {
            // Neden motora (oradan kullanıcıya) taşınır: "bağlantı kurulamadı" tek başına hücresel kısıtı, kopmayı ve DNS'i ayırt ettirmez.
            let reason = Self.connectionFailure(error)
            note("warn", "Ağ isteği başarısız: \(reason)")
            settle(id, failure: reason)
            return
        }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields { headers[String(describing: name).lowercased()] = String(describing: value) }
        respond(id, status: http.statusCode, headers: headers, body: data ?? Data())
    }

    /// Telefondaki vekilin yanıtı (motor isteği bu arada iptal ettiyse yok sayılır).
    private func deliver(_ id: Int32, status: Int, headers: [String: String], body: Data) {
        guard tasks.removeValue(forKey: id) != nil else { return }
        respond(id, status: status, headers: headers, body: body)
    }

    /// Yanıtı motora verir; başlık adları küçük harfli gelir.
    private func respond(_ id: Int32, status: Int, headers: [String: String], body: Data) {
        let headerJSON = (try? JSONSerialization.data(withJSONObject: headers)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let type = headers["content-type"] ?? ""
        // Metin gövdesi (JSON, olay akışı) olduğu gibi, ikili gövde (görsel, ses) base64 olarak verilir.
        let textual = ["json", "text", "event-stream", "xml"].contains { type.contains($0) }
        if textual, let text = String(data: body, encoding: .utf8) {
            engine?.invokeMethod("settle", withArguments: [id, status, headerJSON, text, NSNull(), NSNull()])
        } else {
            engine?.invokeMethod("settle", withArguments: [id, status, headerJSON, NSNull(), body.base64EncodedString(), NSNull()])
        }
    }

    /// İstek vekilin adresinde mi: aynı şema, sunucu ve kapı; yol vekilin yolu ya da onun altında (`/dersdas/claude/v1/...`).
    static func belongs(_ url: URL, to proxy: URL) -> Bool {
        guard url.scheme?.lowercased() == proxy.scheme?.lowercased(), url.host()?.lowercased() == proxy.host()?.lowercased(), url.port == proxy.port else { return false }
        let base = proxy.path().hasSuffix("/") ? String(proxy.path().dropLast()) : proxy.path()
        return url.path() == base || url.path().hasPrefix(base + "/")
    }

    /// `URLSession` hatasının kullanıcıya gösterilecek kısa nedeni; motor bunu "Claude API bağlantısı kurulamadı" iletisine ekler.
    static func connectionFailure(_ error: (any Error)?) -> String {
        guard let error else { return "Bağlantı kurulamadı." }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet?: return "İnternet bağlantısı yok."
        case .dataNotAllowed?: return "Hücresel veri bu uygulama için kapalı; Ayarlar › Hücresel'den açın ya da Wi-Fi'ye bağlanın."
        case .internationalRoamingOff?: return "Uluslararası dolaşımda veri kapalı."
        case .callIsActive?: return "Görüşme sürerken veri kullanılamıyor."
        case .networkConnectionLost?: return "Bağlantı koptu."
        case .timedOut?: return "Bağlantı zaman aşımına uğradı."
        case .cannotFindHost?, .dnsLookupFailed?: return "Sunucu adı çözümlenemedi."
        case .cannotConnectToHost?: return "Sunucuya bağlanılamadı."
        case .secureConnectionFailed?, .serverCertificateUntrusted?, .serverCertificateHasBadDate?, .serverCertificateHasUnknownRoot?, .serverCertificateNotYetValid?:
            return "Güvenli bağlantı kurulamadı."
        case .cancelled?: return "İstek iptal edildi."
        case let code?: return "Bağlantı kurulamadı (\(code.rawValue))."
        case nil: return "Bağlantı kurulamadı (\((error as NSError).domain) \((error as NSError).code))."
        }
    }

    private func settle(_ id: Int32, failure: String) {
        engine?.invokeMethod("settle", withArguments: [id, 0, "{}", NSNull(), NSNull(), failure])
    }
}

extension EmbeddedEngine {
    /// Uygulamanın motoru: paket uygulama kaynaklarından (`engine.jsbundle`); Claude önce VPS'teki vekilden (sunucu erişim anahtarıyla),
    /// o yanıt veremezse Keychain'deki ya da derlemeye gömülü API anahtarıyla doğrudan çağrılır.
    static let shared = EmbeddedEngine(
        source: {
            guard let url = Bundle.main.url(forResource: "engine", withExtension: "jsbundle") else { throw Failure.unavailable("motor paketi uygulamada yok") }
            return try String(contentsOf: url, encoding: .utf8)
        },
        key: { ClaudeKey.current },
        proxy: { Backend.claudeProxyURL },
        token: { PersonalToken.current },
        steps: { UserDefaults.standard.data(forKey: EmbeddedEngine.stepModelsKey) },
        unavailable: { Backend.suspendEngine(for: $0) },
        phoneProxy: true)

    /// Sunucudaki `POST path` çağrısının uygulama içi karşılığı: başarılı yanıtın ham gövdesi. Hata gövdesi sunucudakiyle aynı
    /// biçimdedir ve `APIError`'a çevrilir.
    func reply(to path: String, body: Data) async throws -> Data {
        let reply: Reply
        do {
            reply = try await request(path, body: body)
        } catch Failure.timedOut {
            // Yanıtı yarım saatte gelmeyen istek yedek yolda yeniden başlatılmaz.
            throw APIError(status: 0, code: "engine_timeout", message: Failure.timedOut.localizedDescription)
        } catch let failure as Failure {
            // Motor çalışmıyor (paket yok ya da bozuk): bir süre her istek yedek yoldan gider.
            unavailable(Backend.suspension)
            throw APIError(status: 0, code: "engine", message: failure.localizedDescription, reason: "claude_unavailable")
        }
        try Task.checkCancellation()
        guard (200..<300).contains(reply.status) else {
            let retryAfter = reply.headers["Retry-After"].flatMap(Double.init)
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: reply.body) {
                throw APIError(status: reply.status, code: envelope.error.code, message: envelope.error.message, retryAfter: retryAfter, reason: envelope.error.reason)
            }
            throw APIError(status: reply.status, code: "http_\(reply.status)", message: "İşlem tamamlanamadı (\(reply.status)). Lütfen tekrar dene.")
        }
        return reply.body
    }

    func call<Body: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, _ body: Body) async throws -> Response {
        let data = try await reply(to: path, body: try JSONEncoder().encode(body))
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError(status: 200, code: "decode", message: "Beklenmeyen bir yanıt geldi.")
        }
    }
}


/// Motorun `/data` ağacının diskteki aynası (madde 13): dosyalar `Application Support/EngineData/data/...` altında durur; motor her
/// yazımı, silmeyi ve klasörü bildirir, açılışta ağacın tamamını JSON olarak geri alır. Yollar yalnız `/data` altında olabilir.
nonisolated enum EngineData {
    static let root: URL = URL.applicationSupportDirectory.appending(path: "EngineData", directoryHint: .isDirectory)
    /// Motor yolu (`/data/x/y`) → diskteki yer; `/data` dışı ya da `..` içeren yol reddedilir.
    static func location(_ path: String, under root: URL = root) -> URL? {
        guard path == "/data" || path.hasPrefix("/data/"), !path.split(separator: "/").contains("..") else { return nil }
        return root.appending(path: String(path.dropFirst(1)))
    }
    static func apply(_ op: String, path: String, data: String?, to: String?, under root: URL = root) {
        guard let target = location(path, under: root) else { return }
        let manager = FileManager.default
        switch op {
        case "mkdir":
            try? manager.createDirectory(at: target, withIntermediateDirectories: true)
        case "write":
            guard let data, let bytes = Data(base64Encoded: data) else { return }
            try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? bytes.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        case "remove":
            try? manager.removeItem(at: target)
        default: break
        }
    }
    /// Diskteki ağacın anlık görüntüsü: `{ dirs: [...], files: [{ path, data, mtimeMs }] }`; ayna yoksa boş.
    static func snapshot(under root: URL = root) -> String {
        let base = root.appending(path: "data", directoryHint: .isDirectory)
        var dirs: [String] = [], files: [[String: Any]] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        if let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            while let item = enumerator.nextObject() as? URL {
                guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
                let relative = "/data/" + item.path.dropFirst(base.path.count + 1)
                if values.isDirectory == true { dirs.append(relative); continue }
                guard let data = try? Data(contentsOf: item) else { continue }
                files.append(["path": relative, "data": data.base64EncodedString(), "mtimeMs": (values.contentModificationDate ?? .now).timeIntervalSince1970 * 1000])
            }
        }
        guard !dirs.isEmpty || !files.isEmpty, let json = try? JSONSerialization.data(withJSONObject: ["dirs": dirs, "files": files]) else { return "" }
        return String(decoding: json, as: UTF8.self)
    }
}
