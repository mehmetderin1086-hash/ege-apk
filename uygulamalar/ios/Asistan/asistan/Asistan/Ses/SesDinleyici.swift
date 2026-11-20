import Foundation
import AVFoundation
import Speech
import Observation
import UIKit

/// Cihaz içi Türkçe akışlı konuşma tanıma: AVAudioEngine → SpeechAnalyzer + DictationTranscriber (tr_TR).
@MainActor
@Observable
final class SesDinleyici {
    enum Durum: Equatable { case kapali, hazirlaniyor, dinliyor, cozumluyor, hata(String) }

    var hataOlustu: (() -> Void)?
    private(set) var durum: Durum = .kapali {
        didSet { if case .hata = durum { hataOlustu?() } }
    }
    /// Henüz kesinleşmemiş (volatile) + kesinleşmiş metnin birleşimi.
    private(set) var canliMetin = ""
    private(set) var kesinMetin = ""
    /// Son tanınan metin yalnız oturum boyunca tutulur; uyandırma tanısı için kullanılır.
    private(set) var sonTaninanMetin = ""
    /// Kullanıcı sustu, cümle kesinleşti: Apple metni + bu cümlenin ham sesi (Whisper için).
    var metinGuncellendi: ((String) -> Void)?
    var kesinlesti: ((String, [Float], Double) -> Void)?
    let tampon = SesTamponu()
    /// Enerji kapısının en son elediği metin (tanılama).
    private(set) var sonReddedilen: String?
    /// Canlı giriş düzeyi (dBFS) ve mikrofon yolu; şeritte gösterilir.
    private(set) var girisDb: Float = -100
    private(set) var girisYolu = ""
    private var olcumZamanlayici: Task<Void, Never>?
    /// Konuşma başladı (barge-in için).
    var konusmaBasladi: (() -> Void)?

    /// Oturum kayıt kategorisine alındıktan SONRA yaratılır; erken yaratılan motor girişi hiç açmıyordu (14 Eki: tap sessiz, 3 sn'de 0,5 sn).
    private var motor: AVAudioEngine?
    private(set) var tapBicimi = ""
    private var analizci: SpeechAnalyzer?
    private var yaziciDinleme: Task<Void, Never>?
    private var girdiDevam: AsyncStream<AnalyzerInput>.Continuation?
    var otomatikGonder = true
    /// Live modda Apple cümleyi kesinleştirdiğinde ikinci bir sessizlik
    /// sayacı beklemek, ilk sesli cevaba yaklaşık bir saniye ekliyordu.
    /// Bu seçenek yalnız sürekli Live konuşması için açılır; uyandırma ve
    /// eller serbest komutlarda mevcut bekleme penceresi korunur.
    var kesinSonucuHemenGonder = false
    /// Son sesli bloğun zamanı; "söz bitti → ilk ses" ölçümü (`SesTurOlcumu`) okur.
    private(set) var sonSes = Date.distantPast
    private var sesliSure: Double = 0
    var sessizlikMs = 800
    /// P3.12 akıllı konuşma sonu: bekleme `UcNoktasiKarari` ile söze göre (kısa komut 500 ms, virgül/bağlaç 1600 ms).
    /// Uyandırma ve Live'da kapalı (SesOturumu kurar).
    var akilliSon = false
    private var sessizlikZamanlayici: Task<Void, Never>?
    private var konusmaBildirildi = false
    private var baslatmaNesli = 0
    private var kapatmaGorevi: Task<Void, Never>?
    private var kapanisNesli = 0

    static let yerel = Locale(identifier: "tr_TR")

    private var kesintiGozlemcisi: (any NSObjectProtocol)?
    private func kesintiGozlemcisiKur() {
        if kesintiGozlemcisi != nil { return }
        kesintiGozlemcisi = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let tur = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let neden = (n.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init)
            print("[SES] KESİNTİ tür=\(String(describing: tur)) neden=\(String(describing: neden))")
            Task { @MainActor [weak self] in
                guard let self, tur == .began else { return }
                // Kapalıyken ya da TTS sırasında gelen kesinti hata yazmasın (Live'ı/uyandırmayı kapatmasın).
                guard self.durum == .dinliyor || self.durum == .hazirlaniyor else { return }
                let ad: String = switch neden {
                    case .builtInMicMuted: "sistem mikrofonu sessize aldı"
                    case .appWasSuspended: "uygulama askıya alındı"
                    case .routeDisconnected: "ses yolu koptu"
                    default: "başka bir uygulama/sistem mikrofonu aldı"
                }
                await self.durdur()
                self.durum = .hata("Dinleme kesildi: \(ad). Yuvarlağa dokunarak yeniden başlat.")
            }
        }
    }

    // MARK: P3.12 ses yolu değişimi (AirPods takıldı/çıkarıldı)

    private var yolGozlemcisi: (any NSObjectProtocol)?
    /// Yol değişimi yüzünden durdur + başla sürüyor: bekçi hata yazmaz.
    private(set) var yolYenileniyor = false
    private var sonYalnizUyandirma = false
    private var sonYolDegisimi = Date.distantPast
    private var sonYolYenileme = Date.distantPast

    /// Kapanış sistem kuyruğundan gelebilir: @Sendable, ana aktöre yalnız String taşınır.
    private func yolGozlemcisiKur() {
        if yolGozlemcisi != nil { return }
        yolGozlemcisi = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { @Sendable [weak self] n in
            let neden = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            guard neden == .newDeviceAvailable || neden == .oldDeviceUnavailable else { return }
            let ad = neden == .newDeviceAvailable ? "yeni aygıt" : "aygıt çıktı"
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sonYolDegisimi = .now
                await self.yoluYenile(neden: ad)
            }
        }
    }

    /// Dinleme sürerken ses yolu değişti: aynı kipte (uyandırma ya da komut) durdur + başla; `oturumuAyarla` yolu
    /// yeniden seçer (YolSecici). Kendi kategori/giriş ayarımızın yol olayıyla döngü kurmaması için 1,5 sn aralık.
    private func yoluYenile(neden: String, zorla: Bool = false) async {
        guard durum == .dinliyor, !yolYenileniyor else { return }
        guard zorla || Date().timeIntervalSince(sonYolYenileme) > 1.5 else { return }
        yolYenileniyor = true
        defer { yolYenileniyor = false; sonYolYenileme = .now }
        TaniGunlugu.yaz("SES: yol değişti (\(neden)), dinleme yeniden kuruluyor")
        let k = sonYalnizUyandirma
        await durdur()
        await basla(yalnizUyandirma: k)
    }

    static func destekleniyor() async -> Bool {
        let l = await DictationTranscriber.supportedLocales
        return l.contains { $0.identifier(.bcp47).lowercased().hasPrefix("tr") }
    }

    /// `acilis`: ses oturumu etkinleştikten sonra, mikrofon motoru başlamadan önce beklenir ("dinliyorum" işareti).
    /// `onSes` (P4.3): söz kesmenin halka tamponundaki son sesler (mono Float32); tampona ve çözümleyiciye
    /// mikrofondan önce verilir, kullanıcının ilk hecesi kaybolmaz.
    func basla(yalnizUyandirma: Bool = false, acilis: (@MainActor () async -> Void)? = nil,
               onSes: (ornekler: [Float], oran: Double)? = nil) async {
        guard kapatmaGorevi != nil || durum == .kapali || { if case .hata = durum { return true }; return false }() else { return }
        baslatmaNesli += 1
        let buNesil = baslatmaNesli
        // SpeechAnalyzer yeni bir çözümleyici açılırken öncekinin kapanışıyla
        // çakışırsa bazı gerçek cihazlarda ikinci Live turu takılabiliyor.
        // Normalde çok kısa süren kapanışa sınırlı bir pencere ver; Apple
        // çağrısı bozulursa arayüzü süresiz bekletmeden yeni tura geç.
        let beklenenKapanis = baslatmaNesli - 1
        if kapatmaGorevi != nil, kapanisNesli < beklenenKapanis {
            let son = ContinuousClock.now + .milliseconds(700)
            while kapanisNesli < beklenenKapanis, ContinuousClock.now < son {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        // Eski çözümleyicinin girdi akışı ve mikrofon motoru zaten kapalıdır.
        // Apple kapanışı gecikse bile yeni dinlemeyi ona bağlama.
        kapatmaGorevi = nil
        guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
        sonYalnizUyandirma = yalnizUyandirma
        durum = .hazirlaniyor
        canliMetin = ""; kesinMetin = ""; sonTaninanMetin = ""; konusmaBildirildi = false; sonSes = .distantPast; sesliSure = 0
        do {
            let izinVar = await Self.izinler()
            guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
            guard izinVar else { durum = .hata("Mikrofon ya da konuşma tanıma izni yok. Ayarlar > Asistan'dan açın."); return }
            try await SesOturumu.oturumuAyarla()
            if let acilis {
                // İşaret sesi mikrofon motoru başlamadan biter; kendi sesimiz tanımaya karışmaz.
                await acilis()
                guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
            }
            // Uyandırma tek, kısa bir ifadedir; Apple'ın phrase ön ayarı özellikle
            // bu tip çağrılarda ilk sözcüğün düşmesini azaltır. Normal/Live diktesi
            // ise kesintisiz kısa cümle akışı için progressive ayarda kalır.
            let yazici: DictationTranscriber
            if yalnizUyandirma, let dilModeli = await UyandirmaDilModeli.hazirla() {
                yazici = DictationTranscriber(locale: Self.yerel,
                                               contentHints: [.shortForm, .farField, .customizedLanguage(modelConfiguration: dilModeli)],
                                               transcriptionOptions: [],
                                               reportingOptions: [.volatileResults, .frequentFinalization],
                                               attributeOptions: [])
            } else if !yalnizUyandirma, DikteDilModeli.ayarAcik, let dikteModeli = DikteDilModeli.hazirYapilandirma {
                // Kişisel dikte sözlüğü (kişiler + düzeltme defteri; cihaz içi). Hazır değilse beklenmez.
                yazici = DictationTranscriber(locale: Self.yerel,
                                               contentHints: [.shortForm, .customizedLanguage(modelConfiguration: dikteModeli)],
                                               transcriptionOptions: [],
                                               reportingOptions: [.volatileResults, .frequentFinalization],
                                               attributeOptions: [])
            } else {
                yazici = DictationTranscriber(locale: Self.yerel, preset: yalnizUyandirma ? .phrase : .progressiveShortDictation)
            }
            // İlk dinlemede dikte dil modeli arka planda hazırlanır (dinleme bekletilmez; sonraki turlarda kullanılır).
            if !yalnizUyandirma { DikteDilModeli.arkadaHazirla() }
            if let istek = try await AssetInventory.assetInstallationRequest(supporting: [yazici]) {
                try await istek.downloadAndInstall()
            }
            guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
            let analizci = SpeechAnalyzer(modules: [yazici])
            self.analizci = analizci
            let (akis, devam) = AsyncStream<AnalyzerInput>.makeStream()
            girdiDevam = devam
            let motor = AVAudioEngine()
            self.motor = motor
            let giris = motor.inputNode
            let kaynakBicim = giris.outputFormat(forBus: 0)
            tapBicimi = "\(Int(kaynakBicim.sampleRate)) Hz, \(kaynakBicim.channelCount) kanal, \(kaynakBicim.commonFormat.rawValue)"
            // Çözümleyici ve girdi akışı açıldı: hata dalı onları da kapatsın (sızmasın).
            guard kaynakBicim.sampleRate > 0, kaynakBicim.channelCount > 0 else { await durdur(); durum = .hata("Mikrofon girişi yok (biçim 0)."); return }
            // Dönüştürme Speech çerçevesinin kendi dönüştürücüsüyle (akışa uygun); kendi AVAudioConverter kurgum boş/eksik çıktı veriyordu,
            // ham 48 kHz tampon ise AnalyzerInput'ta çöküyordu (14 Eki). Tampon ham girişi saklar; Whisper cümle sonunda 16 kHz'e indirir.
            let donusturucu = try await AnalyzerInputConverter.converter(compatibleWith: [yazici])
            guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
            tampon.ayarla(oran: kaynakBicim.sampleRate, azamiSure: yalnizUyandirma ? 3 : nil)
            let tampon = self.tampon
            nonisolated(unsafe) let donusturucuRef = donusturucu  // yalnız ses iş parçacığında kullanılır
            // P4.3: söz kesmeden gelen ön ses, tap kurulmadan önce tampona (Whisper + enerji kapısı) ve çözümleyiciye verilir.
            // Ön ses zaman damgasızdır; ardından gelen mikrofon tamponları da zamansız (kesintisiz akış) verilir ki
            // motorun 0'dan başlayan zamanı ön sesle çakışmasın. Float32 dışı / iç içe çok kanallı biçimde atlanır.
            var onSesVerildi = false
            if let onSes, let b = Self.onSesTamponu(onSes.ornekler, oran: onSes.oran, bicim: kaynakBicim) {
                tampon.ekle(b)
                if let girdiler = try? donusturucu.convert(b, at: nil) {
                    for g in girdiler { devam.yield(g) }
                    onSesVerildi = true
                }
                TaniGunlugu.yaz("SES: ön ses \(Int(Double(b.frameLength) / kaynakBicim.sampleRate * 1000)) ms\(onSesVerildi ? "" : " (yalnız tampon)")")
            }
            let zamanli = !onSesVerildi
            giris.installTap(onBus: 0, bufferSize: 4096, format: kaynakBicim, block: Self.hamTapBlogu { b, zaman in
                tampon.ekle(b)
                if let girdiler = try? donusturucuRef.convert(b, at: zamanli ? zaman : nil) { for g in girdiler { devam.yield(g) } }
            })
            motor.prepare()
            try motor.start()
            girisYolu = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "giriş yok"
            kesintiGozlemcisiKur()
            yolGozlemcisiKur()
            olcumZamanlayici = Task { [weak self] in
                var sayac = 0
                var sinyal = MikrofonSinyali()
                while let self, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    let e = SesTamponu.enerji(self.tampon.son(0.25))
                    self.girisDb = 20 * log10(max(e.rms, 1e-5))
                    if e.rms > 0.0025 && e.tepe > 0.005 { self.sonSes = Date(); self.sesliSure += 0.05 }
                    sayac += 1
                    // Ses yolu değişince (AirPods, kablolu kulaklık) AVAudioEngine kendini durdurur ve tap susar; tampondaki
                    // eski örnekler aşağıdaki bekçiyi kandırır. Tam durdur + basla için hata yoluna düş (Hey Asistan beklemesi ve
                    // uyandırmayla açılan komut penceresi kendini onarır; Live'da ve elle dinlemede yuvarlağa dokunarak sürer).
                    if sayac % 5 == 0, !self.yolYenileniyor, self.durum == .dinliyor, self.motor?.isRunning != true || self.tampon.sonEklemedenBeri > 1.5 {
                        // P3.12: az önce aygıt takıldı/çıkarıldıysa (AirPods) hata yazılmaz, aynı kipte yeniden kurulur.
                        // Ayrı Task: bu döngü durdur'la iptal edilir, iptal edilmiş görevde basla erken döner.
                        if Date().timeIntervalSince(self.sonYolDegisimi) < 3 {
                            Task { @MainActor [weak self] in await self?.yoluYenile(neden: "motor durdu", zorla: true) }
                            return
                        }
                        await self.durdur()
                        self.durum = .hata("Ses yolu değişti; dinleme durdu. Yuvarlağa dokunarak yeniden başlat.")
                        return
                    }
                    if sayac % 5 == 0, !self.yolYenileniyor, self.durum == .dinliyor, sinyal.engelli(tepe: e.tepe) {
                        // P3.12 kutudaki AirPods tuzağı: HFP girişi sıfır geliyorsa 5 dk dahili mikrofona dönülür, hata yazılmaz.
                        if AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType == .bluetoothHFP {
                            YolSecici.hfpYasakla(dakika: 5)
                            Task { @MainActor [weak self] in await self?.yoluYenile(neden: "kulaklık mikrofonu sessiz", zorla: true) }
                            return
                        }
                        await self.durdur()
                        self.durum = .hata("Mikrofondan ses gelmiyor. Mac'teki iPhone Ekran Yansıtma veya Device Hub ekran paylaşımını kapatıp yeniden dene. Mikrofon başka bir görüşmede kullanılıyorsa önce o görüşmeyi bitir.")
                        return
                    }
                    if sayac % 20 == 0 {
                        let o = AVAudioSession.sharedInstance()
                        print("[SES] uygulama=\(UIApplication.shared.applicationState.rawValue)(0=ön) tampon=\(String(format: "%.2f", self.tampon.sure))sn rms=\(e.rms) tepe=\(e.tepe) yol=\(o.currentRoute.inputs.first?.portName ?? "-")/\(o.inputDataSource?.dataSourceName ?? "-") digerSes=\(o.isOtherAudioPlaying) prompt=\(o.promptStyle.rawValue) kazanc=\(o.inputGain) motor=\(self.motor?.isRunning ?? false)")
                    }
                }
            }
            try await analizci.start(inputSequence: akis)
            guard buNesil == baslatmaNesli, !Task.isCancelled else { return }
            yaziciDinleme = Task { [weak self] in
                do {
                    for try await sonuc in yazici.results {
                        guard let self, !Task.isCancelled, buNesil == self.baslatmaNesli else { return }
                        let metin = String(sonuc.text.characters)
                        self.sonucGeldi(metin, kesin: sonuc.isFinal)
                    }
                } catch {
                    guard let self, !Task.isCancelled, buNesil == self.baslatmaNesli else { return }
                    await self.durdur()
                    self.durum = .hata("Tanıma durdu: \(error.localizedDescription)")
                }
            }
            durum = .dinliyor
        } catch {
            // Bayat başlatma: araya giren durdur kaynakları zaten temizledi; yeni oturuma ve duruma dokunma.
            guard buNesil == baslatmaNesli else { return }
            await durdur()
            durum = .hata("Dinleme başlatılamadı: \(error.localizedDescription)")
        }
    }

    private func sonucGeldi(_ metin: String, kesin: Bool) {
        sonTaninanMetin = metin
        if kesin {
            kesinMetin = (kesinMetin + " " + metin).trimmingCharacters(in: .whitespaces)
            canliMetin = kesinMetin
        } else {
            canliMetin = (kesinMetin + " " + metin).trimmingCharacters(in: .whitespaces)
        }
        metinGuncellendi?(canliMetin)
        if !konusmaBildirildi, !canliMetin.isEmpty {
            konusmaBildirildi = true
            konusmaBasladi?()
        }
        sessizlikZamanlayici?.cancel()
        guard otomatikGonder else { return }
        if kesin, kesinSonucuHemenGonder, !canliMetin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = gonder(elle: false)
            return
        }
        let bekleme = akilliSon ? UcNoktasiKarari.bekleme(metin: canliMetin, taban: sessizlikMs) : sessizlikMs
        sessizlikZamanlayici = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(bekleme)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            // Yeni tanıma gelmese de kullanıcı konuşuyorsa cümleyi ortadan kesme.
            let beklemeBasi = Date()
            while Date().timeIntervalSince(self.sonSes) < 0.55 && Date().timeIntervalSince(beklemeBasi) < 2 {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard !Task.isCancelled else { return }
            }
            self.gonder(elle: false)
        }
    }

    /// Durdur kaydı siler; gönder mevcut dikteyi tam bir kez teslim eder.
    @discardableResult func gonder(elle: Bool = true) -> Bool {
        guard durum == .dinliyor else { return false }
        let son = canliMetin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !son.isEmpty else { return false }
        sessizlikZamanlayici?.cancel()
        let ornekler = tampon.al()
        let kabul = elle || sesliSure >= 0.15 || SesTamponu.konusmaVar(ornekler, oran: tampon.oran, metin: son)
        kesinMetin = ""; canliMetin = ""; konusmaBildirildi = false; sesliSure = 0
        guard kabul else {
            // Ortam konuşmasını/hayali tanıma metnini bekleme ekranına sızdırma.
            sonReddedilen = "Ses çok kısık. Biraz yaklaşarak tekrar söyle."
            return false
        }
        sonReddedilen = nil
        // Kişisel düzeltme defteri ("mitos" → "mitoz"); uygulanmış metin süzgecin yalnız sesli istekte öğrenmesi için saklanır.
        let defter = DikteDuzeltmeDefteri.ortak
        let duzeltilmis = DikteDilModeli.ayarAcik ? defter.uygula(son) : son
        defter.sonDikte = duzeltilmis
        kesinlesti?(duzeltilmis, ornekler, tampon.oran)
        return true
    }

    #if DEBUG
    /// Deterministik birim sınaması: mikrofon/izin açmadan gerçek sonuç işleyicisini sürer.
    func sinamaSonucu(_ metin: String, kesin: Bool = false) {
        guard ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1" else { return }
        durum = .dinliyor
        // Gerçek konuşmada enerji kapısı burada zaten açılmış olur. Test
        // girdisi ses tamponu taşımadığından aynı kabul koşulunu temsil eder.
        sesliSure = 0.2
        sonucGeldi(metin, kesin: kesin)
    }
    #endif

    /// Whisper çözümlerken arayüz "çözümlüyor" göstersin.
    func cozumluyor(_ acik: Bool) {
        if acik, durum == .kapali || durum == .dinliyor { durum = .cozumluyor }
        else if !acik, durum == .cozumluyor { durum = .kapali }
    }

    /// Ses girişini hemen bırakır. Apple çözümleyicisinin ağır kapanışı arka
    /// planda sürer; kullanıcı arayüzü ve bir sonraki Live turu bunu beklemez.
    func durdur() async {
        #if DEBUG
        let liveTani = ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama")
        if liveTani { print("[LIVE-TANI] dinleyici durdur başladı") }
        #endif
        baslatmaNesli += 1
        if kapatmaGorevi != nil {
            // Kaynaklar önceki çağrıda bırakıldı; sonradan yazılan hata/ara durum
            // ikinci kapatma isteğinde ekranda açık kalmamalı.
            durum = .kapali
            return
        }
        sessizlikZamanlayici?.cancel()
        olcumZamanlayici?.cancel(); olcumZamanlayici = nil
        yaziciDinleme?.cancel()
        girdiDevam?.finish(); girdiDevam = nil
        if let motor {
            #if DEBUG
            if liveTani { print("[LIVE-TANI] tap kaldırılıyor") }
            #endif
            motor.inputNode.removeTap(onBus: 0)
            #if DEBUG
            if liveTani { print("[LIVE-TANI] tap kaldırıldı; motor durduruluyor") }
            #endif
            if motor.isRunning { motor.stop() }
            #if DEBUG
            if liveTani { print("[LIVE-TANI] motor durdu") }
            #endif
        }
        motor = nil
        let kapanacak = analizci
        analizci = nil
        canliMetin = ""; kesinMetin = ""; sonReddedilen = nil
        _ = tampon.al()
        durum = .kapali
        // Yeni başlatma eski çözümleyicinin kapanmasını bekler; eski kapanış yeni motoru silemez.
        let kapanacakNesil = baslatmaNesli
        let gorev = Task { [weak self] in
            await Self.analizciyiKapat(kapanacak)
            guard let self else { return }
            self.kapanisNesli = max(self.kapanisNesli, kapanacakNesil)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") {
                print("[LIVE-TANI] çözümleyici kapanışı tamamlandı nesil=\(kapanacakNesil)")
            }
            #endif
        }
        kapatmaGorevi = gorev
        #if DEBUG
        if liveTani { print("[LIVE-TANI] çözümleyici kapanışı başlatıldı") }
        #endif
    }

    /// SpeechAnalyzer'ın kapanışı bazı cihaz/OS birleşimlerinde uzun sürebiliyor.
    /// Ana aktörden çıkarılması, ses arayüzü ve model akışının donmasını önler.
    @concurrent nonisolated private static func analizciyiKapat(_ analizci: SpeechAnalyzer?) async {
        if let analizci { await analizci.cancelAndFinishNow() }
    }

    /// Sistem geri çağrıları arka plan kuyruğunda gelir: kapanış ana aktöre bağlı kalırsa çalışma anında çöker.
    /// `@concurrent`: approachable concurrency'de nonisolated async işlev çağıranın aktöründe koşar; burada koşmamalı.
    @concurrent nonisolated static func izinler() async -> Bool {
        let mik = await AVAudioApplication.requestRecordPermission()
        guard mik else { return false }
        return await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { @Sendable durum in c.resume(returning: durum == .authorized) }
        }
    }

    /// P4.3: ön sesi (mono Float32, `oran` Hz) mikrofon biçiminde bir PCM tampona çevirir; her kanala aynı ses yazılır.
    /// Boş ses, Float32 dışı ya da iç içe (interleaved) çok kanallı biçimde nil döner (ön ses atlanır).
    nonisolated static func onSesTamponu(_ o: [Float], oran: Double, bicim: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !o.isEmpty, oran > 0, bicim.sampleRate > 0, bicim.channelCount > 0, bicim.commonFormat == .pcmFormatFloat32,
              !bicim.isInterleaved || bicim.channelCount == 1 else { return nil }
        let y = SesTamponu.yenidenOrnekle(o, kaynakOran: oran, hedefOran: bicim.sampleRate)
        guard !y.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: bicim, frameCapacity: AVAudioFrameCount(y.count)),
              let kanallar = b.floatChannelData else { return nil }
        b.frameLength = AVAudioFrameCount(y.count)
        y.withUnsafeBufferPointer { p in
            guard let kaynak = p.baseAddress else { return }
            for c in 0..<Int(bicim.channelCount) { kanallar[c].update(from: kaynak, count: y.count) }
        }
        return b
    }

    /// Tap bloğu ana aktör dışında kurulur ki örtük yalıtım almasın; ses iş parçacığında çalışır, dönüştürme yapmaz.
    nonisolated static func hamTapBlogu(_ teslim: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) -> AVAudioNodeTapBlock {
        return { tampon, zaman in
            nonisolated(unsafe) let tampon = tampon
            nonisolated(unsafe) let zaman = zaman
            if tampon.frameLength > 0 { teslim(tampon, zaman) }
        }
    }
}
