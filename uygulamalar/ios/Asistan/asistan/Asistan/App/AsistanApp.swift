import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct AsistanApp: App {
    @UIApplicationDelegateAdaptor(IndirmeAppDelegate.self) private var indirmeDelegate
    @Environment(\.scenePhase) private var sahne
    // Varsayılan değer yok: init her yolda bir kez kurar (göçler ve disk okuması iki kez yapılmasın).
    @State private var ayarlar: Ayarlar
    @State private var kisiselAlan: KisiselAlan
    @State private var beyin: Beyin
    @State private var sesOturumu: SesOturumu
    @State private var onay: OnayKapisi
    private let kap: ModelContainer

    init() {
        let kap = HafizaDeposu.paylasilanKap
        self.kap = kap
        IzlemeAbonesi.ortak.baslat()
        // Hangi derlemenin açıldığı tani.log'da görünsün (yalnız sürüm kimliği; kullanıcı metni yok). Test barındırıcısında atlanır.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            TaniGunlugu.yaz("AÇILIŞ: sürüm \(SurumBilgisi.simdiki.uzun)")
        }
        BeceriDeposu.hazirBecerileriYukle()
        BeceriDeposu.kaldirilanHazirlariGizle()
        NabizMotoru.kaydol { UserDefaults.standard.integer(forKey: "ayar.nabizDakikaV1") }
        // P4.4: fotoğraf metni indeksi (BGProcessing; Info.plist izni yoksa ya da testte kaydolmaz).
        FotoIndeksi.kaydol()
        let ayarlar: Ayarlar
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--asistan-ui-onizleme") {
            let defaults = UserDefaults(suiteName: "asistan.ui-preview")!
            ayarlar = Ayarlar(defaults: defaults)
            ayarlar.gorunum = .init()
            let args = ProcessInfo.processInfo.arguments
            // UI testleri model etiketi/eylem satırı gibi öğeleri sınar: önizleme Claude temasıyla açılır; `--karma` varsayılan Karma'yı gösterir.
            if !args.contains("--karma") { ayarlar.gorunum.sohbet = .claude; ayarlar.gorunum.renk = SohbetTemaAyarlari.vurgu("Claude") }
            // Hazır görünüm seti yalnız sohbet temalarıdır. `--rahat` geriye uyum için kabul edilir ve
            // bir şey değiştirmez (UI testleri bu bayrakla açılır; Claude teması kalmalı).
            if args.contains("--gece") { ayarlar.gorunum.sohbet = .gece; ayarlar.gorunum.renk = SohbetTemaAyarlari.vurgu("Gece") }
            if args.contains("--calisma") { ayarlar.gorunum.sohbet = .sade; ayarlar.gorunum.renk = SohbetTemaAyarlari.vurgu("Sade") }
            if args.contains("--buyukyazi") { ayarlar.gorunum.yaziOlcegi = 1.4 }
            if args.contains("--dalga") { ayarlar.gorunum.gosterge = .cubuklar; ayarlar.gorunum.zemin = .noktalar }
            _kisiselAlan = State(initialValue: KisiselAlan(dosya: FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).json")))
        } else if SahteModelSunucusu.etkin {
            // P3.10 hermetik UI testi: her açılışta temiz, geçici ayar alanı. Varsayılanlar (Elif, Claude Live,
            // Antigravity önceliği, tema) değiştirilmez; yalnız ses/uyandırma/otomatik hafıza bu geçici alanda kapanır.
            let defaults = UserDefaults(suiteName: "asistan.ui-sahte")!
            defaults.removePersistentDomain(forName: "asistan.ui-sahte")
            ayarlar = Ayarlar(defaults: defaults)
            ayarlar.sesliYanit = false; ayarlar.heyAsistan = false; ayarlar.otomatikHafiza = false
            // UI testleri model etiketi/eylem satırını sınar: sahte kipte Claude teması (Karma bunları gizler); `--karma` Karma'yı açar.
            if !ProcessInfo.processInfo.arguments.contains("--karma") { ayarlar.gorunum.sohbet = .claude; ayarlar.gorunum.renk = SohbetTemaAyarlari.vurgu("Claude") }
            _kisiselAlan = State(initialValue: KisiselAlan(dosya: FileManager.default.temporaryDirectory.appending(path: "sahte-\(UUID().uuidString).json")))
        } else { ayarlar = Ayarlar(ortak: OrtakAyarlar.suite); _kisiselAlan = State(initialValue: KisiselAlan()) }
        HermetikKip.uygula()
        #else
        // P4.2: yalnız gerçek açılış App Group'u verir (Hey Asistan kontrolüyle paylaşım); önizleme/sahte kip vermez.
        ayarlar = Ayarlar(ortak: OrtakAyarlar.suite)
        _kisiselAlan = State(initialValue: KisiselAlan())
        #endif
        let depo = HafizaDeposu(baglam: kap.mainContext)
        let onay = OnayKapisi()
        // Mehmet, açık komutlarda uygulama, medya, kestirme, arama ve mesaj için
        // Asistan'ın ikinci kez onay istememesini seçti. iOS'un kendi zorunlu
        // sistem ekranları (ör. SMS gönderim sayfası) bundan bağımsızdır.
        onay.otomatikKarar = true
        let beyin = Beyin(ayarlar: ayarlar, depo: depo, onay: onay)
        _ayarlar = State(initialValue: ayarlar)
        _onay = State(initialValue: onay)
        _beyin = State(initialValue: beyin)
        let ses = SesOturumu(beyin: beyin, ayarlar: ayarlar)
        _sesOturumu = State(initialValue: ses)
        // P2.14: Live Activity "Durdur" (IsiDurdurIntent, uygulama sürecinde) süren işi keser; iş yoksa köprü etkinliği kendisi kapatır.
        // P4.2: bas-konuş ya da arka plan Live mikrofonu dinliyorsa Durdur onu da kapatır (etkinliği kendisi bitirir).
        IsKoprusu.durdurKancasi = { [weak beyin, weak ses] in
            if let ses, ses.arkaPlanDinlemesiVar {
                Task { await ses.arkaPlanDinlemesiniDurdur() }
                return true
            }
            guard let beyin, beyin.durum != .bosta else { return false }
            beyin.iptal()
            return true
        }
        // P4.2: bas-konuş (AsistanBasKonusIntent, uygulamayı açmadan): dinlemeyi başlatıp hemen döner.
        BasKonusKoprusu.kanca = { [weak ses] in try await ses?.basKonusBaslat() }
        // P3.9: termal durum / Düşük Güç değişince uyandırma beklemesi ve yerel sunucu bekçisi yeniden ayarlanır
        // (scenePhase burada okunamaz; TelefonProxy son bekçi durumunu kendisi tutar).
        GucPolitikasi.ortak.degisti = { [weak ses] k in
            TelefonProxy.ortak.bekciYenile()
            guard let ses else { return }
            Task { await ses.gucPolitikasiDegisti(k.uyandirmaAcik) }
        }
        AcilisOlcer.isaretle("init")
    }

    var body: some Scene {
        WindowGroup {
            SohbetEkrani()
                // Hafıza normal açılmadıysa (kurtarma, bellek içi kap, geri yükleme) üstte şerit.
                .safeAreaInset(edge: .top, spacing: 0) { HafizaAcilisSeridi() }
                .environment(ayarlar)
                .environment(kisiselAlan)
                .preferredColorScheme(ayarlar.gorunum.renkSemasi)
                .tint(ayarlar.gorunum.vurgu)
                .hermetikAnimasyon()   // P3.10: yalnız `--animasyonsuz` kipinde etkili
                .environment(beyin)
                .environment(sesOturumu)
                .environment(onay)
                .modelContainer(kap)
                .onOpenURL { url in
                    // Kestirmeler'in sistem köprüsü dönüşü (x-callback): bekleyen ayar çağrısına sonucu verir.
                    if SistemKoprusu.ortak.geriDonus(url) { return }
                    switch AsistanBaglantisi.coz(url) {
                    case .dinle:
                        // P2.4: Kontrol Merkezi / Siri / Eylem düğmesi açılışı; Kurulum durumu bunu okur.
                        UserDefaults.standard.set(true, forKey: KurulumDurumu.tetikAnahtari)
                        sesOturumu.disTetikGeldi()
                    case .live:
                        Task { await sesOturumu.canliModuAc() }
                    case .canliKamera:
                        // P4.2 kipli kontrol: Live açılır, ardından (Live sürüyor ve kamera kullanılabiliyorsa) kamera.
                        Task {
                            await sesOturumu.canliModuAc()
                            if sesOturumu.mod == .live, !sesOturumu.kameraAcik { await sesOturumu.kameraDegistir() }
                        }
                    case .devam:
                        // P4.2 kipli kontrol: açık sohbet boşsa son sohbet açılır (asistan meşgulken değiştirilmez), sonra dinlenir.
                        if beyin.durum == .bosta, beyin.mesajlar.isEmpty, let s = beyin.depo.sonSohbetler(1).first { beyin.sohbetiAc(s) }
                        sesOturumu.disTetikGeldi()
                    case .ekran(let hedef):
                        AsistanGezgin.ortak.ac(hedef)
                    case .taslak(let metin):
                        beyin.disTaslak = metin
                    case .sor(let metin):
                        // Dış bağlantı (başka uygulama, web, QR): dış kaynaklı tur; yan etkili adımlar sorulur.
                        // Siri, Kestirmeler ve tetik bildirimleri bu bağlantıyı değil `.asistanSor` yolunu kullanır.
                        // Asistan meşgulse istek kısa sırada bekler (en çok 2 dk; Durdur / Yeni sohbet sırayı bırakır).
                        // "/yeni" gibi eğik çizgi metinleri yerel komut olarak çalışmaz, dış kaynaklı tur olarak gider.
                        DisSoruKuyrugu.ortak.ekle(metin, beyin: beyin)
                    case .paylasim:
                        PaylasimAlici.isle(beyin)
                    case .sohbet(let k):
                        // P2.14: yalnız var olan sohbeti açar (yan etkisiz); asistan meşgulse süren iş bölünmez.
                        let d = FetchDescriptor<Sohbet>(predicate: #Predicate { $0.kimlik == k })
                        if beyin.durum == .bosta, let s = try? kap.mainContext.fetch(d).first { beyin.sohbetiAc(s) }
                    case .hizli(let no):
                        // P3.11: Hızlı sor widget'ı. Metin uygulamaya gömülü sabit istemdir, ama bağlantıyı widget'ın
                        // dokunuşundan ayırt etmenin yolu yok (Safari / başka uygulama da açabilir): dış kaynaklı tur sayılır,
                        // yan etkili adımlar sorulur. Widget'tan gelen istek için de onay sorulabilir (bilinçli ödün).
                        if let m = DersGunu.hizliIstem(no) { DisSoruKuyrugu.ortak.ekle(m, beyin: beyin) }
                    case nil:
                        break
                    }
                }
                // P4.4: Spotlight sonucuna dokunuş (OpenIntent çalışmazsa yedek yol). Yalnız var olan sohbeti açar ya da
                // indirilen dosya için İndirmeler'i gösterir; yan etkisiz, asistan meşgulken sohbet değiştirilmez.
                .onContinueUserActivity(CSSearchableItemActionType) { etkinlik in
                    guard let k = AsistanSpotlight.kimlikAyikla(etkinlik.userInfo?[CSSearchableItemActivityIdentifier] as? String) else { return }
                    let d = FetchDescriptor<Sohbet>(predicate: #Predicate { $0.kimlik == k })
                    if let s = try? kap.mainContext.fetch(d).first {
                        if beyin.durum == .bosta { beyin.sohbetiAc(s) }
                    } else if IndirmeYoneticisi.ortak.kayitlar.contains(where: { $0.id == k }) {
                        AsistanGezgin.ortak.ac(.indirmeler)
                    }
                }
                // Yerel Whisper açılışta yüklenmez: Core ML model derlemesi bazı modellerde çöküyor (14 Eki); kullanıcı Ayarlar'dan indirir.
                .task {
                AcilisOlcer.isaretle("ilk_kare")   // P3.9: soğuk açılış ölçümü (Sağlık → 'Açılış')
                IndirmeYoneticisi.ortak.baslat()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--asistan-test-verisi-temizle") {
                        AsistanSinama.testVerisiniTemizle()
                        return
                    }
                    // P3.10 hermetik kip: yalnız sahte model sunucusu ve model listesi; uyandırma, Gömlemci, ses ısıtma atlanır.
                    if SahteModelSunucusu.etkin { await TelefonProxy.ortak.hazirla(); await TelefonProxy.ortak.sina(); return }
                    if ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1" { return }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-kopru-dogrulandi") {
                        UygulamaKatalogu.ortak.kopruEklendi = true
                        await AsistanSinama.dosyaKopruSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-ui-onizleme") {
                        if ProcessInfo.processInfo.arguments.contains("--cekmece-ornek") { beyin.cekmeceOrnegiHazirla(); beyin.arayuzProva() } else if ProcessInfo.processInfo.arguments.contains("--ek-kartlari") { beyin.arayuzProvaEkler() } else if ProcessInfo.processInfo.arguments.contains("--zengin") { beyin.arayuzProvaZengin() } else if ProcessInfo.processInfo.arguments.contains("--kuyruk-ornek") { beyin.arayuzProvaKuyruk() } else if ProcessInfo.processInfo.arguments.contains("--sohbet") { beyin.arayuzProva() }
                        return
                    }
                    #endif
                    // P3.11: widget anlığı (36 sa ders/etkinlik) açılışta yazılır; takvim değişince kendiliğinden tazelenir.
                    WidgetYenileyici.baslat(); WidgetYenileyici.takvimdenYaz()
                    // P4.7: CarPlay ses yolu izlenir; sürüş kipi Beyin/SesOturumu/belge araçlarınca okunur.
                    SurusKipi.ortak.baslat(ayarlar: ayarlar, ses: sesOturumu)
                    await TelefonProxy.ortak.hazirla()
                    AcilisOlcer.isaretle("proxy_hazir")
                    // İlk konuşmayı bekletmeden model listesini ve seçilebilir bulut
                    // seslerini ısıt. Böylece otomatik vites ilk istekte varsayımsal
                    // aday denemek yerine bağlı CLIProxy modellerini kullanır.
                    // P3.9: liste önbellekten dolu başlar; ağa yalnız önbellek bayatsa (6 sa) ya da hesap sayısı değiştiyse gidilir.
                    // Açılışta tek model listesi turu vardır (aşağıdaki ikinci koşullu tur kaldırıldı).
                    Task { await TelefonProxy.ortak.sinaGerekirse() }
                    Task { await AsistanSesleri.ortak.yenile() }
                    // P4.6: bildirim izni varsa ve sunucu görevleri açıksa APNs jetonu istenir (izin burada sorulmaz).
                    Task { await SunucuGorevleri.uzakBildirimeKaydol(sunucuGorevleriAcik: ayarlar.sunucuGorevleri) }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-live-ses-sinama") {
                        await AsistanSinama.liveSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-otomatik") {
                        await sesOturumu.uyandirmayiEtkinlestir()
                        try? await Task.sleep(for: .seconds(2))
                        let prova = Konusmaci()
                        prova.soyle("Hey asistan")
                        var ilkUyandi = false
                        for _ in 0..<140 {
                            if sesOturumu.sesliKip && !sesOturumu.uyandirmaBekliyor { ilkUyandi = true; break }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        let sonuc: [String: Any] = ["uyandi": sesOturumu.sesliKip && !sesOturumu.uyandirmaBekliyor, "ilkUyandi": ilkUyandi, "bekliyor": sesOturumu.uyandirmaBekliyor, "dinleyici": String(describing: sesOturumu.dinleyici.durum), "db": sesOturumu.dinleyici.girisDb, "sonTaninanMetin": sesOturumu.dinleyici.sonTaninanMetin]
                        let dosya = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "asistan-uyandirma-otomatik.json")
                        if let veri = try? JSONSerialization.data(withJSONObject: sonuc, options: .prettyPrinted) { try? veri.write(to: dosya, options: .atomic) }
                        prova.sustur()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-yetenek-sinama") {
                        await TelefonProxy.ortak.sina()
                        let sonuc: [String: Any] = ["modeller": TelefonProxy.ortak.modeller.map(\.id), "anaModel": ayarlar.modelKimligi, "uyandirmaCumlesi": Uyandirma.komut("Hey Asistan, saat kaç?") ?? "hata"]
                        let dosya = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "asistan-yetenek-sinama.json")
                        if let veri = try? JSONSerialization.data(withJSONObject: sonuc, options: .prettyPrinted) { try? veri.write(to: dosya, options: .atomic) }
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-hiz-kabul") {
                        await AsistanSinama.hizKabulSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-ilk-metin-sinama") {
                        await AsistanSinama.ilkMetinSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-indirme-sinama") {
                        await AsistanSinama.indirmeSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-kazima-sinama") {
                        await AsistanSinama.kazimaSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-son-istek-sinama") {
                        await AsistanSinama.sonIstekSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-ofis-sinama") {
                        AsistanSinama.ofisSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-donusturme-sinama") {
                        AsistanSinama.donusturmeSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-arsiv-sinama") {
                        AsistanSinama.arsivSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-grok-yetenekleri-sinama") {
                        await AsistanSinama.grokYetenekleriSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-gelen-kutusu-sinama") {
                        AsistanSinama.gelenKutusuSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-hiz-sinama") {
                        await AsistanSinama.hizSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-caba-sinama") {
                        await AsistanSinama.cabaSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-ses-akis-sinama") {
                        await AsistanSinama.sesAkisiSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-ses-sinama") {
                        await AsistanSinama.sesSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-sunucu-sinama") {
                        await AsistanSinama.sunucuSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-live-baglanti-sinama") {
                        await AsistanSinama.liveBaglantiSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-otomatik-sinama") {
                        await AsistanSinama.otomatikSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-web-yeni") {
                        await AsistanSinama.webYeniSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-web-sinama") {
                        await AsistanSinama.webHamSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-atolye-sinama") {
                        await AsistanSinama.atolyeyiSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-modeller-sinama") {
                        await AsistanSinama.modelleriSina()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--asistan-sinama") {
                        await AsistanSinama.calistir()
                        return
                    }
                    #endif
                    // O4: önceki süreçten kalan Siri / tetik devri (uygulama gönderemeden kapandı): bir saat içindekiler iç sırayla
                    // gönderilir (kullanıcının kendisi sayılır), eskileri gönderilmez, kullanıcıya not gösterilir.
                    let siriKalanlar = GorevKopru.ortak.kutu.eskiler()
                    for m in siriKalanlar.gonderilecek { DisSoruKuyrugu.ic.ekle(m, beyin: beyin) }
                    if let notMetni = SiriSoruKutusu.dusmeNotu(siriKalanlar.dusen) {
                        beyin.sonHata = [beyin.sonHata, notMetni].compactMap { $0 }.joined(separator: "\n")
                    }
                    await sesOturumu.uyandirmayiBaslat()
                    // P3.9: bakım açılışı ve ilk isteği bekletmez: ~4 sn sonra ve Asistan boştayken (en çok 30 sn daha beklenir).
                    Task(priority: .utility) {
                        try? await Task.sleep(for: .seconds(4))
                        var bekleme = 0
                        while beyin.durum != .bosta, bekleme < 30 { try? await Task.sleep(for: .seconds(1)); bekleme += 1 }
                        // Hafıza bakımı: eski olguları kategorile, arama indeksini tamamla (artımlı), günde bir yinelenenleri birleştir.
                        beyin.depo.eskiOlgulariZenginlestir()
                        await beyin.depo.indeksiSenkronla()
                        let bugun = KullanimDefteri.gunAnahtari(.now)
                        if UserDefaults.standard.string(forKey: "hafiza.bakim") != bugun {
                            let n = beyin.depo.yinelenenleriBirlestir()
                            let dolan = beyin.depo.suresiDolanlariTemizle()
                            UserDefaults.standard.set(bugun, forKey: "hafiza.bakim")
                            if n > 0 { TaniGunlugu.yaz("HAFIZA BAKIMI: \(n) yinelenen olgu birleştirildi") }
                            if dolan > 0 { TaniGunlugu.yaz("HAFIZA BAKIMI: \(dolan) süresi dolan olgu silindi") }
                        }
                        // Günde bir tutarlı hafıza yedeği (Yedekler/, son 7); arka planda, açılışı bekletmez.
                        HafizaDeposu.gunlukYedegiBaslat()
                        // Anlamsal hafıza (vekil bge-m3) açıksa eksik gömmeleri tamamla; cihaz içi NL gömme varlığı indirilmez.
                        if UzakGomlemci.etkin { await beyin.depo.vektorleriTamamla(); await beyin.depo.mesajVektorleriniTamamla() }
                        // P4.4: Spotlight sohbet indeksi yalnız sürüm anahtarı değişince (ilk açılışta) baştan yazılır.
                        AsistanSpotlight.tamYenile(depo: beyin.depo)
                    }
                }
                .onChange(of: sahne) { _, yeni in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--asistan-hiz-kabul") || ProcessInfo.processInfo.arguments.contains("--asistan-ilk-metin-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-hiz-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-caba-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-ses-akis-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-ui-onizleme") || ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") || ProcessInfo.processInfo.arguments.contains("--asistan-live-ses-sinama") || SahteModelSunucusu.etkin { return }
                    #endif
                    Task {
                        // Planlama kaydet/sil ile aynı zincirde: eşzamanlı iki planlama silinen tetiğin bildirimini geri kurmasın.
                        // Kişisel alan cihaz kilitliyken okunamadıysa öne gelişte yeniden okunur.
                        if yeni == .active { WidgetYenileyici.takvimdenYaz(); kisiselAlan.yenidenDene(); await sesOturumu.onPlanDegisti(true)
                            // P4.2: Kontrol Merkezi'ndeki Hey Asistan anahtarı değiştiyse ses kipi ona uyar (Live sürerken bölünmez).
                            if ayarlar.ortaktanEsitle(), sesOturumu.mod != .live { await sesOturumu.modSec(ayarlar.heyAsistan ? .ellerSerbest : .normal) }
                            TelefonProxy.ortak.bekciAyarla(aktif: true); await TelefonProxy.ortak.zorlaDogrula(); await TetikDeposu.ortak.planlaSirayla().value; PaylasimAlici.isle(beyin) }
                        else if yeni == .inactive {
                            // Live'ın kilit ekranı etkinliği yalnız ön plandayken açılabilir: arka plana geçmeden hemen önce kurulur.
                            sesOturumu.arkaPlanaGeciliyor()
                        }
                        else if yeni == .background {
                            TelefonProxy.ortak.bekciAyarla(aktif: false); await sesOturumu.onPlanDegisti(false); NabizMotoru.planla(dakika: ayarlar.nabizDakika)
                            // P4.4: indirilen dosyalar Spotlight'ta güncellenir; fotoğraf metni indeksi şarjda çalışmak üzere planlanır.
                            AsistanSpotlight.dosyalariYenile(IndirmeYoneticisi.ortak.kayitlar)
                            FotoIndeksi.planla(acik: ayarlar.fotoMetinIndeksi)
                        }
                    }
                }
        }
    }
}

/// Dış `asistan://sor` istekleri: asistan meşgulken kaybolmasın diye kısa bir sırada bekler, Beyin boşalınca
/// sırayla gönderilir. `ortak` sırasındakiler dış kaynaklı tur sayılır (`disKaynak: true`): yan etkili adımlar kullanıcıya sorulur;
/// "/yeni", "/model x" gibi eğik çizgi metinleri de yerel komut olarak çalışmaz, dış kaynaklı tur olarak modele gider.
/// Dış sıra kısa ömürlüdür (`disEnUzunBekleme`) ve araya Durdur / Yeni sohbet girerse bırakılır: bağlamdan kopuk bir
/// dış istek sonradan kendiliğinden çalışmaz.
/// `ic` sırası süreç içi `.asistanSor` yolu içindir (Siri devri, kullanıcının kendi tetik bildirimi): kullanıcının kendisi sayılır;
/// süresi dolan iç istek sessizce düşmez, kullanıcıya söylenir.
/// İki sıra da Asistan'ı `sessizlik` boyunca kesintisiz boşta görmeden göndermez: kullanıcının o an hazırladığı mesaj
/// (görsel küçültme, sesli kipin kapanışı) önce `gonder`e ulaşsın, sıranın isteği onu düşürmesin.
@MainActor
final class DisSoruKuyrugu {
    static let ortak = DisSoruKuyrugu()
    /// Siri / tetik bildirimi sırası: dış kaynaklı tur değildir (`disKaynak: false`).
    static let ic = DisSoruKuyrugu(disKaynak: false)
    nonisolated static let enFazla = 3
    /// İç sırada bir istek en çok bu kadar bekler (eklendiği andan sayılır); süresi dolan kullanıcıya bildirilir.
    nonisolated static let enUzunBekleme: Duration = .seconds(600)
    /// Dış sırada bir istek en çok bu kadar bekler, sonra sessizce bırakılır (kısa ömürlü).
    nonisolated static let disEnUzunBekleme: Duration = .seconds(120)
    /// Gönderimden önce Asistan'ın kesintisiz boşta görülmesi gereken süre.
    nonisolated static let sessizlik: Duration = .milliseconds(1500)
    /// Durdur / Yeni sohbet sonrası iç sıranın beklediği süre: söz kesen sesli komut (Whisper dökümü) önce gelsin.
    nonisolated static let mudahaleSessizligi: Duration = .seconds(8)
    nonisolated static let yoklamaAraligi: Duration = .milliseconds(500)
    private(set) var bekleyenler: [String] = []
    private var eklenme: [String: ContinuousClock.Instant] = [:]
    /// Süresi dolan iç istekler: Asistan boşalınca kullanıcıya söylenir.
    private var dusenler: [String] = []
    private var bekci: Task<Void, Never>?
    private var kusak = 0
    private let disKaynak: Bool

    init(disKaynak: Bool = true) { self.disKaynak = disKaynak }

    private var omur: Duration { disKaynak ? DisSoruKuyrugu.disEnUzunBekleme : DisSoruKuyrugu.enUzunBekleme }

    /// Saf: yeni istek sıranın sonuna eklenir; boş ya da yinelenen eklenmez, taşarsa en eskisi düşer.
    nonisolated static func sirala(_ metin: String, _ kuyruk: [String]) -> [String] {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !kuyruk.contains(t) else { return kuyruk }
        return Array((kuyruk + [t]).suffix(enFazla))
    }

    /// Saf: dış kaynaktan gelen eğik çizgi komutu ("/yeni", "/model opus") yerel komut olarak çalışmasın;
    /// metin normal, dış kaynaklı bir tur olarak modele gitsin (yan etkili her adım onaydan geçer).
    nonisolated static func komutuEtkisizlestir(_ metin: String) -> String {
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SlashKomutlari.coz(t) != nil else { return metin }
        return "Dış kaynaktan gelen metin (yerel komut olarak çalıştırılmadı): " + t
    }

    /// Saf: ömrünü aşmış istekler (yaşı bilinmeyen istek dolmuş sayılmaz).
    nonisolated static func suresiDolanlar(_ kuyruk: [String], yaslar: [String: Duration], omur: Duration) -> [String] {
        kuyruk.filter { (yaslar[$0] ?? .zero) > omur }
    }

    /// Saf: süresi dolan iç istekler için kullanıcıya gösterilecek not.
    nonisolated static func dusmeNotu(_ l: [String]) -> String? {
        guard let ilk = l.first else { return nil }
        let alinti = "“\(ilk.prefix(60))”"
        if l.count == 1 { return "Asistan uzun süre meşgul kaldığı için sıradaki isteğin gönderilemedi: \(alinti). Yeniden söyleyebilirsin." }
        return "Asistan uzun süre meşgul kaldığı için sıradaki \(l.count) isteğin gönderilemedi (ilki: \(alinti)). Yeniden söyleyebilirsin."
    }

    /// Bekçinin yoklamalar arasında taşıdığı gözlem (saf karar için).
    nonisolated struct Gozlem: Equatable, Sendable {
        /// Asistan'ın kesintisiz boşta görüldüğü ilk an (bekçinin başlangıcına göre).
        var bostaBaslangic: Duration?
        /// Son görülen `Beyin.nesil`.
        var nesil: Int
        /// Durdur / Yeni sohbet (ya da bekçinin görmediği bir tur) sonrası: daha uzun sessizlik beklenir.
        var mudahaleSonrasi = false
    }
    nonisolated enum Karar: Equatable, Sendable { case bekle, gonder, disIstekleriBirak }

    /// Saf: bir yoklamadaki karar. Asistan `sessizlik` boyunca kesintisiz boşta görülünce `gonder`.
    /// `Beyin.nesil` bekçi Asistan'ı meşgul görmeden değiştiyse ve Asistan boştaysa araya Durdur / Yeni sohbet girmiştir
    /// (`iptal` ve `yeniSohbet` nesli artırır, olağan bitiş artırmaz): dış istekler bırakılır, iç istekler daha uzun bekler.
    nonisolated static func karar(_ g: inout Gozlem, simdi: Duration, bosta: Bool, nesil: Int, disKaynak: Bool) -> Karar {
        if nesil != g.nesil {
            g.nesil = nesil
            guard bosta else { g.bostaBaslangic = nil; g.mudahaleSonrasi = false; return .bekle }
            if disKaynak { g.bostaBaslangic = nil; return .disIstekleriBirak }
            g.bostaBaslangic = simdi; g.mudahaleSonrasi = true
            return .bekle
        }
        guard bosta else { g.bostaBaslangic = nil; g.mudahaleSonrasi = false; return .bekle }
        guard let b = g.bostaBaslangic else { g.bostaBaslangic = simdi; return .bekle }
        guard simdi - b >= (g.mudahaleSonrasi ? mudahaleSessizligi : sessizlik) else { return .bekle }
        g.bostaBaslangic = nil; g.mudahaleSonrasi = false
        return .gonder
    }

    /// Sırayı ve bekçiyi açıkça temizler (ör. Durdur / Yeni sohbet yolundan çağrılabilir; dış sıra bunu bekçide kendisi de algılar).
    func bosalt() {
        kusak += 1
        bekci?.cancel(); bekci = nil
        bekleyenler = []; eklenme = [:]; dusenler = []
    }

    func ekle(_ metin: String, beyin: Beyin) {
        let simdi = ContinuousClock.now
        bekleyenler = Self.sirala(disKaynak ? Self.komutuEtkisizlestir(metin) : metin, bekleyenler)
        for m in bekleyenler where eklenme[m] == nil { eklenme[m] = simdi }
        eklenme = eklenme.filter { bekleyenler.contains($0.key) }
        guard bekci == nil, !bekleyenler.isEmpty else { return }
        let k = kusak
        let koken = simdi
        bekci = Task {
            // Kuruluşta Asistan boştaysa beklemeden gönderilir (bağlantı uygulamayı dışarıdan açtı; yazılan bir mesaj yok).
            var g = Gozlem(bostaBaslangic: beyin.durum == .bosta ? Duration.zero - DisSoruKuyrugu.sessizlik : nil, nesil: beyin.nesil)
            while self.kusak == k, !Task.isCancelled, !self.bekleyenler.isEmpty || !self.dusenler.isEmpty {
                let an = ContinuousClock.now
                // Önce süre sınırı: uygulama askıdan dönünce ömrünü aşmış istek gönderilmesin.
                let dolan = DisSoruKuyrugu.suresiDolanlar(self.bekleyenler, yaslar: self.eklenme.mapValues { an - $0 }, omur: self.omur)
                if !dolan.isEmpty {
                    self.bekleyenler.removeAll { dolan.contains($0) }
                    for m in dolan { self.eklenme[m] = nil }
                    if !self.disKaynak {
                        self.dusenler += dolan
                        // O4: düşen iç istek (kullanıcıya not gösterilir) bir sonraki açılışta Siri kutusundan yeniden çalışmasın.
                        for m in dolan { GorevKopru.ortak.kutu.cikar(metin: m) }
                    }
                    TaniGunlugu.yaz("SIRA: \(dolan.count) istek süresi dolduğu için bırakıldı (\(self.disKaynak ? "dış" : "iç"))")
                }
                let bosta = beyin.durum == .bosta
                if !self.bekleyenler.isEmpty {
                    switch DisSoruKuyrugu.karar(&g, simdi: an - koken, bosta: bosta, nesil: beyin.nesil, disKaynak: self.disKaynak) {
                    case .gonder:
                        let siradaki = self.bekleyenler.removeFirst()
                        self.eklenme[siradaki] = nil
                        beyin.gonder(siradaki, disKaynak: self.disKaynak)
                        g.nesil = beyin.nesil   // kendi gönderimi müdahale sayılmasın (çok kısa süren yanıt dahil)
                    case .disIstekleriBirak:
                        TaniGunlugu.yaz("SIRA: Durdur / Yeni sohbet sonrası \(self.bekleyenler.count) dış istek bırakıldı")
                        self.bekleyenler.removeAll(); self.eklenme.removeAll()
                    case .bekle:
                        break
                    }
                } else if bosta, let notMetni = DisSoruKuyrugu.dusmeNotu(self.dusenler) {
                    // Sıradakilerin hepsi gitti ya da düştü, Asistan boş: düşen iç istekler sessiz kalmasın.
                    beyin.sonHata = [beyin.sonHata, notMetni].compactMap { $0 }.joined(separator: "\n")
                    self.dusenler = []
                }
                if self.bekleyenler.isEmpty, self.dusenler.isEmpty { break }
                try? await Task.sleep(for: DisSoruKuyrugu.yoklamaAraligi)
            }
            if self.kusak == k { self.bekci = nil }
        }
    }
}
