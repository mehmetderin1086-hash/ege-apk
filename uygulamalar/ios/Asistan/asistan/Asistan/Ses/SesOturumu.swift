import Foundation
import AVFoundation
import Observation
import UIKit

/// Dinleme ↔ beyin ↔ konuşma akışını yöneten üst katman.
@MainActor
@Observable
final class SesOturumu {
    enum Mod: String, CaseIterable, Identifiable {
        case normal = "Normal", ellerSerbest = "Eller serbest", live = "Live"
        var id: String { rawValue }
    }
    private(set) var mod: Mod = .normal
    private(set) var gecisVar = false
    var ipucu: String {
        if uyandirmaBekliyor { return "Başlamak için Hey Asistan de" }
        if dinleyici.durum == .dinliyor { return "Bitirip göndermek için yuvarlağa dokun" }
        if konusmaci.konusuyor || beyin.durum != .bosta { return "Söz almak için yuvarlağa dokun" }
        return mod == .ellerSerbest ? "Hey Asistan’ı başlatmak için dokun" : "Konuşmak için yuvarlağa dokun"
    }
    let dinleyici = SesDinleyici()
    let konusmaci = Konusmaci()
    let sozKesme = SozKesmeDinleyici()
    let gercekLive = GercekZamanliLive()
    let openaiLive = OpenAIRealtimeLive()
    /// P3.12: AirPods/kilit ekranı kumandası; yalnız Ayarlar 'Kulaklık düğmesi' açıkken sesli kipte bağlanır.
    let kumanda = KumandaKomutlari()
    /// Live kamera ajanı: açıkken her konuşma turuna son kare eklenir.
    let kamera = KameraAkisi()
    private(set) var kameraAcik = false

    /// Gemini Live görüntü taşımıyor: yalnız o motor çalışırken kamera açılmaz (asistan görmeden "görüyor" sanılmasın).
    var kameraKullanilabilir: Bool { !(gercekLive.etkin && !openaiLive.etkin) }

    func kameraDegistir() async {
        if kameraAcik {
            kamera.durdur(); kameraAcik = false; openaiLive.kareSaglayici = nil
        } else if kameraKullanilabilir, await kamera.baslat() {
            // İzin/başlatma beklenirken Live bittiyse ya da Gemini Live (görüntü taşımaz) bağlandıysa kamerayı açık bırakma.
            guard Self.kameraAcikKalir(mod: mod, kullanilabilir: kameraKullanilabilir) else { kamera.durdur(); return }
            kameraAcik = true
            let k = kamera
            openaiLive.kareSaglayici = { k.sonKareJPEG() }
        }
    }
    /// Kamera başlatma beklemesinden sonra (saf mantık): yalnız Live sürüyor ve kamera hâlâ kullanılabiliyorsa açık kalır.
    static func kameraAcikKalir(mod: Mod, kullanilabilir: Bool) -> Bool { mod == .live && kullanilabilir }
    /// Live açılışında sırayla denenecek gerçek zamanlı motorlar; boş sıra doğrudan sıralı Live (Claude) demektir.
    nonisolated enum CanliYol: Equatable { case openai, gemini }
    /// "claude" (varsayılan): WebSocket hiç denenmez. "openai": anahtar varsa OpenAI Realtime; "yalnız Claude"
    /// kapalıysa Gemini Live yedeği. "gemini": yalnız Gemini Live. Hepsi düşerse sıralı Live sürer.
    static func canliMotorSirasi(canliMotor: String, openaiAnahtariVar: Bool, canliClaude: Bool) -> [CanliYol] {
        switch canliMotor {
        case "openai": return (openaiAnahtariVar ? [.openai] : []) + (canliClaude ? [] : [.gemini])
        case "gemini": return [.gemini]
        default: return []
        }
    }
    let yerelWhisper = YerelWhisper()
    private let beyin: Beyin
    private let ayarlar: Ayarlar
    private var uyandirma = UyandirmaAkisi()
    var uyandirmaBekliyor: Bool { uyandirma.durum == .bekliyor }
    var uyandirmaHazir: Bool { uyandirmaBekliyor && dinleyici.durum == .dinliyor }
    private(set) var uyandirmaHatasi: String?
    var sesliKip: Bool { uyandirma.etkin }
    private var onPlanda = true
    private var elleSusturuldu = false
    private(set) var canliMod = false
    var gercekZamanliEtkin: Bool { gercekLive.etkin || openaiLive.etkin }
    var canliGirisDb: Float { openaiLive.etkin ? openaiLive.girisDb : gercekLive.etkin ? gercekLive.girisDb : dinleyici.girisDb }
    var canliCikisDb: Float { openaiLive.etkin ? openaiLive.cikisDb : gercekLive.etkin ? gercekLive.cikisDb : konusmaci.cikisDb }
    var canliDurum: String {
        // Yalnız çalışan/bağlanan motorun durumu; yedeğe geçildiyse eski OpenAI hatası gösterilmez.
        switch (openaiLive.etkin || openaiLive.durum == .baglaniyor ? openaiLive : gercekLive as any GercekZamanliMotor).durum {
        case .baglaniyor: return "Gerçek zamanlı Live bağlanıyor"
        case .dinliyor: return "Canlı dinliyorum"
        case .yanitliyor: return "Canlı yanıtlıyorum"
        case .hata(let h): if !canliMod { return h }
        case .kapali: break
        }
        if case .hata(let h) = openaiLive.durum, !canliMod, !gercekZamanliEtkin { return h }
        if case .hata(let h) = dinleyici.durum { return Self.mikrofonHataMetni(h, live: mod == .live) }
        if dinleyici.durum == .dinliyor && canliMod { return "Dinliyorum" }
        if konusmaci.konusuyor { return "Konuşuyorum" }
        if beyin.durum != .bosta { return "Yanıt hazırlanıyor" }
        return canliMod ? "Hazırlanıyor" : "Live"
    }
    private var komutBekleme: Task<Void, Never>?
    private var komutNesli = 0
    private var uyandirmaTekrar: Task<Void, Never>?
    private var uyandirmaDeneme = 0
    /// P2.13 sesli onay: soru seslendirilip yanıt dinlenirken true. Barge-in, söz kesme ve VPIO açılışı bu sırada
    /// devre dışıdır (erken "evet" araç görevini `beyin.iptal()` ile düşürmesin; ikinci motor dinleyiciyle açık kalmasın).
    private var onayAkisi = false
    /// Sesli onay dinlenirken kesinleşen söz buraya gider (kullaniciKonustu'ya değil).
    @ObservationIgnored private var onayAlici: ((String, [Float], Double) -> Void)?
    var onayDinleniyor: Bool { onayAlici != nil }
    @ObservationIgnored private var onayDevam: CheckedContinuation<SesliOnayKarari.Sonuc, Never>?
    /// Devam kurulmadan gelen karar (tek atış).
    @ObservationIgnored private var onayErkenKarar: SesliOnayKarari.Sonuc?
    @ObservationIgnored private var onayBekci: Task<Void, Never>?
    /// Sesli onayın dinleme penceresi (sn).
    nonisolated static let onayDinlemeSuresi: Double = 5
    /// P2.13 Siri devri: `asistan://sor?…&ses=1` turunun yanıtı sesli okunur, ardından kısa takip penceresi açılır.
    private var siriTakip = false
    /// Siri devrinden sonra açılan takip dinlemesinin süresi (sn).
    nonisolated static let siriTakipSuresi: Double = 8

    /// Live ekranında dinleyici hatasının açıklaması gösterilir (ör. "Ses yolu değişti… yuvarlağa dokun"); öbür kiplerde kısa metin.
    static func mikrofonHataMetni(_ hata: String, live: Bool) -> String {
        live && !hata.isEmpty ? hata : "Mikrofon kullanılamıyor"
    }

    /// Dinleyici hatasından sonra Hey Asistan kendiliğinden yeniden denensin mi (saf mantık): bekleme kipinde ya da
    /// uyandırmayla açılmış komut penceresinde geçici hatalar (ses yolu, kesinti) onarılır; izin hataları onarılmaz.
    /// Elle açılan dinleme (Live dahil) burada yeniden başlatılmaz.
    static func uyandirmaOnarilir(bekliyor: Bool, uyandirmaKomutunda: Bool, hata: String) -> Bool {
        (bekliyor || uyandirmaKomutunda) && uyandirmaTekrarGerekli(hata: hata)
    }

    static func canliDevamEder(modelHatasi: Bool, sesHatasi: Bool, yerelYedek: Bool) -> Bool {
        !modelHatasi && (!sesHatasi || yerelYedek)
    }

    /// İzin hatası kullanıcı tarafından düzeltilmelidir. Ses yolu ve kesinti
    /// hataları ise geçicidir; eller serbest mod kısa bir bekleme ardından onarır.
    /// `is_` süresinde biterse sonucunu, bitmezse boş metin döndürür (iş iptal edilir).
    static func sureliCozum(saniye: Double, _ is_: @escaping @MainActor () async throws -> String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { grup in
            grup.addTask { try await is_() }
            grup.addTask { try await Task.sleep(for: .seconds(saniye)); return "" }
            let ilk = try await grup.next() ?? ""
            grup.cancelAll()
            return ilk
        }
    }
    static func uyandirmaTekrarGerekli(hata: String) -> Bool {
        // Türkçe normalleştirme: "ı" aksan sayılmadığı için folding "tanıma"yı "tanima" yapmıyordu; izin dışı kalıcı hata sürekli yeniden deneniyordu.
        let h = AtolyeYonlendirme.normalize(hata)
        return !h.contains("izn") && !h.contains("konusma tanima")
    }

    init(beyin: Beyin, ayarlar: Ayarlar) {
        self.beyin = beyin
        self.ayarlar = ayarlar
        mod = ayarlar.heyAsistan ? .ellerSerbest : .normal
        konusmaci.ayarlar = ayarlar
        SesIsaretleri.ortak.acik = { [weak ayarlar] in ayarlar?.isaretSesleri ?? true }
        dinleyici.hataOlustu = { [weak self] in
            guard let self else { return }
            komutNesli += 1
            komutBekleme?.cancel()
            let hata: String
            if case .hata(let aciklama) = dinleyici.durum { hata = aciklama } else { hata = "Mikrofon kullanılamıyor." }
            TaniGunlugu.yaz("SES dinleme hatası: \(hata) sahne=\(Self.sahneAdi(UIApplication.shared.applicationState)) canli=\(self.canliMod)")
            // P4.2: bas-konuş dinlemesi hata verdi: kilit ekranı etkinliği "Dinliyorum"da asılı kalmasın.
            if tekSeferSesli { Task { await self.basKonusuKapat(adim: Self.mikrofonHataMetni(hata, live: false)) } }
            // Durum `uyandirma.kapat()` öncesi okunur: uyandırmayla açılmış komut penceresi de kendini onarır.
            // P4.3: arka planda yeniden deneme yok (iOS kaydı yeniden başlatmayı reddedebilir; pil/günlük döngüsü olmasın).
            let yenidenDene = onPlanda && Self.uyandirmaOnarilir(bekliyor: uyandirmaBekliyor,
                                                     uyandirmaKomutunda: uyandirma.durum == .komut && uyandirma.uyandirmaIleAcildi,
                                                     hata: hata)
            if !onPlanda { arkaPlanBaslatmaHatasiniIsle() }
            // Live tur arası açılış düştüyse (ses çıkışından mikrofona geçiş) Live kapatılmadan bir kez daha denenir.
            if Self.canliOnarilir(canliMod: canliMod, onPlanda: onPlanda, hata: hata, denenen: canliOnarimSayisi) {
                canliOnarimSayisi += 1
                TaniGunlugu.yaz("LIVE: dinleme yeniden açılıyor (tek seferlik onarım)")
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(700))
                    guard let self else { return }
                    guard self.canliMod, self.onPlanda else {
                        // Bekleme sırasında arka plana gidildi ya da Live kapandı: olağan hata yolu (yarım durum kalmasın).
                        self.uyandirma.kapat(); self.canliMod = false; self.uyandirmaHatasi = hata; self.tur = nil
                        self.oturumuBirakGerekirse()
                        return
                    }
                    await self.dinleyici.basla(acilis: self.acilisIsaretiBeklemeden)
                }
                return
            }
            // Hata işareti açık dinleme (elle/uyandırma komutu) ya da onarılmayacak hatada çalar; bekleme kipinin
            // her ön plana gelişte yinelenen hatası (ör. izin yok) bip bip etmesin.
            let hataIsareti = sesliKip || (!yenidenDene && !uyandirmaBekliyor)
            uyandirma.kapat()
            canliMod = false
            uyandirmaHatasi = hata
            tur = nil
            if yenidenDene {
                uyandirmayiYenidenDene()
                if hataIsareti { SesIsaretleri.ortak.calBeklemeden(.hata) }
            } else if hataIsareti {
                // Bırakma kararı tondan sonra verilir: setActive(false) tonu yarıda kesmesin.
                Task { [weak self] in
                    await SesIsaretleri.ortak.cal(.hata)
                    self?.oturumuBirakGerekirse()
                }
            } else { oturumuBirakGerekirse() }
        }
        dinleyici.metinGuncellendi = { [weak self] metin in
            guard let self else { return }
            let yeniUyandi = uyandirma.araSonuc(metin)
            #if DEBUG
            if yeniUyandi, ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-tani") { print("[UYAN] komut penceresi acildi") }
            #endif
            // Mikrofon zaten açık: "Hey Asistan" duyuldu işareti beklenmeden çalar.
            if yeniUyandi { SesIsaretleri.ortak.calBeklemeden(.dinliyorum); kumandaBagla() }
            if yeniUyandi || (uyandirma.durum == .komut && uyandirma.uyandirmaIleAcildi) {
                komutSuresiniBaslat()
            }
        }
        dinleyici.kesinlesti = { [weak self] metin, ornekler, oran in
            // Sesli onay dinleniyorsa söz onaya gider; yeni tur başlatmaz.
            if let a = self?.onayAlici { a(metin, ornekler, oran); return }
            self?.kullaniciKonustu(metin, ornekler: ornekler, oran: oran)
        }
        dinleyici.konusmaBasladi = { [weak self] in
            guard let self, sesliKip, !onayAkisi else { return }
            // Barge-in: kullanıcı konuşmaya başladıysa asistanı sustur ve yazmayı kes (yarım tur ölçülmez).
            if canliMod, beyin.durum != .bosta { TaniGunlugu.yaz("LIVE İPTAL: dinleyici konuşma başlangıcı") }
            tur = nil
            if konusmaci.konusuyor { konusmaci.sustur() }
            if beyin.durum != .bosta { beyin.iptal() }
        }
        beyin.yanitBitti = { [weak self] metin in self?.yanitTamamlandi(metin) }
        // P3.5: sonradan gelen denetim notu sesli kipte kısaca söylenir. Mikrofon açıkken, Live (gerçek zamanlı) etkinken,
        // asistan konuşurken ya da yeni istek sürerken söylenmez (kendi sesini duymasın / Live sesiyle çakışmasın); not ekranda kalır.
        beyin.kontrolGeldi = { [weak self] not in
            guard let self, not.hasPrefix("Denetim: "), self.ayarlar.sesliYanit || self.canliMod, self.sesliKip, !self.gercekZamanliEtkin,
                  self.dinleyici.durum == .kapali, !self.sozKesme.calisiyor, self.beyin.durum == .bosta, !self.konusmaci.konusuyor else { return }
            let metin = "Küçük bir düzeltme: " + not.replacingOccurrences(of: "Denetim: ", with: "")
            // Akıştan bağımsız söz: `bitti` tetiklenmez, söz kesme izleyicisini (soyle'nin hazırlık kancası açar) biterken kendimiz kapatırız.
            Task { [weak self] in
                guard let self else { return }
                await konusmaci.soyleVeBekle(metin)
                if !konusmaci.konusuyor { sozKesme.durdur(); oturumuBirakGerekirse() }
            }
        }
        // Yeni denemede söz kesme tabanı yeniden ölçülsün.
        beyin.denemeYenilendi = { [weak self] in self?.sozKesme.durdur(); self?.konusmaci.akisBasladi() }
        konusmaci.bitti = { [weak self] in self?.sozKesme.durdur(); self?.konusmaBitti() }
        // Kulaklık çıkınca sesli kip/Live'da okuma duraklatılmaz: tur susturulup bitirilir (mikrofon/Hey Asistan geri açılır,
        // arka plan bekçisinin sessizlik sayacı donuk 'konuşuyor' durumuyla sıfırlanmaz).
        konusmaci.kulaklikCikarildi = { [weak self] in
            guard let self, sesliKip || canliMod || tekSeferSesli || siriTakip else { return false }
            TaniGunlugu.yaz("SES: kulaklık çıkarıldı, sesli tur susturuldu")
            sozKesme.durdur()
            tur = nil
            konusmaci.sustur()
            // iptal yanitBitti("") ile konusmaBitti'yi kendisi çağırır; meşgul değilse doğrudan bitirilir.
            if beyin.durum != .bosta { beyin.iptal() } else { konusmaBitti() }
            return true
        }
        // Söz kesme: asistan konuşurken mikrofon kapalıdır (yankı); yerine yankı bastırmalı düzey izleyicisi çalışır.
        // VPIO motoru ses kuyruğa alınırken (sessizlikte) açılır; çalan sesin ortasında açılırsa ilk heceler kesiliyordu.
        konusmaci.konusmaHazirlaniyor = { [weak self] in
            guard let self else { return }
            if tur != nil, tur?.ilkTTS == nil { tur?.ilkTTS = .now }
            // Sesli onay sorusunda VPIO açılmaz: ardından dinleyici açılacak, iki motor aynı anda kalmasın.
            guard sesliKip, !onayAkisi, ayarlar.sozKesme, dinleyici.durum != .dinliyor else { return }
            sozKesme.baslat()
        }
        // Taban ölçümü oynatma başlayınca. Hazırlıkta açılamadıysa (dinleyici o an dinliyordu) burada geç açılır.
        konusmaci.konusmayaBasladi = { [weak self] in
            guard let self else { return }
            if tur != nil { tur?.ilkOynatma = .now; turuKaydet() }
            // P4.2: bas-konuş yanıtı okunmaya başladı (etkinlik hâlâ açıksa kilit ekranında görünür).
            if tekSeferSesli { Task { await self.beyin.isAktivitesi.guncelle(.init(adim: "Yanıtlıyor")) } }
            guard sesliKip, !onayAkisi, ayarlar.sozKesme, dinleyici.durum != .dinliyor else { return }
            if !sozKesme.calisiyor { sozKesme.baslat() }
            sozKesme.olcumuBaslat()
        }
        sozKesme.tetiklendi = { [weak self] in
            guard let self, sesliKip, !onayAkisi else { return }
            // P4.3: söz kesme kararından önceki son 0,5 sn (kullanıcının ilk hecesi; eskisi yankı artığı) dinleyiciye ön ses olarak gider.
            // isle → durdur → tetiklendi sırasında, susturma başka bir yolu tetiklemeden önce okunur.
            let on = sozKesme.onSesiAl()
            let onSes = (ornekler: OnSes.hazirla(on.ornekler, oran: on.oran, enCokSaniye: SozKesmeDinleyici.onSesGeriSuresi), oran: on.oran)
            TaniGunlugu.yaz("SÖZ KESME: kullanıcı konuştu, asistan susturuldu")
            tur = nil
            konusmaci.sustur()
            if beyin.durum != .bosta { beyin.iptal() }
            Task { await self.dinleyici.basla(onSes: onSes.ornekler.isEmpty ? nil : onSes) }
        }
        // Gerçek zamanlı oturum kurulduktan sonra koparsa (ağ, goAway, ses yolu) yeniden bağlan ya da sıralı Live'a geç.
        gercekLive.oturumKoptu = { [weak self] neden in Task { await self?.canliKoptu(neden) } }
        openaiLive.oturumKoptu = { [weak self] neden in Task { await self?.canliKoptu(neden) } }
        // Uygulama içi medya (ses kartı, video) durunca oturum bırakma kararı yeniden verilir: kısılan müzik geri gelsin.
        SesCalar.ortak.bitti = { [weak self] in self?.oturumuBirakGerekirse() }
        // Toplantı kaydı bitince oturum bırakma kararı güncel duruma göre burada verilir.
        SesKaydedici.ortak.oturumuBirakIstegi = { [weak self] in self?.oturumuBirakGerekirse() }
        // P2.13: sesli kipte açılan onay diyaloğu seslendirilir ve sesli yanıt dinlenir (dokunmalı diyalog da açık kalır).
        beyin.onay.sesliSorucu = { [weak self] i in await self?.sesliOnayIste(i) }
    }

    func uyandirmayiBaslat() async {
        // P4.3: arka planda yalnız 'Arka planda Hey Asistan' açıkken, arka plana geçerken bekleme sürüyorduysa ve bu dönemde
        // başlatma hatası olmadıysa (iOS arka planda kaydı yeniden başlatmayı reddedebilir; sonsuz deneme yok).
        guard onPlanda || Self.arkaPlandaBeklemeSurer(ayar: ayarlar.arkaPlanUyandirma, bekliyor: arkaPlanUyandirmaEtkin,
                                                       canli: canliMod, onPlanda: onPlanda,
                                                       sonHataArkaPlanda: arkaPlanBaslatmaHatasi),
              mod == .ellerSerbest, !elleSusturuldu, ayarlar.heyAsistan, !sesliKip, !uyandirmaBekliyor, beyin.durum == .bosta, !konusmaci.konusuyor,
              GucPolitikasi.ortak.karar.uyandirmaAcik else { return }   // P3.9: kritik ısıda (ya da sıcak + Düşük Güç) mikrofon beklemesi açılmaz
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-tani") { print("[UYAN] bekleme basladi") }
        #endif
        dinleyici.otomatikGonder = true
        dinleyici.kesinSonucuHemenGonder = false
        dinleyici.sessizlikMs = 750
        // P3.12: 'Hey Asistan' kısa ifadesi 500 ms'de kesilmesin; bekleme sırasında oturum karışabilir kalsın (müzik durmasın).
        dinleyici.akilliSon = false
        kumanda.coz()
        uyandirmaHatasi = nil
        uyandirma.bekle()
        await dinleyici.basla(yalnizUyandirma: true)
        if case .hata(let hata) = dinleyici.durum {
            uyandirma.kapat()
            uyandirmaHatasi = hata
            if Self.uyandirmaTekrarGerekli(hata: hata) { uyandirmayiYenidenDene() }
        } else if uyandirmaHazir {
            uyandirmaDeneme = 0
            uyandirmaTekrar?.cancel()
            uyandirmaTekrar = nil
        }
    }
    /// P3.9: güç politikası değişti. Kapanınca yalnız 'Hey Asistan' beklemesi durur (Live'a ve süren sesli kipe dokunulmaz);
    /// açılınca koşullar uygunsa bekleme yeniden başlar.
    func gucPolitikasiDegisti(_ acik: Bool) async {
        if acik { await uyandirmayiBaslat(); return }
        guard uyandirmaBekliyor, !canliMod else { return }
        TaniGunlugu.yaz("GÜÇ: uyandırma beklemesi durduruldu")
        await uyandirmayiDurdur()
    }
    func uyandirmayiEtkinlestir() async {
        mod = .ellerSerbest
        ayarlar.heyAsistan = true
        elleSusturuldu = false
        await uyandirmayiBaslat()
    }
    func uyandirmayiDurdur() async {
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        uyandirmaDeneme = 0
        guard uyandirmaBekliyor else { return }
        uyandirma.kapat()
        await dinleyici.durdur()
        oturumuBirakGerekirse()
    }
    func onPlanDegisti(_ acik: Bool) async {
        onPlanda = acik
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-tani") { print("[UYAN] onPlanda=\(acik) bekliyor=\(uyandirmaBekliyor) sesli=\(sesliKip) mikrofon=\(dinleyici.durum)") }
        #endif
        if acik {
            // P4.2: arka planda süren Live öne geldi: bekçi durur, kilit ekranı etkinliği kapanır; Live olağan sürer.
            if arkaPlanCanli { await arkaPlanCanliyiKapat(adim: "Uygulamada sürüyor", liveBitir: false) }
            else if erkenCanliEtkinlik {
                // .inactive'te açılan etkinlik arka plana geçmeden öne döndü (Denetim Merkezi, bildirim çekmecesi): kapanır.
                erkenCanliEtkinlik = false
                if beyin.durum == .bosta { await beyin.isAktivitesi.bitir(sureSn: 0, hata: false, adim: "Uygulamada sürüyor") }
            }
            // P4.3: arka plan dönemi bitti; bekleme sürüyorsa uyandirmayiBaslat dokunmaz, durduysa yeniden açar.
            arkaPlanUyandirmaEtkin = false
            arkaPlanBaslatmaHatasi = false
            await uyandirmayiBaslat()
        }
        else {
            // P4.2: bas-konuş turu arka planda sürer (kendi vazgeçme süresi ve Live Activity'si var).
            if tekSeferSesli { return }
            // Sistem köprüsü Kestirmeler'i kısa süre öne aldı ve x-callback ile geri dönecek: Live ve sesli kip kapatılmaz.
            if SistemKoprusu.ortak.gecisSuruyor { return }
            // P4.2: 'Live arka planda sürsün' açıkken sıralı (Claude) Live kapatılmaz; mikrofon açık kalır, sessizlik bekçisi başlar.
            let gercekZamanli = gercekZamanliEtkin || gercekLive.durum == .baglaniyor || openaiLive.durum == .baglaniyor
            if mod == .live, Self.arkaPlandaSurdur(canliMod: canliMod, ayar: ayarlar.canliArkaPlan, gercekZamanli: gercekZamanli) {
                arkaPlanCanliyiBaslat()
                return
            }
            // P4.3: karar Live kapatılmadan önce okunur (canlıyken bekleme sürmez).
            let beklemeSurer = Self.arkaPlandaBeklemeSurer(ayar: ayarlar.arkaPlanUyandirma, bekliyor: uyandirmaBekliyor, canli: canliMod)
            canliGoreviKapat()
            kumanda.coz()
            gercekLive.kapat(); openaiLive.kapat()
            canliMod = false
            uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
            // P4.3: 'Arka planda Hey Asistan' açıkken bekleme dinlemesi kapatılmaz (açık komut penceresinde olağan davranış).
            if beklemeSurer {
                arkaPlanUyandirmaEtkin = true
                arkaPlanBaslatmaHatasi = false
                TaniGunlugu.yaz("ARKA PLAN: Hey Asistan beklemesi sürüyor")
                return
            }
            // Uygulama arka plana geçtiğinde açık komut penceresi de kapanır.
            komutBekleme?.cancel()
            if uyandirmaBekliyor || uyandirma.durum == .komut {
                komutNesli += 1; uyandirma.kapat()
                await dinleyici.durdur()
            }
            oturumuBirakGerekirse()
        }
    }

    /// Ayarlara göre yerel Whisper modelini hazırla (indir + yükle).
    /// `elle`: Ayarlar düğmesi; önceki yüklemenin çökme işaretini silip yeniden dener (otomatik çağrılar saygı duyar).
    func whisperiHazirla(elle: Bool = false) {
        guard ayarlar.yerelWhisperKullan else { return }
        if elle { whisperHatasiniTemizle() }
        yerelWhisper.hazirla(model: ayarlar.whisperModeli, elle: elle)
    }

    /// Ayarlar'da gösterilen son Whisper hatasını siler; "hazır değil" tanı satırı yeniden yazılabilir.
    func whisperHatasiniTemizle() {
        sonWhisperHatasi = nil
        whisperHazirDegilYazildi = false
    }

    /// `setActive` bazı cihazlarda yüzlerce milisaniye sürebilir. Ses düğmesine
    /// basıldığında SwiftUI ana aktörünü tutmaması için `SesOturumuKapisi` aktöründe çalışır.
    /// İstek nesli burada eşzamanlı artar: arkadan gelen bir bırakma bu yeni oturumu kapatmaz.
    static func oturumuAyarla() async throws {
        SesOturumuKapisi.istek.artir()
        try await SesOturumuKapisi.ortak.etkinlestir()
    }

    /// Dinleme, konuşma, söz kesme ve gerçek zamanlı Live hiçbiri sürmüyorsa `.duckOthers` oturumu bırakılır
    /// (Müzik/podcast sesi yeniden yükselir). Saf mantık; çalışan G/Ç varken bırakmak sesi keser.
    /// Uygulamanın kendi medyası (sohbetteki ses kartı) çalarken de bırakılmaz: setActive(false) onu da durdurur.
    /// Toplantı kaydı (SesKaydedici) süren ya da duraklatılmış kayıtta da oturum bırakılmaz: setActive(false) kaydı keser.
    static func oturumBirakilir(dinleyiciCalisiyor: Bool, konusuyor: Bool, sozKesmeCalisiyor: Bool,
                                gercekZamanli: Bool, beyinBosta: Bool, uyandirmaBekliyor: Bool,
                                medyaCaliyor: Bool = false, kayitSuruyor: Bool = false) -> Bool {
        !dinleyiciCalisiyor && !konusuyor && !sozKesmeCalisiyor && !gercekZamanli && beyinBosta && !uyandirmaBekliyor
            && !medyaCaliyor && !kayitSuruyor
    }

    private func oturumuBirakGerekirse() {
        var dinleyiciCalisiyor = dinleyici.durum != .kapali
        if case .hata = dinleyici.durum { dinleyiciCalisiyor = false }
        let gercekZamanli = gercekZamanliEtkin || gercekLive.durum == .baglaniyor || openaiLive.durum == .baglaniyor
        guard Self.oturumBirakilir(dinleyiciCalisiyor: dinleyiciCalisiyor, konusuyor: konusmaci.konusuyor,
                                   sozKesmeCalisiyor: sozKesme.calisiyor, gercekZamanli: gercekZamanli,
                                   beyinBosta: beyin.durum == .bosta, uyandirmaBekliyor: uyandirmaBekliyor,
                                   medyaCaliyor: SesCalar.ortak.medyaCaliyor,
                                   kayitSuruyor: SesKaydedici.ortak.suruyor) else { return }
        let nesil = SesOturumuKapisi.istek.deger
        Task { await SesOturumuKapisi.ortak.birak(nesil: nesil) }
    }

    /// P3.12: Ayarlar 'Kulaklık düğmesi' açıksa AirPods kumandası bağlanır (kapalıysa çözülür).
    private func kumandaBagla() {
        if ayarlar.kumanda { kumanda.bagla(self) } else { kumanda.coz() }
    }

    /// Kontrol/App Shortcut'tan gelen "dinle" isteği.
    func disTetikGeldi() {
        Task { await sesliKipiAc() }
    }

    var canliSesSecilebilir: Bool {
        mod == .live && !gecisVar && beyin.durum == .bosta && !konusmaci.konusuyor
            && openaiLive.durum != .yanitliyor && gercekLive.durum != .yanitliyor
    }

    /// Sesi boş turda değiştir: süren yanıtın cümleleri iki farklı sesle okunmasın.
    func canliSesiSec(_ kimlik: String) async -> Bool {
        guard canliSesSecilebilir else { return false }
        ayarlar.sesKimligi = kimlik
        konusmaci.sesiYenidenDene(kimlik)
        if ayarlar.canliMotor != "claude" || gercekZamanliEtkin {
            gecisVar = true
            defer { gecisVar = false }
            ayarlar.canliMotor = "claude"
            await canliModuAc()
        }
        return true
    }

    func canliModuAc() async {
        mod = .live
        canliOnarimSayisi = 0
        ayarlar.heyAsistan = false
        // Live hemen açılır: "kapandı" işareti çalınmaz (ardından "dinliyorum" gelir).
        await sesliKipiKapat(isaret: false)
        elleSusturuldu = false
        canliMod = true
        kumandaBagla()
        // Live motoru "claude" (varsayılan) ise doğrudan sıralı Live; "openai" seçiliyse önce OpenAI Realtime,
        // "yalnız Claude" kapalıysa Gemini Live yedeği. Hiçbiri bağlanmazsa sıralı Live (Claude).
        if await gercekZamanliBaglan() { return }
        guard mod == .live else { return }
        await sesliKipiAc(canli: true)
    }

    /// Ayardaki sırayla gerçek zamanlı motoru bağlar. Bağlanırken kullanıcı Bitir'e basmış olabilir:
    /// mod değiştiyse açılan motor hemen kapatılır ve false döner.
    private func gercekZamanliBaglan() async -> Bool {
        let sira = Self.canliMotorSirasi(canliMotor: ayarlar.canliMotor, openaiAnahtariVar: OpenAIAnahtari.var_, canliClaude: ayarlar.canliClaude)
        // P3.1: küçük araç seti (IzlenenArac sarmalı korunur) + saat/hafıza olgulu kısa talimat her iki motora.
        let kopru = CanliAracKoprusu(araclar: beyin.araclar.filter { CanliAracKoprusu.canliAraclar.contains($0.name) })
        let talimat: @MainActor () -> String = { [beyin] in
            CanliAracKoprusu.canliTalimat(olgular: beyin.depo.talimatOlgulari(adet: CanliAracKoprusu.enFazlaOlgu), simdi: .now)
        }
        openaiLive.aracKoprusu = kopru; openaiLive.talimatSaglayici = talimat
        gercekLive.aracKoprusu = kopru; gercekLive.talimatSaglayici = talimat
        for yol in sira {
            guard mod == .live else { return false }
            let m: any GercekZamanliMotor = yol == .openai ? openaiLive : gercekLive as any GercekZamanliMotor
            guard await m.baslat() else { continue }
            if mod != .live { m.kapat(); return false }
            // Gemini Live görüntü taşımaz: açık kamera kapatılır.
            if yol == .gemini, kameraAcik { await kameraDegistir() }
            // Live yalnız kullanıcının sesini taşır: önceki yazılı turun dış kaynak bayrağı yan etkili adımı diyaloğa sokmasın.
            beyin.onay.disKaynakTuru = false
            // Adım bütçesi ve Ajan merkezi kaydı bu oturum için açılır (araç adımları buraya yazılır).
            canliGoreviKapat()
            AjanDefteri.ortak.gorevBaslat("Live sesli oturum")
            canliGorevKimligi = AjanDefteri.ortak.gorevler.first?.id
            return true
        }
        return false
    }

    /// Gerçek zamanlı Live oturumunun Ajan merkezi kaydı (P3.1). Kayıt hâlâ en yeni ve sürüyorsa kapatılır:
    /// arada Beyin kendi görevini açtıysa (gorevBaslat aktif görevi değiştirir) ya da kayıt başka yoldan bittiyse dokunulmaz.
    private var canliGorevKimligi: UUID?
    private func canliGoreviKapat(_ durum: String = "Tamamlandı") {
        guard let id = canliGorevKimligi else { return }
        canliGorevKimligi = nil
        guard let ilk = AjanDefteri.ortak.gorevler.first, ilk.id == id, ilk.durum == "Sürüyor" else { return }
        AjanDefteri.ortak.gorevBitir(model: "live", sonuc: "", durum: durum)
    }

    private var sonCanliKopma = Date.distantPast
    /// Kopan gerçek zamanlı oturum yeniden kurulsun mu (saf mantık): Live sürüyor, uygulama önde, motor kapalı
    /// ve kullanıcı bu arada sıralı dinlemeyi açmamış olmalı.
    static func canliYenidenBaglanir(mod: Mod, canliMod: Bool, onPlanda: Bool, gercekZamanliEtkin: Bool, sesliKip: Bool) -> Bool {
        mod == .live && canliMod && onPlanda && !gercekZamanliEtkin && !sesliKip
    }
    /// Kurulmuş gerçek zamanlı oturum koptu: bir kez yeniden bağlanılır; 30 sn içinde yine koparsa
    /// (bağlan-kop döngüsü) doğrudan sıralı Live'a geçilir. Mikrofon ve soket motor tarafında kapatıldı.
    private func canliKoptu(_ neden: String) async {
        TaniGunlugu.yaz("LIVE koptu: \(neden)")
        canliGoreviKapat("Koptu")   // yeniden bağlanma başarılıysa yeni kayıt açılır
        while gecisVar { try? await Task.sleep(for: .milliseconds(100)) }
        // Kullanıcı bu arada küreye dokunup sıralı dinlemeyi açtıysa ikinci ses yolu kurulmaz.
        guard Self.canliYenidenBaglanir(mod: mod, canliMod: canliMod, onPlanda: onPlanda,
                                        gercekZamanliEtkin: gercekZamanliEtkin, sesliKip: sesliKip) else { return }
        // Yeniden bağlanırken küre kapalı (canliModuAc'teki modSec gibi): baslat'ın izin/bağlanma beklemesinde
        // gelen dokunuş ikinci mikrofon yolu açmasın. `while` ile bu satır arasında await yok, adım bölünmez.
        gecisVar = true; defer { gecisVar = false }
        let tekrar = Date().timeIntervalSince(sonCanliKopma) > 30
        sonCanliKopma = .now
        if tekrar, await gercekZamanliBaglan() { return }
        guard mod == .live, canliMod else { return }
        await sesliKipiAc(canli: true)
    }

    /// Live tam ekranındaki "Bitir": geçiş (bağlanma) sürerken de çalışır; ekran hemen kapanır.
    func canliBitir() async {
        TaniGunlugu.yaz("LIVE İPTAL: Bitir")
        mod = .normal; ayarlar.heyAsistan = false
        if kameraAcik { await kameraDegistir() }
        await sesliKipiKapat(); beyin.iptal()
        while gecisVar { try? await Task.sleep(for: .milliseconds(100)) }
        if mod == .normal { await sesliKipiKapat() }   // geçiş sırasında açılmış dinlemeyi de kapat
        oturumuBirakGerekirse()
    }

    /// Live sırasında yanıtı kesip yeni sözü dinlemeye geçmek için.
    func sozuAl() async {
        TaniGunlugu.yaz("LIVE İPTAL: kullanıcı söz aldı")
        if gercekZamanliEtkin { (openaiLive.etkin ? openaiLive : gercekLive as any GercekZamanliMotor).sozuAl(); return }
        await sesliKipiAc(canli: canliMod)
    }

    func sesliKipiAc(canli: Bool = false) async {
        // Cihaz testleri mikrofonu kendileri açar; arayüz/kısayol ikinci motor başlatmasın.
        guard ProcessInfo.processInfo.environment["ASISTAN_SES"] != "1" else { return }
        // İndirilmiş yerel Whisper arka planda yüklenir (açılışta değil; çökme işareti varsa hiç); ilk tur Apple metniyle gider.
        let whisperModeli = ayarlar.whisperModeli
        if ayarlar.yerelWhisperKullan,  // disk taraması yalnız yerel Whisper seçiliyken
           YerelWhisper.sesliAcilistaYuklenir(kullan: ayarlar.yerelWhisperKullan, durum: yerelWhisper.durum,
                                              indirilmis: YerelWhisper.indirilmis(whisperModeli),
                                              cokmus: YerelWhisper.oncekiYuklemeCokmus(whisperModeli)) {
            whisperiHazirla()
        }
        elleSusturuldu = false
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        komutNesli += 1; komutBekleme?.cancel()
        await dinleyici.durdur()
        uyandirma.kapat()
        // Siri devrinin yanıtı okunurken söz alındı: iptal edilen yanıt dinleme sürerken sesli okunmasın (P2.13).
        siriTakip = false
        konusmaci.sustur()
        // Asistan konuşurken söz alındı: yankı bastırmalı ikinci motor dinleyiciyle aynı anda açık kalmasın.
        sozKesme.durdur()
        beyin.iptal()
        canliMod = canli
        dinleyici.otomatikGonder = canli || mod == .ellerSerbest
        dinleyici.kesinSonucuHemenGonder = canli
        dinleyici.sessizlikMs = canli ? 1000 : 1200
        // P3.12: akıllı konuşma sonu (Live kesin sonucu hemen gönderir, etkilenmez); kumanda dinleme açılmadan bağlanır
        // ki oturum karışmaz kurulsun.
        dinleyici.akilliSon = !canli && ayarlar.akilliKonusmaSonu
        kumandaBagla()
        if case .hata = dinleyici.durum { await dinleyici.durdur() }
        // Beklerken Live bitirildiyse mikrofonu açma (Bitir sonrası dinleme açık kalmasın).
        if canli, mod != .live { canliMod = false; return }
        uyandirma.elleDinle()
        tur = nil
        await dinleyici.basla(acilis: acilisIsareti)
        if canli, mod != .live { uyandirma.kapat(); canliMod = false; await dinleyici.durdur() }
    }

    /// `isaret`: önceden açık bir dinleme (elle ya da uyandırma komutu) varsa "kapandı" tonu çalınır.
    func sesliKipiKapat(isaret: Bool = true) async {
        let caldir = isaret && sesliKip
        // P4.2: bas-konuş turu başka yoldan kapatıldı (mod değişimi, elle kapatma): etkinlik "Durduruldu" ile biter.
        if tekSeferSesli {
            tekSeferSesli = false
            if beyin.durum == .bosta { Task { await beyin.isAktivitesi.bitir(sureSn: 0, hata: false, adim: "Durduruldu") } }
        }
        canliGoreviKapat()   // motor kapatılmadan önce (canliBitir/modSec/canliModuAc bu yoldan geçer)
        kumanda.coz()
        elleSusturuldu = true
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        uyandirmaDeneme = 0
        sozKesme.durdur()
        gercekLive.kapat(); openaiLive.kapat()
        izleme?.cancel()
        canliMod = false
        siriTakip = false
        tur = nil
        komutNesli += 1; komutBekleme?.cancel()
        uyandirma.kapat()
        konusmaci.sustur()
        await dinleyici.durdur()
        // Ton mikrofon kapandıktan sonra, oturum bırakılmadan önce: setActive(false) tonu yarıda kesmesin.
        if caldir { await SesIsaretleri.ortak.cal(.kapandi) }
        oturumuBirakGerekirse()
    }

    func modSec(_ yeni: Mod) async {
        guard !gecisVar else { return }
        gecisVar = true; defer { gecisVar = false }
        await sesliKipiKapat(); beyin.iptal()
        mod = yeni; ayarlar.heyAsistan = yeni == .ellerSerbest
        elleSusturuldu = false
        if yeni == .ellerSerbest { await uyandirmayiBaslat() }
        if yeni == .live { await canliModuAc() }
        if yeni == .normal { oturumuBirakGerekirse() }
    }

    func yuvarlagaDokun() async {
        guard !gecisVar else { return }
        gecisVar = true; defer { gecisVar = false }
        if gercekZamanliEtkin { (openaiLive.etkin ? openaiLive : gercekLive as any GercekZamanliMotor).sozuAl(); return }
        if dinleyici.durum == .dinliyor && !uyandirmaBekliyor {
            _ = dinleyici.gonder()
        } else {
            await sesliKipiAc(canli: mod == .live)
        }
    }

    func degistir() async {
        if uyandirmaBekliyor { await uyandirmayiDurdur(); return }
        if case .hata = dinleyici.durum { await sesliKipiAc(); return }
        if sesliKip { await sesliKipiKapat() } else { await sesliKipiAc() }
    }

    private func kullaniciKonustu(_ appleMetni: String, ornekler: [Float], oran: Double) {
        guard let giris = uyandirma.kesinSonuc(appleMetni) else { return }
        if canliMod { TaniGunlugu.yaz("LIVE TUR: girdi kabul edildi; karakter=\(giris.count)"); canliOnarimSayisi = 0 }
        komutBekleme?.cancel()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--asistan-uyandirma-tani") { print("[UYAN] tek komut kabul edildi") }
        #endif
        let buNesil = komutNesli
        // "Söz bitti → ilk ses" ölçümü (yalnız sıralı hat; gerçek zamanlı motorlar bu yoldan geçmez).
        tur = SesTurOlcumu(sonSes: dinleyici.sonSes, kesinlesme: .now,
                           kip: canliMod ? "live" : mod == .ellerSerbest ? "eller-serbest" : "normal")
        // Uyandırma tamponu çağrı öncesi ses içerebilir. Bu akışta yalnız cihaz içi metin kullanılır.
        let yalnizYerelMetin = uyandirma.uyandirmaIleAcildi
        // Yanıt seslendirilirken mikrofon kapalı (yankı). Durdurma bitmeden gönderme yapılmaz ki
        // çok hızlı biten yanıtta "basla" eski "dinliyor" durumunu görüp sessizce dönmesin.
        Task {
            await dinleyici.durdur()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") {
                print("[LIVE-TANI] dinleyici durdu nesil=\(buNesil)/\(komutNesli)")
            }
            #endif
            guard buNesil == komutNesli else { return }
            // "Aldım" işareti beklenmez: Whisper/beyin.gonder bloklanmasın (hız önceliği).
            SesIsaretleri.ortak.calBeklemeden(.aldim)
            var metin = giris
            let yeterli = !yalnizYerelMetin && oran > 0 && Double(ornekler.count) / oran >= 0.4
            if yeterli, ayarlar.yerelWhisperKullan, !yerelWhisper.hazir, !whisperHazirDegilYazildi {
                // Model açılışta yüklenmez (14 Eki Core ML çökmesi): seçim sessizce Apple metnine düşmesin, iz kalsın.
                whisperHazirDegilYazildi = true
                TaniGunlugu.yaz("STT: yerel Whisper hazır değil, Apple metni kullanıldı")
                sonWhisperHatasi = "Telefondaki Whisper yüklü değil (Ayarlar > Ses)."
            }
            if yeterli, ayarlar.yerelWhisperKullan, yerelWhisper.hazir {
                // Telefondaki Whisper: ses cihazdan çıkmaz. Hata/boşta Apple metni kalır.
                dinleyici.cozumluyor(true)
                let t0 = Date()
                do {
                    // Hız önceliği: Whisper 2 sn içinde bitmezse Apple metni kullanılır.
                    let w = try await Self.sureliCozum(saniye: 2) { try await self.yerelWhisper.cozumle(ornekler, oran: oran) }
                    if !w.isEmpty { metin = w }
                    sonWhisperSuresi = Date().timeIntervalSince(t0)
                    SaglikMerkezi.ortak.kaydet("stt", sure: sonWhisperSuresi!, etiket: "yerel-whisper")
                } catch {
                    sonWhisperHatasi = error.localizedDescription
                    SaglikMerkezi.ortak.kaydet("stt", sure: Date().timeIntervalSince(t0), basarili: false, etiket: "yerel-whisper")
                }
                dinleyici.cozumluyor(false)
            } else if yeterli, ayarlar.bulutWhisperKullan {
                dinleyici.cozumluyor(true)
                let t0 = Date()
                do {
                    let ham = try await WhisperIstemcisi.cozumle(ornekler: ornekler, oran: oran, ipucu: Self.whisperIpucu)
                    // Uydurma/istem yankısı Apple metninin yerine geçmesin (boş sonuç Apple metnini korur).
                    let w = Self.bulutSonucuTemizle(ham)
                    if !w.isEmpty { metin = w }
                    sonWhisperSuresi = Date().timeIntervalSince(t0)
                    SaglikMerkezi.ortak.kaydet("stt", sure: sonWhisperSuresi!, etiket: "bulut-whisper")
                } catch {
                    sonWhisperHatasi = error.localizedDescription
                    SaglikMerkezi.ortak.kaydet("stt", sure: Date().timeIntervalSince(t0), basarili: false, etiket: "bulut-whisper")
                }
                dinleyici.cozumluyor(false)
            }
            guard buNesil == komutNesli else { return }
            metin = Uyandirma.komut(metin) ?? metin
            konusmaci.akisBasladi()
            // Gerçek Gemini Live oturumu etkinse bu yol kullanılmaz; sesi doğrudan
            // WebSocket taşır. Bağlantı kurulamazsa sıralı sesli yedek, kullanıcının
            // bağlı Antigravity Gemini 3.8 Flash hesabıyla başlar.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") { print("[LIVE-TANI] beyne gönderiliyor") }
            #endif
            tur?.gonderim = .now
            // P4.2: bas-konuş turu kısa sesli yanıt ister (canlı ses kipi); arka plan Live'da sessizlik sayacı sıfırlanır.
            if tekSeferSesli { Task { await beyin.isAktivitesi.guncelle(.init(adim: "Düşünüyor")) } }
            if arkaPlanCanli { sonKonusma = .now }
            beyin.gonder(metin, gorsel: kameraAcik ? kamera.sonKare() : nil, canliSes: canliMod || tekSeferSesli)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama") { print("[LIVE-TANI] beyne gönderildi") }
            #endif
            akisiIzle()
        }
    }

    /// Whisper'a bağlam: Türkçe, asistan komutları; özel adların yazımına yardım eder.
    static let whisperIpucu = "Türkçe sesli asistan komutu. Hatırlatıcı, takvim, alarm, zamanlayıcı, hava durumu, kişiler, harita, müzik."
    private(set) var sonWhisperSuresi: TimeInterval?
    private(set) var sonWhisperHatasi: String?
    private var whisperHazirDegilYazildi = false

    /// Bulut Whisper çıktısı: yerel yoldaki uydurma süzgeci + istem metninin geri yankısı elenir.
    static func bulutSonucuTemizle(_ s: String) -> String {
        let t = YerelWhisper.temizle(s)
        let tr = Locale(identifier: "tr_TR")
        let k = t.lowercased(with: tr)
        if k.isEmpty || k.contains("sesli asistan komutu") || whisperIpucu.lowercased(with: tr).hasPrefix(k) { return "" }
        return t
    }

    private var izleme: Task<Void, Never>?
    func akisiIzle() {
        izleme?.cancel()
        guard ayarlar.sesliYanit || canliMod || siriTakip || tekSeferSesli else { return }
        izleme = Task { [weak self] in
            var son = ""
            while let self, !Task.isCancelled, beyin.durum != .bosta {
                if !beyin.seslendirilebilir { try? await Task.sleep(for: .milliseconds(120)); continue }
                let m = beyin.akanMetin
                if !m.isEmpty, tur != nil, tur?.ilkMetin == nil { tur?.ilkMetin = .now }
                if m != son { son = m; konusmaci.akisParcasi(seslendirilecek(m)) }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    /// P4.7: sürüş kipinde seslendirme ilk 2 cümlede durur (kırpılan metin akan metnin öneki: okunmuş parçalar
    /// yinelenmez, 3. cümle bölücüye hiç ulaşmaz). Tam metin sohbet balonunda kalır.
    private func seslendirilecek(_ metin: String) -> String {
        SurusKipi.ortak.aktif ? SurusKipi.kisalt(metin) : metin
    }

    private func yanitTamamlandi(_ metin: String) {
        izleme?.cancel()
        guard (ayarlar.sesliYanit || canliMod || siriTakip || tekSeferSesli), beyin.seslendirilebilir, !metin.isEmpty else { konusmaci.sustur(); konusmaBitti(); return }
        if tur != nil, tur?.ilkMetin == nil { tur?.ilkMetin = .now }
        konusmaci.akisBitti(seslendirilecek(metin))
    }

    private func konusmaBitti() {
        // Ses çalmadan biten tur (TTS hatası, sesli yanıt kapalı) ölçülmez; yazılı bir sonraki yanıta da sızmaz.
        tur = nil
        // Söz kesme izleyicisi yalnız konuşma sürerken açık kalır (yanitTamamlandi'nin erken dalı dahil).
        sozKesme.durdur()
        // P2.13: Siri'den sesli devredilen turun yanıtı bitti: kısa takip penceresi açılır (devam sorusu için).
        let siridenSesli = siriTakip
        siriTakip = false
        if siridenSesli, !sesliKip, onPlanda, beyin.durum == .bosta, !konusmaci.konusuyor {
            Task { await siriTakipPenceresiAc() }
            return
        }
        // P4.2: bas-konuş turunun yanıtı okundu (ya da okunamadı): tur kapanır, açık kalan etkinlik bitirilir. Ardından olağan
        // akış mikrofonu kapatır (tek tur); uygulama arka plandaysa Hey Asistan beklemesi açılmaz (onPlanda false).
        if tekSeferSesli, beyin.durum == .bosta, !konusmaci.konusuyor { basKonusTurunuKapat() }
        if arkaPlanCanli { sonKonusma = .now }
        // Beyin hâlâ çalışıyorsa (araç çağrısı arası duraklama) mikrofon açılmaz: asistan kendi sesini duymasın.
        if !sesliKip {
            Task { await uyandirmayiBaslat(); oturumuBirakGerekirse() }
            return
        }
        guard sesliKip, beyin.durum == .bosta, !konusmaci.konusuyor else { return }
        // Bulut TTS düştüğünde iPhone sesi yanıtı tamamladıysa Live kapatılmaz.
        // Sadece gerçekten yanıt üretilememesi veya oynatılamayan ses Live'ı sonlandırır.
        if !Self.canliDevamEder(modelHatasi: beyin.sonHata != nil,
                                 sesHatasi: konusmaci.sesHatasi != nil,
                                 yerelYedek: konusmaci.yerelYedekKullanildi) { canliMod = false }
        // P4.2: arka planda süren Live de sürekli kalır (onPlanda false olsa da).
        let devam = uyandirma.yanitBitti(surekli: Self.canliSurer(onPlanda: onPlanda, arkaPlanCanli: arkaPlanCanli,
                                                                  canliMod: canliMod, kip: beyin.aktifKip))
        if !devam { canliMod = false }
        if canliMod { TaniGunlugu.yaz("LIVE TUR: ses bitti; dinlemeyeDonus=\(devam) yedek=\(konusmaci.yerelYedekKullanildi)") }
        if devam {
            // Live tur arası: ton beklenmez (her tura 170 ms eklemesin); mikrofon motoru hemen açılır.
            Task { await dinleyici.basla(acilis: acilisIsaretiBeklemeden) }
            // Tur sonunda Beyin iş etkinliğini kapattı; kilit ekranında 'Canlı · dinliyorum' geri gelir.
            if arkaPlanCanli {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    self?.canliEtkinliginiAc()
                }
            }
        } else if arkaPlanCanli {
            // Arka planda dokunacak ekran yok: Live tümüyle kapanır (etkinlik "Canlı konuşma bitti").
            Task { await arkaPlanCanliyiKapat(adim: "Canlı konuşma bitti", liveBitir: true) }
        }
        else { Task { await uyandirmayiBaslat(); oturumuBirakGerekirse() } }
    }

    /// Live'da art arda düşen açılışların sayısı; kullanıcı konuşunca (başarılı tur) sıfırlanır.
    @ObservationIgnored private var canliOnarimSayisi = 0
    /// Live açılış hatası onarılır mı: yalnız ön planda, izin dışı hatada ve tur başına bir kez.
    nonisolated static func canliOnarilir(canliMod: Bool, onPlanda: Bool, hata: String, denenen: Int) -> Bool {
        // "izin" ünlü düşmesiyle "izni" olur ("tanıma izni yok"): ikisi de onarılmaz.
        canliMod && onPlanda && denenen < 1 && !["izin", "izni"].contains { hata.localizedCaseInsensitiveContains($0) }
    }

    /// Sesli tur ölçümü (`SesTurOlcumu`); yalnız sıralı hat, gerçek zamanlı motorlar girmez.
    @ObservationIgnored private var tur: SesTurOlcumu?
    /// Dinleme açılırken ses oturumu etkinleşince, mikrofon motoru başlamadan önce çalan "dinliyorum" tonu.
    private var acilisIsareti: @MainActor () async -> Void { { await SesIsaretleri.ortak.cal(.dinliyorum) } }
    /// Aynı ton, beklenmeden: Live tur arası açılışlarda (ton mikrofon açılışını geciktirmez).
    private var acilisIsaretiBeklemeden: @MainActor () async -> Void { { SesIsaretleri.ortak.calBeklemeden(.dinliyorum) } }

    /// Ölçülen turu SaglikMerkezi'ne yazar (yalnız süre, kip ve ses sağlayıcısı) ve sıfırlar.
    private func turuKaydet() {
        guard let t = tur else { return }
        tur = nil
        guard let asamalar = t.asamalar() else { return }
        let saglayici = ayarlar.sesKimligi.split(separator: ":").first.map(String.init) ?? "apple"
        for a in asamalar {
            SaglikMerkezi.ortak.kaydet(a.tur, sure: a.sure, etiket: "\(t.kip)|\(saglayici)")
        }
    }

    private func komutSuresiniBaslat() {
        komutBekleme?.cancel()
        komutBekleme = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, uyandirma.durum == .komut, uyandirma.uyandirmaIleAcildi else { return }
            komutNesli += 1
            uyandirma.kapat()
            await dinleyici.durdur()
            // Komut penceresi süresinde boş kaldı: "kapandı" tonu bekleme dinlemesi açılmadan önce biter.
            await SesIsaretleri.ortak.cal(.kapandi)
            await uyandirmayiBaslat()
        }
    }

    private func uyandirmayiYenidenDene() {
        uyandirmaTekrar?.cancel()
        guard onPlanda, mod == .ellerSerbest, ayarlar.heyAsistan, !elleSusturuldu else { return }
        uyandirmaDeneme += 1
        let saniye = min(15, 2 + uyandirmaDeneme * 2)
        uyandirmaTekrar = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(saniye)) } catch { return }
            guard let self, !Task.isCancelled, self.onPlanda, self.mod == .ellerSerbest,
                  self.ayarlar.heyAsistan, !self.elleSusturuldu, !self.uyandirmaBekliyor,
                  !self.sesliKip, self.beyin.durum == .bosta, !self.konusmaci.konusuyor else { return }
            await self.uyandirmayiBaslat()
        }
    }

    // MARK: P2.13 Sesli onay

    /// Sesli kipte (eller serbest komutu ya da sıralı Live) ekrana gelen onayı seslendirir ve kısa süre sesli yanıt dinler.
    /// true/false: sesli karar; nil: sesli yol kullanılamaz ya da yanıt belirsiz (dokunmalı diyalog ekranda kalır).
    /// Gerçek zamanlı motor (OpenAI/Gemini) mikrofonu tutarken dinlenmez; CanliEkrani'nin diyaloğu kalır.
    func sesliOnayIste(_ i: OnayKapisi.Istek) async -> Bool? {
        // P4.7: sürüş kipinde sesli kip kapalıyken de sorulur (sürücü ekrana bakmasın); gerçek zamanlı Live'da yine sorulmaz.
        guard onPlanda, sesliKip || canliMod || SurusKipi.ortak.aktif, !gercekZamanliEtkin else { return nil }
        // FIFO'daki ikinci onay: öncekine dokunarak yanıt verildiyse onun sesli akışı birkaç yüz ms içinde sonlanır.
        // Hemen vazgeçmek yerine kısa süre beklenir (yoksa ikinci onay hiç sesli sorulmaz). İstek bu arada çözüldüyse vazgeçilir.
        var bekleme = 0
        while onayAkisi || onayDinleniyor, bekleme < 20, beyin.onay.bekleyen?.id == i.id {
            try? await Task.sleep(for: .milliseconds(100)); bekleme += 1
        }
        guard !onayAkisi, !onayDinleniyor, beyin.onay.bekleyen?.id == i.id else { return nil }
        onayAkisi = true
        defer { onayAkisi = false }
        // Onaylı tur "söz bitti → ilk ses" ölçümüne girmez (kullanıcının karar süresi ölçülmesin).
        tur = nil
        let karar = await sesliOnayDinle(i)
        // Bu arada dokunarak yanıtlandı ya da araç iptal edildi: sesli geri bildirim verilmez.
        guard beyin.onay.bekleyen?.id == i.id else { return nil }
        switch karar {
        case .evet: await konusmaci.soyleVeBekle("Tamam."); return true
        case .hayir: await konusmaci.soyleVeBekle("Peki, yapmıyorum."); return false
        case .belirsiz: await konusmaci.soyleVeBekle("Anlayamadım, ekrandan onayla."); return nil
        }
    }

    /// Soruyu okur, ardından `onayDinlemeSuresi` sn dinler (konuşma sürüyorsa en çok 2 sn daha). Dinleyici ayarları geri yüklenir.
    private func sesliOnayDinle(_ i: OnayKapisi.Istek) async -> SesliOnayKarari.Sonuc {
        // Önceki cümle bitsin; söz kesme motoru (VPIO) da kapansın: dinleyiciyle aynı anda açık kalmasın.
        await konusmaci.susmasiniBekle()
        sozKesme.durdur()
        guard beyin.onay.bekleyen?.id == i.id else { return .belirsiz }
        let soru = SesliOnayKarari.soruMetni(baslik: Konusmaci.okunabilir(i.baslik), ayrinti: Konusmaci.okunabilir(i.ayrinti))
        // Soru okunurken ekrandan yanıtlanırsa (id değişir) okuma kesilir: sıradaki onayın sorusu geç kalmasın.
        let degisimIzleyici = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                if self.beyin.onay.bekleyen?.id != i.id { self.konusmaci.sustur(); return }
            }
        }
        await konusmaci.soyleVeBekle(soru)
        degisimIzleyici.cancel()
        // Sınırda hâlâ okunuyorsa kesilir: mikrofon asistanın kendi sesini duymasın.
        if konusmaci.konusuyor { konusmaci.sustur() }
        sozKesme.durdur()
        guard beyin.onay.bekleyen?.id == i.id, onPlanda, !gercekZamanliEtkin else { return .belirsiz }
        let eski = (dinleyici.otomatikGonder, dinleyici.kesinSonucuHemenGonder, dinleyici.sessizlikMs)
        dinleyici.otomatikGonder = true
        dinleyici.kesinSonucuHemenGonder = true
        dinleyici.sessizlikMs = 700
        onayErkenKarar = nil
        onayAlici = { [weak self] metin, ornekler, oran in
            var k = SesliOnayKarari.karar(metin: metin, ornekler: ornekler, oran: oran)
            // P4.7: sürüşte "yok, yapma" gibi tam eşleşmeyen ret de ret sayılır (yalnız ret; onay gevşetilmez, fail-closed).
            if k == .belirsiz, SurusKipi.ortak.aktif, SurusKipi.evetHayir(metin) == false { k = .hayir }
            self?.onayiSonlandir(k)
        }
        if dinleyici.durum != .kapali { await dinleyici.durdur() }
        // Kullanıcı bu arada mikrofona dokunup yeni dinleme açarsa (komutNesli artar) onun dinlemesi kapatılmaz.
        let nesil = komutNesli
        await dinleyici.basla(acilis: acilisIsareti)
        let karar = await withCheckedContinuation { (c: CheckedContinuation<SesliOnayKarari.Sonuc, Never>) in
            if let e = onayErkenKarar { onayErkenKarar = nil; c.resume(returning: e); return }
            onayDevam = c
            onayBekci = Task { [weak self] in
                var gecen = 0.0
                while true {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    gecen += 0.2
                    guard let self else { return }
                    if self.beyin.onay.bekleyen?.id != i.id { break }
                    if case .hata = self.dinleyici.durum { break }
                    if gecen >= Self.onayDinlemeSuresi, self.dinleyici.canliMetin.isEmpty || gecen >= Self.onayDinlemeSuresi + 2 { break }
                }
                self?.onayiSonlandir(.belirsiz)
            }
        }
        onayBekci?.cancel(); onayBekci = nil
        onayAlici = nil
        onayErkenKarar = nil
        guard komutNesli == nesil else { return karar }
        await dinleyici.durdur()
        dinleyici.otomatikGonder = eski.0
        dinleyici.kesinSonucuHemenGonder = eski.1
        dinleyici.sessizlikMs = eski.2
        return karar
    }

    /// Sesli onayı tek atışla sonuçlandırır; devam henüz kurulmadıysa ilk karar saklanır.
    private func onayiSonlandir(_ s: SesliOnayKarari.Sonuc) {
        guard let c = onayDevam else {
            if onayAlici != nil, onayErkenKarar == nil { onayErkenKarar = s }
            return
        }
        onayDevam = nil
        c.resume(returning: s)
    }

    // MARK: P4.2 Bas-konuş ve arka planda Live

    /// Bas-konuş turu sürüyor (dinleme → yanıt → seslendirme). Sesli yanıt ayarı kapalı olsa da yanıt okunur.
    private(set) var tekSeferSesli = false
    /// Sıralı (Claude) Live uygulama arka plandayken sürüyor (Ayarlar 'Live arka planda sürsün').
    private(set) var arkaPlanCanli = false
    /// Kilit ekranı "Durdur" (IsiDurdurIntent → IsKoprusu) bu dinlemeyi kesmeli mi.
    var arkaPlanDinlemesiVar: Bool { tekSeferSesli || arkaPlanCanli }
    @ObservationIgnored private var basKonusBaslangic: Date?
    @ObservationIgnored private var canliArkaBaslangic: Date?
    @ObservationIgnored private var sonKonusma = Date()
    @ObservationIgnored private var canliBekciNesli = 0
    /// Kilit ekranı etkinliği .inactive evresinde (arka plana geçmeden) açıldı; arka plana geçilirse devralınır, dönülürse kapanır.
    @ObservationIgnored private var erkenCanliEtkinlik = false
    /// Komut bu süre içinde başlamazsa bas-konuş vazgeçer; konuşma sürüyorsa en çok `basKonusEnUzun` sn beklenir.
    nonisolated static let basKonusSuresi: Double = 12
    nonisolated static let basKonusEnUzun: Double = 24
    /// Arka planda Live bu kadar sessizlikte kapanır.
    nonisolated static let canliSessizlikSiniri: TimeInterval = 600

    nonisolated enum BasKonusSonucu: Equatable, Sendable { case gonder(String), vazgec(String) }

    /// Saf karar: bas-konuş bekçisinin vardığı sonuç. Boş (ya da yalnız boşluk) metin ve süre aşımı vazgeçmedir;
    /// `.gonder` "komut sürüyor, dinleyici kesinleştirince gönderir" demektir.
    nonisolated static func basKonusSonucu(metin: String?, sureAsildi: Bool) -> BasKonusSonucu {
        let t = (metin ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .vazgec("Komut duyulmadı") }
        if sureAsildi { return .vazgec("Komut tamamlanamadı") }
        return .gonder(t)
    }

    /// Saf karar: uygulama arka plana geçerken Live sürsün mü. Yalnız Live açık, ayar açık ve gerçek zamanlı motor
    /// (OpenAI Realtime / Gemini Live; WebSocket arka planda tutulmaz) kullanılmıyorken (sıralı Claude yolu).
    nonisolated static func arkaPlandaSurdur(canliMod: Bool, ayar: Bool, gercekZamanli: Bool) -> Bool {
        canliMod && ayar && !gercekZamanli
    }

    // MARK: P4.3 Arka planda Hey Asistan

    /// Bu arka plan döneminde 'Hey Asistan' beklemesi sürüyor (arka plana geçerken bekleme açıktı ve ayar açıktı).
    @ObservationIgnored private var arkaPlanUyandirmaEtkin = false
    /// Bu arka plan döneminde dinleme başlatılamadı/kesildi: öne gelinceye dek yeniden denenmez.
    @ObservationIgnored private var arkaPlanBaslatmaHatasi = false

    /// Saf karar: 'Arka planda Hey Asistan' beklemesi sürer (ya da arka planda yeniden açılır) mı. Ayar açık, bekleme
    /// etkin ve Live kapalı olmalı; arka planda bir başlatma hatası olduysa o dönem için hayır (sonsuz deneme yok).
    nonisolated static func arkaPlandaBeklemeSurer(ayar: Bool, bekliyor: Bool, canli: Bool,
                                                   onPlanda: Bool = false, sonHataArkaPlanda: Bool = false) -> Bool {
        ayar && bekliyor && !canli && (onPlanda || !sonHataArkaPlanda)
    }

    /// Arka planda dinleme hata verdi: tek tanı satırı yazılır, uygulama öne gelinceye dek yeniden başlatılmaz.
    private func arkaPlanBaslatmaHatasiniIsle() {
        guard arkaPlanUyandirmaEtkin, !arkaPlanBaslatmaHatasi else { return }
        arkaPlanBaslatmaHatasi = true
        TaniGunlugu.yaz("ARKA PLAN: dinleme yeniden başlatılamadı")
    }

    /// Saf karar: son konuşmadan bu yana sınır kadar (ya da daha çok) sessizlik geçti mi.
    nonisolated static func sessizlikDoldu(son: Date, simdi: Date, sinir: TimeInterval = 600) -> Bool {
        simdi.timeIntervalSince(son) >= sinir
    }

    /// Saf karar: yanıt bitince Live dinlemesi sürer mi. Önde ya da arka planda süren Live'da evet; görsel/arşiv/belge
    /// kiplerinde tur tek seferliktir.
    nonisolated static func canliSurer(onPlanda: Bool, arkaPlanCanli: Bool, canliMod: Bool, kip: CalismaKipi) -> Bool {
        (onPlanda || arkaPlanCanli) && canliMod && ![.gorsel, .arsiv, .belge].contains(kip)
    }

    /// Bas-konuş (AsistanBasKonusIntent): Live Activity açar (AudioRecordingIntent kuralı), ses oturumunu etkinleştirir,
    /// tek komut dinlemesini başlatır ve DÖNER (intent zaman aşımına düşmesin). Komut bekleme/vazgeçme `komutBekleme`
    /// görevinde sürer; komut gelince olağan `kullaniciKonustu` yolu gönderir, yanıt `tekSeferSesli` ile sesli okunur.
    func basKonusBaslat() async throws {
        // Live sürüyorsa bas-konuş söz almaktır: ikinci mikrofon yolu açılmaz.
        if canliMod || mod == .live || gercekZamanliEtkin { await sozuAl(); return }
        // Intent uygulamayı arka planda açtıysa sahne değişimi gelmeyebilir: Hey Asistan beklemesi açılmasın.
        if UIApplication.shared.applicationState == .background { onPlanda = false }
        // Süren yanıt/iş söz alınınca kesilir. İptalin kapattığı iş etkinliği (Beyin.durum didSet) bizimkini kapatmasın.
        konusmaci.sustur(); sozKesme.durdur()
        if beyin.durum != .bosta { beyin.iptal() }
        var bekleme = 0
        while beyin.isAktivitesi.acik, bekleme < 20 { try? await Task.sleep(for: .milliseconds(50)); bekleme += 1 }
        basKonusBaslangic = .now
        beyin.isAktivitesi.baslat(istek: "Sesli komut", baslangic: .now, durum: .init(adim: "Dinliyorum", dinliyor: true))
        if !beyin.isAktivitesi.acik { TaniGunlugu.yaz("LIVE ACTIVITY açılamadı (bas-konuş, sahne=\(Self.sahneAdi(UIApplication.shared.applicationState)))") }
        TaniGunlugu.yaz("BAS-KONUŞ: başladı (önde=\(onPlanda))")
        do { try await Self.oturumuAyarla() } catch {
            await beyin.isAktivitesi.bitir(sureSn: 0, hata: false, adim: "Mikrofon açılamadı")
            throw error
        }
        komutNesli += 1; komutBekleme?.cancel()
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        if uyandirmaBekliyor { uyandirma.kapat() }
        if dinleyici.durum != .kapali { await dinleyici.durdur() }
        siriTakip = false
        elleSusturuldu = false
        tekSeferSesli = true
        uyandirma.elleDinle()
        dinleyici.otomatikGonder = true
        dinleyici.kesinSonucuHemenGonder = false
        dinleyici.sessizlikMs = 1200
        dinleyici.akilliSon = ayarlar.akilliKonusmaSonu
        kumandaBagla()
        tur = nil
        await dinleyici.basla(acilis: acilisIsareti)
        if case .hata(let h) = dinleyici.durum {
            await basKonusuKapat(adim: Self.mikrofonHataMetni(h, live: false))
            return
        }
        let nesil = komutNesli
        komutBekleme = Task { [weak self] in
            var gecen = 0.0
            while true {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                gecen += 0.25
                guard let self, self.komutNesli == nesil, self.tekSeferSesli, self.uyandirma.durum == .komut else { return }
                guard gecen >= Self.basKonusSuresi else { continue }
                if case .vazgec(let neden) = Self.basKonusSonucu(metin: self.dinleyici.canliMetin,
                                                                 sureAsildi: gecen >= Self.basKonusEnUzun) {
                    // Kapatma bu görevi (komutBekleme) iptal eder; ton ve oturum bırakma iptalsiz ayrı görevde koşar.
                    Task { await self.basKonusuKapat(adim: neden) }
                    return
                }
            }
        }
    }

    /// Bas-konuş turu yanıtla bitti (konusmaBitti): bayrak iner, Beyin'in kapatmadığı etkinlik (yerel komut, yanıtsız tur) biter.
    private func basKonusTurunuKapat() {
        tekSeferSesli = false
        let sure = basKonusBaslangic.map { Int(Date().timeIntervalSince($0)) } ?? 0
        basKonusBaslangic = nil
        if beyin.isAktivitesi.acik {
            let hata = beyin.sonHata != nil
            Task { await beyin.isAktivitesi.bitir(sureSn: sure, hata: hata) }
        }
    }

    /// Bas-konuş vazgeçti ya da durduruldu: mikrofon kapanır ("kapandı" tonu), etkinlik verilen adımla gri biter;
    /// uygulama öndeyse Hey Asistan beklemesi geri gelir.
    private func basKonusuKapat(adim: String) async {
        guard tekSeferSesli else { return }
        tekSeferSesli = false
        let sure = basKonusBaslangic.map { Int(Date().timeIntervalSince($0)) } ?? 0
        basKonusBaslangic = nil
        let oncekiSusturma = elleSusturuldu
        await sesliKipiKapat()
        elleSusturuldu = oncekiSusturma
        if beyin.durum == .bosta { await beyin.isAktivitesi.bitir(sureSn: sure, hata: false, adim: adim) }
        TaniGunlugu.yaz("BAS-KONUŞ: kapandı (\(adim))")
        if onPlanda { await uyandirmayiBaslat() }
    }

    /// Kilit ekranı "Durdur": bas-konuş ya da arka plan Live'ı keser (süren yanıt da iptal edilir).
    func arkaPlanDinlemesiniDurdur() async {
        if arkaPlanCanli { await arkaPlanCanliyiKapat(adim: "Durduruldu", liveBitir: true); return }
        guard tekSeferSesli else { return }
        if beyin.durum != .bosta { beyin.iptal() }   // durum didSet iş etkinliğini "Durduruldu" ile kapatır
        await basKonusuKapat(adim: "Durduruldu")
    }

    /// Arka planda Live başladı: kilit ekranı etkinliği açılır, sessizlik bekçisi (5 sn aralıkla) çalışır.
    private func arkaPlanCanliyiBaslat() {
        arkaPlanCanli = true
        canliArkaBaslangic = .now
        sonKonusma = .now
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        TaniGunlugu.yaz("LIVE arka planda sürüyor")
        erkenCanliEtkinlik = false
        canliEtkinliginiAc()
        canliBekciNesli += 1
        let nesil = canliBekciNesli
        // Bekçi kendini iptal etmez (iptal edilmiş görevde canliBitir'in bekleme döngüsü dönmez); nesil değişince çıkar.
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.canliBekciNesli == nesil, self.arkaPlanCanli else { return }
                if !self.canliMod || self.mod != .live {
                    await self.arkaPlanCanliyiKapat(adim: "Canlı konuşma bitti", liveBitir: false)
                    return
                }
                // Asistan düşünürken/konuşurken ya da kullanıcı konuşurken sessizlik sayılmaz.
                if self.beyin.durum != .bosta || (self.konusmaci.konusuyor && !self.konusmaci.duraklatildi) || !self.dinleyici.canliMetin.isEmpty {
                    self.sonKonusma = .now
                    continue
                }
                if Self.sessizlikDoldu(son: self.sonKonusma, simdi: .now, sinir: Self.canliSessizlikSiniri) {
                    TaniGunlugu.yaz("LIVE arka planda 10 dk sessiz kaldı, kapatıldı")
                    await self.arkaPlanCanliyiKapat(adim: "Sessizlik: canlı kapandı", liveBitir: true)
                    return
                }
            }
        }
    }

    /// Kilit ekranında 'Canlı · dinliyorum' etkinliği (Beyin bir iş etkinliği açmamışsa).
    /// Activity.request yalnız ön planda (.inactive dahil) başarılıdır; arka planda açılışı iOS reddeder ve
    /// `IsAktivitesi.baslat` hatayı yuttuğundan sonuç burada `acik` ile denetlenip günlüğe yazılır.
    private func canliEtkinliginiAc() {
        guard arkaPlanCanli, !beyin.isAktivitesi.acik, beyin.durum == .bosta else { return }
        beyin.isAktivitesi.baslat(istek: "Canlı konuşma", baslangic: canliArkaBaslangic ?? .now,
                                  durum: .init(adim: "Canlı · dinliyorum", dinliyor: true))
        if !beyin.isAktivitesi.acik {
            TaniGunlugu.yaz("LIVE ACTIVITY açılamadı (canlı, sahne=\(Self.sahneAdi(UIApplication.shared.applicationState)))")
        }
    }

    /// .inactive'te (hâlâ ön plan) kilit ekranı etkinliği açılır: arka plana geçince yalnız güncellenir.
    /// AsistanApp scenePhase == .inactive iken çağırır; Live arka planda sürmeyecekse hiçbir şey yapmaz.
    func arkaPlanaGeciliyor() {
        let gercekZamanli = gercekZamanliEtkin || gercekLive.durum == .baglaniyor || openaiLive.durum == .baglaniyor
        guard onPlanda, mod == .live, !tekSeferSesli, !arkaPlanCanli,
              Self.arkaPlandaSurdur(canliMod: canliMod, ayar: ayarlar.canliArkaPlan, gercekZamanli: gercekZamanli),
              !beyin.isAktivitesi.acik, beyin.durum == .bosta else { return }
        beyin.isAktivitesi.baslat(istek: "Canlı konuşma", baslangic: .now, durum: .init(adim: "Canlı · dinliyorum", dinliyor: true))
        if beyin.isAktivitesi.acik { erkenCanliEtkinlik = true }
        else { TaniGunlugu.yaz("LIVE ACTIVITY açılamadı (canlı, sahne=\(Self.sahneAdi(UIApplication.shared.applicationState)))") }
    }

    nonisolated static func sahneAdi(_ d: UIApplication.State) -> String {
        switch d {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "?"
        }
    }

    /// Arka plan Live'ı biter: bekçi durur, etkinlik verilen adımla kapanır. `liveBitir`: Live da tümüyle kapatılır
    /// (sessizlik, Durdur); öne dönüşte false (Live olağan sürer).
    private func arkaPlanCanliyiKapat(adim: String, liveBitir: Bool) async {
        guard arkaPlanCanli else { return }
        arkaPlanCanli = false
        canliBekciNesli += 1
        let sure = canliArkaBaslangic.map { Int(Date().timeIntervalSince($0)) } ?? 0
        canliArkaBaslangic = nil
        if liveBitir { await canliBitir() }
        if beyin.durum == .bosta { await beyin.isAktivitesi.bitir(sureSn: sure, hata: false, adim: adim) }
    }

    // MARK: P2.13 Siri devri

    /// Siri'den `ses=1` ile devredilen soru gönderildi (sohbet ekranı çağırır): yanıt sesli okunur, bitince kısa takip
    /// penceresi açılır. Eller serbest bekleme dinlemesi açıksa önce kapatılır (asistan kendi sesini duymasın).
    func disSesliTurBasladi() async {
        guard onPlanda, !sesliKip, mod != .live, !canliMod, !gercekZamanliEtkin else { return }
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        komutNesli += 1; komutBekleme?.cancel()
        let bekliyordu = uyandirmaBekliyor
        if bekliyordu { uyandirma.kapat() }
        // Çok hızlı biten turda yanıt zaten okunuyorsa kesilmez; yalnız bitince takip penceresi açılır.
        let zatenOkunuyor = konusmaci.konusuyor
        siriTakip = true
        // Bölücü sıfırlanır; yanıt aşağıdaki beklemeler sürerken biterse yanitTamamlandi tamamını okur.
        if !zatenOkunuyor { konusmaci.akisBasladi() }
        if bekliyordu { await dinleyici.durdur() }
        try? await Self.oturumuAyarla()
        guard siriTakip, !zatenOkunuyor else { return }
        if beyin.durum != .bosta { akisiIzle(); return }
        guard !konusmaci.konusuyor else { return }
        // Yanıt bu görev başlamadan bitti (yerel komut): son asistan yanıtı okunur.
        if let son = beyin.mesajlar.last, son.rol == .asistan, !son.metin.isEmpty, beyin.seslendirilebilir {
            konusmaci.akisBitti(seslendirilecek(son.metin))
        } else {
            siriTakip = false
            await uyandirmayiBaslat()
            oturumuBirakGerekirse()
        }
    }

    /// Siri devrinin yanıtı okundu: `siriTakipSuresi` sn elle açılmış gibi dinlenir. Konuşulursa olağan tur sürer
    /// (yanıttan sonra kapanır); sessiz kalırsa dinleme kapanır ve (açıksa) Hey Asistan beklemesi geri gelir.
    private func siriTakipPenceresiAc() async {
        guard onPlanda, !sesliKip, mod != .live, !gercekZamanliEtkin, beyin.durum == .bosta, !konusmaci.konusuyor else { return }
        let oncekiSusturma = elleSusturuldu
        komutNesli += 1; komutBekleme?.cancel()
        uyandirmaTekrar?.cancel(); uyandirmaTekrar = nil
        if uyandirmaBekliyor { uyandirma.kapat() }
        if dinleyici.durum != .kapali { await dinleyici.durdur() }
        uyandirma.elleDinle()
        dinleyici.otomatikGonder = true
        dinleyici.kesinSonucuHemenGonder = false
        dinleyici.sessizlikMs = 1200
        dinleyici.akilliSon = ayarlar.akilliKonusmaSonu
        tur = nil
        await dinleyici.basla(acilis: acilisIsareti)
        guard uyandirma.durum == .komut else { return }
        let nesil = komutNesli
        komutBekleme = Task { [weak self] in
            var gecen = 0.0
            while true {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                gecen += 0.25
                guard let self, self.komutNesli == nesil, self.uyandirma.durum == .komut else { return }
                // Konuşma sürüyorsa en çok 12 sn daha beklenir.
                if gecen >= Self.siriTakipSuresi, self.dinleyici.canliMetin.isEmpty || gecen >= Self.siriTakipSuresi + 12 { break }
            }
            guard let self, self.komutNesli == nesil, self.uyandirma.durum == .komut else { return }
            await self.sesliKipiKapat()   // "kapandı" işareti, oturum bırakma
            self.elleSusturuldu = oncekiSusturma
            await self.uyandirmayiBaslat()
        }
    }
}

/// Ses oturumu etkinleştirme/bırakma sırası (ana aktör dışında). Etkinleştirme isteği nesli eşzamanlı artırır;
/// bırakma, kararı verildiği andaki nesil hâlâ geçerliyse yapılır. Böylece arka planda gecikmiş bir bırakma,
/// kullanıcının hemen ardından açtığı yeni dinlemeyi (ya da Live sesini) kapatamaz.
actor SesOturumuKapisi {
    nonisolated static let ortak = SesOturumuKapisi()
    nonisolated static let istek = SesOturumuNesli()

    func etkinlestir() async throws {
        let o = AVAudioSession.sharedInstance()
        // Varsayılan Bluetooth HFP yok: eşleşmiş kulaklık kutudayken giriş sıfır geliyordu (14 Eki). Çıkış A2DP'ye gidebilir,
        // giriş telefonda kalır. P3.12: Ayarlar 'Kulaklık mikrofonu' / 'Kulaklık düğmesi' açıksa yol YolSecici'de seçilir.
        try YolSecici.uygula(o)
        // 28 Eki A–Z kabulü: Live tur arası yeniden açılışta '!int' (cannotInterruptOthers, 560557684). Ses çıkışı yeni bitmiş,
        // sistem oturum geçişini henüz kapatmamışken gelir; kısa beklemeyle ikinci deneme geçer. Kalıcı hata ise son deneme fırlatır.
        var deneme = 0
        let baslangicBirakma = birakmaNesli
        while true {
            // Uyku sırasında aktör serbesttir: araya bir bırakma girdiyse (kullanıcı Live'ı bitirdi) oturumu yeniden açma;
            // yoksa kapalı Live'ın ardından .duckOthers oturumu açık kalır, müzik kısık kalır.
            guard birakmaNesli == baslangicBirakma else { throw CancellationError() }
            do { try o.setActive(true); break } catch {
                deneme += 1
                let kod = (error as NSError).code
                let durum = "kod=\(kod) kategori=\(o.category.rawValue) digerSes=\(o.isOtherAudioPlaying) ikincilSes=\(o.secondaryAudioShouldBeSilencedHint)"
                guard Self.gecici(kod), deneme < Self.beklemeler.count + 1 else {
                    TaniGunlugu.yaz("SES OTURUMU etkinleşmedi (\(deneme). deneme, vazgeçildi): \(durum)")
                    throw error
                }
                TaniGunlugu.yaz("SES OTURUMU etkinleşmedi (\(deneme). deneme, yeniden): \(durum)")
                try await Task.sleep(for: .milliseconds(Self.beklemeler[deneme - 1]))
            }
        }
        if o.isInputGainSettable, o.inputGain < 0.5 { try? o.setInputGain(1.0) }
        print("[SES] oturum etkin: kategori=\(o.category.rawValue) kip=\(o.mode.rawValue) giriş=\(o.currentRoute.inputs.map(\.portName)) çıkış=\(o.currentRoute.outputs.map(\.portName)) izin=\(AVAudioApplication.shared.recordPermission.rawValue) prompt=\(o.promptStyle.rawValue)")
    }

    /// Geçici sayılan AVAudioSession hataları: '!int' cannotInterruptOthers, '!pri' insufficientPriority, '!act' isBusy (561017449).
    nonisolated static func gecici(_ kod: Int) -> Bool {
        [AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue, AVAudioSession.ErrorCode.insufficientPriority.rawValue,
         AVAudioSession.ErrorCode.isBusy.rawValue].contains(kod)
    }
    /// Yeniden deneme beklemeleri (ms): toplam ≈ 1 sn; Live tur arası gecikmesi yalnız hata olduğunda eklenir.
    nonisolated static let beklemeler: [Int] = [150, 300, 550]

    /// Diğer uygulamaların kısılan sesini geri verir. Arada yeni bir etkinleştirme istendiyse hiçbir şey yapmaz.
    /// Geçerli nesille yapılan bırakma sayısı; yeniden denemedeki `etkinlestir` bununla vazgeçer.
    private var birakmaNesli = 0

    func birak(nesil: Int) {
        guard Self.istek.deger == nesil else { return }
        birakmaNesli += 1
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { print("[SES] oturum bırakılamadı: \(error.localizedDescription)") }
    }
}

/// Kilitli sayaç: ses oturumu etkinleştirme istekleri (herhangi bir iş parçacığından artırılabilir).
nonisolated final class SesOturumuNesli: @unchecked Sendable {
    private let kilit = NSLock()
    private var sayi = 0
    var deger: Int { kilit.withLock { sayi } }
    @discardableResult func artir() -> Int { kilit.withLock { sayi += 1; return sayi } }
}
