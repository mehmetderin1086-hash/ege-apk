#if DEBUG
import Foundation
import Network

/// P3.10 hermetik test: `--sahte-model` kipinde CLIProxy'nin yerine geçen, yalnız 127.0.0.1'de dinleyen sahte model sunucusu.
/// `GET /v1/models`, `POST /v1/messages` (Anthropic SSE ya da tek JSON) ve `POST /v1/chat/completions` (OpenAI SSE) yanıtlar;
/// yanıtlar `SahteSenaryo` kurallarından gelir. Ağa, Keychain'e, VPS'e çıkmaz. Yalnız DEBUG derlemede vardır.
/// AGENTS kuralı: bütün Network.framework kapanışları @Sendable, sunucunun kendi kuyruğunda çalışır (MainActor'a dokunmaz).
nonisolated final class SahteModelSunucusu: @unchecked Sendable {
    /// Uygulamanın kullandığı tekil; yalnız `--sahte-model` kipinde başlatılır (TelefonProxy.hazirla).
    /// Birim testleri bunu değil, kendi `SahteModelSunucusu()` örneklerini kullanır (küresel durum kirlenmesin).
    static let ortak = SahteModelSunucusu()
    static let etkin = ProcessInfo.processInfo.arguments.contains("--sahte-model")
    /// P3.10-arıza geçiş kipi örneği (sahte kipin `ortak`'ından ayrı): model arızası açıkken `TelefonProxy.taban` bunu döndürür.
    /// Arıza tüketilmeyen istekler gerçek tabana (iPhone CLIProxy) iletilir; `ArizaAnahtarlari.hepsiniKapat()` durdurur.
    static let gecis = SahteModelSunucusu()

    nonisolated struct Kayit: Sendable, Equatable {
        let yol: String
        let model: String
        /// Son kullanıcı metninin ilk 40 karakteri (tani.log'a yazılmaz; yalnız bellek içi).
        let metin: String
    }

    nonisolated enum Hata: LocalizedError {
        case baslatilamadi(String)
        var errorDescription: String? {
            switch self { case .baslatilamadi(let s): "sahte sunucu başlatılamadı: \(s)" }
        }
    }

    private let kilit = NSLock()
    private let kuyruk = DispatchQueue(label: "asistan.sahte-model-sunucusu")
    private var dinleyici: NWListener?
    private var baglantilar: [ObjectIdentifier: NWConnection] = [:]
    private var senaryo: SahteSenaryo = .yerlesik
    private var _tabanURL: URL?
    private var _gunluk: [Kayit] = []
    /// Geçiş kipi (P3.10-arıza): hedef varsa istekler senaryodan değil hedeften yanıtlanır.
    private var _hedef: URL?
    private var _ariza: ArizaDeposu?
    private var _ilkParcaGecikmesi: Duration = .seconds(8)
    /// Geçiş kipinde bağlantı başına iletim görevi; istemci bağlantısı kapanınca iptal edilir.
    private var gecisGorevleri: [ObjectIdentifier: Task<Void, Never>] = [:]

    init() {}

    /// Dinleyici hazırsa kök adres ("http://127.0.0.1:<port>"); değilse nil.
    var tabanURL: URL? { kilit.lock(); defer { kilit.unlock() }; return _tabanURL }
    /// Gelen isteklerin özeti (birim testinde okunur).
    var istekGunlugu: [Kayit] { kilit.lock(); defer { kilit.unlock() }; return _gunluk }

    func senaryoAyarla(_ s: SahteSenaryo) { kilit.lock(); senaryo = s; kilit.unlock() }
    private var simdikiSenaryo: SahteSenaryo { kilit.lock(); defer { kilit.unlock() }; return senaryo }

    private var baslatma: Task<URL, Error>?

    /// Port 0 → işletim sistemi boş port atar. Zaten çalışıyorsa senaryoyu günceller ve aynı adresi döndürür;
    /// eşzamanlı iki çağrı aynı başlatmayı bekler (ikinci dinleyici açılmaz).
    @discardableResult
    func baslat(senaryo: SahteSenaryo, port: UInt16 = 0) async throws -> URL {
        senaryoAyarla(senaryo)
        return try await baslatmaGorevi(port: port).value
    }

    /// Geçiş kipi: her POST isteğinde `ariza` deposundan bir model arızası tüketilirse ilgili yapay yanıt döner
    /// (429 + retry-after, 500, akış yarıda kesilir, ilk parça gecikir); tüketilmezse istek başlıkları (Authorization dahil)
    /// korunarak `hedef`e iletilir ve gelen baytlar parça parça yazılır. Zaten çalışıyorsa hedefi günceller, aynı adresi döndürür.
    @discardableResult
    func baslatGecis(hedef: URL, ariza: ArizaDeposu = ArizaAnahtarlari.gecerli, ilkParcaGecikmesi: Duration = .seconds(8)) async throws -> URL {
        gecisAyarla(hedef: hedef, ariza: ariza, gecikme: ilkParcaGecikmesi)
        return try await baslatmaGorevi(port: 0).value
    }

    private func gecisAyarla(hedef: URL, ariza: ArizaDeposu, gecikme: Duration) {
        kilit.lock(); _hedef = hedef; _ariza = ariza; _ilkParcaGecikmesi = gecikme; kilit.unlock()
    }

    private var gecisAyari: (hedef: URL, ariza: ArizaDeposu, gecikme: Duration)? {
        kilit.lock(); defer { kilit.unlock() }
        guard let h = _hedef, let a = _ariza else { return nil }
        return (h, a, _ilkParcaGecikmesi)
    }

    private func baslatmaGorevi(port: UInt16) -> Task<URL, Error> {
        kilit.lock(); defer { kilit.unlock() }
        if let url = _tabanURL { return Task<URL, Error> { url } }
        if let b = baslatma { return b }
        let t = Task<URL, Error> { try await self.dinle(port: port) }
        baslatma = t
        return t
    }

    private func baslatmaBitti() { kilit.lock(); baslatma = nil; kilit.unlock() }
    private func dinleyiciAyarla(_ d: NWListener?) { kilit.lock(); dinleyici = d; kilit.unlock() }
    private func tabanAyarla(_ u: URL?) { kilit.lock(); _tabanURL = u; kilit.unlock() }

    private func dinle(port: UInt16) async throws -> URL {
        defer { baslatmaBitti() }
        let parametreler = NWParameters.tcp
        parametreler.allowLocalEndpointReuse = true
        parametreler.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let d: NWListener
        do { d = try NWListener(using: parametreler) } catch { throw Hata.baslatilamadi("\(error)") }
        dinleyiciAyarla(d)
        d.newConnectionHandler = { @Sendable [weak self] baglanti in self?.kabulEt(baglanti) }
        let tek = TekSeferlik()
        return try await withCheckedThrowingContinuation { (devam: CheckedContinuation<URL, Error>) in
            d.stateUpdateHandler = { @Sendable [weak self, weak d] durum in
                switch durum {
                case .ready:
                    guard let p = d?.port?.rawValue, let url = URL(string: "http://127.0.0.1:\(p)") else {
                        if tek.al() { devam.resume(throwing: Hata.baslatilamadi("port yok")) }
                        return
                    }
                    self?.tabanAyarla(url)
                    if tek.al() { devam.resume(returning: url) }
                case .failed(let e):
                    self?.durdur()
                    if tek.al() { devam.resume(throwing: Hata.baslatilamadi("\(e)")) }
                case .cancelled:
                    if tek.al() { devam.resume(throwing: Hata.baslatilamadi("iptal")) }
                default: break
                }
            }
            d.start(queue: kuyruk)
        }
    }

    func durdur() {
        kilit.lock()
        let d = dinleyici; dinleyici = nil; _tabanURL = nil
        let b = Array(baglantilar.values); baglantilar = [:]
        let g = Array(gecisGorevleri.values); gecisGorevleri = [:]
        kilit.unlock()
        d?.cancel()
        b.forEach { $0.cancel() }
        g.forEach { $0.cancel() }
    }

    // MARK: Bağlantı

    /// Bağlantı başına biriken bayt (yalnız sunucu kuyruğunda değişir).
    nonisolated private final class Tampon: @unchecked Sendable { var veri = Data() }

    private func kabulEt(_ b: NWConnection) {
        kilit.lock(); baglantilar[ObjectIdentifier(b)] = b; kilit.unlock()
        b.stateUpdateHandler = { @Sendable [weak self, weak b] durum in
            guard let self, let b else { return }
            switch durum {
            case .failed, .cancelled:
                self.kilit.lock()
                self.baglantilar[ObjectIdentifier(b)] = nil
                let g = self.gecisGorevleri.removeValue(forKey: ObjectIdentifier(b))
                self.kilit.unlock()
                g?.cancel()   // geçiş kipi: istemci kapandı → hedefe giden akış da kesilir
            default: break
            }
        }
        b.start(queue: kuyruk)
        oku(b, Tampon())
    }

    private func oku(_ b: NWConnection, _ t: Tampon) {
        b.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { @Sendable [weak self] veri, _, bitti, hata in
            guard let self else { b.cancel(); return }
            if let veri { t.veri.append(veri) }
            if let istek = SahteHTTP.ayristir(t.veri) { self.yonlendir(istek, b); return }
            if bitti || hata != nil { b.cancel(); return }
            if t.veri.count > 32 << 20 { self.yanitla(b, durum: 413, govde: SahteSSE.hata(durum: 413)); return }
            self.oku(b, t)
        }
    }

    // MARK: Yönlendirme

    private func yonlendir(_ istek: SahteHTTP.Istek, _ b: NWConnection) {
        let govde = ((try? JSONSerialization.jsonObject(with: istek.govde)) as? [String: Any]) ?? [:]
        let model = (govde["model"] as? String) ?? ""
        let akis = (govde["stream"] as? Bool) ?? false
        let konusma = SahteKonusma.coz(govde)
        kilit.lock()
        _gunluk.append(Kayit(yol: istek.yol, model: model, metin: String(konusma.son.prefix(40))))
        if _gunluk.count > 500 { _gunluk.removeFirst(_gunluk.count - 500) }   // geçiş kipi telefonda 30 dk açık kalabilir
        kilit.unlock()
        if let g = gecisAyari { gecisYonlendir(istek, b, ayar: g); return }
        let s = simdikiSenaryo

        switch (istek.yontem, istek.yol) {
        case ("GET", "/v1/models"):
            yanitla(b, durum: 200, govde: SahteSSE.modellerJSON(s.modeller))
        case ("POST", "/v1/messages"), ("POST", "/v1/chat/completions"):
            let anthropic = istek.yol == "/v1/messages"
            let k = s.kural(sonKullaniciMetni: konusma.son, gecmis: konusma.gecmis, model: model)
            let gecikme = max(0, k.gecikmeMs ?? 0)
            if let d = k.durum, d >= 400 {
                kuyruk.asyncAfter(deadline: .now() + .milliseconds(gecikme)) { @Sendable [weak self] in
                    self?.yanitla(b, durum: d, govde: SahteSSE.hata(durum: d))
                }
                return
            }
            let metin = s.yanitMetni(k)
            let ad = model.isEmpty ? "claude-sahte" : model
            guard akis else {
                let g = anthropic ? SahteSSE.anthropicMesaj(metin: metin, model: ad) : SahteSSE.openaiMesaj(metin: metin, model: ad)
                kuyruk.asyncAfter(deadline: .now() + .milliseconds(gecikme)) { @Sendable [weak self] in self?.yanitla(b, durum: 200, govde: g) }
                return
            }
            let cerceveler: [String]
            if anthropic, let arac = k.arac, !arac.isEmpty, !konusma.aracSonucu {
                cerceveler = SahteSSE.anthropicAracCagrisi(ad: arac, girdiJSON: k.aracGirdisi ?? "{}", model: ad)
            } else {
                cerceveler = anthropic ? SahteSSE.anthropic(metin: metin, model: ad) : SahteSSE.openai(metin: metin, model: ad)
            }
            akisGonder(b, cerceveler: cerceveler, gecikmeMs: gecikme, aralikMs: max(0, k.parcaArasiMs ?? 0))
        default:
            yanitla(b, durum: 404, govde: SahteSSE.json(["error": ["type": "not_found_error", "message": "sahte sunucuda yok: \(istek.yol)"]]))
        }
    }

    // MARK: Geçiş kipi (P3.10-arıza)

    /// Hedefe iletilmeyen başlıklar (URLSession kendisi koyar ya da bağlantıya özgüdür).
    static let aktarilmayanBasliklar: Set<String> = ["host", "content-length", "connection", "accept-encoding", "transfer-encoding", "expect", "keep-alive"]

    /// OpenAI biçimli hata gövdesi (`/v1/chat/completions`, `/v1/responses`).
    static func openaiHata(durum: Int) -> String {
        SahteSSE.json(["error": ["message": "arıza modu: yapay \(durum)",
                                 "type": durum == 429 ? "rate_limit_error" : "server_error",
                                 "code": durum == 429 ? "rate_limit_exceeded" : "server_error"]])
    }

    /// Sıra önemlidir: ilk tüketilen arıza uygulanır (biri tüketilince öbürleri harcanmaz).
    static let modelArizaSirasi: [ArizaTuru] = [.modelKota429, .modelSunucu500, .akisYarida, .ilkParcaGec]

    private func gecisYonlendir(_ istek: SahteHTTP.Istek, _ b: NWConnection, ayar: (hedef: URL, ariza: ArizaDeposu, gecikme: Duration)) {
        // Yalnız model istekleri (POST) arızalanır; GET /v1/models canlılık ve model listesi için hep iletilir.
        let tur: ArizaTuru? = istek.yontem == "POST" ? Self.modelArizaSirasi.first(where: { ayar.ariza.tuket($0) }) : nil
        let openai = istek.yol.hasSuffix("/chat/completions") || istek.yol.hasSuffix("/responses")
        switch tur {
        case .modelKota429?:
            TaniGunlugu.yaz("ARIZA: model 429 (\(istek.yol))")
            yanitla(b, durum: 429, govde: openai ? Self.openaiHata(durum: 429) : SahteSSE.hata(durum: 429), ekBasliklar: "retry-after: 30\r\n")
            return
        case .modelSunucu500?:
            TaniGunlugu.yaz("ARIZA: model 500 (\(istek.yol))")
            yanitla(b, durum: 500, govde: openai ? Self.openaiHata(durum: 500) : SahteSSE.hata(durum: 500))
            return
        case .akisYarida?: TaniGunlugu.yaz("ARIZA: akış yarıda kesilecek (\(istek.yol))")
        case .ilkParcaGec?: TaniGunlugu.yaz("ARIZA: ilk parça gecikecek (\(istek.yol))")
        default: break
        }
        let kesmeOlayi: Int? = tur == .akisYarida ? 2 : nil
        let bekleme: Duration? = tur == .ilkParcaGec ? ayar.gecikme : nil
        let kimlik = ObjectIdentifier(b)
        let hedef = ayar.hedef
        let gorev = Task<Void, Never> { [weak self] in
            await self?.ilet(istek, b, hedef: hedef, kesmeOlayi: kesmeOlayi, bekleme: bekleme)
        }
        kilit.lock(); gecisGorevleri[kimlik] = gorev; kilit.unlock()
    }

    /// İsteği hedefe iletir ve yanıtı chunked olarak istemciye aktarır. Durum kodu ve Content-Type korunur.
    /// `kesmeOlayi`: bu kadar SSE olayından sonra bağlantı sonlandırıcı parça gönderilmeden kesilir (akış JSON ise ilk 64 bayttan sonra).
    private func ilet(_ istek: SahteHTTP.Istek, _ b: NWConnection, hedef: URL, kesmeOlayi: Int?, bekleme: Duration?) async {
        var baslikGitti = false
        do {
            if let bekleme { try await Task.sleep(for: bekleme) }
            let yol = String(istek.yol.drop { $0 == "/" })
            var r = URLRequest(url: yol.isEmpty ? hedef : hedef.appending(path: yol), timeoutInterval: 300)
            r.httpMethod = istek.yontem
            for (ad, deger) in istek.basliklar where !Self.aktarilmayanBasliklar.contains(ad) { r.setValue(deger, forHTTPHeaderField: ad) }
            if !istek.govde.isEmpty { r.httpBody = istek.govde }
            let oturum = URLSession(configuration: .ephemeral)
            defer { oturum.invalidateAndCancel() }
            let (baytlar, yanit) = try await oturum.bytes(for: r)
            let http = yanit as? HTTPURLResponse
            let durum = http?.statusCode ?? 502
            let icerikTuru = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"
            let akisMi = icerikTuru.lowercased().contains("event-stream")
            var ek = ""
            if let ra = http?.value(forHTTPHeaderField: "Retry-After") { ek = "retry-after: \(ra)\r\n" }
            try await gonder(b, Data(("HTTP/1.1 \(durum) \(Self.durumMetni(durum))\r\nContent-Type: \(icerikTuru)\r\n" + ek +
                                      "Cache-Control: no-cache\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n").utf8))
            baslikGitti = true
            var tampon = Data()
            var olay = 0
            var onceki: UInt8 = 0
            for try await bayt in baytlar {
                tampon.append(bayt)
                var olaySonu = false
                if bayt != 13 { olaySonu = bayt == 10 && onceki == 10; onceki = bayt }   // "\n\n" ya da "\r\n\r\n"
                if olaySonu { olay += 1 }
                let jsonKesme = kesmeOlayi != nil && !akisMi && tampon.count >= 64
                guard olaySonu || jsonKesme || tampon.count >= 16 << 10 else { continue }
                try await gonder(b, Self.parca(tampon))
                tampon.removeAll(keepingCapacity: true)
                if let k = kesmeOlayi, olay >= k || jsonKesme {
                    TaniGunlugu.yaz("ARIZA: akış \(olay) olaydan sonra kesildi")
                    b.cancel()   // sonlandırıcı "0\r\n\r\n" gönderilmez: istemci kesik akış görür
                    return
                }
            }
            if !tampon.isEmpty { try await gonder(b, Self.parca(tampon)) }
            if kesmeOlayi != nil { b.cancel(); return }   // olay sayısına ulaşmayan kısa yanıt da kesik biter
            try await gonder(b, Data("0\r\n\r\n".utf8))
            b.cancel()
        } catch {
            // İstemci kapandıysa (görev iptali) sessizce bırak; hedefe ulaşılamadıysa ve başlık gitmediyse 502 dön.
            if !baslikGitti, !Task.isCancelled, !(error is CancellationError) {
                yanitla(b, durum: 502, govde: SahteSSE.hata(durum: 502))
            } else {
                b.cancel()
            }
        }
    }

    /// NWConnection.send'in async sarmalı (tamamlayıcı ağ kuyruğundan çağrılır, @Sendable).
    private func gonder(_ b: NWConnection, _ veri: Data) async throws {
        try await withCheckedThrowingContinuation { (devam: CheckedContinuation<Void, Error>) in
            b.send(content: veri, completion: .contentProcessed { @Sendable hata in
                if let hata { devam.resume(throwing: hata) } else { devam.resume() }
            })
        }
    }

    // MARK: Yanıt yazma

    private static func durumMetni(_ d: Int) -> String {
        switch d {
        case 200: "OK"; case 400: "Bad Request"; case 401: "Unauthorized"; case 403: "Forbidden"; case 404: "Not Found"
        case 413: "Payload Too Large"; case 429: "Too Many Requests"; case 529: "Overloaded"; default: d >= 500 ? "Server Error" : "Error"
        }
    }

    /// `ekBasliklar` her biri "\r\n" ile biten ek başlık satırlarıdır (ör. "retry-after: 30\r\n").
    private func yanitla(_ b: NWConnection, durum: Int, govde: String, ekBasliklar: String = "") {
        let g = Data(govde.utf8)
        var veri = Data(("HTTP/1.1 \(durum) \(Self.durumMetni(durum))\r\nContent-Type: application/json\r\n" + ekBasliklar +
                         "Content-Length: \(g.count)\r\nConnection: close\r\n\r\n").utf8)
        veri.append(g)
        b.send(content: veri, completion: .contentProcessed { @Sendable _ in b.cancel() })
    }

    /// SSE: chunked aktarım; her çerçeve ayrı parça. Bitince bağlantı kapanır.
    private func akisGonder(_ b: NWConnection, cerceveler: [String], gecikmeMs: Int, aralikMs: Int) {
        let baslik = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".utf8)
        b.send(content: baslik, completion: .contentProcessed { @Sendable [weak self] hata in
            guard let self, hata == nil else { b.cancel(); return }
            self.kuyruk.asyncAfter(deadline: .now() + .milliseconds(gecikmeMs)) { @Sendable [weak self] in
                self?.parcaGonder(b, cerceveler, 0, aralikMs)
            }
        })
    }

    private static func parca(_ s: String) -> Data { parca(Data(s.utf8)) }

    private static func parca(_ v: Data) -> Data {
        var d = Data((String(v.count, radix: 16) + "\r\n").utf8)
        d.append(v); d.append(Data("\r\n".utf8))
        return d
    }

    private func parcaGonder(_ b: NWConnection, _ cerceveler: [String], _ i: Int, _ aralikMs: Int) {
        guard i < cerceveler.count else {
            b.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { @Sendable _ in b.cancel() })
            return
        }
        b.send(content: Self.parca(cerceveler[i]), completion: .contentProcessed { @Sendable [weak self] hata in
            guard let self, hata == nil else { b.cancel(); return }
            if aralikMs > 0 {
                self.kuyruk.asyncAfter(deadline: .now() + .milliseconds(aralikMs)) { @Sendable [weak self] in
                    self?.parcaGonder(b, cerceveler, i + 1, aralikMs)
                }
            } else {
                self.parcaGonder(b, cerceveler, i + 1, aralikMs)
            }
        })
    }
}

/// Devamın tek kez çözülmesi için kilitli bayrak.
nonisolated private final class TekSeferlik: @unchecked Sendable {
    private let kilit = NSLock()
    private var alindi = false
    func al() -> Bool { kilit.lock(); defer { kilit.unlock() }; if alindi { return false }; alindi = true; return true }
}
#endif
