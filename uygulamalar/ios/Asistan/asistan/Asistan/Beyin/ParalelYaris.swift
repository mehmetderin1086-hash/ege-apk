import Foundation

/// Araçsız sohbet istekleri için paralel model yarışı. Aynı istek birkaç modele aynı anda akışlı gider;
/// ilk (boşluk olmayan) metin parçasını üreten kazanır, kaybedenler hemen iptal edilir. Araç/yan etki
/// gerektiren istekler buraya girmez (aynı işlem iki kez çalışabilir).
nonisolated enum ParalelYaris {
    struct Mesaj: Sendable, Equatable { let rol: String; let metin: String }
    struct Sonuc: Sendable { let model: String; let metin: String; let ilkSn: TimeInterval }
    enum Hata: LocalizedError {
        case hicbiriYanitlamadi([String])
        var errorDescription: String? {
            switch self { case .hicbiriYanitlamadi(let d): "Hiçbir model yanıt vermedi: \(d.isEmpty ? "ayrıntı yok" : d.joined(separator: "; "))" }
        }
    }
    enum AkisHatasi: LocalizedError {
        case kesildi, sunucu(String)
        var errorDescription: String? {
            switch self { case .kesildi: "akış tamamlanmadan koptu"; case .sunucu(let s): "sunucu hatası: \(s)" }
        }
    }

    /// 18 Eki 2026 telefonda ölçüldü (düz sohbet, ilk metin): haiku-4-5 0,65-1,3 sn, gpt-6.1-sol 1,0-2,2 sn,
    /// antigravity-gemini-3.8-flash-tiered 2,5-4,7 sn. Üç ayrı sağlayıcı: biri takılırsa diğeri kazanır.
    static let varsayilanModeller = ["claude-haiku-4-5", "gpt-6.1-sol", "antigravity-gemini-3.8-flash-tiered"]

    /// Antigravity hesabı önceliğinde yarışan modeller (telefonda ölçüldü: ilk metin gemini-3-flash 0,8-1,4 sn, claude-sonnet-5-5-low 1,1-1,2 sn).
    static let antigravityModeller = ["antigravity-gemini-3-flash", "antigravity-claude-sonnet-5-5-low"]

    /// Yarışacak modeller: Antigravity önceliği açıksa ve hesapta varsa onlar, yoksa doğrudan hesaplardaki varsayılanlar.
    /// `mevcut` boşsa (liste henüz bilinmiyor) Antigravity tahmin edilmez.
    static func yarisModelleri(antigravity: Bool, mevcut: [String]) -> [String] {
        guard antigravity, !mevcut.isEmpty else { return varsayilanModeller }
        let ag = antigravityModeller.filter(mevcut.contains)
        return ag.isEmpty ? varsayilanModeller : ag
    }

    /// Live yarışı yalnız Claude ile: doğrudan Haiku (0,65-1,3 sn) + Sonnet (Antigravity hesabı önceliğinde `-low`, yoksa doğrudan).
    static func canliClaudeYarisi(antigravity: Bool, mevcut: [String]) -> [String] {
        let ikinci = antigravity && mevcut.contains("antigravity-claude-sonnet-5-5-low") ? "antigravity-claude-sonnet-5-5-low" : "claude-sonnet-5-5"
        return ["claude-haiku-4-5", ikinci]
    }

    /// P3.7: yarışan sağlayıcı sayısı. Düşük Veri kipinde (ya da ağır termal durumda) aynı istek üç kez gitmesin: tek model.
    /// Düşük güç kipinde en çok iki. P3.9 termal/düşük güç girdilerini bağlar.
    static func genislik(ayar: Int, dusukVeri: Bool, termalAgir: Bool = false, dusukGuc: Bool = false) -> Int {
        let olagan = max(1, min(3, ayar))
        if dusukVeri || termalAgir { return 1 }
        if dusukGuc { return min(2, olagan) }
        return olagan
    }

    /// İlk parçayı alan model kazanır; kalanlar kaybeder.
    actor Kapi {
        private(set) var kazanan: String?
        func al(_ model: String) -> Bool {
            if kazanan == nil { kazanan = model }
            return kazanan == model
        }
    }

    static func govde(model: String, sistem: String, mesajlar: [Mesaj]) throws -> Data {
        var liste: [[String: String]] = [["role": "system", "content": sistem]]
        liste += mesajlar.map { ["role": $0.rol, "content": String($0.metin.prefix(6000))] }
        return try JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": liste] as [String: Any])
    }

    /// `data: {...}` satırından metin parçası; bitiş işareti ya da ilgisiz satır için nil.
    static func parcaCoz(_ satir: String) -> String? {
        guard let n = nesne(satir), let secenek = (n["choices"] as? [[String: Any]])?.first,
              let delta = secenek["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }

    private static func nesne(_ satir: String) -> [String: Any]? {
        guard satir.hasPrefix("data:") else { return nil }
        let yuk = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard yuk != "[DONE]", let veri = yuk.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: veri)) as? [String: Any]
    }

    /// Akışın temiz bittiğini gösteren satır: `[DONE]` ya da boş olmayan `finish_reason`.
    static func bitisMi(_ satir: String) -> Bool {
        if satir.hasPrefix("data:"), satir.dropFirst(5).trimmingCharacters(in: .whitespaces) == "[DONE]" { return true }
        guard let n = nesne(satir), let s = (n["choices"] as? [[String: Any]])?.first else { return false }
        return (s["finish_reason"] as? String).map { !$0.isEmpty } ?? false
    }

    /// Sunucunun akış içinde gönderdiği hata nesnesi (`data: {"error":{...}}`).
    static func hataMetni(_ satir: String) -> String? {
        guard let e = nesne(satir)?["error"] else { return nil }
        if let d = e as? [String: Any] { return (d["message"] as? String) ?? "bilinmeyen" }
        return "\(e)"
    }

    /// Kazanan bitince hemen döner ve kalan istekleri iptal eder; hepsi başarısızsa hata verir.
    final class Sonlandirici: @unchecked Sendable {
        private let kilit = NSLock()
        private var devam: CheckedContinuation<Sonuc, Error>?
        private var gorevler: [String: Task<Void, Never>] = [:]
        private var kalan: Int
        private var hatalar: [String] = []
        private var bitti = false
        /// Kapıyı alan model; belli olduktan sonra kaybedenlerin sonucu sayılmaz, kazananın kopması yarışı bitirir.
        private var kazanan: String?
        init(adet: Int) { kalan = adet }

        /// Yarış daha önce bittiyse (ör. başlamadan iptal) devam hemen iptal hatasıyla çözülür.
        func baslat(_ d: CheckedContinuation<Sonuc, Error>) {
            kilit.lock()
            if bitti { kilit.unlock(); d.resume(throwing: CancellationError()); return }
            devam = d
            kilit.unlock()
        }
        func ekle(_ model: String, _ gorev: Task<Void, Never>) {
            kilit.lock(); defer { kilit.unlock() }
            if bitti { gorev.cancel() } else { gorevler[model] = gorev }
        }
        var devamEdiyor: Bool { kilit.lock(); defer { kilit.unlock() }; return !bitti }
        /// Kapıyı alan model dışındakileri hemen kapat.
        func kazandi(_ model: String) {
            kilit.lock()
            if kazanan == nil { kazanan = model }
            let digerleri = gorevler.filter { $0.key != model }.map(\.value)
            kilit.unlock()
            digerleri.forEach { $0.cancel() }
        }
        /// İptal edilen kaybedenler sayaca dokunmadan çıkar; bu yüzden kazanan koparsa sayacı beklemeden hemen
        /// hatayla bitir (yoksa devam hiç çözülmez ve ekran 'yazıyor'da asılı kalır).
        func sonuc(_ model: String, _ r: Sonuc?, hata: String?) {
            kilit.lock()
            if bitti { kilit.unlock(); return }
            if let r {
                bitti = true
                let d = devam; devam = nil; let g = Array(gorevler.values)
                kilit.unlock()
                g.forEach { $0.cancel() }
                d?.resume(returning: r)
                return
            }
            if let hata { hatalar.append(hata) }
            if let k = kazanan, k != model { kilit.unlock(); return }   // kazanan belliyken kaybedenin sonucu sayılmaz
            kalan -= 1
            if kalan <= 0 || kazanan == model {
                bitti = true
                let d = devam; devam = nil; let h = hatalar; let g = Array(gorevler.values)
                kilit.unlock()
                g.forEach { $0.cancel() }
                d?.resume(throwing: Hata.hicbiriYanitlamadi(h))
                return
            }
            kilit.unlock()
        }
        /// Zaman aşımı ya da iptal: kalan her şeyi kapat ve verilen hatayla bitir.
        func bitir(hata: Error) {
            kilit.lock()
            if bitti { kilit.unlock(); return }
            bitti = true
            let d = devam; devam = nil; let g = Array(gorevler.values)
            kilit.unlock()
            g.forEach { $0.cancel() }
            d?.resume(throwing: hata)
        }
    }

    /// `akis(model, birikenMetin)` yalnız kazanan için çağrılır. Kazanan akış temiz bitmeden koparsa hata fırlatır
    /// (yarım yanıt tam sayılmaz); çağıran bu durumda başka bir yola düşer.
    static func yaris(taban: URL, anahtar: String, modeller: [String], sistem: String, mesajlar: [Mesaj],
                      ilkMetinSiniri: TimeInterval = 8, toplamSiniri: TimeInterval = 120,
                      akis: @escaping @Sendable (String, String) async -> Void) async throws -> Sonuc {
        guard !modeller.isEmpty else { throw Hata.hicbiriYanitlamadi(["model yok"]) }
        let kapi = Kapi()
        let baslangic = Date()
        let son = Sonlandirici(adet: modeller.count)
        KullanimDefteri.ortak.yarisSohbeti(saglayiciSayisi: modeller.count)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (devam: CheckedContinuation<Sonuc, Error>) in
                son.baslat(devam)
                for model in modeller where son.devamEdiyor {
                    KullanimDefteri.ortak.say(model, .istek)
                    son.ekle(model, Task {
                        do {
                            let r = try await oku(model: model, taban: taban, anahtar: anahtar, sistem: sistem, mesajlar: mesajlar,
                                                  baslangic: baslangic, toplamSiniri: toplamSiniri, kapi: kapi,
                                                  kazandi: { son.kazandi($0) }, akis: akis)
                            if r != nil { KullanimDefteri.ortak.say(model, .basari) }
                            son.sonuc(model, r, hata: r == nil ? "\(model): yanıt vermedi" : nil)
                        } catch {
                            if Task.isCancelled { return }
                            KullanimDefteri.ortak.say(model, .hata)
                            son.sonuc(model, nil, hata: "\(model): \(error.localizedDescription)")
                        }
                    })
                }
                // İlk metin sınırı: kimse başlamadıysa tüm yarış başarısız sayılır (çağıran yedek yola düşer).
                Task {
                    try? await Task.sleep(for: .seconds(ilkMetinSiniri))
                    if await kapi.kazanan == nil { son.bitir(hata: Hata.hicbiriYanitlamadi(["ilk metin \(Int(ilkMetinSiniri)) sn içinde gelmedi"])) }
                }
            }
        } onCancel: { son.bitir(hata: CancellationError()) }
    }

    private static func oku(model: String, taban: URL, anahtar: String, sistem: String, mesajlar: [Mesaj],
                            baslangic: Date, toplamSiniri: TimeInterval, kapi: Kapi, kazandi: @escaping @Sendable (String) -> Void,
                            akis: @escaping @Sendable (String, String) async -> Void) async throws -> Sonuc? {
        var istek = URLRequest(url: taban.appending(path: "v1/chat/completions"))
        istek.httpMethod = "POST"
        istek.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.httpBody = try govde(model: model, sistem: sistem, mesajlar: mesajlar)
        let ayar = URLSessionConfiguration.ephemeral
        ayar.timeoutIntervalForRequest = 30      // akış içi boşta kalma; ilk metin sınırı yaris() içinde ayrıca uygulanır
        ayar.timeoutIntervalForResource = toplamSiniri
        let oturum = URLSession(configuration: ayar)
        defer { oturum.invalidateAndCancel() }
        let (bayt, yanit) = try await oturum.bytes(for: istek)
        if let http = yanit as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return try await satirlariOku(bayt.lines, model: model, baslangic: baslangic, kapi: kapi, kazandi: kazandi, akis: akis)
    }

    /// SSE bitişi HTTP bağlantısından önce gelebilir. Son satırdaki metni de alıp hemen dön;
    /// ağ oturumunu çağıranın defer'i kapatır, bitmiş yanıt boşta kalma hatasına dönüşmez.
    static func satirlariOku<S: AsyncSequence>(_ satirlar: S, model: String, baslangic: Date, kapi: Kapi,
                                               kazandi: @escaping @Sendable (String) -> Void,
                                               akis: @escaping @Sendable (String, String) async -> Void) async throws -> Sonuc? where S.Element == String {
        var metin = ""
        var ilkSn: TimeInterval?
        var temizBitti = false
        for try await satir in satirlar {
            try Task.checkCancellation()
            if let k = await kapi.kazanan, k != model { return nil }
            if let h = hataMetni(satir) { throw AkisHatasi.sunucu(h) }
            if let parca = parcaCoz(satir), !parca.isEmpty,
               ilkSn != nil || !parca.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if ilkSn == nil {
                    guard await kapi.al(model) else { return nil }
                    kazandi(model)
                    ilkSn = Date().timeIntervalSince(baslangic)
                }
                metin += parca
                await akis(model, metin)
            }
            if bitisMi(satir) { temizBitti = true; break }
        }
        try Task.checkCancellation()
        guard let ilkSn, !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if !temizBitti { throw AkisHatasi.kesildi }
        return Sonuc(model: model, metin: metin, ilkSn: ilkSn)
    }
}
