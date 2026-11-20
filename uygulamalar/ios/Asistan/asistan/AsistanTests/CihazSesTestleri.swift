import Testing
import Foundation
import AVFoundation
import Speech
import CallKit
@testable import Asistan

/// Gerçek cihazda/simülatörde Türkçe STT hattı: sistem TTS ile Türkçe ses dosyası üret → DictationTranscriber tr_TR ile yazıya dök.
/// Mikrofon gerektirmez. ASISTAN_SES=1 ile koşar (model indirme yapabilir).
@Suite("Cihaz ses hattı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_SES"] == "1"))
@MainActor
struct CihazSesTestleri {
    /// Eski sürümde burası arka plan kuyruğunda EXC_BREAKPOINT ile çöküyordu (MainActor'a bağlı kapanış).
    @Test(.timeLimit(.minutes(1))) func izinIstegiCokmez() async {
        let sonuc = await SesDinleyici.izinler()
        print("İZİN SONUCU: \(sonuc)")
    }

    /// Gerçek mikrofon: motor + tap + analizci başlar, 3 sn çalışır, durur. Çökme ve durum geçişi denetlenir.
    @Test(.timeLimit(.minutes(2))) func mikrofonlaDinlemeBaslarVeDurur() async throws {
        let d = SesDinleyici()
        await d.basla()
        print("DİNLEYİCİ DURUM: \(d.durum)")
        #expect(d.durum == .dinliyor)
        try await Task.sleep(for: .seconds(3))
        #expect(d.durum == .dinliyor)
        let sure = d.tampon.sure
        let e = SesTamponu.enerji(d.tampon.al())
        print("MİKROFON TAMPONU: \(String(format: "%.2f", sure)) sn, rms \(e.rms), tepe \(e.tepe), yol: \(d.girisYolu), girişler: \(AVAudioSession.sharedInstance().availableInputs?.map(\.portName) ?? []), oturum: \(AVAudioSession.sharedInstance().sampleRate) Hz, tap: \(d.tapBicimi), kategori: \(AVAudioSession.sharedInstance().category.rawValue)")
        #expect(sure > 2.0, "tampon dolmadı")
        #expect(e.tepe > 0, "mikrofon tam sıfır veriyor")
        await d.durdur()
        #expect(d.durum == .kapali)
    }

    @Test func turkceDestekleniyor() async {
        #expect(await SesDinleyici.destekleniyor())
        #expect(Konusmaci.turkceSes != nil)
    }

    @Test(.timeLimit(.minutes(5)))
    func ttsSonraSttTurkce() async throws {
        let cumle = "Yarın saat on dörtte diş hekimi randevum var."
        let dosya = FileManager.default.temporaryDirectory.appending(path: "stt-\(UUID().uuidString).caf")
        try await Self.seslendir(cumle, dosya)
        let yazici = DictationTranscriber(locale: SesDinleyici.yerel, preset: .shortDictation)
        if let istek = try await AssetInventory.assetInstallationRequest(supporting: [yazici]) {
            try await istek.downloadAndInstall()
        }
        let analizci = SpeechAnalyzer(modules: [yazici])
        let ses = try AVAudioFile(forReading: dosya)
        print("SES DOSYASI: \(ses.length) kare, \(ses.fileFormat.sampleRate) Hz, \(Double(ses.length) / ses.fileFormat.sampleRate) sn, biçim \(ses.processingFormat)")
        #expect(ses.length > 8000)
        let toplama = Task { () -> String in
            var son = ""; var sayi = 0; var sonVolatile = ""
            for try await r in yazici.results {
                sayi += 1
                let t = String(r.text.characters)
                if r.isFinal { son += t + " " } else { sonVolatile = t }
                print("STT SONUÇ #\(sayi) final=\(r.isFinal): \(t)")
            }
            return son.isEmpty ? sonVolatile : son
        }
        try await analizci.start(inputAudioFile: ses, finishAfterFile: true)
        try await analizci.finalizeAndFinishThroughEndOfInput()
        let metin = try await toplama.value.lowercased()
        print("STT ÇIKTISI: \(metin)")
        #expect(metin.contains("diş") || metin.contains("dis"))
        #expect(metin.contains("randevu"))
        #expect(metin.contains("yarın") || metin.contains("yarin"))
    }

    /// AVSpeechSynthesizer.write ile PCM tamponları dosyaya yazar.
    static func seslendir(_ metin: String, _ hedef: URL) async throws {
        let sentez = AVSpeechSynthesizer()
        let u = AVSpeechUtterance(string: metin)
        u.voice = Konusmaci.turkceSes
        var dosya: AVAudioFile?
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            nonisolated(unsafe) var bitti = false
            sentez.write(u) { tampon in
                guard let pcm = tampon as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !bitti { bitti = true; c.resume() }
                    return
                }
                do {
                    if dosya == nil { dosya = try AVAudioFile(forWriting: hedef, settings: pcm.format.settings) }
                    try dosya?.write(from: pcm)
                } catch { if !bitti { bitti = true; c.resume(throwing: error) } }
            }
        }
        dosya = nil
    }
}

/// Gerçek OpenAI (VPS aktarıcısı) ile Türkçe döküm. ASISTAN_SES=1 ile.
@Suite("Whisper canlı", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_WHISPER"] == "1"))
@MainActor
struct WhisperCanliTestleri {
    @Test(.timeLimit(.minutes(2))) func ttsSonraWhisper() async throws {
        try #require(WhisperIstemcisi.kullanilabilir)
        let dosya = FileManager.default.temporaryDirectory.appending(path: "w-\(UUID().uuidString).caf")
        try await CihazSesTestleri.seslendir("Yarın saat on dörtte diş hekimi randevum var, hatırlatıcı koy.", dosya)
        let f = try AVAudioFile(forReading: dosya)
        let hedef = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let giris = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: giris)
        let d = AVAudioConverter(from: f.processingFormat, to: hedef)!
        let cikti = AVAudioPCMBuffer(pcmFormat: hedef, frameCapacity: AVAudioFrameCount(Double(f.length) * 16000 / f.processingFormat.sampleRate) + 16)!
        var verildi = false
        var hata: NSError?
        d.convert(to: cikti, error: &hata) { _, s in if verildi { s.pointee = .endOfStream; return nil }; verildi = true; s.pointee = .haveData; return giris }
        let ornekler = Array(UnsafeBufferPointer(start: cikti.floatChannelData![0], count: Int(cikti.frameLength)))
        let t0 = Date()
        let metin = try await WhisperIstemcisi.cozumle(ornekler: ornekler, oran: 16000, ipucu: SesOturumu.whisperIpucu)
        print("WHISPER ÇIKTISI (\(String(format: "%.1f", Date().timeIntervalSince(t0))) sn): \(metin)")
        let k = metin.lowercased()
        #expect(k.contains("diş") && k.contains("randevu") && k.contains("hatırlat"))
    }
}

/// Telefonda WhisperKit: modeli indirir (ilk seferde dakikalar), TTS dosyasını çözer, süreyi yazar. ASISTAN_YEREL_WHISPER=<model adı> ile.
@Suite("Yerel Whisper canlı", .enabled(if: !(ProcessInfo.processInfo.environment["ASISTAN_YEREL_WHISPER"] ?? "").isEmpty))
@MainActor
struct YerelWhisperCanliTestleri {
    @Test(.timeLimit(.minutes(20))) func indirYukleCoz() async throws {
        let model = ProcessInfo.processInfo.environment["ASISTAN_YEREL_WHISPER"]!
        if ProcessInfo.processInfo.environment["ASISTAN_YEREL_SIL"] == "1" { YerelWhisper.sil(model) }
        print("YEREL WHISPER MODEL: \(model) indirilmiş=\(YerelWhisper.indirilmis(model)) hesap=\(ProcessInfo.processInfo.environment["ASISTAN_YEREL_HESAP"] ?? "varsayılan")")
        let w = YerelWhisper()
        let t0 = Date()
        w.hazirla(model: model)
        while !w.hazir, Date().timeIntervalSince(t0) < 1100 {
            if case .hata(let h) = w.durum { Issue.record("hazırlama hatası: \(h)"); return }
            try await Task.sleep(for: .milliseconds(500))
        }
        try #require(w.hazir, "model \(model) hazır olmadı: \(w.durum)")
        print("YEREL WHISPER HAZIR: \(model), \(String(format: "%.0f", Date().timeIntervalSince(t0))) sn")
        let dosya = FileManager.default.temporaryDirectory.appending(path: "yw-\(UUID().uuidString).caf")
        try await CihazSesTestleri.seslendir("Yarın saat on dörtte diş hekimi randevum var, hatırlatıcı koy.", dosya)
        let f = try AVAudioFile(forReading: dosya)
        let hedef = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let giris = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: giris)
        let d = AVAudioConverter(from: f.processingFormat, to: hedef)!
        let cikti = AVAudioPCMBuffer(pcmFormat: hedef, frameCapacity: AVAudioFrameCount(Double(f.length) * 16000 / f.processingFormat.sampleRate) + 16)!
        var verildi = false; var hata: NSError?
        d.convert(to: cikti, error: &hata) { _, s in if verildi { s.pointee = .endOfStream; return nil }; verildi = true; s.pointee = .haveData; return giris }
        let ornekler = Array(UnsafeBufferPointer(start: cikti.floatChannelData![0], count: Int(cikti.frameLength)))
        for tur in 1...2 {
            let t1 = Date()
            let metin = try await w.cozumle(ornekler)
            print("YEREL WHISPER ÇIKTI #\(tur) (\(String(format: "%.1f", Date().timeIntervalSince(t1))) sn, ses \(String(format: "%.1f", Double(ornekler.count) / 16000)) sn): \(metin)")
            if tur == 2 {
                let k = metin.lowercased()
                #expect(k.contains("diş") && k.contains("randevu"), "çıktı: \(metin)")
            }
        }
    }
}

/// Motorsuz tanı: AVAudioRecorder ölçerle mikrofon düzeyi. Test ortamında mikrofon gerçekten susuyor mu?
@Suite("Mikrofon ham tanı", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_SES"] == "1"))
@MainActor
struct MikrofonTaniTestleri {
    @Test(.timeLimit(.minutes(1))) func kayitciDuzeyi() async throws {
        try await SesOturumu.oturumuAyarla()
        let url = FileManager.default.temporaryDirectory.appending(path: "tani-\(UUID().uuidString).m4a")
        let k = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
        k.isMeteringEnabled = true
        #expect(k.record())
        var enYuksek: Float = -160
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(200))
            k.updateMeters()
            enYuksek = max(enYuksek, k.averagePower(forChannel: 0))
        }
        k.stop()
        let boyut = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("KAYITÇI: en yüksek ortalama güç \(enYuksek) dB, dosya \(boyut) bayt, izin: \(AVAudioApplication.shared.recordPermission.rawValue), diğer ses çalıyor: \(AVAudioSession.sharedInstance().isOtherAudioPlaying), giriş var: \(AVAudioSession.sharedInstance().isInputAvailable), kazanç: \(AVAudioSession.sharedInstance().inputGain) ayarlanabilir: \(AVAudioSession.sharedInstance().isInputGainSettable), kaynaklar: \(AVAudioSession.sharedInstance().inputDataSources?.map(\.dataSourceName) ?? []), seçili: \(AVAudioSession.sharedInstance().inputDataSource?.dataSourceName ?? "-"), gizlilik kısıtı: \(AVAudioSession.sharedInstance().currentRoute.inputs.first?.hasHardwareVoiceCallProcessing ?? false)")
        #expect(enYuksek > -100)
    }
}

/// Geri besleme tanısı: hoparlörden TTS çalarken mikrofon kaydeder. Sıfır kalıyorsa mikrofon sistemce kapalı.
@Suite("Mikrofon geri besleme", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_SES"] == "1"))
@MainActor
struct GeriBeslemeTestleri {
    static func olc(_ etiket: String, kategori: AVAudioSession.Category, kip: AVAudioSession.Mode, secenek: AVAudioSession.CategoryOptions, konus: Bool) async throws -> Float {
        let o = AVAudioSession.sharedInstance()
        try o.setCategory(kategori, mode: kip, options: secenek)
        try o.setActive(true)
        let url = FileManager.default.temporaryDirectory.appending(path: "gb-\(UUID().uuidString).wav")
        let k = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
        k.isMeteringEnabled = true
        #expect(k.record())
        let sentez = AVSpeechSynthesizer()
        if konus {
            let u = AVSpeechUtterance(string: "Bir iki üç dört beş altı yedi sekiz dokuz on. Yarın saat on dörtte diş hekimi randevum var.")
            u.voice = Konusmaci.turkceSes; u.volume = 1
            sentez.speak(u)
        }
        var enYuksek: Float = -160
        for _ in 0..<16 {
            try await Task.sleep(for: .milliseconds(250))
            k.updateMeters(); enYuksek = max(enYuksek, k.averagePower(forChannel: 0))
        }
        sentez.stopSpeaking(at: .immediate)
        let kaydediyordu = k.isRecording
        k.stop()
        // Dosyanın gerçek enerjisi (ölçerden bağımsız); 0 kare = donanım hiç örnek vermedi
        let f = try AVAudioFile(forReading: url)
        var ornekler: [Float] = []
        if f.length > 0, let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) {
            try f.read(into: b)
            ornekler = Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength)))
        }
        let e = SesTamponu.enerji(ornekler)
        print("GERİ BESLEME [\(etiket)] kayıt sürüyordu=\(kaydediyordu) kare=\(f.length)")
        print("GERİ BESLEME [\(etiket)] konuş=\(konus): ölçer en yüksek \(enYuksek) dB, dosya rms \(e.rms) tepe \(e.tepe) (\(ornekler.count / 16000) sn), girişSessiz=\(AVAudioApplication.shared.isInputMuted), yol=\(o.currentRoute.inputs.first?.portName ?? "-")→\(o.currentRoute.outputs.first?.portName ?? "-")")
        try? o.setActive(false, options: .notifyOthersOnDeactivation)
        return e.tepe
    }

    @Test(.timeLimit(.minutes(3))) func hoparlordenMikrofona() async throws {
        // Neyin tuttuğu: aktif çağrılar (telefon/FaceTime/VoIP), istem stili, kesinti bildirimleri
        let cagrilar = CXCallObserver().calls
        print("ÇAĞRILAR: \(cagrilar.count) → \(cagrilar.map { "giden=\($0.isOutgoing) bağlı=\($0.hasConnected) bitti=\($0.hasEnded) beklemede=\($0.isOnHold)" })")
        let o = AVAudioSession.sharedInstance()
        print("OTURUM: promptStyle=\(o.promptStyle.rawValue) (0=normal,1=short,2=none→çağrı/Siri var) ikincilSessiz=\(o.secondaryAudioShouldBeSilencedHint) izin=\(AVAudioApplication.shared.recordPermission.rawValue) girişSessiz=\(AVAudioApplication.shared.isInputMuted)")
        let gozlem = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { n in
            let tur = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let neden = (n.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init)
            print("KESİNTİ: tür=\(String(describing: tur)) neden=\(String(describing: neden)) (4=builtInMicMuted)")
        }
        defer { NotificationCenter.default.removeObserver(gozlem) }
        let a = try await Self.olc("playAndRecord/default/speaker", kategori: .playAndRecord, kip: .default, secenek: [.defaultToSpeaker], konus: true)
        let b = try await Self.olc("record/measurement", kategori: .record, kip: .measurement, secenek: [], konus: false)
        let c = try await Self.olc("playAndRecord/voiceChat", kategori: .playAndRecord, kip: .voiceChat, secenek: [.defaultToSpeaker], konus: true)
        let d = try await Self.olc("record/default sessiz", kategori: .record, kip: .default, secenek: [], konus: false)
        print("GERİ BESLEME ÖZET tepe: playAndRecord=\(a) record=\(b) voiceChat=\(c) sessizKayit=\(d)")
        #expect(max(a, b, c, d) > 0, "mikrofon her kategoride tam sıfır: sistem düzeyinde kapalı")
    }
}

/// Mikrofon kaynakları: Alt / Ön / Arka tek tek. Alt ölü, ön/arka canlı ise donanım arızası ve çözüm kaynak değiştirmek.
@Suite("Mikrofon kaynakları", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_SES"] == "1"))
@MainActor
struct MikrofonKaynakTestleri {
    @Test(.timeLimit(.minutes(3))) func kaynaklariOlc() async throws {
        let o = AVAudioSession.sharedInstance()
        try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try o.setActive(true)
        guard let port = o.availableInputs?.first(where: { $0.portType == .builtInMic }) else { Issue.record("dahili mikrofon yok"); return }
        try o.setPreferredInput(port)
        var sonuc: [String: Float] = [:]
        for ds in port.dataSources ?? [] {
            do { try port.setPreferredDataSource(ds); try o.setInputDataSource(ds) } catch { print("KAYNAK \(ds.dataSourceName): seçilemedi \(error)") ; continue }
            let url = FileManager.default.temporaryDirectory.appending(path: "k-\(UUID().uuidString).wav")
            let k = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
            k.isMeteringEnabled = true
            _ = k.record()
            let sentez = AVSpeechSynthesizer()
            let u = AVSpeechUtterance(string: "Bir iki üç dört beş altı yedi sekiz dokuz on.")
            u.voice = Konusmaci.turkceSes; u.volume = 1
            sentez.speak(u)
            var enYuksek: Float = -160
            for _ in 0..<12 { try await Task.sleep(for: .milliseconds(250)); k.updateMeters(); enYuksek = max(enYuksek, k.averagePower(forChannel: 0)) }
            sentez.stopSpeaking(at: .immediate); k.stop()
            let f = try AVAudioFile(forReading: url)
            var tepe: Float = 0
            if f.length > 0, let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) {
                try f.read(into: b); tepe = SesTamponu.enerji(Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength)))).tepe
            }
            sonuc[ds.dataSourceName] = tepe
            print("KAYNAK \(ds.dataSourceName) (yön: \(ds.orientation?.rawValue ?? "-")): kare=\(f.length) ölçer=\(enYuksek) dB tepe=\(tepe) seçili=\(o.inputDataSource?.dataSourceName ?? "-")")
        }
        print("KAYNAK ÖZET: \(sonuc)")
        #expect(sonuc.values.contains { $0 > 0 }, "üç mikrofon da sıfır")
    }
}
