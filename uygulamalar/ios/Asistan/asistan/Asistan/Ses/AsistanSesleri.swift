import Foundation
import AVFoundation
import CryptoKit

nonisolated struct AsistanSesi: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let engine: String
    let voice: String
    let title: String
    static let elif = AsistanSesi(id: "azure:Elif", engine: "azure", voice: "Elif", title: "Azure HD · Elif — Kadın")
    static let kore = AsistanSesi(id: "claude:Kore", engine: "claude", voice: "Kore", title: "Chirp · Kore — Kadın")
    /// OpenAI TTS (gpt-4o-mini-tts), iPhone'daki CLIProxy kasasındaki OpenAI anahtarıyla; sunucu gerekmez.
    static let openaiSesleri: [AsistanSesi] = [("marin", "Marin — Kadın"), ("coral", "Coral — Kadın"), ("sage", "Sage — Kadın"), ("cedar", "Cedar — Erkek")]
        .map { AsistanSesi(id: "openai:\($0.0)", engine: "openai", voice: $0.0, title: "OpenAI · \($0.1)") }
}

@MainActor @Observable final class AsistanSesleri {
    static let ortak = AsistanSesleri()
    /// Konuşma sırasındaki ilk ses gecikmesini sınırlı tut. Ses hizmeti bu
    /// sürede üretemezse Konusmaci yerel Türkçe sese geçer; yanıt sessizce
    /// yüzlerce saniye beklemez.
    nonisolated static let bulutSesZamanAsimi: TimeInterval = 15
    private(set) var sunucuSesleri: [AsistanSesi] = [.elif]
    /// Seçilebilir tüm sesler: sunucudakiler + OpenAI TTS.
    var sesler: [AsistanSesi] {
        [.kore] + sunucuSesleri.filter { $0.id != AsistanSesi.kore.id }
            + AsistanSesi.openaiSesleri.filter { o in !sunucuSesleri.contains(where: { $0.id == o.id }) }
    }
    var hata: String?
    func sesAdi(_ kimlik: String) -> String {
        if kimlik == "apple" { return "iPhone · Türkçe" }
        if kimlik.hasPrefix("apple:") {
            return "iPhone · " + (AVSpeechSynthesisVoice(identifier: String(kimlik.dropFirst(6)))?.name ?? "Türkçe")
        }
        return sesler.first(where: { $0.id == kimlik })?.title ?? kimlik
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "ses.katalog"), let saved = try? JSONDecoder().decode([AsistanSesi].self, from: data) { sunucuSesleri = saved.filter { $0.engine != "openai" } }
    }
    func yenile() async {
        do {
            let veri = try await Self.istek("voices")
            sunucuSesleri = try JSONDecoder().decode([AsistanSesi].self, from: veri).filter { $0.engine != "openai" }
            if let cache = try? JSONEncoder().encode(sunucuSesleri) { UserDefaults.standard.set(cache, forKey: "ses.katalog") }
            hata = nil
        } catch { hata = "Ses listesi yenilenemedi: \(error.localizedDescription)" }
    }
    @concurrent nonisolated static func istek(_ yol: String, body: Data? = nil, zamanAsimi: TimeInterval = 20) async throws -> Data {
        guard let base = Gizli.vekilTaban, base.scheme == "https", let token = Gizli.vekilToken else { throw SunucuGorevleri.Hata.baglanti }
        let root = base.lastPathComponent == "v1" ? base.deletingLastPathComponent() : base
        let url = root.appending(path: "v1/asistan").appending(path: yol)
        var r = URLRequest(url: url, timeoutInterval: zamanAsimi)
        r.setValue(token, forHTTPHeaderField: "X-Personal-Token")
        if let body { r.httpMethod = "POST"; r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let ayar = URLSessionConfiguration.ephemeral
        ayar.timeoutIntervalForRequest = zamanAsimi
        ayar.timeoutIntervalForResource = zamanAsimi
        let oturum = URLSession(configuration: ayar)
        defer { oturum.invalidateAndCancel() }
        let (data, response) = try await oturum.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SunucuGorevleri.Hata.http(status) }
        return data
    }
    @concurrent nonisolated static func ses(_ metin: String, kimlik: String) async throws -> Data {
        let parcalar = kimlik.split(separator: ":", maxSplits: 1).map(String.init)
        guard parcalar.count == 2 else { throw SunucuGorevleri.Hata.http(400) }
        // P3.12: kısa, sık yinelenen metinler ("Tamam.", "Hatırlatıcı kuruldu.") diskten gelir; ağa çıkmaz.
        let kisa = metin.count <= TTSOnbellegi.enUzunMetin
        if kisa, let d = TTSOnbellegi.oku(metin: metin, kimlik: kimlik) { return d }
        let data = try await uret(metin, kimlik: kimlik, parcalar: parcalar)
        if kisa { TTSOnbellegi.yaz(data, metin: metin, kimlik: kimlik) }
        return data
    }

    @concurrent nonisolated private static func uret(_ metin: String, kimlik: String, parcalar: [String]) async throws -> Data {
        let engine = parcalar[0]
        if engine == "openai" { return try await openaiSes(metin, ses: parcalar[1]) }
        let voice = engine == "xtts" ? kimlik : parcalar[1]
        let body = try JSONSerialization.data(withJSONObject: ["engine": engine, "voice": voice, "text": metin])
        struct Yanit: Decodable { let audio: String }
        let sure: TimeInterval = ["claude", "chirp", "gemini"].contains(engine) ? 30 : bulutSesZamanAsimi
        let yanit = try JSONDecoder().decode(Yanit.self, from: await istek("speak", body: body, zamanAsimi: sure))
        guard let data = Data(base64Encoded: yanit.audio), data.count > 44 else { throw SunucuGorevleri.Hata.http(502) }
        return data
    }

    /// OpenAI TTS: telefondaki yerel CLIProxy (kasadaki OpenAI anahtarı) üzerinden; MP3 döner.
    @concurrent nonisolated static func openaiSes(_ metin: String, ses: String) async throws -> Data {
        let (taban, anahtar) = await MainActor.run { (TelefonProxy.ortak.taban, TelefonProxy.ortak.yerelAnahtar) }
        await TelefonProxy.ortak.hazirla()
        var r = URLRequest(url: taban.appending(path: "v1/audio/speech"), timeoutInterval: bulutSesZamanAsimi)
        r.httpMethod = "POST"
        r.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-4o-mini-tts", "voice": ses, "input": String(metin.prefix(1500)),
                                                                  "response_format": "mp3", "instructions": "Türkçe, doğal, sıcak ve akıcı konuş; sakin bir tempo kullan."])
        let (v, y) = try await URLSession.shared.data(for: r)
        let kod = (y as? HTTPURLResponse)?.statusCode ?? 0
        guard kod == 200, v.count > 44 else { throw SunucuGorevleri.Hata.http(kod == 200 ? 502 : kod) }
        return v
    }
}

/// P3.12: kısa bulut seslerinin disk önbelleği (Caches/TTSOnbellegi; sistem gerektiğinde siler, yedeğe girmez).
/// Anahtar ses kimliği + kırpılmış, Türkçe küçük harfli metnin SHA256'sıdır. En çok `enCokDosya` dosya; aşılınca en eski
/// değiştirilme tarihliler silinir (okunan dosyanın tarihi yenilenir: en son kullanılan kalır).
nonisolated enum TTSOnbellegi {
    static let enUzunMetin = 80
    static let enCokDosya = 300

    static var varsayilanKlasor: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "TTSOnbellegi", directoryHint: .isDirectory)
    }

    static func anahtar(metin: String, kimlik: String) -> String {
        let norm = metin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "tr_TR"))
        let ozet = SHA256.hash(data: Data((kimlik + "\n" + norm).utf8))
        return ozet.map { String(format: "%02x", $0) }.joined()
    }

    static func dosya(metin: String, kimlik: String, klasor: URL) -> URL {
        klasor.appending(path: anahtar(metin: metin, kimlik: kimlik) + ".ses", directoryHint: .notDirectory)
    }

    static func oku(metin: String, kimlik: String, klasor: URL = varsayilanKlasor) -> Data? {
        let url = dosya(metin: metin, kimlik: kimlik, klasor: klasor)
        guard let d = try? Data(contentsOf: url), d.count > 44 else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
        return d
    }

    static func yaz(_ veri: Data, metin: String, kimlik: String, klasor: URL = varsayilanKlasor, sinir: Int = enCokDosya) {
        guard veri.count > 44 else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: klasor, withIntermediateDirectories: true)
        guard (try? veri.write(to: dosya(metin: metin, kimlik: kimlik, klasor: klasor), options: .atomic)) != nil else { return }
        budama(klasor: klasor, sinir: sinir)
    }

    /// Dosya sayısı sınırı aşıldıysa en eski değiştirilme tarihlileri siler.
    static func budama(klasor: URL, sinir: Int) {
        let fm = FileManager.default
        guard let liste = try? fm.contentsOfDirectory(at: klasor, includingPropertiesForKeys: [.contentModificationDateKey]),
              liste.count > sinir else { return }
        let tarihli = liste.map { u in (u, (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (u, _) in tarihli.sorted(by: { $0.1 < $1.1 }).prefix(liste.count - sinir) { try? fm.removeItem(at: u) }
    }
}

/// P3.12: bulut ses devre kesicisi (saf mantık). `esik` art arda hata → `sure` boyunca doğrudan iPhone sesi (her yanıt
/// 15 sn zaman aşımı beklemesin). Süre dolunca yarı açık: ilk bulut denemesi başarılıysa kapanır, hatalıysa yeniden açılır.
nonisolated struct BulutSesDevresi: Sendable, Equatable {
    static let esik = 2
    static let sure: TimeInterval = 300
    private(set) var artArda = 0
    private(set) var acikBitis: Date?

    mutating func hata(simdi: Date) {
        artArda += 1
        // Yarı açık deneme (süre dolmuş açık devre) ya da eşik: devre (yeniden) açılır.
        if acikBitis != nil || artArda >= Self.esik { acikBitis = simdi.addingTimeInterval(Self.sure) }
    }

    mutating func basari() { artArda = 0; acikBitis = nil }

    func yerelMi(simdi: Date) -> Bool { acikBitis.map { simdi < $0 } ?? false }
}

/// Hata beklemesi ses kimliği bazındadır; Azure hatası ChatGPT/Chirp seçimini kilitlemez.
nonisolated struct BulutSesDevreleri: Sendable {
    private var kayitlar: [String: BulutSesDevresi] = [:]
    mutating func hata(kimlik: String, simdi: Date) {
        kayitlar[kimlik, default: BulutSesDevresi()].hata(simdi: simdi)
    }
    mutating func basari(kimlik: String) { kayitlar.removeValue(forKey: kimlik) }
    func yerelMi(kimlik: String, simdi: Date) -> Bool {
        kayitlar[kimlik]?.yerelMi(simdi: simdi) ?? false
    }
}
