import Foundation
import CryptoKit

/// Kota ve token tasarrufu ayarları (telefona özgü; Vault durumunda saklanır).
public enum HesapStratejisi: String, Codable, Sendable, CaseIterable { case sirayla, birBitir }

public struct TasarrufAyarlari: Codable, Sendable, Equatable {
    /// Aynı istek (temperature 0 ya da `x-proxy-cache: 1`) tekrar gelirse yanıt telefondan döner; upstream'e hiç gidilmez.
    public var yanitOnbellegi = true
    /// Yanıt önbelleği ömrü (saniye).
    public var onbellekSuresi = 900
    /// Anthropic isteklerine `cache_control` kesme noktaları ekler (sistem istemi, araçlar, konuşma sonu): tekrarlı uzun istemler %90'a kadar ucuzlar.
    public var otomatikPromptOnbellegi = true
    /// Günlük (yerel saat) toplam giriş+çıkış token sınırı; 0 = sınırsız. Aşılınca yeni istek 429 ile reddedilir.
    public var gunlukTokenSiniri = 0
    /// Kota başlıklarına göre doluluğu bu yüzdeyi geçen hesaplar, başka hesap varsa atlanır (0 = kapalı).
    public var kotaKorumaYuzdesi = 95
    /// Aynı anda gelen aynı istekler tek upstream çağrısını paylaşır.
    public var esZamanliTekillestirme = true
    /// Hesap seçim stratejisi: sırayla dönme ya da "birini bitir, sonra diğeri" (abonelik pencerelerinde çoğu zaman daha verimli).
    public var hesapStratejisi: HesapStratejisi? = nil
    public var strateji: HesapStratejisi { hesapStratejisi ?? .sirayla }
    /// OpenAI / Codex isteklerine kararlı `prompt_cache_key` ekler (konuşma başına); sağlayıcı reddederse alan çıkarılıp yeniden denenir.
    public var openAIOnbellekAnahtari: Bool? = nil
    public var openAIAnahtariAcik: Bool { openAIOnbellekAnahtari ?? true }
    /// Eski araç çıktılarını (son birkaç mesajdan öncekiler, çok uzunsa) kararlı biçimde kısaltır. Varsayılan KAPALI: doğruluk kaybı olabilir.
    public var aracCiktisiKirpma: Bool? = nil
    public var kirpmaAcik: Bool { aracCiktisiKirpma ?? false }

    public init() {}
}

/// Tasarruf sayaçları (yalnız bellekte; uygulama yeniden başlayınca sıfırlanır).
public struct TasarrufSayaclari: Sendable, Equatable {
    public var onbellekIsabeti = 0
    public var tekillestirilen = 0
    public var onbellegeYazilanYanit = 0
    /// Önbellekten karşılanan tahmini token (giriş+çıkış).
    public var tasarrufEdilenToken = 0
    /// Anthropic prompt önbelleğinden okunan giriş tokenları (ucuz fiyatlı).
    public var promptOnbellekOkunan = 0
    public var promptOnbellekYazilan = 0
    public var butceReddi = 0
    public var kotaAtlama = 0
    public var kirpilanAracCiktisi = 0
    public init() {}
}

/// Anthropic `cache_control` kesme noktalarını isteğe kendiliğinden ekler (saf işlev; test edilir).
public enum PromptOnbellegi {
    /// Kabaca token tahmini (Türkçe/İngilizce karışık için ~3,5 karakter/token).
    static func tahmin(_ j: JSON) -> Int {
        switch j {
        case .string(let s): return Int(Double(s.utf8.count) / 3.8)
        case .array(let a): return a.reduce(0) { $0 + tahmin($1) }
        case .object(let o): return o.reduce(0) { $0 + ($1.key == "cache_control" ? 0 : tahmin($1.value)) }
        default: return 0
        }
    }

    static func zatenVar(_ j: JSON) -> Bool {
        switch j {
        case .object(let o): return o["cache_control"] != nil || o.values.contains(where: zatenVar)
        case .array(let a): return a.contains(where: zatenVar)
        default: return false
        }
    }

    static let kesme: JSON = .object(["type": .string("ephemeral")])

    /// Son içerik bloğuna kesme noktası koyar (metin dizesi → blok dizisine çevrilir).
    static func sonBlogaKoy(_ icerik: JSON?) -> JSON? {
        switch icerik {
        case .string(let s)?:
            guard !s.isEmpty else { return nil }
            return .array([.object(["type": .string("text"), "text": .string(s), "cache_control": kesme])])
        case .array(var a)?:
            guard let i = a.lastIndex(where: { $0["type"]?.string != "thinking" && $0["type"]?.string != "redacted_thinking" }) else { return nil }
            var b = a[i]; b["cache_control"] = kesme; a[i] = b
            return .array(a)
        default: return nil
        }
    }

    /// Dönüş: değişen gövde ve eklenen kesme noktası sayısı (0 = değişmedi).
    public static func uygula(_ body: JSON, esik: Int = 1000) -> (JSON, Int) {
        guard body["messages"]?.array?.isEmpty == false, !zatenVar(body) else { return (body, 0) }
        var b = body
        var eklenen = 0
        let sistem = tahmin(b["system"] ?? .null), araclar = tahmin(b["tools"] ?? .null)
        if sistem >= esik, let yeni = sonBlogaKoy(b["system"]) { b["system"] = yeni; eklenen += 1 }
        if araclar >= esik / 2, var a = b["tools"]?.array, !a.isEmpty {
            var son = a[a.count - 1]; son["cache_control"] = kesme; a[a.count - 1] = son; b["tools"] = .array(a); eklenen += 1
        }
        // Konuşma sonu: önceki turlar sonraki istekte önbellekten okunur (kesme noktası en son mesajın son bloğunda).
        if var m = b["messages"]?.array, tahmin(.array(m)) + sistem + araclar >= esik + 500, eklenen < 4 {
            var son = m[m.count - 1]
            if let yeni = sonBlogaKoy(son["content"]) { son["content"] = yeni; m[m.count - 1] = son; b["messages"] = .array(m); eklenen += 1 }
        }
        return (eklenen > 0 ? b : body, eklenen)
    }
}

/// Yanıt önbelleği + eş zamanlı istek tekilleştirme.
public actor YanitOnbellegi {
    struct Kayit: Sendable { let durum: Int; let basliklar: [String: String]; let govde: Data; let tahminiToken: Int; let zaman: Date }
    private var kayitlar: [String: Kayit] = [:]
    private var sira: [String] = []
    private var havuzda: [String: Task<Kayit?, Never>] = [:]
    let enFazla: Int, enFazlaBayt: Int

    public init(enFazla: Int = 64, enFazlaBayt: Int = 256_000) { self.enFazla = enFazla; self.enFazlaBayt = enFazlaBayt }

    /// İstek anahtarı: yol + model + gövde (anahtar sırası sabit). Hesap/anahtar bilgisi anahtara girmez.
    public static func anahtar(path: String, body: Data) -> String {
        let govde = (try? JSON.parse(body)).flatMap { try? JSONSerialization.data(withJSONObject: $0.foundation, options: [.sortedKeys]) } ?? body
        return SHA256.hash(data: Data(path.utf8) + govde).map { String(format: "%02x", $0) }.joined()
    }

    /// Önbelleğe uygunluk: akışsız ya da akışlı fark etmez; `temperature == 0` ya da açık `x-proxy-cache: 1`; `no` ise asla.
    public static func uygun(_ body: JSON, istekBasligi: String?) -> Bool {
        if let b = istekBasligi?.lowercased() { if b == "no" || b == "0" || b == "false" { return false }; if b == "1" || b == "yes" || b == "true" { return true } }
        if let t = body["temperature"]?.double, t == 0 { return true }
        return false
    }

    func al(_ k: String, sure: TimeInterval, simdi: Date = .now) -> Kayit? {
        guard let r = kayitlar[k] else { return nil }
        if simdi.timeIntervalSince(r.zaman) > sure { kayitlar[k] = nil; sira.removeAll { $0 == k }; return nil }
        sira.removeAll { $0 == k }; sira.append(k)
        return r
    }

    func yaz(_ k: String, _ r: Kayit) {
        guard r.govde.count <= enFazlaBayt, r.durum == 200 else { return }
        kayitlar[k] = r; sira.removeAll { $0 == k }; sira.append(k)
        while sira.count > enFazla { kayitlar[sira.removeFirst()] = nil }
    }

    func havuz(_ k: String) -> Task<Kayit?, Never>? { havuzda[k] }
    func havuzaKoy(_ k: String, _ t: Task<Kayit?, Never>) { havuzda[k] = t }
    func havuzdanCikar(_ k: String) { havuzda[k] = nil }
    public func temizle() { kayitlar = [:]; sira = []; havuzda = [:] }
    public var sayi: Int { kayitlar.count }
}

extension JSON {
    /// JSONSerialization için Foundation nesnesi.
    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n.rounded() == n && abs(n) < 1e15 ? NSNumber(value: Int64(n)) : NSNumber(value: n)
        case .string(let s): return s
        case .array(let a): return a.map(\.foundation)
        case .object(let o): return o.mapValues(\.foundation)
        }
    }
}

/// Upstream yanıt başlıklarından kota doluluğu (Claude `anthropic-ratelimit-*`, Codex `x-codex-*`): hesap başına son görülen değerler.
public actor KotaDurumu {
    public struct Hesap: Sendable, Equatable {
        public var basliklar: [String: String] = [:]
        public var guncelleme = Date()
        /// 0…1 arası en yüksek doluluk; bilinmiyorsa nil.
        public var doluluk: Double?
        /// Sıfırlanma zamanı (varsa).
        public var sifirlanma: Date?
    }
    public private(set) var hesaplar: [String: Hesap] = [:]
    public init() {}

    public func isle(hesap: String, basliklar: [String: String], simdi: Date = .now) {
        let h = Self.coz(basliklar, simdi: simdi)
        guard !h.basliklar.isEmpty else { return }
        hesaplar[hesap] = h
    }

    /// Başlık adı "ratelimit"/"x-codex" içerenleri alır; "…utilization/used-percent" ya da kalan/limit oranından doluluk çıkarır.
    public static func coz(_ tum: [String: String], simdi: Date = .now) -> Hesap {
        var h = Hesap(); h.guncelleme = simdi
        let alinan = tum.filter { $0.key.lowercased().contains("ratelimit") || $0.key.lowercased().hasPrefix("x-codex") || $0.key.lowercased() == "retry-after" }
        h.basliklar = Dictionary(uniqueKeysWithValues: alinan.map { ($0.key.lowercased(), $0.value) })
        var doluluklar: [Double] = []
        for (k, v) in h.basliklar {
            guard let x = Double(v.trimmingCharacters(in: .whitespaces)) else { continue }
            if k.contains("utilization") { doluluklar.append(x > 1 ? x / 100 : x) }
            else if k.contains("used-percent") || k.contains("used_percent") { doluluklar.append(x / 100) }
            else if k.hasSuffix("-remaining"), let limit = h.basliklar[k.replacingOccurrences(of: "-remaining", with: "-limit")].flatMap(Double.init), limit > 0 {
                doluluklar.append(1 - x / limit)
            }
            if k.contains("reset"), h.sifirlanma == nil {
                if let t = ISO8601DateFormatter().date(from: v) { h.sifirlanma = t }
                else if x > 1_000_000_000 { h.sifirlanma = Date(timeIntervalSince1970: x) }
                else if x > 0, x < 100_000_000 { h.sifirlanma = simdi.addingTimeInterval(x) }
            }
        }
        h.doluluk = doluluklar.max().map { min(1, max(0, $0)) }
        return h
    }

    public func doluluk(_ hesap: String) -> Double? {
        guard let h = hesaplar[hesap] else { return nil }
        // Sıfırlanma zamanı geçtiyse bayat doluluk geçersiz.
        if let s = h.sifirlanma, s < .now { return nil }
        return h.doluluk
    }
}

/// Günlük token bütçesi (UsageLog kayıtlarından).
public enum GunlukButce {
    public static func kullanilan(_ kayitlar: [UsageRecord], simdi: Date = .now, takvim: Calendar = .current) -> Int {
        kayitlar.filter { takvim.isDate($0.date, inSameDayAs: simdi) && $0.status == 200 }.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }
}

public actor SayacDeposu {
    public private(set) var sayaclar = TasarrufSayaclari()
    public init() {}
    func degistir(_ f: (inout TasarrufSayaclari) -> Void) { f(&sayaclar) }
    public func sifirla() { sayaclar = TasarrufSayaclari() }
}

/// Aynı anda gelen aynı isteği tek upstream çağrısında birleştirir: ilk gelen "lider", diğerleri sonucu bekler.
actor Tekillestirici {
    private var bekleyenler: [String: [CheckedContinuation<YanitOnbellegi.Kayit?, Never>]] = [:]
    /// true → lider sensin (işi sen yap); false → bekle() ile sonucu al.
    func liderMi(_ k: String) -> Bool {
        if bekleyenler[k] == nil { bekleyenler[k] = []; return true }
        return false
    }
    func bekle(_ k: String) async -> YanitOnbellegi.Kayit? {
        await withCheckedContinuation { bekleyenler[k, default: []].append($0) }
    }
    func bitir(_ k: String, _ sonuc: YanitOnbellegi.Kayit?) {
        let w = bekleyenler.removeValue(forKey: k) ?? []
        for c in w { c.resume(returning: sonuc) }
    }
}

/// Eski araç sonuçlarını kararlı biçimde kısaltır (aynı mesaj her istekte aynı çıktıyı verir; önbellek öneki bozulmaz).
public enum AracCiktisiKirpici {
    public static let esik = 6000, bas = 2500, son = 1000, korunanSonMesaj = 4

    static func kirp(_ s: String) -> String {
        guard s.count > esik else { return s }
        return String(s.prefix(bas)) + "\n[… \(s.count - bas - son) karakter kırpıldı …]\n" + String(s.suffix(son))
    }

    /// Dönüş: yeni gövde ve kısaltılan blok sayısı.
    public static func uygula(_ body: JSON) -> (JSON, Int) {
        guard var m = body["messages"]?.array, m.count > korunanSonMesaj else { return (body, 0) }
        var sayi = 0
        for i in 0..<(m.count - korunanSonMesaj) {
            guard var blok = m[i]["content"]?.array else { continue }
            var degisti = false
            for j in blok.indices where blok[j]["type"]?.string == "tool_result" {
                if let s = blok[j]["content"]?.string, s.count > esik { blok[j]["content"] = .string(kirp(s)); degisti = true; sayi += 1 }
                else if var ic = blok[j]["content"]?.array {
                    var d = false
                    for k in ic.indices { if ic[k]["type"]?.string == "text", let t = ic[k]["text"]?.string, t.count > esik { ic[k]["text"] = .string(kirp(t)); d = true; sayi += 1 } }
                    if d { blok[j]["content"] = .array(ic); degisti = true }
                }
            }
            if degisti { m[i]["content"] = .array(blok) }
        }
        var b = body; if sayi > 0 { b["messages"] = .array(m) }
        return (b, sayi)
    }
}

/// OpenAI/Codex önbellek anahtarı ve 429 sınıflandırması.
public enum UpstreamYardimci {
    /// Konuşmadan kararlı `prompt_cache_key` (yoksa ekler; istemci verdiyse dokunmaz).
    public static func onbellekAnahtariEkle(_ body: JSON, anahtar: String?) -> JSON {
        guard body["prompt_cache_key"] == nil, let anahtar else { return body }
        var b = body; b["prompt_cache_key"] = .string("cp-" + anahtar.prefix(24)); return b
    }
    /// Sağlayıcı bilinmeyen alanı reddettiyse (400) alanı çıkarıp yeniden denemek güvenli mi?
    public static func alanReddi(_ status: Int, _ mesaj: String, alan: String = "prompt_cache_key") -> Bool {
        status == 400 && mesaj.lowercased().contains(alan.lowercased())
    }
    /// 429'un nedeni aylık/harcama sınırıysa yeniden denemek anlamsız: hesap uzun süre dinlendirilir.
    public static func harcamaSiniri(_ mesaj: String) -> Bool {
        let m = mesaj.lowercased()
        return m.contains("enforced_spend_limit") || m.contains("spend limit") || m.contains("monthly") && m.contains("limit") || m.contains("usage_limit_reached") || m.contains("insufficient_quota")
    }
}
