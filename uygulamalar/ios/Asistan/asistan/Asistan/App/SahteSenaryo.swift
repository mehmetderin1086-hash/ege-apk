#if DEBUG
import Foundation

/// P3.10 hermetik test: `--sahte-model` kipinde yerel sahte model sunucusunun (SahteModelSunucusu) yanıt kuralları.
/// Saf mantık; ağ kodu içermez. Senaryo `ASISTAN_SAHTE_SENARYO` ortam değişkeninden JSON olarak gelir,
/// yoksa ya da bozuksa yerleşik senaryo kullanılır. Yalnız DEBUG derlemede vardır.
nonisolated struct SahteSenaryo: Codable, Sendable, Equatable {
    nonisolated struct Kural: Codable, Sendable, Equatable {
        /// Son kullanıcı metninde aranır (büyük/küçük harf ve Türkçe karakter katlanır). Boş dizgi her isteğe uyar.
        var icerir: String
        /// Yanıt metni; nil ise senaryonun varsayılanı.
        var metin: String?
        /// Doluysa (ve son mesaj henüz bir araç sonucu değilse) Anthropic yolunda bu adla araç çağrısı döner.
        var arac: String?
        /// Araç çağrısının girdisi (JSON nesne metni); nil ise "{}".
        var aracGirdisi: String?
        /// 400 ve üstüyse bu HTTP kodu hata gövdesiyle döner.
        var durum: Int?
        /// İlk parçadan önce bekleme (ms).
        var gecikmeMs: Int?
        /// Parçalar arası bekleme (ms).
        var parcaArasiMs: Int?
        /// Doluysa kural yalnız model kimliği bunu içeren isteklere uyar (ör. yarışta tek modeli 429'a düşürmek).
        var model: String?
        /// Doluysa kural yalnız önceki mesajlarda (son kullanıcı mesajı hariç) bu metin geçiyorsa uyar: bağlam sınaması.
        var gecmisteIcerir: String?

        init(icerir: String, metin: String? = nil, arac: String? = nil, aracGirdisi: String? = nil, durum: Int? = nil,
             gecikmeMs: Int? = nil, parcaArasiMs: Int? = nil, model: String? = nil, gecmisteIcerir: String? = nil) {
            self.icerir = icerir; self.metin = metin; self.arac = arac; self.aracGirdisi = aracGirdisi; self.durum = durum
            self.gecikmeMs = gecikmeMs; self.parcaArasiMs = parcaArasiMs; self.model = model; self.gecmisteIcerir = gecmisteIcerir
        }
    }

    var kurallar: [Kural]
    var varsayilan: String
    var modeller: [String]

    init(kurallar: [Kural], varsayilan: String, modeller: [String]) {
        self.kurallar = kurallar; self.varsayilan = varsayilan; self.modeller = modeller
    }

    static let ortamAnahtari = "ASISTAN_SAHTE_SENARYO"

    static let yerlesikModeller: [String] = {
        var l: [String] = []
        for m in ParalelYaris.varsayilanModeller + ParalelYaris.antigravityModeller + ["claude-opus-5-5", "claude-sonnet-5-5"] where !l.contains(m) { l.append(m) }
        return l
    }()

    /// Bağlam kuralları önce gelir: sonraki sorular "pamuk" geçmeden de önceki mesajı bilmeli.
    static let yerlesikKurallar: [Kural] = [
        Kural(icerir: "kaç yaşında", metin: "Bağlamdan: Pamuk 3 yaşında.", gecmisteIcerir: "pamuk"),
        Kural(icerir: "kedimin adı neydi", metin: "Bağlamdan: kedinin adı Pamuk.", gecmisteIcerir: "pamuk"),
        Kural(icerir: "pamuk", metin: "Ne güzel, kedin 3 yaşındaymış."),
        Kural(icerir: "yedi artı beş", metin: "12"),
        Kural(icerir: "fotosentez", metin: "Fotosentez, bitkilerin ışık enerjisiyle karbondioksit ve sudan glikoz ve oksijen üretmesidir."),
        Kural(icerir: "galatasaray", metin: "Galatasaray'ın bir sonraki maçı için sahte yanıt.", gecikmeMs: 3000),
        Kural(icerir: "hikaye",
              metin: Array(repeating: "Bir varmış bir yokmuş, uzak bir köyde meraklı bir kedi yaşarmış.", count: 30).joined(separator: " "),
              parcaArasiMs: 200),
    ]

    static let yerlesik = SahteSenaryo(kurallar: yerlesikKurallar, varsayilan: "Sahte yanıt.", modeller: yerlesikModeller)

    /// `ASISTAN_SAHTE_SENARYO` JSON'u; yoksa ya da bozuksa yerleşik senaryo.
    static func ortamdan(_ env: [String: String]) -> SahteSenaryo {
        guard let ham = env[ortamAnahtari], !ham.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let s = try? JSONDecoder().decode(SahteSenaryo.self, from: Data(ham.utf8)) else { return .yerlesik }
        return s
    }

    private enum CodingKeys: String, CodingKey { case kurallar, varsayilan, modeller, yerlesikKurallar }

    /// Kısmi JSON kabul edilir: eksik alanlar yerleşikten gelir; `yerlesikKurallar` (varsayılan true) yerleşik kuralları
    /// senaryonun kurallarının ARKASINA ekler, böylece test yalnız değiştirmek istediği kuralı yazar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ozel = try c.decodeIfPresent([Kural].self, forKey: .kurallar) ?? []
        let ekle = try c.decodeIfPresent(Bool.self, forKey: .yerlesikKurallar) ?? true
        kurallar = ozel + (ekle ? Self.yerlesikKurallar : [])
        varsayilan = try c.decodeIfPresent(String.self, forKey: .varsayilan) ?? Self.yerlesik.varsayilan
        modeller = try c.decodeIfPresent([String].self, forKey: .modeller) ?? Self.yerlesikModeller
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kurallar, forKey: .kurallar)
        try c.encode(varsayilan, forKey: .varsayilan)
        try c.encode(modeller, forKey: .modeller)
        try c.encode(false, forKey: .yerlesikKurallar)   // kurallar zaten birleşik; yeniden çözülünce ikilenmesin
    }

    /// Türkçe katlama: "YEDİ ARTI BEŞ" ve "yedi arti bes" aynı anahtara iner.
    static func katla(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "tr_TR"))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// İlk uyan kural; hiçbiri uymazsa varsayılan metinli kural.
    func kural(sonKullaniciMetni: String, gecmis: String = "", model: String = "") -> Kural {
        let son = Self.katla(sonKullaniciMetni), once = Self.katla(gecmis), m = model.lowercased()
        for k in kurallar {
            if !k.icerir.isEmpty, !son.contains(Self.katla(k.icerir)) { continue }
            if let km = k.model, !km.isEmpty, !m.contains(km.lowercased()) { continue }
            if let g = k.gecmisteIcerir, !g.isEmpty, !once.contains(Self.katla(g)) { continue }
            return k
        }
        return Kural(icerir: "", metin: varsayilan)
    }

    func yanitMetni(_ k: Kural) -> String { k.metin ?? varsayilan }
}

/// İstek gövdesinden konuşma: son kullanıcı metni, önceki mesajlar ve son mesajın araç sonucu olup olmadığı.
/// Anthropic `messages[].content` (dizgi ya da blok dizisi) ve OpenAI `messages[]` (sistem satırı atlanır) aynı biçimde okunur.
nonisolated enum SahteKonusma {
    nonisolated struct Ozet: Sendable, Equatable { var son: String; var gecmis: String; var aracSonucu: Bool }

    static func coz(_ govde: [String: Any]) -> Ozet {
        let mesajlar = (govde["messages"] as? [[String: Any]]) ?? []
        var metinler: [(rol: String, metin: String, arac: Bool)] = []
        for m in mesajlar {
            let rol = (m["role"] as? String) ?? ""
            if rol == "system" || rol == "developer" { continue }
            var metin = "", arac = false
            if let s = m["content"] as? String { metin = s }
            else if let bloklar = m["content"] as? [[String: Any]] {
                for b in bloklar {
                    let tur = (b["type"] as? String) ?? ""
                    if tur == "tool_result" { arac = true }
                    if let t = b["text"] as? String { metin += (metin.isEmpty ? "" : "\n") + t }
                }
            }
            metinler.append((rol, metin, arac))
        }
        guard let sonIndeks = metinler.lastIndex(where: { $0.rol == "user" }) else {
            return Ozet(son: "", gecmis: metinler.map(\.metin).joined(separator: "\n"), aracSonucu: false)
        }
        let son = metinler[sonIndeks]
        let gecmis = metinler[..<sonIndeks].map { kullaniciBolumu($0.metin) }.joined(separator: "\n")
        return Ozet(son: kullaniciBolumu(son.metin), gecmis: gecmis, aracSonucu: son.arac)
    }

    /// Beyin isteğin arkasına "\n[Hafıza notu …]", "\n[Bu istek için … kip …]" gibi bağlam blokları ekler; kurallar
    /// yalnız kullanıcının yazdığı kısma baksın (kip talimatındaki bir sözcük yanlış kurala uymasın).
    static func kullaniciBolumu(_ metin: String) -> String {
        guard let r = metin.range(of: "\n[") else { return metin }
        let bas = metin[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return bas.isEmpty ? metin : bas
    }
}

/// Sahte akış çerçeveleri. Her öğe tam bir SSE çerçevesidir ("…\n\n" ile biter).
nonisolated enum SahteSSE {
    /// Metni birkaç kelimelik parçalara böler (boşluklar korunur; birleşince özgün metin çıkar).
    static func parcala(_ metin: String, kelime: Int = 3) -> [String] {
        var parcalar: [String] = [], simdiki = "", sayac = 0
        for ch in metin {
            simdiki.append(ch)
            if ch == " " { sayac += 1; if sayac % kelime == 0 { parcalar.append(simdiki); simdiki = "" } }
        }
        if !simdiki.isEmpty { parcalar.append(simdiki) }
        return parcalar
    }

    static func json(_ nesne: Any) -> String {
        guard let v = try? JSONSerialization.data(withJSONObject: nesne, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: v, as: UTF8.self)
    }

    private static func olay(_ ad: String, _ nesne: [String: Any]) -> String { "event: \(ad)\ndata: \(json(nesne))\n\n" }

    private static func baslangic(model: String) -> String {
        olay("message_start", ["type": "message_start",
                               "message": ["id": "msg_sahte_\(UUID().uuidString.prefix(8))", "type": "message", "role": "assistant",
                                           "model": model, "content": [] as [Any], "stop_reason": NSNull(),
                                           "usage": ["input_tokens": 1, "output_tokens": 0]] as [String: Any]])
    }

    private static func bitis(neden: String, cikti: Int) -> [String] {
        [olay("message_delta", ["type": "message_delta", "delta": ["stop_reason": neden, "stop_sequence": NSNull()] as [String: Any],
                                "usage": ["output_tokens": cikti]]),
         olay("message_stop", ["type": "message_stop"])]
    }

    /// Anthropic `/v1/messages` akışı: message_start → content_block_start → text_delta'lar → content_block_stop → message_delta → message_stop.
    static func anthropic(metin: String, model: String) -> [String] {
        let parcalar = parcala(metin)
        var l = [baslangic(model: model),
                 olay("content_block_start", ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]])]
        for p in parcalar {
            l.append(olay("content_block_delta", ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": p]]))
        }
        l.append(olay("content_block_stop", ["type": "content_block_stop", "index": 0]))
        return l + bitis(neden: "end_turn", cikti: max(1, parcalar.count))
    }

    /// Anthropic araç çağrısı akışı: tool_use bloğu, girdi input_json_delta parçalarıyla, stop_reason tool_use.
    static func anthropicAracCagrisi(ad: String, girdiJSON: String, model: String = "claude-sahte") -> [String] {
        let girdi = girdiJSON.isEmpty ? "{}" : girdiJSON
        var l = [baslangic(model: model),
                 olay("content_block_start", ["type": "content_block_start", "index": 0,
                                              "content_block": ["type": "tool_use", "id": "toolu_sahte_\(UUID().uuidString.prefix(8))",
                                                                "name": ad, "input": [String: Any]()] as [String: Any]])]
        // JSON'u ortadan ikiye böl: istemcinin parçaları birleştirdiği sınansın.
        let orta = girdi.index(girdi.startIndex, offsetBy: girdi.count / 2)
        for p in [String(girdi[..<orta]), String(girdi[orta...])] where !p.isEmpty {
            l.append(olay("content_block_delta", ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": p]]))
        }
        l.append(olay("content_block_stop", ["type": "content_block_stop", "index": 0]))
        return l + bitis(neden: "tool_use", cikti: 1)
    }

    /// Anthropic akışsız yanıt gövdesi.
    static func anthropicMesaj(metin: String, model: String) -> String {
        json(["id": "msg_sahte", "type": "message", "role": "assistant", "model": model,
              "content": [["type": "text", "text": metin]], "stop_reason": "end_turn",
              "usage": ["input_tokens": 1, "output_tokens": max(1, parcala(metin).count)]] as [String: Any])
    }

    /// OpenAI `/v1/chat/completions` akışı: delta.content parçaları, finish_reason "stop", `data: [DONE]`.
    static func openai(metin: String, model: String) -> [String] {
        var l: [String] = []
        for p in parcala(metin) {
            l.append("data: \(json(["id": "chatcmpl-sahte", "object": "chat.completion.chunk", "model": model, "choices": [["index": 0, "delta": ["content": p], "finish_reason": NSNull()] as [String: Any]]] as [String: Any]))\n\n")
        }
        l.append("data: \(json(["id": "chatcmpl-sahte", "object": "chat.completion.chunk", "model": model, "choices": [["index": 0, "delta": [String: Any](), "finish_reason": "stop"] as [String: Any]]] as [String: Any]))\n\n")
        l.append("data: [DONE]\n\n")
        return l
    }

    /// OpenAI akışsız yanıt gövdesi.
    static func openaiMesaj(metin: String, model: String) -> String {
        json(["id": "chatcmpl-sahte", "object": "chat.completion", "model": model,
              "choices": [["index": 0, "message": ["role": "assistant", "content": metin], "finish_reason": "stop"] as [String: Any]]] as [String: Any])
    }

    /// Hata gövdesi: Anthropic zarfı (`type: error`) ve OpenAI'nin okuduğu `error.message` birlikte.
    static func hata(durum: Int) -> String {
        let tur: String = switch durum {
        case 401: "authentication_error"
        case 403: "permission_error"
        case 404: "not_found_error"
        case 429: "rate_limit_error"
        case 529: "overloaded_error"
        default: "api_error"
        }
        return json(["type": "error", "error": ["type": tur, "message": "sahte hata \(durum)"]])
    }

    static func modellerJSON(_ modeller: [String]) -> String {
        json(["object": "list", "data": modeller.map { ["id": $0, "object": "model", "owned_by": "sahte"] }])
    }
}

/// En küçük HTTP/1.1 istek ayrıştırıcısı (yalnız sahte sunucu için). Gövde Content-Length kadar gelmeden nil döner.
nonisolated enum SahteHTTP {
    nonisolated struct Istek: Sendable, Equatable {
        var yontem: String
        var yol: String
        /// Başlık adları küçük harfle.
        var basliklar: [String: String]
        var govde: Data
    }

    static func ayristir(_ veri: Data) -> Istek? {
        let ayirac = Data("\r\n\r\n".utf8)
        guard let bas = veri.range(of: ayirac) else { return nil }
        let baslikMetni = String(decoding: veri[veri.startIndex..<bas.lowerBound], as: UTF8.self)
        var satirlar = baslikMetni.components(separatedBy: "\r\n")
        guard !satirlar.isEmpty else { return nil }
        let ilk = satirlar.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard ilk.count >= 2 else { return nil }
        var basliklar: [String: String] = [:]
        for s in satirlar {
            guard let iki = s.firstIndex(of: ":") else { continue }
            basliklar[s[..<iki].trimmingCharacters(in: .whitespaces).lowercased()] = s[s.index(after: iki)...].trimmingCharacters(in: .whitespaces)
        }
        let uzunluk = Int(basliklar["content-length"] ?? "0") ?? 0
        let govdeBasi = bas.upperBound
        guard veri.endIndex - govdeBasi >= uzunluk else { return nil }
        let govde = Data(veri[govdeBasi..<(govdeBasi + uzunluk)])
        var yol = String(ilk[1])
        if let soru = yol.firstIndex(of: "?") { yol = String(yol[..<soru]) }
        return Istek(yontem: String(ilk[0]).uppercased(), yol: yol, basliklar: basliklar, govde: govde)
    }
}
#endif
