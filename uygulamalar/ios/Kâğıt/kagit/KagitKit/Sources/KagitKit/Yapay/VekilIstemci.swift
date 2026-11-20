import Foundation

/// VPS'teki Claude vekiline bağlanan istemci.
///
/// - `claude-*` modelleri: Anthropic uyumlu `POST {kok}/messages`
/// - diğerleri (gemini, gpt): OpenAI uyumlu `POST {kok}/chat/completions`
/// Yanıt akışlı istenir: Caddy 120 sn içinde yanıt başlığı bekler, akış başlığı hemen gönderir.
/// Hata, 429 ve 5xx durumunda sıradaki modele düşülür.
public struct VekilIstemci: YapayKaynak {
    public let kok: String
    let anahtar: String
    public let seciliModel: String
    let oturum: URLSession
    /// Her model denemesi için en uzun bekleme (sn).
    let zamanAsimi: TimeInterval

    public var etiket: String { "Claude (bulut)" }
    public var baglamSiniri: Int { 60_000 }

    public init(kok: String, anahtar: String, model: String = YapayModeller.varsayilan,
                oturum: URLSession = .shared, zamanAsimi: TimeInterval = 300) {
        self.kok = kok.hasSuffix("/") ? String(kok.dropLast()) : kok
        self.anahtar = anahtar
        self.seciliModel = model
        self.oturum = oturum
        self.zamanAsimi = zamanAsimi
    }

    struct HTTPHatasi: Error { let kod: Int; let govde: String }

    public func yanit(_ istek: YapayIstek, akis: YapayAkisi?) async throws -> YapayYaniti {
        var sonHata = "bilinmeyen hata"
        for model in YapayModeller.siralama(secili: seciliModel) {
            try Task.checkCancellation()
            do {
                let metin = try await tekModel(model, istek, akis: akis)
                let temiz = metin.trimmingCharacters(in: .whitespacesAndNewlines)
                if temiz.isEmpty { throw KagitHata.yapayZeka("\(model) boş yanıt döndürdü") }
                return YapayYaniti(metin: temiz, model: model, kaynakEtiketi: Self.etiketle(model))
            } catch is CancellationError {
                throw KagitHata.iptal
            } catch let h as HTTPHatasi {
                sonHata = "\(model): HTTP \(h.kod) \(h.govde.prefix(200))"
                // Anahtar geçersizse diğer modellerde de başarısız olur.
                if h.kod == 401 || h.kod == 403 {
                    throw KagitHata.yapayZeka("Vekil anahtarı kabul edilmedi (HTTP \(h.kod)). Ayarlar'dan anahtarı denetleyin.")
                }
            } catch let h as KagitHata {
                if h == .iptal { throw h }
                sonHata = "\(model): \(h.errorDescription ?? "hata")"
            } catch let u as URLError where u.code == .cancelled {
                throw KagitHata.iptal
            } catch {
                sonHata = "\(model): \(error.localizedDescription)"
            }
        }
        throw KagitHata.yapayZeka("Hiçbir model yanıt vermedi. Son hata: \(sonHata)")
    }

    public static func etiketle(_ model: String) -> String {
        if model.hasPrefix("claude") { return "Claude (bulut)" }
        if model.hasPrefix("gemini") { return "Gemini (bulut)" }
        if model.hasPrefix("gpt") { return "GPT (bulut)" }
        return "Bulut"
    }

    // MARK: Tek model

    func tekModel(_ model: String, _ istek: YapayIstek, akis: YapayAkisi?) async throws -> String {
        let anthropic = model.hasPrefix("claude")
        let url = URL(string: "\(kok)/\(anthropic ? "messages" : "chat/completions")")!
        var r = URLRequest(url: url, timeoutInterval: zamanAsimi)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(anahtar, forHTTPHeaderField: "X-Personal-Token")
        if anthropic { r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        r.httpBody = try JSONSerialization.data(withJSONObject: govde(model, istek, anthropic: anthropic))

        let (bayt, yanit) = try await oturum.bytes(for: r)
        guard let http = yanit as? HTTPURLResponse else { throw KagitHata.yapayZeka("Geçersiz sunucu yanıtı") }
        guard (200..<300).contains(http.statusCode) else {
            var ham = Data()
            for try await b in bayt { ham.append(b); if ham.count > 2000 { break } }
            throw HTTPHatasi(kod: http.statusCode, govde: String(decoding: ham, as: UTF8.self))
        }
        let tur = (http.value(forHTTPHeaderField: "content-type") ?? "").lowercased()
        if tur.contains("event-stream") {
            return try await akisOku(bayt, anthropic: anthropic, akis: akis)
        }
        var ham = Data()
        for try await b in bayt { ham.append(b) }
        let metin = try Self.tamYanit(ham)
        akis?(metin)
        return metin
    }

    func govde(_ model: String, _ istek: YapayIstek, anthropic: Bool) -> [String: Any] {
        var mesajlar: [[String: String]] = istek.mesajlar.map { ["role": $0.rol.rawValue, "content": $0.icerik] }
        var g: [String: Any] = ["model": model, "max_tokens": max(istek.azamiToken, 512), "stream": true]
        if let s = istek.sicaklik { g["temperature"] = s }
        if anthropic {
            if !istek.sistem.isEmpty { g["system"] = istek.sistem }
        } else if !istek.sistem.isEmpty {
            mesajlar.insert(["role": "system", "content": istek.sistem], at: 0)
        }
        g["messages"] = mesajlar
        return g
    }

    private func akisOku(_ bayt: URLSession.AsyncBytes, anthropic: Bool, akis: YapayAkisi?) async throws -> String {
        var toplam = ""
        for try await satir in bayt.lines {
            guard satir.hasPrefix("data:") else { continue }
            let yuk = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if yuk == "[DONE]" { break }
            guard let veri = yuk.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] else { continue }
            if let h = j["error"] as? [String: Any] {
                throw KagitHata.yapayZeka((h["message"] as? String) ?? "akış hatası")
            }
            var parca: String?
            if anthropic {
                if j["type"] as? String == "content_block_delta", let d = j["delta"] as? [String: Any] {
                    parca = d["text"] as? String
                }
            } else if let ch = (j["choices"] as? [[String: Any]])?.first,
                      let d = ch["delta"] as? [String: Any] {
                parca = d["content"] as? String
            }
            if let parca, !parca.isEmpty {
                toplam += parca
                akis?(parca)
            }
        }
        return toplam
    }

    /// Akışsız (tek parça JSON) yanıtı çözer.
    static func tamYanit(_ veri: Data) throws -> String {
        guard let j = try JSONSerialization.jsonObject(with: veri) as? [String: Any] else {
            throw KagitHata.yapayZeka("Yanıt çözümlenemedi")
        }
        if let h = j["error"] as? [String: Any] {
            throw KagitHata.yapayZeka((h["message"] as? String) ?? "sunucu hatası")
        }
        if let blok = j["content"] as? [[String: Any]] {
            return blok.compactMap { $0["text"] as? String }.joined()
        }
        if let ch = (j["choices"] as? [[String: Any]])?.first,
           let m = ch["message"] as? [String: Any], let c = m["content"] as? String {
            return c
        }
        throw KagitHata.yapayZeka("Yanıtta metin yok")
    }
}
