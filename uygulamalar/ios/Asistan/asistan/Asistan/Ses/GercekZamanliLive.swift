import Foundation
import Observation
import AVFoundation

@MainActor @Observable
final class GercekZamanliLive: GercekZamanliMotor {
    typealias Durum = GercekLiveDurumu
    private enum BaglantiHatasi: LocalizedError {
        case http(Int), gecersizAdres, zamanAsimi
        var errorDescription: String? {
            switch self {
            case .http(let kod): "Live anahtar sunucusu HTTP \(kod) döndürdü."
            case .gecersizAdres: "Live anahtar sunucusu geçerli Gemini WebSocket adresi döndürmedi."
            case .zamanAsimi: "Gemini Live kurulumu zamanında tamamlanmadı."
            }
        }
    }
    private struct Anahtar: Decodable { let model, wsUrl: String; let maxSessionSec: Int }
    private(set) var durum: Durum = .kapali
    private(set) var kullaniciMetni = ""
    private(set) var yanitMetni = ""
    private(set) var model: String?
    /// Bağlantı kurulamazsa hızlı sıralı Live yedeği çalışmaya devam eder;
    /// tanılama için son neden korunur, erişim anahtarı veya URL saklanmaz.
    private(set) var sonBaglantiHatasi: String?
    private var soket: URLSessionWebSocketTask?
    private var ses: CanliSesIO?
    private var alici: Task<Void, Never>?
    /// Her kapat() artırır: bağlanırken kapatılan eski baslat() yeni oturuma dokunmaz.
    private var oturum = 0
    private var sesNesli = 0
    private var baglantiZamani: Date?
    /// Sunucu goAway gönderdi; kapanış süren yanıt bitince yapılacak.
    private var ayrilmaBekliyor = false
    /// Sağlayıcı kota/erişim hatasında her Live turunda uzun WebSocket beklemesini önler.
    private var yenidenDenemeSonu = Date.distantPast
    var etkin: Bool { if case .dinliyor = durum { true } else if case .yanitliyor = durum { true } else { false } }
    var girisDb: Float { ses?.girisDb ?? -100 }
    var cikisDb: Float { ses?.cikisDb ?? -100 }
    /// Kurulmuş oturum kendiliğinden bittiğinde (goAway, hata, kopma, ses yolu) çağrılır; mikrofon ve soket kapatılmıştır.
    var oturumKoptu: ((String) -> Void)?
    /// İşlev çağrısı köprüsü (P3.1); nil ise model araçsız konuşur.
    var aracKoprusu: CanliAracKoprusu?
    /// Kurulumda okunan sistem talimatı (saat + hafıza olguları); nil ise kurulum talimatsız gider.
    var talimatSaglayici: (@MainActor () -> String)?
    /// Sunucunun `toolCallCancellation` ile iptal ettiği çağrılar: yanıtları gönderilmez.
    private var iptalEdilenCagrilar: Set<String> = []

    func baslat() async -> Bool {
        guard !etkin, durum != .baglaniyor else { return etkin }
        guard Date() >= yenidenDenemeSonu else { return false }
        guard await AVAudioApplication.requestRecordPermission() else { durum = .hata("Mikrofon izni verilmedi."); return false }
        guard let taban = Gizli.vekilTaban, let token = Gizli.vekilToken else { durum = .hata("Live sunucu bağlantısı yok."); return false }
        durum = .baglaniyor; kullaniciMetni = ""; yanitMetni = ""; sonBaglantiHatasi = nil
        let benim = oturum
        do {
            var istek = URLRequest(url: SunucuGorevleri.asistanAdresi(taban, "live-token"))
            istek.httpMethod = "POST"; istek.httpBody = Data("{}".utf8); istek.timeoutInterval = 12
            istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
            istek.setValue(token, forHTTPHeaderField: "X-Personal-Token")
            let (veri, yanit) = try await URLSession.shared.data(for: istek)
            guard benim == oturum else { return false }   // beklerken kapatıldı
            guard let http = yanit as? HTTPURLResponse else { throw BaglantiHatasi.gecersizAdres }
            // Sunucu 204 ile doğrudan WebSocket yerine Antigravity sıralı Live
            // kullanılacağını bildirir. Bu beklenen bir durumdur, hata değildir.
            if http.statusCode == 204 {
                durum = .kapali
                return false
            }
            guard http.statusCode == 200 else { throw BaglantiHatasi.http(http.statusCode) }
            let anahtar = try JSONDecoder().decode(Anahtar.self, from: veri)
            guard let url = URL(string: anahtar.wsUrl), url.scheme == "wss", url.host == "generativelanguage.googleapis.com" else { throw BaglantiHatasi.gecersizAdres }
            model = anahtar.model
            let soket = URLSession.shared.webSocketTask(with: url); soket.maximumMessageSize = 16 * 1024 * 1024
            self.soket = soket; soket.resume(); baglantiZamani = .now
            iptalEdilenCagrilar = []
            try await gonder(Self.kurulumMesaji(model: anahtar.model, talimat: talimatSaglayici?(),
                                                araclar: Self.aracBildirimleri(aracKoprusu?.tanimlar() ?? [])))
            alici = Task { [weak self] in await self?.al() }
            // Geçerli bir Live kurulumu normalde ilk birkaç saniyede setupComplete döndürür.
            // Sağlayıcı kota hatasında sıralı Live'a hızlı dönüş daha iyi bir deneyim verir.
            for _ in 0..<40 {
                try await Task.sleep(for: .milliseconds(50))
                guard benim == oturum else { return false }
                if etkin { return true }
                if case .hata = durum { break }
            }
            throw BaglantiHatasi.zamanAsimi
        } catch {
            guard benim == oturum else { return false }   // kullanıcı kapattı: hata değil, yeniden deneme engeli koyma
            sonBaglantiHatasi = error.localizedDescription
            #if DEBUG
            print("[LIVE] gerçek zamanlı bağlantı hatası: \(error.localizedDescription)")
            #endif
            yenidenDenemeSonu = Date().addingTimeInterval(120)
            kapat()
            return false
        }
    }

    func kapat() {
        oturum += 1; ayrilmaBekliyor = false
        alici?.cancel(); alici = nil; ses?.durdur(); ses = nil
        soket?.cancel(with: .normalClosure, reason: nil); soket = nil
        if let bas = baglantiZamani { SaglikMerkezi.ortak.kaydet("live_oturum", sure: Date().timeIntervalSince(bas), etiket: model) }
        baglantiZamani = nil; durum = .kapali
    }

    func sozuAl() { sesNesli += 1; ses?.yanitiKes(); durum = .dinliyor }

    /// Kurulmuş oturum bittiyse mikrofonu ve soketi kapatır, ses oturumuna haber verir (yeniden bağlanma/yedek).
    /// Kurulum sırasında yalnız durum yazılır; `baslat` kendi temizliğini ve bekleme engelini uygular.
    private func oturumuBitir(_ neden: String) {
        guard etkin else { if durum == .baglaniyor { durum = .hata(neden) }; return }
        kapat(); durum = .hata(neden); oturumKoptu?(neden)
    }

    private func al() async {
        while !Task.isCancelled, let soket {
            do {
                let mesaj = try await soket.receive()
                let veri: Data? = switch mesaj { case .data(let d): d; case .string(let s): s.data(using: .utf8); @unknown default: nil }
                guard let veri, let json = try? JSONSerialization.jsonObject(with: veri) as? [String: Any] else { continue }
                isle(json)
            } catch { oturumuBitir("Live bağlantısı kesildi."); return }
        }
    }

    private func isle(_ json: [String: Any]) {
        #if DEBUG
        if json["setupComplete"] == nil, json["error"] != nil || json["goAway"] != nil {
            print("[LIVE] sunucu olayı: \(json)")
        }
        #endif
        if json["setupComplete"] != nil { sesiBaslat(); return }
        switch Self.kapanisTuru(json) {
        case .hata: oturumuBitir("Live oturumu sona erdi."); return
        case .ayrilma:
            // goAway "bağlantı yakında kapanacak" uyarısıdır (timeLeft kadar açık kalır): asistan konuşuyorsa
            // cümle yarıda kesilmez, kapanış tur bitip çalınan ses tükenince yapılır.
            if durum == .yanitliyor { ayrilmaBekliyor = true } else { planliAyril() }
            return
        case nil: break
        }
        if let iptaller = (json["toolCallCancellation"] as? [String: Any])?["ids"] as? [String] {
            iptalEdilenCagrilar.formUnion(iptaller); return
        }
        let cagrilar = Self.aracCagrilari(json)
        if !cagrilar.isEmpty { araclariCalistir(cagrilar); return }
        guard let icerik = json["serverContent"] as? [String: Any] else { return }
        if let metin = (icerik["inputTranscription"] as? [String: Any])?["text"] as? String { kullaniciMetni += metin }
        if let metin = (icerik["outputTranscription"] as? [String: Any])?["text"] as? String { yanitMetni += metin }
        if let parcalar = (icerik["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] {
            for parca in parcalar {
                if let satir = parca["inlineData"] as? [String: Any], let b64 = satir["data"] as? String, let pcm = Data(base64Encoded: b64) {
                    sesNesli += 1; durum = .yanitliyor; ses?.oynat(pcm)
                }
            }
        }
        if icerik["interrupted"] as? Bool == true { sozuAl() }
        if icerik["turnComplete"] as? Bool == true { yanitCalinincaDinle() }
        if ayrilmaBekliyor, durum == .dinliyor { planliAyril() }
    }

    /// Sunucu turu tamamlandığında hoparlör kuyruğunu da bekle; eski turun bitişi yeni yanıtı değiştirmez.
    private func yanitCalinincaDinle() {
        guard let ses, durum == .yanitliyor else { durum = .dinliyor; return }
        let benim = oturum, nesil = sesNesli
        ses.calinincaBildir { [weak self] in
            Task { @MainActor in
                guard let self, self.oturum == benim, self.sesNesli == nesil else { return }
                self.durum = .dinliyor
                if self.ayrilmaBekliyor { self.planliAyril() }
            }
        }
    }

    nonisolated enum SunucuKapanisi: Equatable { case hata, ayrilma }
    /// Sunucu olayının kapanış türü (saf mantık): `error` hemen kapatır, `goAway` planlı ayrılmadır.
    nonisolated static func kapanisTuru(_ json: [String: Any]) -> SunucuKapanisi? {
        if json["error"] != nil { return .hata }
        if json["goAway"] != nil { return .ayrilma }
        return nil
    }

    /// goAway sonrası: kuyruktaki model sesi çalınıp bitince oturum kapatılır (yeniden bağlanma `oturumKoptu` ile).
    /// Bu arada yeni bir yanıt başladıysa kapanış o turun sonuna ertelenir. Süre dolarsa sunucu soketi kapatır, `al` yolu biter.
    private func planliAyril() {
        ayrilmaBekliyor = false
        guard let ses else { oturumuBitir("Live oturumu yenileniyor."); return }
        let benim = oturum
        ses.calinincaBildir { [weak self] in
            Task { @MainActor in
                guard let self, self.oturum == benim else { return }   // bu arada kapatıldı
                if self.durum == .yanitliyor { self.ayrilmaBekliyor = true } else { self.oturumuBitir("Live oturumu yenileniyor.") }
            }
        }
    }

    private func sesiBaslat() {
        let ses = CanliSesIO(); self.ses = ses
        // Ses yolu değişimi/kesintiden sonra hat kurulamadıysa oturum ölü kalmasın.
        let benim = oturum
        ses.kesildi = { [weak self] neden in
            Task { @MainActor in
                guard let self, self.oturum == benim else { return }   // eski oturumun gecikmiş haberi
                self.oturumuBitir(neden)
            }
        }
        let soket = self.soket
        do {
            try ses.baslat { parca in
                let nesne: [String: Any] = ["realtimeInput": ["audio": ["data": parca.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]]]
                guard let veri = try? JSONSerialization.data(withJSONObject: nesne) else { return }
                soket?.send(.string(String(decoding: veri, as: UTF8.self))) { _ in }
            }
            durum = .dinliyor
        } catch { durum = .hata("Live mikrofonu başlatılamadı.") }
    }

    /// Güncel BidiGenerateContent şeması ses kiplerini `generationConfig` altında bekler.
    /// `talimat`/`araclar` verilmezse çıktı eski biçimle birebir aynıdır (P3.1: systemInstruction + functionDeclarations).
    static func kurulumMesaji(model: String, talimat: String? = nil, araclar: [[String: Any]] = []) -> [String: Any] {
        var setup: [String: Any] = ["model": "models/\(model)",
                                    "generationConfig": ["responseModalities": ["AUDIO"]]]
        if let talimat, !talimat.isEmpty { setup["systemInstruction"] = ["parts": [["text": talimat]]] }
        if !araclar.isEmpty { setup["tools"] = [["functionDeclarations": araclar]] }
        return ["setup": setup]
    }

    /// Köprü tanımlarını Gemini `functionDeclarations` biçimine çevirir; parametresiz araçta `parameters` yazılmaz.
    nonisolated static func aracBildirimleri(_ tanimlar: [CanliAracTanimi]) -> [[String: Any]] {
        tanimlar.map { t in
            var d: [String: Any] = ["name": t.ad, "description": t.aciklama]
            if !t.parametresiz { d["parameters"] = t.sema }
            return d
        }
    }

    /// `toolCall.functionCalls[]` → (id, ad, argüman JSON metni) (saf).
    nonisolated static func aracCagrilari(_ json: [String: Any]) -> [(id: String, ad: String, argumanlar: String)] {
        guard let liste = (json["toolCall"] as? [String: Any])?["functionCalls"] as? [[String: Any]] else { return [] }
        return liste.compactMap { c in
            guard let ad = c["name"] as? String else { return nil }
            let args = (c["args"] as? [String: Any]) ?? [:]
            let metin = (try? JSONSerialization.data(withJSONObject: args)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return (id: (c["id"] as? String) ?? "", ad: ad, argumanlar: metin)
        }
    }

    /// Araç sonuçlarını tek `toolResponse` mesajında toplar (saf).
    nonisolated static func aracYaniti(_ yanitlar: [(id: String, ad: String, cikti: String)]) -> [String: Any] {
        ["toolResponse": ["functionResponses": yanitlar.map { y -> [String: Any] in
            ["id": y.id, "name": y.ad, "response": ["result": y.cikti]]
        }]]
    }

    /// Çağrıları sırayla köprüde çalıştırır; oturum değiştiyse (kapat) sonuç gönderilmez, iptal edilenler ayıklanır.
    private func araclariCalistir(_ cagrilar: [(id: String, ad: String, argumanlar: String)]) {
        let benim = oturum
        let kopru = aracKoprusu
        Task { [weak self] in
            var yanitlar: [(id: String, ad: String, cikti: String)] = []
            for c in cagrilar {
                let cikti = await kopru?.calistir(ad: c.ad, json: c.argumanlar) ?? "Araç yok: Live'da araç bağlı değil."
                yanitlar.append((id: c.id, ad: c.ad, cikti: cikti))
            }
            guard let self, benim == self.oturum else { return }
            let kalan = yanitlar.filter { !self.iptalEdilenCagrilar.contains($0.id) }
            guard !kalan.isEmpty else { return }
            try? await self.gonder(Self.aracYaniti(kalan))
        }
    }

    private func gonder(_ nesne: [String: Any]) async throws {
        let veri = try JSONSerialization.data(withJSONObject: nesne)
        try await soket?.send(.string(String(decoding: veri, as: UTF8.self)))
    }
}
