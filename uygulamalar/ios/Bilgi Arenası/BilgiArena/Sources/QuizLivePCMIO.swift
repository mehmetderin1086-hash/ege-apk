// Adapted from Asistan/Ses/CanliSesIO.swift for the quiz; no assistant services or server routing.
import AVFoundation
import Foundation

/// Tam çift yönlü Live sesi: 16 kHz Int16 mikrofon, 24 kHz Int16 model çıkışı.
final class QuizLivePCMIO: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private let oynatici = AVAudioPlayerNode()
    private let cikis = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private let giris: AVAudioFormat
    private let kilit = NSLock()
    private var girisSeviyesi: Float = -100
    private var cikisSeviyesi: Float = -100
    /// Ses yolu değişince tap yeni donanım biçimiyle yeniden kurulur; teslim kapanışı bunun için saklanır.
    private var parcaTeslim: (@Sendable (Data) -> Void)?
    private var gozlemciler: [any NSObjectProtocol] = []
    private var durduruldu = false
    /// Kesinti (alarm, Siri, arama) sürüyor: motor sistemce durduruldu, bitişte `hattiYenile` devam ettirir.
    private var askida = false
    /// Oynatma isteğinden doğan yeniden başlatma denemesi kuyrukta (her ses parçası ayrı deneme açmasın).
    private var denemeSirada = false
    private var kesildiGeriCagrisi: (@Sendable (String) -> Void)?
    /// Yapılandırma değişimi ve kesinti olayları sırayla işlenir (aynı anda iki yeniden kurulum olmasın).
    private let olayKuyrugu: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q }()

    /// Ses yolu değişimi/kesintiden sonra hat yeniden kurulamadıysa çağrılır (herhangi bir iş parçacığında).
    var kesildi: (@Sendable (String) -> Void)? {
        get { kilit.withLock { kesildiGeriCagrisi } }
        set { kilit.withLock { kesildiGeriCagrisi = newValue } }
    }

    /// `girisHz`: mikrofondan modele giden örnekleme (Gemini 16 kHz, OpenAI Realtime 24 kHz).
    init(girisHz: Double = 16_000) {
        giris = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: girisHz, channels: 1, interleaved: true)!
    }

    var girisDb: Float { kilit.withLock { girisSeviyesi } }
    var cikisDb: Float { kilit.withLock { cikisSeviyesi } }

    func baslat(parca: @escaping @Sendable (Data) -> Void) throws {
        // Bekleyen bir ses oturumu bırakma isteği bu Live sesini kapatmasın.
        let oturum = AVAudioSession.sharedInstance()
        try oturum.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try oturum.setPreferredSampleRate(48_000)
        try oturum.setActive(true)
        // P3.12: kategori .voiceChat + HFP kalır; yalnız giriş seçilir (kulaklık yasaklıysa/HFP yoksa dahili, kablolu varsa o).
        try? motor.inputNode.setVoiceProcessingEnabled(true)
        motor.attach(oynatici)
        motor.connect(oynatici, to: motor.mainMixerNode, format: cikis)
        // Ağdan peşin gelen PCM'nin değil, gerçekten çalınan sesin düzeyi.
        oynatici.installTap(onBus: 0, bufferSize: 1024, format: cikis) { [weak self] tampon, _ in
            guard let self, let kanal = tampon.floatChannelData?[0] else { return }
            let db = Self.desibel(UnsafeBufferPointer(start: kanal, count: Int(tampon.frameLength)))
            self.kilit.withLock { if !self.durduruldu && !self.askida { self.cikisSeviyesi = db } }
        }
        kilit.withLock { parcaTeslim = parca; durduruldu = false; askida = false; denemeSirada = false }
        try hattiKur()
        gozlemcileriKur()
    }

    /// Mikrofon tap'ini o anki donanım biçimiyle (yeniden) kurar ve motoru başlatır. Ses yolu değişince
    /// (AirPods/HFP ↔ hoparlör) biçim değişir; eski biçimli tap ile yeniden başlatmak uyuşmazlık istisnası verebilir.
    private func hattiKur() throws {
        let teslim = kilit.withLock { () -> (@Sendable (Data) -> Void)? in parcaTeslim }
        guard let parca = teslim else { return }
        let mikrofon = motor.inputNode
        mikrofon.removeTap(onBus: 0)
        let kaynak = mikrofon.outputFormat(forBus: 0)
        guard kaynak.sampleRate > 0, kaynak.channelCount > 0,
              let yeni = AVAudioConverter(from: kaynak, to: giris) else {
            throw NSError(domain: "CanliSes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mikrofon ses biçimi kullanılamıyor."])
        }
        // Her tap kendi dönüştürücüsünü taşır: eski biçimli geç bir tampon yeni dönüştürücüye girmez.
        let donusturucu = yeni   // yalnız ses iş parçacığında kullanılır
        mikrofon.installTap(onBus: 0, bufferSize: 2048, format: kaynak) { [weak self] tampon, _ in self?.isle(tampon, donusturucu: donusturucu, parca: parca) }
        motor.prepare(); try motor.start(); oynatici.play()
        kilit.withLock { askida = false }
    }

    /// Yapılandırma değişimi (motor kendini durdurur) ve kesinti bitişi için gözlemciler. Kapanışlar
    /// sistem iş parçacığında çalışır; sınıf aktör dışı olduğundan ana aktöre bağlanmaz.
    private func gozlemcileriKur() {
        let merkez = NotificationCenter.default
        let degisim = merkez.addObserver(forName: .AVAudioEngineConfigurationChange, object: motor, queue: olayKuyrugu) { [weak self] _ in
            self?.hattiYenile(neden: "Ses yolu değişti, Live sesi yeniden başlatılamadı.")
        }
        let kesinti = merkez.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: olayKuyrugu) { [weak self] n in
            let tur = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            // Başlangıçta motor durur (oynatma istekleri bekler); bitişte devam edilir.
            if tur == .began {
                self?.kilit.withLock { self?.askida = true; self?.girisSeviyesi = -100; self?.cikisSeviyesi = -100 }
                return
            }
            guard tur == .ended else { return }
            let secenek = AVAudioSession.InterruptionOptions(rawValue: (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
            let neden = "Live sesi bir kesintiyle durdu."
            guard secenek.contains(.shouldResume), (try? AVAudioSession.sharedInstance().setActive(true)) != nil else {
                self?.kesildiBildir(neden); return
            }
            self?.hattiYenile(neden: neden)
        }
        kilit.withLock { gozlemciler = [degisim, kesinti] }
    }

    /// `neden` nil ise (oynatma isteğinden doğan deneme) başarısızlık bildirilmez: kesinti/ses yolu gözlemcileri karar verir.
    private func hattiYenile(neden: String?) {
        guard !kilit.withLock({ durduruldu }) else { return }
        if motor.isRunning { return }   // biçim değişmeden gelen bildirim: hat çalışıyor
        do { try hattiKur() } catch { if let neden { kesildiBildir(neden) } }
    }

    enum OynatmaKarari: Equatable { case cal, yenidenBaslat, vazgec }
    /// Durmuş motorda `AVAudioPlayerNode.play()` NSException ile çöker (saf mantık): motor çalışıyorsa çalınır;
    /// durmuşsa ve kesinti sürmüyorsa yeniden başlatma denenir; kesintide ya da kapanışta sessizce vazgeçilir.
    static func oynatmaKarari(motorCalisiyor: Bool, askida: Bool, durduruldu: Bool) -> OynatmaKarari {
        if durduruldu { return .vazgec }
        if motorCalisiyor { return .cal }
        return askida ? .vazgec : .yenidenBaslat
    }

    /// Oynatıcıyı yalnız motor çalışırken başlatır. Motor durmuşsa yeniden kurulum seri olay kuyruğunda denenir
    /// (tap yeni donanım biçimiyle kurulur, ardından `hattiKur` oynatıcıyı kendisi başlatır); olmazsa sessizce vazgeçilir.
    /// Kuyruktaki tamponlar korunur.
    private func oynaticiyiBaslat() {
        let (askidaMi, durdurulduMu) = kilit.withLock { (askida, durduruldu) }
        switch Self.oynatmaKarari(motorCalisiyor: motor.isRunning, askida: askidaMi, durduruldu: durdurulduMu) {
        case .cal: if !oynatici.isPlaying { oynatici.play() }
        case .vazgec: break
        case .yenidenBaslat:
            let ekle = kilit.withLock { () -> Bool in
                guard !denemeSirada else { return false }
                denemeSirada = true; return true
            }
            guard ekle else { return }
            olayKuyrugu.addOperation { [weak self] in
                guard let self else { return }
                self.kilit.withLock { self.denemeSirada = false }
                hattiYenile(neden: nil)
            }
        }
    }

    private func kesildiBildir(_ neden: String) {
        let geri = kilit.withLock { () -> (@Sendable (String) -> Void)? in durduruldu ? nil : kesildiGeriCagrisi }
        guard let geri else { return }
        geri(neden)
    }

    func durdur() {
        let eskiler = kilit.withLock { () -> [any NSObjectProtocol] in
            durduruldu = true; kesildiGeriCagrisi = nil; parcaTeslim = nil
            let g = gozlemciler; gozlemciler = []; return g
        }
        for g in eskiler { NotificationCenter.default.removeObserver(g) }
        // Sürmekte olan bir yeniden kurulum motoru durdurduktan sonra yeniden başlatmasın.
        olayKuyrugu.cancelAllOperations(); olayKuyrugu.waitUntilAllOperationsAreFinished()
        motor.inputNode.removeTap(onBus: 0); oynatici.removeTap(onBus: 0); oynatici.stop(); motor.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        kilit.withLock { girisSeviyesi = -100; cikisSeviyesi = -100 }
    }

    func oynat(_ veri: Data) {
        let adet = veri.count / 2
        guard adet > 0, let tampon = AVAudioPCMBuffer(pcmFormat: cikis, frameCapacity: AVAudioFrameCount(adet)) else { return }
        tampon.frameLength = AVAudioFrameCount(adet)
        let hedef = tampon.floatChannelData![0]
        veri.withUnsafeBytes { ham in
            let ornekler = ham.bindMemory(to: Int16.self)
            for i in 0..<adet { hedef[i] = Float(Int16(littleEndian: ornekler[i])) / 32768 }
        }
        oynatici.scheduleBuffer(tampon)
        oynaticiyiBaslat()
    }

    /// Kuyruğu temizler (oynatıcıyı durdurmak motor dursa da güvenlidir); yeniden başlatma motora bağlıdır.
    func yanitiKes() { oynatici.stop(); oynaticiyiBaslat(); kilit.withLock { cikisSeviyesi = -100 } }

    /// Kuyruktaki model sesi çalınıp bitince (ya da oynatıcı durdurulunca) `geri` çağrılır; herhangi bir iş parçacığında.
    /// Motor çalışmıyorsa beklenmez, hemen çağrılır.
    func calinincaBildir(_ geri: @escaping @Sendable () -> Void) {
        guard motor.isRunning, !kilit.withLock({ durduruldu }),
              let sessiz = AVAudioPCMBuffer(pcmFormat: cikis, frameCapacity: 1),
              let kanal = sessiz.floatChannelData?[0] else { geri(); return }
        sessiz.frameLength = 1; kanal[0] = 0
        oynatici.scheduleBuffer(sessiz, completionCallbackType: .dataPlayedBack) { _ in geri() }
        oynaticiyiBaslat()
    }

    private func isle(_ tampon: AVAudioPCMBuffer, donusturucu: AVAudioConverter, parca: @escaping @Sendable (Data) -> Void) {
        if let kanal = tampon.floatChannelData?[0] {
            let db = Self.desibel(UnsafeBufferPointer(start: kanal, count: Int(tampon.frameLength)))
            kilit.withLock { if !durduruldu && !askida { girisSeviyesi = db } }
        }
        let kapasite = AVAudioFrameCount(Double(tampon.frameLength) * giris.sampleRate / tampon.format.sampleRate + 32)
        guard let cikti = AVAudioPCMBuffer(pcmFormat: giris, frameCapacity: kapasite) else { return }
        var kullanildi = false; var hata: NSError?
        donusturucu.convert(to: cikti, error: &hata) { _, durum in
            if kullanildi { durum.pointee = .noDataNow; return nil }
            kullanildi = true; durum.pointee = .haveData; return tampon
        }
        guard hata == nil, cikti.frameLength > 0, let ornek = cikti.int16ChannelData?[0] else { return }
        parca(Data(bytes: ornek, count: Int(cikti.frameLength) * 2))
    }

    /// Ses iş parçacığında tahsis yapmadan RMS ölçer; bozuk örnek animasyonu zehirlemez.
    static func desibel(_ ornekler: UnsafeBufferPointer<Float>) -> Float {
        guard !ornekler.isEmpty else { return -100 }
        var toplam: Double = 0
        for ornek in ornekler {
            guard ornek.isFinite else { return -100 }
            let f = Double(ornek)
            toplam += f * f
        }
        let guc = toplam / Double(ornekler.count)
        return guc > 0 ? Float(max(-100, min(0, 10 * log10(guc)))) : -100
    }
}
