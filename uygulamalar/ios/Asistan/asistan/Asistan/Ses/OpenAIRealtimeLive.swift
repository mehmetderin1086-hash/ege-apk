import Foundation
import Observation
import Security

/// Gerçek zamanlı Live motorlarının ortak durumu.
enum GercekLiveDurumu: Equatable { case kapali, baglaniyor, dinliyor, yanitliyor, hata(String) }

/// Gemini Live ve OpenAI Realtime motorlarının ortak yüzü (arayüz ve ses oturumu yalnız bunu bilir).
@MainActor
protocol GercekZamanliMotor: AnyObject {
    var durum: GercekLiveDurumu { get }
    var etkin: Bool { get }
    var kullaniciMetni: String { get }
    var yanitMetni: String { get }
    var girisDb: Float { get }
    var cikisDb: Float { get }
    func baslat() async -> Bool
    func kapat()
    func sozuAl()
}

/// OpenAI API anahtarı: yalnız bu telefonun Keychain'inde (paylaşılmaz, sunucuya gönderilmez, günlüğe yazılmaz).
nonisolated enum OpenAIAnahtari {
    private static func sorgu() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mehmetderin.asistan", kSecAttrAccount as String: "openai-api"]
    }
    /// iPhone'daki CLIProxy hesap kasasında tanımlı OpenAI API anahtarı (api.openai.com, etkin); `TelefonProxy` kasa yüklenince doldurur.
    nonisolated(unsafe) static var kasaAnahtari: String?

    /// Elle girilen (Keychain) anahtar.
    static var elleGirilen: String? {
        var q = sorgu(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var v: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &v) == errSecSuccess, let d = v as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    /// Kullanılacak anahtar: önce elle girilen, yoksa kasadaki.
    static var deger: String? {
        if let e = elleGirilen, !e.isEmpty { return e }
        if let k = kasaAnahtari, !k.isEmpty { return k }
        return nil
    }
    static var var_: Bool { (deger ?? "").isEmpty == false }
    static var kaynak: String { (elleGirilen ?? "").isEmpty ? ((kasaAnahtari ?? "").isEmpty ? "yok" : "kasa") : "elle" }

    /// Kasa durumundan OpenAI anahtarını seçer (saf mantık).
    static func kasadanSec(_ saglayicilar: [(adres: String, etkin: Bool, anahtar: String)]) -> String? {
        saglayicilar.first { $0.etkin && !$0.anahtar.isEmpty && URL(string: $0.adres)?.host == "api.openai.com" }?.anahtar
    }

    /// "sk-…" biçimi; boşluk/satır sonu temizlenir. Geçersizse false.
    @discardableResult
    static func kaydet(_ ham: String) -> Bool {
        let t = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        guard gecerli(t), let d = t.data(using: .utf8) else { return false }
        sil()
        var q = sorgu(); q[kSecValueData as String] = d; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func sil() { SecItemDelete(sorgu() as CFDictionary) }
    static func gecerli(_ s: String) -> Bool { s.hasPrefix("sk-") && s.count >= 20 && !s.contains(where: \.isWhitespace) }
    /// Ekranda göstermek için maskeli biçim: "sk-…ab12".
    static func maske(_ s: String) -> String { s.count > 8 ? "\(s.prefix(3))…\(s.suffix(4))" : "•••" }
}

/// OpenAI Realtime olay biçimleri (GA arayüzü; eski beta adları da kabul edilir).
nonisolated enum OpenAIRealtimeMesajlari {
    static let model = "gpt-realtime"
    static let ses = "marin"
    static let ornekHz = 24_000
    static let talimat = "Sen Mehmet'in kişisel sesli asistanısın. Türkçe konuş; kısa, doğal ve akıcı yanıtla (1-3 cümle). Telefonda işlem yapamazsın ve bir şeyi yaptığını iddia etme. Bilmediğini uydurma."

    static func adres() -> URL { URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")! }

    /// `araclar` boşken çıktı araçsız biçimle birebir aynıdır; doluysa `tools` + `tool_choice: auto` eklenir (P3.1).
    static func oturumGuncelle(talimat: String = talimat, araclar: [[String: Any]] = []) -> [String: Any] {
        var oturum: [String: Any] = ["type": "realtime", "model": model, "output_modalities": ["audio"], "instructions": talimat,
                     "audio": [
                        "input": ["format": ["type": "audio/pcm", "rate": ornekHz],
                                  "transcription": ["model": "gpt-4o-transcribe", "language": "tr"],
                                  "turn_detection": ["type": "server_vad", "interrupt_response": true, "create_response": true]],
                        "output": ["format": ["type": "audio/pcm", "rate": ornekHz], "voice": ses]]]
        if !araclar.isEmpty { oturum["tools"] = araclar; oturum["tool_choice"] = "auto" }
        return ["type": "session.update", "session": oturum]
    }

    /// Köprü tanımlarını Realtime `tools` biçimine çevirir.
    static func aracTanimlari(_ tanimlar: [CanliAracTanimi]) -> [[String: Any]] {
        tanimlar.map { ["type": "function", "name": $0.ad, "description": $0.aciklama, "parameters": $0.sema] }
    }

    /// Araç sonucunu konuşmaya ekler ve modelden yanıtı sürdürmesini ister.
    static func aracCiktisi(id: String, cikti: String) -> [[String: Any]] {
        [["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": id, "output": cikti]],
         ["type": "response.create"]]
    }

    /// Kamera karesini konuşmaya görüntü olarak ekler (yanıt istemez; sesli tur yanıtı tetikler).
    static func goruntuMesaji(_ jpeg: Data) -> [String: Any] {
        ["type": "conversation.item.create",
         "item": ["type": "message", "role": "user",
                  "content": [["type": "input_image", "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]]]]
    }

    static func sesParcasi(_ pcm: Data) -> [String: Any] { ["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()] }

    /// Metin girdisiyle yanıt iste (mikrofonsuz doğrulama için).
    static func metinIstegi(_ metin: String) -> [[String: Any]] {
        [["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": metin]]]],
         ["type": "response.create"]]
    }

    enum Olay: Equatable {
        case hazir
        case sesParcasi(Data)
        case yanitMetni(String)
        case kullaniciMetni(String)
        case kullaniciKonusuyor            // söz kesme: oynatılanı kes
        case yanitBasladi                  // sunucuda yanıt üretimi başladı (iptal edilebilir)
        case yanitBitti
        case hata(String)
        case uyari(String)                 // ölümcül olmayan hata (ör. iptal edilecek yanıt yok): oturum sürer
        case aracCagrisi(id: String, ad: String, argumanlar: String)   // model işlev çağırdı (P3.1)
    }

    /// Bu kodlarla gelen `error` olayı oturumu bozmaz (yanıt yokken iptal, boş ses tamponu).
    static let oturumSurerHataKodlari: Set<String> = ["response_cancel_not_active", "input_audio_buffer_commit_empty"]

    static func coz(_ json: [String: Any]) -> Olay? {
        guard let tur = json["type"] as? String else { return nil }
        switch tur {
        case "session.created", "session.updated": return .hazir
        case "response.output_audio.delta", "response.audio.delta":
            if let b = json["delta"] as? String, let d = Data(base64Encoded: b) { return .sesParcasi(d) }
            return nil
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.output_text.delta":
            return (json["delta"] as? String).map(Olay.yanitMetni)
        case "conversation.item.input_audio_transcription.completed":
            return (json["transcript"] as? String).map(Olay.kullaniciMetni)
        case "input_audio_buffer.speech_started": return .kullaniciKonusuyor
        case "response.created": return .yanitBasladi
        case "response.done": return .yanitBitti
        // İşlev çağrısının asıl kaynağı tamamlanmış çıktı öğesidir (ad, call_id ve argümanlar birlikte gelir).
        case "response.output_item.done":
            guard let oge = json["item"] as? [String: Any], oge["type"] as? String == "function_call",
                  let id = oge["call_id"] as? String, let ad = oge["name"] as? String else { return nil }
            return .aracCagrisi(id: id, ad: ad, argumanlar: (oge["arguments"] as? String) ?? "{}")
        // Argüman olayı adı taşıyorsa kullanılır; ad yoksa (beta biçimi) yok sayılır, öğe olayı işler. Çift çalışmayı motor önler.
        case "response.function_call_arguments.done":
            guard let id = json["call_id"] as? String, let ad = json["name"] as? String else { return nil }
            return .aracCagrisi(id: id, ad: ad, argumanlar: (json["arguments"] as? String) ?? "{}")
        case "error":
            let hata = json["error"] as? [String: Any]
            let m = (hata?["message"] as? String) ?? "bilinmeyen hata"
            if let kod = hata?["code"] as? String, oturumSurerHataKodlari.contains(kod) { return .uyari(m) }
            return .hata(m)
        default: return nil
        }
    }

    /// API hatasını kullanıcıya anlaşılır Türkçe metne çevirir (anahtar içermez).
    static func hataMetni(_ ham: String) -> String {
        let k = ham.lowercased()
        if k.contains("incorrect api key") || k.contains("invalid_api_key") || k.contains("401") { return "OpenAI anahtarı geçersiz. Ayarlar'dan kontrol et." }
        if k.contains("quota") || k.contains("insufficient") || k.contains("billing") { return "OpenAI kredisi/kotası bitmiş görünüyor." }
        if k.contains("model") && (k.contains("not found") || k.contains("access")) { return "Bu OpenAI hesabı gerçek zamanlı modele erişemiyor." }
        if k.contains("rate") { return "OpenAI istek sınırına takıldı; biraz sonra dene." }
        return "OpenAI Live hatası: \(ham.prefix(120))"
    }
}

/// OpenAI Realtime API ile gerçek zamanlı sesten sese Live (anahtar telefondaki Keychain'den).
@MainActor @Observable
final class OpenAIRealtimeLive: GercekZamanliMotor {
    /// Live kamera açıkken son kareyi (JPEG) verir.
    var kareSaglayici: (() -> Data?)?
    private(set) var durum: GercekLiveDurumu = .kapali
    private(set) var kullaniciMetni = ""
    private(set) var yanitMetni = ""
    private(set) var sonBaglantiHatasi: String?
    /// Test/tanı: alınan toplam yanıt sesi (bayt) ve olay sayısı.
    private(set) var alinanSesBayt = 0
    private(set) var yanitSayisi = 0
    var etkin: Bool { if case .dinliyor = durum { true } else if case .yanitliyor = durum { true } else { false } }
    var girisDb: Float { ses?.girisDb ?? -100 }
    var cikisDb: Float { ses?.cikisDb ?? -100 }

    private var soket: URLSessionWebSocketTask?
    private var ses: CanliSesIO?
    private var alici: Task<Void, Never>?
    /// Her kapat() artırır: bağlanırken kapatılan eski baslat() yeni oturuma dokunmaz.
    private var oturum = 0
    private var sesNesli = 0
    private var baglantiZamani: Date?
    private let mikrofonlu: Bool
    private var hazir = false
    /// Sunucuda yanıt üretimi sürüyor mu: `response.cancel` yalnız o zaman gönderilir.
    private var yanitSuruyor = false
    /// Kurulmuş oturum kendiliğinden bittiğinde (kopma, ses yolu) çağrılır; mikrofon ve soket kapatılmıştır.
    var oturumKoptu: ((String) -> Void)?
    /// İşlev çağrısı köprüsü (P3.1); nil ise model araçsız konuşur.
    var aracKoprusu: CanliAracKoprusu?
    /// Bağlanırken okunan oturum talimatı (saat + hafıza olguları); nil ise sabit kısa talimat.
    var talimatSaglayici: (@MainActor () -> String)?
    /// Bu oturumda çalıştırılan call_id'ler: aynı çağrı iki olayla gelirse bir kez çalışır.
    private var islenenCagrilar: Set<String> = []

    /// `mikrofonlu: false` = ses G/Ç açılmaz (yalnız metin ile protokol doğrulaması).
    init(mikrofonlu: Bool = true) { self.mikrofonlu = mikrofonlu }

    func baslat() async -> Bool {
        guard !etkin, durum != .baglaniyor else { return etkin }
        guard let anahtar = OpenAIAnahtari.deger, !anahtar.isEmpty else { durum = .hata("OpenAI API anahtarı yok. Ayarlar'dan ekle."); return false }
        durum = .baglaniyor; kullaniciMetni = ""; yanitMetni = ""; sonBaglantiHatasi = nil; hazir = false; islenenCagrilar = []
        let talimat = talimatSaglayici?() ?? OpenAIRealtimeMesajlari.talimat
        let araclar = OpenAIRealtimeMesajlari.aracTanimlari(aracKoprusu?.tanimlar() ?? [])
        var istek = URLRequest(url: OpenAIRealtimeMesajlari.adres(), timeoutInterval: 15)
        istek.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        let s = URLSession.shared.webSocketTask(with: istek); s.maximumMessageSize = 16 * 1024 * 1024
        soket = s; s.resume(); baglantiZamani = .now
        alici = Task { [weak self] in await self?.al() }
        let benim = oturum
        do {
            try await gonder(OpenAIRealtimeMesajlari.oturumGuncelle(talimat: talimat, araclar: araclar))
            for _ in 0..<80 {
                try await Task.sleep(for: .milliseconds(100))
                guard benim == oturum else { return false }
                if hazir { break }
                // Soket ve alıcı görevi sızmasın; kullanıcıya gösterilen hata metni korunur.
                if case .hata = durum { kapat(hataKoru: true); return false }
            }
            guard hazir else { throw URLError(.timedOut) }
            if mikrofonlu { try sesiBaslat() }
            durum = .dinliyor
            TaniGunlugu.yaz("OPENAI LIVE bağlandı")
            return true
        } catch {
            guard benim == oturum else { return false }
            sonBaglantiHatasi = error.localizedDescription
            if case .baglaniyor = durum { durum = .hata("OpenAI Live bağlantısı kurulamadı.") }
            TaniGunlugu.yaz("OPENAI LIVE bağlantı hatası: \(error.localizedDescription)")
            kapat(hataKoru: true)
            return false
        }
    }

    func kapat() { kapat(hataKoru: false) }

    private func kapat(hataKoru: Bool) {
        oturum += 1
        alici?.cancel(); alici = nil; ses?.durdur(); ses = nil
        soket?.cancel(with: .normalClosure, reason: nil); soket = nil
        if let bas = baglantiZamani { SaglikMerkezi.ortak.kaydet("live_oturum", sure: Date().timeIntervalSince(bas), etiket: OpenAIRealtimeMesajlari.model) }
        baglantiZamani = nil; yanitSuruyor = false
        if !(hataKoru && { if case .hata = durum { true } else { false } }()) { durum = .kapali }
    }

    func sozuAl() {
        sesNesli += 1
        ses?.yanitiKes()
        durum = .dinliyor
        // Yanıt yokken iptal, sunucudan "response_cancel_not_active" hatası döndürür; yalnız yanıt sürerken gönder.
        if yanitSuruyor {
            yanitSuruyor = false
            Task { try? await gonder(["type": "response.cancel"]) }
        }
    }

    /// Kurulmuş oturum bittiyse mikrofonu ve soketi kapatır, ses oturumuna haber verir (yeniden bağlanma/yedek).
    /// Kurulum sırasında yalnız durum yazılır; `baslat` kendi temizliğini yapar.
    private func oturumuBitir(_ neden: String) {
        guard etkin else { if durum == .baglaniyor { durum = .hata(neden) }; return }
        kapat(hataKoru: false); durum = .hata(neden); oturumKoptu?(neden)
    }

    /// Mikrofonsuz doğrulama: metin gönder, sesli yanıt + transkript gelsin.
    func metinGonder(_ metin: String) async throws {
        for m in OpenAIRealtimeMesajlari.metinIstegi(metin) { try await gonder(m) }
    }

    private func sesiBaslat() throws {
        let io = CanliSesIO(girisHz: Double(OpenAIRealtimeMesajlari.ornekHz)); ses = io
        // Ses yolu değişimi/kesintiden sonra hat kurulamadıysa oturum ölü kalmasın.
        let benim = oturum
        io.kesildi = { [weak self] neden in
            Task { @MainActor in
                guard let self, self.oturum == benim else { return }   // eski oturumun gecikmiş haberi
                self.oturumuBitir(neden)
            }
        }
        let s = soket
        try io.baslat { parca in
            guard let veri = try? JSONSerialization.data(withJSONObject: OpenAIRealtimeMesajlari.sesParcasi(parca)) else { return }
            s?.send(.string(String(decoding: veri, as: UTF8.self))) { _ in }
        }
    }

    private func al() async {
        while !Task.isCancelled, let soket {
            do {
                let m = try await soket.receive()
                let veri: Data? = switch m { case .data(let d): d; case .string(let t): t.data(using: .utf8); @unknown default: nil }
                guard let veri, let json = try? JSONSerialization.jsonObject(with: veri) as? [String: Any], let olay = OpenAIRealtimeMesajlari.coz(json) else { continue }
                isle(olay)
            } catch {
                oturumuBitir("OpenAI Live bağlantısı kesildi.")
                return
            }
        }
    }

    private func isle(_ olay: OpenAIRealtimeMesajlari.Olay) {
        switch olay {
        case .hazir: hazir = true
        case .sesParcasi(let d): sesNesli += 1; durum = .yanitliyor; alinanSesBayt += d.count; ses?.oynat(d)
        case .yanitMetni(let t): yanitMetni += t
        case .kullaniciMetni(let t): kullaniciMetni += (kullaniciMetni.isEmpty ? "" : " ") + t.trimmingCharacters(in: .whitespacesAndNewlines)
        case .kullaniciKonusuyor:
            sesNesli += 1
            ses?.yanitiKes(); durum = .dinliyor
            // Kamera ajanı: kullanıcı konuşmaya başlayınca son kare bağlama eklenir (yanıt bunu görerek üretilir).
            if let jpeg = kareSaglayici?() { Task { try? await gonder(OpenAIRealtimeMesajlari.goruntuMesaji(jpeg)) } }
        case .yanitBasladi: sesNesli += 1; yanitSuruyor = true
        case .yanitBitti:
            yanitSayisi += 1; yanitSuruyor = false
            yanitCalinincaDinle()
        case .uyari(let m): TaniGunlugu.yaz("OPENAI LIVE uyarı: \(m.prefix(160))")
        case .aracCagrisi(let id, let ad, let argumanlar): araciCalistir(id: id, ad: ad, argumanlar: argumanlar)
        case .hata(let m):
            TaniGunlugu.yaz("OPENAI LIVE hata: \(m.prefix(160))")
            // Kurulmuş oturumda ölümcül hata sunucunun soketi kapatmasıyla gelir (al() → oturumuBitir);
            // tek başına `error` olayı motoru devre dışı bırakıp mikrofonu açık bırakmasın. Kurulumda durum yazılır ki baslat kırılsın.
            if !etkin { durum = .hata(OpenAIRealtimeMesajlari.hataMetni(m)) }
        }
    }

    /// response.done ağ üretiminin sonudur; kuyruktaki ses hâlâ çalabilir.
    private func yanitCalinincaDinle() {
        guard let ses, durum == .yanitliyor else { durum = .dinliyor; return }
        let benim = oturum, nesil = sesNesli
        ses.calinincaBildir { [weak self] in
            Task { @MainActor in
                guard let self, self.oturum == benim, self.sesNesli == nesil else { return }
                self.durum = .dinliyor
            }
        }
    }

    /// Modelin işlev çağrısı: köprüde çalışır, sonuç aynı oturumdaysa `function_call_output` + `response.create` ile döner.
    /// kapat() oturumu artırdığı için geç gelen sonuç yeni oturuma gitmez. Köprü yoksa model takılmasın diye kısa çıktı gönderilir.
    private func araciCalistir(id: String, ad: String, argumanlar: String) {
        guard islenenCagrilar.insert(id).inserted else { return }
        let benim = oturum
        let kopru = aracKoprusu
        Task { [weak self] in
            let cikti = await kopru?.calistir(ad: ad, json: argumanlar) ?? "Araç yok: Live'da araç bağlı değil. Kullanıcıya sohbet ekranından istemesini söyle."
            guard let self, benim == self.oturum else { return }
            for m in OpenAIRealtimeMesajlari.aracCiktisi(id: id, cikti: cikti) { try? await self.gonder(m) }
        }
    }

    private func gonder(_ nesne: [String: Any]) async throws {
        let veri = try JSONSerialization.data(withJSONObject: nesne)
        try await soket?.send(.string(String(decoding: veri, as: UTF8.self)))
    }
}
