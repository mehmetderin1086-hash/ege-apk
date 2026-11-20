import Foundation
import AVFoundation
import Observation

/// Sistem TTS (Türkçe ses). Cümle cümle kuyruğa alır; barge-in'de susturulur.
@MainActor
@Observable
final class Konusmaci: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    nonisolated static let yerelYedek = "__apple_fallback__"
    /// Seslendirme başladı bildirimi yanıt başına bir kez, ses gerçekten çalmaya başlayınca gider.
    private var baslamaBildirildi = false
    var ayarlar: Ayarlar? {
        didSet { if let ayarlar { hiz = Self.hizSinirla(Float(ayarlar.okumaHizi)) } }
    }
    private(set) var sesHatasi: String?
    /// Bulut sesi düşse de iPhone sesi yanıtı devraldıysa bu bir Live oturum
    /// hatası değildir; sonraki tur için dinleme yeniden açılabilir.
    private(set) var yerelYedekKullanildi = false
    private var bulutIsi: Task<Void, Never>?
    /// (metin, ses kimliği)
    private var kuyruk: [(String, String)] = []
    private var oynatici: AVAudioPlayer?
    /// Önceden üretilmiş sıradaki bulut sesi ve metni (okuma çubuğu metni gösterir).
    private var hazirSes: (Data, String)?
    /// P3.12 okuma kontrolleri (okuma çubuğu, AirPods): duraklatılmış okuma `konusuyor` kalır, `bitti` tetiklenmez.
    private(set) var duraklatildi = false
    /// Okuma hızı (0,8-1,6); bulut sesinde AVAudioPlayer.rate, iPhone sesinde konuşma hızı çarpanı.
    private(set) var hiz: Float = 1.0
    /// Şu an okunan parçanın metni.
    private(set) var simdiCalan: String?
    /// P3.12 bulut ses devre kesicisi: art arda iki hatadan sonra 5 dk doğrudan iPhone sesi.
    static var devreler = BulutSesDevreleri()
    @ObservationIgnored private var yolGozlemcisi: (any NSObjectProtocol)?
    private(set) var oynatilanParcaSayisi = 0
    private(set) var oncedenHazirGecisSayisi = 0
    private(set) var sonUretimMs: Double?
    private var duzeyOlcumu: Task<Void, Never>?
    private(set) var cikisDb: Float = -100
    private var nesil = UUID()
    private let sentez = AVSpeechSynthesizer()
    private(set) var konusuyor = false
    private var bolucu = CumleBolucu()
    /// Yanıtın tamamı kuyruğa alındı mı: cümle aralarındaki boşluk "bitti" sayılmasın.
    private var akisTamam = false
    /// Yanıtın TAMAMI okunup bitince (akış bitti + sentezleyici sustu).
    var bitti: (() -> Void)?
    /// Seslendirme başladı (söz kesme dinleyicisi için: taban ölçümü şimdi başlar).
    var konusmayaBasladi: (() -> Void)?
    /// Ses kuyruğa alındı, henüz çalmıyor: söz kesme motoru (VPIO) sessizlikte açılır,
    /// çalan sesin ortasında açılıp ilk heceleri kesmez.
    var konusmaHazirlaniyor: (() -> Void)?
    /// Kulaklık çıkarıldı: sesli kip/Live turu kendi akışını yönetiyorsa true döner (duraklatma yerine tur bitirilir,
    /// yoksa `bitti` hiç tetiklenmez ve mikrofon/Hey Asistan geri açılmaz).
    var kulaklikCikarildi: (() -> Bool)?

    override init() {
        super.init()
        sentez.delegate = self
        // Kulaklık çıkarıldı (eski aygıt gitti): okuma hoparlörden sürmesin, duraklasın. Kapanış sistem kuyruğunda
        // çağrılabilir: @Sendable, ana aktöre yalnız Bool taşınır.
        yolGozlemcisi = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { @Sendable [weak self] n in
            let neden = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            guard neden == .oldDeviceUnavailable else { return }
            let onceki = n.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let kulaklikti = onceki?.outputs.contains { Self.kulaklikCikisi($0.portType) } ?? false
            guard kulaklikti else { return }
            Task { @MainActor [weak self] in
                guard let self, self.konusuyor, !self.duraklatildi else { return }
                if self.kulaklikCikarildi?() == true { return }
                TaniGunlugu.yaz("SES: kulaklık çıkarıldı, okuma duraklatıldı")
                self.duraklat()
            }
        }
    }

    nonisolated static func kulaklikCikisi(_ p: AVAudioSession.Port) -> Bool {
        p == .headphones || p == .bluetoothA2DP || p == .bluetoothHFP || p == .bluetoothLE || p == .usbAudio
    }

    nonisolated static func hizSinirla(_ h: Float) -> Float { min(1.6, max(0.8, h.isFinite ? h : 1)) }

    /// iPhone sesinin konuşma hızı: varsayılan × 1,05 × okuma hızı (sistem sınırları içinde).
    nonisolated static func sentezHizi(_ hiz: Float) -> Float {
        min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.05 * hiz))
    }

    // MARK: P3.12 okuma kontrolleri

    func duraklat() {
        guard konusuyor, !duraklatildi else { return }
        duraklatildi = true
        oynatici?.pause()
        if sentez.isSpeaking { sentez.pauseSpeaking(at: .word) }
        duzeyOlcumu?.cancel(); duzeyOlcumu = nil; cikisDb = -100
    }

    func devamEt() {
        guard duraklatildi else { return }
        duraklatildi = false
        SesOturumuKapisi.istek.artir()   // bekleyen bir bırakma süren okumayı kesmesin
        if let o = oynatici {
            if o.play() { olcumuBaslat(o) } else { sesHatasi = "Ses oynatılamadı."; oynatici = nil }
        } else if sentez.isPaused {
            sentez.continueSpeaking()
        }
        siradaki()
    }

    func duraklatDevam() { duraklatildi ? devamEt() : duraklat() }

    func hiziDegistir(_ h: Float) {
        hiz = Self.hizSinirla(h)
        if let o = oynatici, o.enableRate { o.rate = hiz }
        if let ayarlar, ayarlar.okumaHizi != Double(hiz) { ayarlar.okumaHizi = Double(hiz) }
    }

    static var turkceSes: AVSpeechSynthesisVoice? {
        let sesler = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
        return sesler.max { a, b in a.quality.rawValue < b.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    /// Kullanıcının açık seçimi, aynı sesi de beş dakika beklemeden yeniden deneyebilir.
    func sesiYenidenDene(_ kimlik: String) {
        Self.devreler.basari(kimlik: kimlik)
        if !konusuyor { sesHatasi = nil; yerelYedekKullanildi = false }
    }

    func akisBasladi() {
        sustur()
        sesHatasi = nil
        yerelYedekKullanildi = false
        bolucu.sifirla()
        bolucu.ilkVirgul = ayarlar?.ilkSesHizli ?? true
        oynatilanParcaSayisi = 0; oncedenHazirGecisSayisi = 0; sonUretimMs = nil
        akisTamam = false
        if sentez.isSpeaking { sentez.stopSpeaking(at: .immediate) }
    }

    func akisParcasi(_ kumulatif: String) {
        for c in bolucu.yeniCumleler(kumulatif) { soyle(c) }
    }

    func akisBitti(_ kumulatif: String) {
        if let k = bolucu.kalan(kumulatif) { soyle(k) }
        akisTamam = true
        tamamlandiMi()
    }

    func soyle(_ metin: String) {
        let t = Self.okunabilir(metin)
        guard !t.isEmpty else { return }
        let secim = ayarlar?.sesKimligi ?? "apple"
        if secim != "apple" && !secim.hasPrefix("apple:") {
            var kalan = t[...]
            // Bir sağlayıcının hatası başka bir sesin denenmesini engellemez.
            if !yerelYedekKullanildi, Self.devreler.yerelMi(kimlik: secim, simdi: .now) {
                yerelYedekKullanildi = true
                sesHatasi = "Seçili ses geçici olarak kullanılamıyor; iPhone sesi kullanılıyor. Başka ses seçebilir veya yeniden deneyebilirsin."
            }
            // Yanıt ortasında iPhone sesine düşüldüyse kalanı da iPhone sesiyle okunur (iki ses üst üste binmesin, gidip gelmesin).
            let kimlik = Self.kuyrukKimligi(secim: secim, yedekte: yerelYedekKullanildi)
            while !kalan.isEmpty {
                let parca = String(kalan.prefix(1400))
                kuyruk.append((parca, kimlik)); kalan = kalan.dropFirst(parca.count)
            }
            // Bildirim (söz kesme tabanı) bulut sesi indirilince, oynatma başlarken gider.
            if !konusuyor { konusuyor = true; konusmaHazirlaniyor?() }
            siradaki()
            return
        }
        let u = AVSpeechUtterance(string: t)
        u.voice = secim.hasPrefix("apple:") ? AVSpeechSynthesisVoice(identifier: String(secim.dropFirst(6))) ?? Self.turkceSes : Self.turkceSes
        u.rate = Self.sentezHizi(hiz)
        u.prefersAssistiveTechnologySettings = false
        if !konusuyor { konusuyor = true; konusmaHazirlaniyor?() }
        baslamaBildir()
        // Daha önce alınmış (kuyrukta bekleyen) bir ses oturumu bırakma kararı bu okumayı kesmesin.
        SesOturumuKapisi.istek.artir()
        sentez.speak(u)
    }

    /// P2.13: Akıştan bağımsız tek metni (sesli onay sorusu, kısa geri bildirim) okur ve susana ya da `sinir` dolana
    /// kadar bekler. `akisTamam`'a dokunmaz: `bitti` tetiklenmez, tur akışı (mikrofonu açma kararı) değişmez.
    func soyleVeBekle(_ metin: String, sinir: Duration = .seconds(20)) async {
        soyle(metin)
        await susmasiniBekle(sinir: sinir)
    }

    /// Süren seslendirme (önceki cümle) bitene ya da `sinir` dolana kadar 100 ms aralıkla bekler.
    func susmasiniBekle(sinir: Duration = .seconds(20)) async {
        let son = ContinuousClock.now + sinir
        while konusuyor, ContinuousClock.now < son, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Bulut kimliği seçimi (saf mantık): yedeğe düşülmüşse yanıtın kalanı iPhone sesiyle sürer.
    nonisolated static func kuyrukKimligi(secim: String, yedekte: Bool) -> String {
        yedekte ? yerelYedek : secim
    }

    private func baslamaBildir() {
        guard !baslamaBildirildi else { return }
        baslamaBildirildi = true
        konusmayaBasladi?()
    }

    func sustur() {
        akisTamam = false
        nesil = UUID(); bulutIsi?.cancel(); bulutIsi = nil
        kuyruk.removeAll(); hazirSes = nil; oynatici?.stop(); oynatici = nil
        sentez.stopSpeaking(at: .immediate)
        konusuyor = false; baslamaBildirildi = false
        duraklatildi = false; simdiCalan = nil
        duzeyOlcumu?.cancel(); duzeyOlcumu = nil; cikisDb = -100
    }

    private func siradaki() {
        // iPhone sesi (yedek) hâlâ okurken hazır bulut sesi başlamaz; didFinish yeniden çağırır.
        // Duraklatılmışken yeni parça başlamaz (önceden üretim sürebilir; devamEt yeniden çağırır).
        if oynatici == nil, !sentez.isSpeaking, !duraklatildi, let hazir = hazirSes {
            hazirSes = nil
            do { try oynat(hazir.0, metin: hazir.1) }
            catch {
                sesHatasi = "Ses oynatılamadı."
                kuyruk.removeAll(); oynatici = nil
            }
        }
        // En çok bir sonraki cümleyi hazır tut. Azure'un sunucu genelindeki tek sırasını korur.
        guard bulutIsi == nil, hazirSes == nil, !kuyruk.isEmpty else { tamamlandiMi(); return }
        let (metin, ses) = kuyruk.removeFirst()
        if ses == Self.yerelYedek {
            // Bulut sesi sıradaki cümlede düşerse, devam eden sesin üstüne binme.
            guard oynatici == nil, !duraklatildi else { kuyruk.insert((metin, ses), at: 0); return }
            let u = AVSpeechUtterance(string: metin)
            u.voice = Self.turkceSes
            u.rate = Self.sentezHizi(hiz)
            baslamaBildir()   // ilk bulut parçası düştüyse iPhone sesi devralır
            SesOturumuKapisi.istek.artir()
            sentez.speak(u)
            return
        }
        let tur = nesil
        bulutIsi = Task { [weak self] in
            do {
                let bas = Date()
                let data = try await AsistanSesleri.ses(metin, kimlik: ses)
                guard let self, !Task.isCancelled, tur == nesil else { return }
                sonUretimMs = Date().timeIntervalSince(bas) * 1000
                SaglikMerkezi.ortak.kaydet("tts", sure: Date().timeIntervalSince(bas), etiket: ses)
                Self.devreler.basari(kimlik: ses)
                bulutIsi = nil
                hazirSes = (data, metin)
                siradaki()
            } catch {
                guard let self, !Task.isCancelled, tur == nesil else { return }
                bulutIsi = nil; hazirSes = nil
                SaglikMerkezi.ortak.kaydet("tts", sure: 0, basarili: false, etiket: ses)
                Self.devreler.hata(kimlik: ses, simdi: .now)
                // Bulut sesi geçici olarak erişilemezse yanıt sessiz kalmasın. Devam eden
                // parça biter, ardından mevcut cümle ve kuyruk iPhone sesiyle okunur.
                let bekleyen = [(metin, Self.yerelYedek)] + kuyruk.map { ($0.0, Self.yerelYedek) }
                kuyruk = bekleyen
                yerelYedekKullanildi = true
                sesHatasi = "Seçili bulut sesi üretilemedi (\(Self.kisaNeden(error))); yanıt iPhone Türkçe sesiyle sürdürüldü."
                TaniGunlugu.yaz("TTS düştü: \(ses) → iPhone sesi (\(Self.kisaNeden(error)))")
                siradaki()
            }
        }
    }

    /// Durum şeridi için kısa hata nedeni: HTTP kodu ya da ilk 60 karakter.
    nonisolated static func kisaNeden(_ e: Error) -> String {
        let m = String(describing: e)
        if let r = m.range(of: #"http\((\d{3})\)"#, options: .regularExpression) {
            return "HTTP " + m[r].filter(\.isNumber)
        }
        let d = e.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.count > 60 ? String(d.prefix(60)) + "…" : d
    }

    private func oynat(_ data: Data, metin: String) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self; player.isMeteringEnabled = true; oynatici = player
        // Hız oynatma başlamadan açılmalı (enableRate sonradan etkisiz).
        player.enableRate = true; player.rate = hiz
        SesOturumuKapisi.istek.artir()   // bekleyen bir bırakma bu sesi kesmesin
        guard player.play() else { throw SunucuGorevleri.Hata.http(502) }
        simdiCalan = metin
        baslamaBildir()
        oynatilanParcaSayisi += 1
        olcumuBaslat(player)
    }

    private func olcumuBaslat(_ player: AVAudioPlayer) {
        duzeyOlcumu?.cancel()
        duzeyOlcumu = Task { [weak self, weak player] in
            while !Task.isCancelled, let self, let player, player.isPlaying {
                player.updateMeters()
                cikisDb = player.averagePower(forChannel: 0)
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            self?.cikisDb = -100
        }
    }
    private func tamamlandiMi() {
        guard bulutIsi == nil, oynatici == nil, hazirSes == nil, kuyruk.isEmpty, !sentez.isSpeaking else { return }
        // Duraklatılmış okuma akış sürerken (yeni cümle bekleniyor) bitmiş sayılmaz: okuma çubuğu kalır.
        if duraklatildi, !akisTamam { return }
        konusuyor = false; baslamaBildirildi = false
        duraklatildi = false; simdiCalan = nil
        if akisTamam { akisTamam = false; bitti?() }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard oynatici === player else { return }
            duzeyOlcumu?.cancel(); duzeyOlcumu = nil; cikisDb = -100
            oynatici = nil
            if hazirSes != nil { oncedenHazirGecisSayisi += 1 }
            if !flag { sesHatasi = "Ses oynatılamadı." }
            siradaki()
        }
    }

    /// Markdown artığı ve okunmayan simgeleri temizler.
    static func okunabilir(_ s: String) -> String {
        var t = (s.components(separatedBy: "\n\nKaynak:").first ?? s).components(separatedBy: "\nKaynaklar:").first ?? s
        // Kod blokları okunmaz; tablo çizgileri ve satır başı liste işaretleri sessizce atılır.
        let kodsuz = t.components(separatedBy: "```").enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        t = kodsuz.joined(separator: " ")
        t = t.components(separatedBy: "\n").filter { $0.range(of: #"^\s*\|?[\s:|-]+\|?\s*$"#, options: .regularExpression) == nil || !$0.contains("|") }.joined(separator: "\n")
        t = t.replacingOccurrences(of: "|", with: ", ")
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\(https?://[^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        for k in ["**", "__", "`", "#"] { t = t.replacingOccurrences(of: k, with: "") }
        t = t.replacingOccurrences(of: "•", with: "")
        t = t.replacingOccurrences(of: "—", with: ",")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            guard !sentez.isSpeaking else { return }
            // Yedek ses biterken bekleyen hazır bulut sesi de çalınsın; kuyruk boşsa siradaki tamamlandiMi'yi çağırır.
            siradaki()
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in tamamlandiMi() }
    }
    /// Okuma çubuğu metni: iPhone sesi bu parçayı okumaya başladı (ana aktöre yalnız String taşınır).
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        let metin = u.speechString
        Task { @MainActor in if konusuyor { simdiCalan = metin } }
    }
}
