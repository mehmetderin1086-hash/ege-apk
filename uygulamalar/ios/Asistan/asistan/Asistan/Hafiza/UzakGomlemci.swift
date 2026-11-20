import Foundation

/// Vekildeki bge-m3 gömme ucu (`v1/kaynak/embed`, X-Personal-Token; kaynak-ai arkasındaki bge-embed). 1024 boyut, birim vektör.
/// Cihaz içi NL gömmesi ayırt edici olmadığı için (19 Eki 2026 ölçümü) anlamsal hafıza yalnız bunu kullanır.
/// Ayar `ayar.anlamsalHafiza` varsayılan KAPALI: sunucu ucu açılana ve kişisel olgu metinlerinin vekile gitmesi kabul edilene
/// kadar hiçbir metin gönderilmez. Hata metni ya da gövde tanı günlüğüne yazılmaz.
nonisolated enum UzakGomlemci {
    static let boyut = 1024
    /// Tek istekte en çok metin sayısı ve metin başına karakter (bge-m3 bağlamı, istek boyu).
    static let enFazlaMetin = 32
    static let enFazlaKarakter = 512
    static let zamanAsimi: TimeInterval = 8
    /// Ayar anahtarı (Ayarlar.anlamsalHafiza aynı anahtara yazar; burası aktör dışından doğrudan okur).
    static let ayarAnahtari = "ayar.anlamsalHafiza"

    nonisolated enum Hata: Error, Equatable {
        case bicim
        case boyut(Int)
        case sayi(beklenen: Int, gelen: Int)
        case http(Int)
    }

    /// Anlamsal hafıza açık ve vekil kimliği var mı. Ayar kapalıyken Keychain'e hiç bakılmaz.
    static var etkin: Bool {
        guard UserDefaults.standard.bool(forKey: ayarAnahtari) else { return false }
        return Gizli.vekilTaban != nil && Gizli.vekilToken != nil
    }

    /// Metinlerin gömmeleri (sıra korunur). En çok `enFazlaMetin` metin, her biri `enFazlaKarakter`'e kırpılır.
    @concurrent static func vektorler(_ metinler: [String]) async throws -> [[Float]] {
        guard !metinler.isEmpty else { return [] }
        guard let taban = Gizli.vekilTaban, let token = Gizli.vekilToken else { throw URLError(.userAuthenticationRequired) }
        let parca = metinler.prefix(enFazlaMetin).map { String($0.prefix(enFazlaKarakter)) }
        var istek = URLRequest(url: taban.appending(path: "v1/kaynak/embed"))
        istek.httpMethod = "POST"
        istek.timeoutInterval = zamanAsimi
        istek.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try JSONSerialization.data(withJSONObject: ["texts": parca])
        let (veri, yanit) = try await URLSession.shared.data(for: istek)
        guard let http = yanit as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw Hata.http(http.statusCode) }
        let v = try coz(veri)
        guard v.count == parca.count else { throw Hata.sayi(beklenen: parca.count, gelen: v.count) }
        return v
    }

    /// Tek sorgu vektörü; `ms` içinde gelmezse ya da hata olursa nil (çağıran yalnız BM25 ile sürer).
    static func sinirliVektor(_ metin: String, ms: Int = 1200) async -> [Float]? {
        await withTaskGroup(of: [Float]?.self) { g in
            g.addTask { try? await vektorler([metin]).first }
            g.addTask { try? await Task.sleep(for: .milliseconds(ms)); return nil }
            let ilk = await g.next() ?? nil
            g.cancelAll()
            return ilk
        }
    }

    /// Saf yanıt çözücü: `{"embeddings": [[..]]}` ya da OpenAI biçimi `{"data": [{"embedding": [..], "index": n}]}`.
    /// Her vektör 1024 boyutlu olmalı; birim uzunluğa getirilir.
    static func coz(_ veri: Data) throws -> [[Float]] {
        guard let kok = try JSONSerialization.jsonObject(with: veri) as? [String: Any] else { throw Hata.bicim }
        var hamlar: [[Any]] = []
        if let e = kok["embeddings"] as? [[Any]] {
            hamlar = e
        } else if let d = kok["data"] as? [[String: Any]] {
            let sirali = d.enumerated().sorted { ($0.element["index"] as? Int ?? $0.offset) < ($1.element["index"] as? Int ?? $1.offset) }
            hamlar = try sirali.map { guard let e = $0.element["embedding"] as? [Any] else { throw Hata.bicim }; return e }
        } else { throw Hata.bicim }
        return try hamlar.map { ham in
            let v = ham.compactMap { ($0 as? NSNumber)?.floatValue }
            guard v.count == ham.count else { throw Hata.bicim }
            guard v.count == boyut else { throw Hata.boyut(v.count) }
            return Gomlemci.birim(v)
        }
    }

    /// Saklanan gömme bge-m3 boyutunda mı: eski 512 boyutlu NL gömmesi ya da bozuk veri nil sayılır (yeniden doldurulur).
    static func gecerli(_ d: Data?) -> [Float]? {
        guard let d, d.count == boyut * MemoryLayout<Float>.size else { return nil }
        return Gomlemci.vektor(d)
    }
    static func gecerliDizi(_ v: [Float]?) -> [Float]? {
        guard let v, v.count == boyut else { return nil }
        return v
    }
}
