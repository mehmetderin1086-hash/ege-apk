import Foundation
import FoundationModels
import ClaudeForFoundationModels
import CoreGraphics
import UIKit

/// Model kurma ve araçlı model zinciri (vekil → yedek, yeniden deneme, zaman aşımı).
extension Beyin {
    // MARK: Model kurma
    func claudeModeli(_ adim: ModelZinciri.Adim, caba istenen: ClaudeModel.Effort, webArama: Bool? = nil, timeout: TimeInterval = 120) -> ClaudeLanguageModel {
        let model = ClaudeModel.sabit(adim.model)
        let caba = model.capabilities.effortLevels.contains(istenen) ? istenen : nil
        if webArama == nil { uygulananCaba = caba.flatMap { DusunmeSecimi.Caba(rawValue: $0.rawValue) } }
        let sunucu: Set<ClaudeServerTool> = [] // WebAraci supplies cited research through the phone proxy.
        switch adim.yol {
        case .telefon:
            return ClaudeLanguageModel(name: model,
                                       auth: .proxied(headers: ["Authorization": "Bearer \(TelefonProxy.ortak.yerelAnahtar)"]),
                                       fixedEffort: caba, serverTools: sunucu,
                                       baseURL: TelefonProxy.ortak.taban, timeout: timeout)
        case .vekil:
            return ClaudeLanguageModel(name: model,
                                       auth: .proxied(headers: ["X-Personal-Token": Gizli.vekilToken ?? ""]),
                                       fixedEffort: caba, serverTools: sunucu,
                                       baseURL: Gizli.vekilTaban!, timeout: timeout)
        case .anahtar:
            return ClaudeLanguageModel(name: model, auth: .apiKey(Gizli.claudeAnahtari ?? ""),
                                       fixedEffort: caba, serverTools: sunucu, timeout: timeout)
        }
    }

    func oturumGetir(_ adim: ModelZinciri.Adim, caba: DusunmeSecimi.Caba, canliSes: Bool) -> LanguageModelSession {
        // P3.4: gruplama açıkken imzaya araç grubu ve oturum ek bağlamı (kestirmeler, kişiselleştirme, proje) da girer;
        // değişince oturum transcript korunarak yeni talimat ve araç alt kümesiyle yeniden kurulur. Kapalıyken imza aynıdır.
        let gruplama = ayarlar.aracGruplama
        let ekBaglam = gruplama ? oturumEkBaglami() : ""
        let imza = "\(caba.rawValue)|\(ayarlar.webArama)|\(TelefonKestirmeleri.ortak.kayitlar)"
            + (gruplama ? "|g=\(AracGruplari.imza(aracGrubu))|e=\(ekBaglam.hashValue)" : "")
        let ayniAyar = oturumYolu == adim.yol && oturumModeli == adim.model && oturumAyarImzasi == imza
        if let oturum, ayniAyar, disGecmis.isEmpty { return oturum }
        // Kısa isteklerde uzun süre sessiz kalan sağlayıcı, otomatik yedek
        // seçeneğe geçebilsin. Yüksek çaba gerektiren işlerin bütçesi korunur.
        let model = claudeModeli(adim, caba: ClaudeModel.Effort(rawValue: caba.rawValue)!, timeout: Self.yanitZamanAsimi(caba, canliSes: canliSes))
        var yeni: LanguageModelSession
        if let eski = oturum, gruplama {
            // P3.4: geçmiş korunur; ilk talimat girdisi yeni talimat + seçilen araçların tanımlarıyla değiştirilir.
            let secilen = secilenAraclar(eski.transcript)
            let talimat = AracGruplari.talimat(olgular: depo.talimatOlgulari(), gruplar: aracGrubu, ekBaglam: ekBaglam)
            yeni = LanguageModelSession(model: model, tools: secilen,
                                        transcript: Self.talimatDegistir(eski.transcript, talimat: talimat, araclar: secilen))
        } else if let eski = oturum, oturumAyarImzasi?.contains("|g=") == true {
            // P3.4 bayrağı oturum sürerken kapatıldı: süzülmüş talimat ve alt küme tanımları tam metinle değiştirilir.
            yeni = LanguageModelSession(model: model, tools: araclar,
                                        transcript: Self.talimatDegistir(eski.transcript, talimat: Talimatlar.olustur(olgular: depo.talimatOlgulari()), araclar: araclar))
        } else if let eski = oturum {
            // Yol/model değişti: geçmişi (talimat dahil, transcript'in içinde) koru.
            yeni = LanguageModelSession(model: model, tools: araclar, transcript: eski.transcript)
        } else {
            // Olgular yalnız oturum kurulurken talimata girer; sonradan eklenenler "hafiza" aracı üzerinden zaten modelin elindedir.
            yeni = gruplama
                ? LanguageModelSession(model: model, tools: secilenAraclar(Transcript()),
                                       instructions: AracGruplari.talimat(olgular: depo.talimatOlgulari(), gruplar: aracGrubu, ekBaglam: ekBaglam))
                : LanguageModelSession(model: model, tools: araclar,
                                       instructions: Talimatlar.olustur(olgular: depo.talimatOlgulari()))
            // Taze oturum (ilk istek, Durdur'dan sonra, uygulama yeniden açılınca): bağlam ekrandaki konuşmadan kurulur;
            // aksi hâlde her mesaj sıfırdan başlar. Kısa yolların (yerel yanıt, yarış) biriktirdiği çiftler zaten
            // mesajlar'da olduğundan disGecmis her zaman baştan kurulur; yoksa Durdur'dan sonra yalnız son çift kalırdı.
            let ozetCifti: [Transcript.Entry] = ozet.isEmpty ? [] : [
                .prompt(.init(segments: [.text(.init(content: "[Önceki konuşmanın özeti — yalnız bağlam]\n\(ozet)"))])),
                .response(.init(segments: [.text(.init(content: "Anlaşıldı; bu bağlamı kullanacağım."))]))]
            let sinir = Self.tazeGecmisSiniri(mesajSayisi: mesajlar.count, sikistirmaTabani: sikistirmaTabani, ozetVar: !ozet.isEmpty)
            disGecmis = ozetCifti + mesajlardanGecmis(en: sinir)
        }
        if !disGecmis.isEmpty {
            let birlesik = Transcript(entries: Array(yeni.transcript) + disGecmis)
            yeni = LanguageModelSession(model: model, tools: gruplama ? secilenAraclar(birlesik) : araclar,
                                        transcript: birlesik)
            disGecmis = []
        }
        oturum = yeni; oturumYolu = adim.yol; oturumModeli = adim.model; oturumAyarImzasi = imza
        return yeni
    }

    // MARK: P3.4 araç grubu ve transcript yardımcıları

    /// Bu tur için modele verilecek araçlar: süzgecin grubu (yoksa tam set) + transcript'te geçmişte çağrılmış araçlar.
    func secilenAraclar(_ t: Transcript) -> [any Tool] {
        guard let g = aracGrubu else { return araclar }
        return AracGruplari.secilen(g, hepsi: araclar, ek: AracGruplari.gecmisAraclari(t))
    }

    /// Gruplama açıkken her tura eklenmeyip oturum talimatına giren bağlam. Kestirme listesi yalnız cihaz grubu
    /// (kisayolCalistir) seçiliyken ya da tam sette girer.
    func oturumEkBaglami() -> String {
        let kestirmeVar = aracGrubu.map { $0.contains("cihaz") } ?? true
        let kestirmeler = kestirmeVar ? TelefonKestirmeleri.ortak.kayitlar.map { "\($0.ad) → \($0.kestirme)" } : []
        return AracGruplari.ekBaglam(kestirmeler: kestirmeler, dostBaglami: ayarlar.dostBaglami,
                                     projeTalimati: ProjeDeposu.ortak.aktif?.talimat)
    }

    /// Saf: ilk talimat girdisinin metnini (ve `araclar` verilirse araç tanımlarını) değiştirir; talimat girdisi yoksa başa ekler.
    nonisolated static func talimatDegistir(_ t: Transcript, talimat: String, araclar: [any Tool]? = nil) -> Transcript {
        var girdiler = Array(t)
        let tanimlar = araclar?.map { Transcript.ToolDefinition(tool: $0) }
        if let i = girdiler.firstIndex(where: { if case .instructions = $0 { true } else { false } }),
           case .instructions(var ins) = girdiler[i] {
            ins.segments = [.text(.init(content: talimat))]
            if let tanimlar { ins.toolDefinitions = tanimlar }
            girdiler[i] = .instructions(ins)
        } else {
            girdiler.insert(.instructions(.init(segments: [.text(.init(content: talimat))], toolDefinitions: tanimlar ?? [])), at: 0)
        }
        return Transcript(entries: girdiler)
    }

    /// Saf: tura özel blokları (hafıza notu, süzgeç bloğu, kip talimatı, uzman bağlamı) yanıttan sonra ayıklar.
    /// Son prompt'un metni `temiz` olur (ilk metin parçası; diğer metin parçaları atılır). Eski turların görselleri
    /// "[görsel eklenmişti]" metnine çevrilir; son turunkiler `gorselKoru` ise korunur.
    nonisolated static func sonIstemiSadelestir(_ t: Transcript, temiz: String, gorselKoru: Bool) -> Transcript {
        var girdiler = Array(t)
        guard let son = girdiler.lastIndex(where: { if case .prompt = $0 { true } else { false } }) else { return t }
        let yerTutucu = Transcript.Segment.text(.init(content: "[görsel eklenmişti]"))
        for i in girdiler.indices {
            guard case .prompt(var p) = girdiler[i] else { continue }
            var yeni: [Transcript.Segment] = []
            var metinYazildi = false
            for seg in p.segments {
                switch seg {
                case .text:
                    if i == son {
                        if !metinYazildi { yeni.append(.text(.init(content: temiz))); metinYazildi = true }
                    } else {
                        yeni.append(seg)
                    }
                case .attachment:
                    yeni.append(i == son && gorselKoru ? seg : yerTutucu)
                default:
                    yeni.append(seg)
                }
            }
            if i == son, !metinYazildi { yeni.insert(.text(.init(content: temiz)), at: 0) }
            p.segments = yeni
            girdiler[i] = .prompt(p)
        }
        return Transcript(entries: girdiler)
    }

    nonisolated static func yanitZamanAsimi(_ caba: DusunmeSecimi.Caba, canliSes: Bool = false) -> TimeInterval {
        // Sıralı Live akışında iki ayrı CLIProxy yolu vardır. Normal sohbetin
        // 18 saniyelik bütçesi burada iki kez harcanırsa kullanıcı sessizce
        // 40 saniyeden fazla bekliyordu. İlk ses için kısa bütçe, çalışan
        // Antigravity hattını korur; takılan hat ise hızla ölçülmüş yedeğe
        // geçer. Yüksek çabalı yazılı isteklerin normal bütçesi değişmez.
        if canliSes { return 8 }
        return switch caba {
        case .low: 6
        case .medium: 10
        case .high: 50
        }
    }

    /// Taze oturumda ekrandan taşınacak mesaj sayısı (güncel istek hariç). Özet varsa özetlenmiş mesajlar ikinci kez taşınmaz.
    nonisolated static func tazeGecmisSiniri(mesajSayisi: Int, sikistirmaTabani: Int, ozetVar: Bool) -> Int {
        ozetVar ? min(16, max(0, mesajSayisi - 1 - sikistirmaTabani)) : 16
    }

    /// Bekçiye verilen araç sayısı: yalnız bu denemede başlatılanlar (toplam sayaç sıfırlanmaz, birikir).
    nonisolated static func denemeAracSayisi(toplam: Int, taban: Int) -> Int { max(0, toplam - taban) }

    /// Denemenin mutlak sınırı: metin akmaya başladıysa 360 sn (uzun araçsız rapor/çeviri kesilmesin), bu denemede araç
    /// çalıştıysa 240 sn, yoksa 90 sn. Takılan akış ayrıca AkisBekcisi'nde boşta kalma süresiyle (ilerleme sonrası 30 sn) kesilir;
    /// bu sınır yalnız bitmeyen akışa karşı. İlk metin bütçesi (yanitZamanAsimi) değişmez.
    nonisolated static func bekciMutlakSiniri(aracSayisi: Int, metinVar: Bool = false) -> TimeInterval {
        if metinVar { return 360 }
        return aracSayisi > 0 ? 240 : 90
    }


    /// P4.2: uygulama arka planda mı (bas-konuş, kilit ekranında Live). Arka planda iPhone CLIProxy yolu ve paralel yarış
    /// (ikisi de yerel loopback sunucuya gider) atlanır.
    static var arkaPlanda: Bool { UIApplication.shared.applicationState == .background }

    /// `temizMetin` (P3.4, yalnız gruplama açıkken dolu): istemin kullanıcı kısmı; yanıttan sonra transcript'teki son istem buna
    /// sadeleştirilir (tura özel bloklar sonraki turlara taşınmaz).
    func calistir(_ metin: String, gorseller: [CGImage], caba: DusunmeSecimi.Caba, canliSes: Bool, nesil buNesil: Int, temizMetin: String? = nil) async {
        #if DEBUG
        let liveTani = ProcessInfo.processInfo.arguments.contains("--asistan-live-sinama")
        if liveTani { print("[LIVE-TANI] model akışı başladı") }
        #endif
        // P4.2: arka planda (bas-konuş, kilitliyken Live) yerel loopback sunucu askıda olabilir; hazırlık beklenmez, .telefon atlanır.
        let arkaPlanda = Self.arkaPlanda
        if !ayarlar.yalnizAnahtar, !arkaPlanda { await TelefonProxy.ortak.hazirla() }
        // P3.4: araç çıktılarıyla şişen oturum transcript'i de sıkıştırmayı tetikler (ekrandaki mesajlar onları göstermez).
        let transcriptOlcusu = oturum.map { Self.transcriptUzunlugu($0.transcript) } ?? 0
        if Self.sikistirmaGerekli(mesajlar: mesajlar.map(\.metin), tabani: sikistirmaTabani, transcriptUzunlugu: transcriptOlcusu) {
            await baglamSikistir()
            // Mesaj özeti transcript'i küçültmediyse (az mesaj, uzun araç çıktısı) oturum ekrandaki konuşmadan yeniden kurulur.
            if let o = oturum, Self.transcriptUzunlugu(o.transcript) > Self.transcriptSikistirmaEsigi {
                TaniGunlugu.yaz("TRANSCRIPT SIFIRLANDI: \(Self.transcriptUzunlugu(o.transcript)) karakter")
                oturum = nil; oturumYolu = nil; oturumModeli = nil; oturumAyarImzasi = nil
            }
        }
        #if DEBUG
        if liveTani { print("[LIVE-TANI] telefon proxy hazır") }
        #endif
        guard !Task.isCancelled, buNesil == nesil else { return }
        let kotaBeklemeleri = await TelefonProxy.ortak.kotaBeklemeleri()
        for model in HizliModelSecimi.adaylar(caba) {
            for (aile, sure) in kotaBeklemeleri where model.hasPrefix(aile) { modelVitesi.beklet(model, saniye: sure) }
        }
        guard !Task.isCancelled, buNesil == nesil else { return }
        var modeller = modelVitesi.sira(caba: caba, kip: aktifKip, metin: sonKullaniciMetni, gorsel: !gorseller.isEmpty && !canliSes,
                                       modeller: TelefonProxy.ortak.modeller.map(\.id), elle: ayarlar.modelKimligi,
                                       otomatik: ayarlar.otomatikModel, yalnizAnahtar: ayarlar.yalnizAnahtar, canliSes: canliSes, canliClaude: ayarlar.canliClaude)
        modelSecimNotu = ayarlar.otomatikModel ? "Sohbet: Haiku · GPT · Gemini paralel yarışır, ilk yanıt kazanır. Araçlı işler: sabit birincil + yedek sırası" : "Elle seçilen model"
        if !ayarlar.otomatikModel {
            // Elle seçilen model önce denenir; hata verirse ölçülmüş yedekler devreye girer.
            let yedek = modelVitesi.sira(caba: caba, kip: aktifKip, metin: sonKullaniciMetni, gorsel: !gorseller.isEmpty && !canliSes,
                                         modeller: TelefonProxy.ortak.modeller.map(\.id), elle: ayarlar.modelKimligi,
                                         otomatik: true, yalnizAnahtar: ayarlar.yalnizAnahtar, canliSes: canliSes)
            modeller += yedek.filter { !modeller.contains($0) }
        }
        if ayarlar.otomatikModel, ayarlar.antigravityOncelik, zorlananModel == nil, !(canliSes && ayarlar.canliClaude) {
            modeller = ModelVitesi.antigravityOncele(modeller, mevcut: TelefonProxy.ortak.modeller.map(\.id), caba: caba)
        }
        if let z = zorlananModel { modeller = [z] + modeller.filter { $0 != z } }   // yeniden üretim: seçilen model önce
        modeller = AjanDefteri.ortak.butceyeGoreSuz(modeller, zorla: zorlananModel)   // günlük Opus/Fable sınırı
        let z = zincir
        let adimKur: (Bool) -> [ModelZinciri.Adim] = { yoksay in
            modeller.flatMap { z.adimlar(model: $0, askiYoksay: yoksay).filter { $0.yol != .anahtar || $0.model.hasPrefix("claude-") } }
        }
        var adimlar = adimKur(false)
        // P3.7: bütün adımlar model|yol ya da rota askısındaysa yine de dene (askı yalnız öncelik düşürür).
        if adimlar.isEmpty { adimlar = adimKur(true) }
        adimlar = ModelZinciri.arkaPlanSuz(adimlar, arkaPlanda: arkaPlanda)
        guard !adimlar.isEmpty else {
            bitir(hata: modeller.isEmpty ? "Uygun modeller kota veya erişim sınırı nedeniyle beklemede. Biraz sonra yeniden dene; Ayarlar’dan elle model de seçebilirsin." : "CLI Proxy uygulamasında hesabını bağla, sonra Asistan'a dön ve tekrar dene.", tur: modeller.isEmpty ? .kota : .yetki, nesil: buNesil)
            return
        }
        var sonHata: (any Error)?
        var sonYol: ModelZinciri.Yol?
        var denemeler = 0
        var sinirliAileler = Set<String>()
        var yenidenDenenen = Set<String>()
        var tamSetDenendi = false   // P3.4: alt kümeyle yetersiz yanıtta tam setle tek yeniden deneme
        var i = -1
        while i + 1 < adimlar.count {
            i += 1
            let adim = adimlar[i]
            if Task.isCancelled || buNesil != nesil { return }
            let aile = adim.model.hasPrefix("claude-") ? "claude" : (adim.model.hasPrefix("gpt-") ? "gpt" : "gemini")
            if sinirliAileler.contains(aile) { continue }
            guard denemeler < 3 else { break }; denemeler += 1
            aktifYol = adim.yol; aktifModel = adim.model
            KullanimDefteri.ortak.say(adim.model, .istek)
            #if DEBUG
            if liveTani { print("[LIVE-TANI] deneme model=\(adim.model) yol=\(adim.yol)") }
            #endif
            if i > 0 { akanMetin = ""; denemeYenilendi?() }
            let oturum = oturumGetir(adim, caba: caba, canliSes: canliSes)
            let oncekiTranscript = oturum.transcript
            let aracSayisi = gorevler.yanEtkiliBaslatilan
            // Bekçi yalnız bu denemedeki araçları saymalı; toplam sayaç uygulama ömrü boyunca birikir.
            let aracTabani = gorevler.toplamBaslatilan
            let baslangic = Date(); var ilkMetin: Double?
            do {
                let istem = Prompt {
                    metin
                    for g in gorseller { Attachment(g) }
                }
                // Sağlayıcı timeout'u bazı SSE oturumlarında ilk parça gelmeden
                // dönmüyordu. Bu ayrı görev yalnız mevcut denemeyi iptal eder;
                // ana istek sonraki yedek modeli güvenle deneyebilir.
                let bekleme = Self.yanitZamanAsimi(caba, canliSes: canliSes)
                let deneme = Task { [weak self] () throws -> (String, TimeInterval?) in
                    guard let self else { throw CancellationError() }
                    var son = ""; var ilk: TimeInterval?
                    // akanMetin en çok ~90 ms'de bir yazılır (her parçada balon yeniden ayrıştırılıp çiziliyordu); ilk dolu parça hemen.
                    // Tam metin akisTamponu'nda durur; döngü sonunda ve hata yolunda akanMetin'e son tam metin yazılır
                    // (AkisBekcisi, tekrarGuvenli/eksikKisaYanitGuvenli ve iptal arşivi tam metni görsün).
                    var sonYazim: ContinuousClock.Instant?
                    self.akisTamponu = ""
                    #if DEBUG
                    if liveTani { print("[LIVE-TANI] streamResponse çağrılıyor") }
                    #endif
                    do {
                        for try await parca in oturum.streamResponse(to: istem) {
                            #if DEBUG
                            if liveTani, ilk == nil { print("[LIVE-TANI] ilk model parçası geldi") }
                            #endif
                            if Task.isCancelled || buNesil != self.nesil { throw CancellationError() }
                            if ilk == nil, !parca.content.isEmpty {
                                ilk = Date().timeIntervalSince(baslangic)
                                SaglikMerkezi.ortak.kaydet("model_ilk_metin", sure: ilk!, etiket: adim.model)
                            }
                            son = parca.content
                            self.akisTamponu = son
                            let simdi = ContinuousClock.now
                            if sonYazim == nil || simdi - sonYazim! >= .milliseconds(90) {
                                self.akanMetin = son
                                if !son.isEmpty { sonYazim = simdi }
                            }
                            if self.durum != .yaziyor, !son.isEmpty { self.durum = .yaziyor }
                        }
                    } catch {
                        // Akış koptu: yedek kararı ve görünen yarım metin tam metne dayansın. İptal edilmiş (zaman aşımı/Durdur)
                        // deneme yazmaz; sonraki denemenin metnini bayat metinle ezmesin.
                        if !Task.isCancelled, buNesil == self.nesil { self.akanMetin = son }
                        throw error
                    }
                    if !Task.isCancelled, buNesil == self.nesil { self.akanMetin = son }
                    return (son, ilk)
                }
                let sonuc: (String, TimeInterval?)
                do {
                    // Bazı sağlayıcı akışları `Task.cancel()` sonrasında kapanış
                    // olayını hiç üretmiyor. Unstructured yarış, ekranın bu
                    // bekleyişe takılmasını önler; iptal edilen eski akışın
                    // nesil kontrolü sonraki yanıtı değiştirmesini engeller.
                    let kapi = AkisYarisKapisi()
                    // Durdur (calisanIs.cancel) yapılandırılmamış deneme görevine kendiliğinden geçmez; elle aktar.
                    sonuc = try await withTaskCancellationHandler { try await withCheckedThrowingContinuation { devam in
                        Task {
                            do {
                                let deger = try await deneme.value
                                if await kapi.kapat() { devam.resume(returning: deger) }
                            } catch {
                                if await kapi.kapat() { devam.resume(throwing: error) }
                            }
                        }
                        Task {
                            #if DEBUG
                            if liveTani { print("[LIVE-TANI] zaman aşımı sayacı başladı \(bekleme)sn") }
                            #endif
                            // Araç (ör. web araştırması) çalışırken model doğal olarak metin üretmez;
                            // bütçe yalnız araç çalışmayan süreyi sayar. Mutlak sınır: bekciMutlakSiniri.
                            do {
                                // Zaman aşımı ilerlemeye bakar: yeni metin/araç etkinliği sayacı sıfırlar (çok adımlı araç işleri kesilmez).
                                var bekci = AkisBekcisi(ilkMetinButcesi: bekleme)
                                while true {
                                    try await Task.sleep(for: .milliseconds(500))
                                    // Durdur/yeni istek: eski denemeyi bekletme, hemen kapat (dış catch nesil farkıyla sessizce döner).
                                    if buNesil != self.nesil || deneme.isCancelled { break }
                                    let arac = Self.denemeAracSayisi(toplam: self.gorevler.toplamBaslatilan, taban: aracTabani)
                                    // Önceki isteklerden 'Çalışıyor' kalmış bayat adım boş süre sayımını durdurmasın.
                                    let calisiyor = self.gorevler.adimlar.contains(where: { $0.durum == "Çalışıyor" && $0.baslangic >= baslangic })
                                    if bekci.adim(uzunluk: self.akanMetin.count, aracSayisi: arac, aracCalisiyor: calisiyor) { break }
                                    if Date().timeIntervalSince(baslangic) > Self.bekciMutlakSiniri(aracSayisi: arac, metinVar: !self.akanMetin.isEmpty) { break }
                                }
                            } catch { return }
                            #if DEBUG
                            if liveTani { print("[LIVE-TANI] zaman aşımı tetiklendi") }
                            #endif
                            deneme.cancel()
                            if await kapi.kapat() { devam.resume(throwing: AkisYarisZamanAsimi()) }
                        }
                    } } onCancel: { deneme.cancel() }
                } catch is AkisYarisZamanAsimi {
                    // Seyreltilmiş akışta son parçalar yalnız tamponda kalmış olabilir; iptal edilen deneme yazmaz, burada aktar
                    // (yedek kararı ve bitir arşivi tam metni görsün). Nesil farkında (Durdur/yeni istek) dokunulmaz.
                    if buNesil == nesil {
                        akanMetin = Self.arsivlenecekMetin(akan: akanMetin, tampon: akisTamponu)
                        akisTamponu = ""
                    }
                    if akanMetin.isEmpty { throw IlkMetinZamanAsimi(saniye: bekleme) }
                    // İlk parça görüldüyse yinelenen araç çağrısı yapmamak için
                    // yedeğe geçilmez; hata sonlandırıcı tarafından görünür olur.
                    throw AkisTamamlanmaZamanAsimi(saniye: bekleme)
                } catch is CancellationError {
                    throw CancellationError()
                }
                let son = sonuc.0
                ilkMetin = sonuc.1
                if Task.isCancelled || buNesil != nesil { return }
                guard !son.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BosModelYaniti() }
                // P3.4: alt kümede uygun araç olmadığı için yapamadığını söyledi ve bu denemede araç çalışmadı: oturum tam setle
                // önceki transcript'ten kurulur, aynı adım bir kez daha denenir.
                if ayarlar.aracGruplama, aracGrubu != nil, !tamSetDenendi,
                   Self.denemeAracSayisi(toplam: gorevler.toplamBaslatilan, taban: aracTabani) == 0, AracGruplari.yetersizYanit(son) {
                    tamSetDenendi = true
                    TaniGunlugu.yaz("YÖNLENDİRME FARKI: grup=\(AracGruplari.imza(aracGrubu)) yetersiz yanıt → tam set")
                    aracGrubu = nil
                    akanMetin = ""; akisTamponu = ""
                    denemeYenilendi?()
                    self.oturum = LanguageModelSession(model: claudeModeli(adim, caba: ClaudeModel.Effort(rawValue: caba.rawValue)!, timeout: Self.yanitZamanAsimi(caba, canliSes: canliSes)), tools: araclar, transcript: oncekiTranscript)
                    self.oturumAyarImzasi = nil
                    i -= 1; denemeler -= 1
                    continue
                }
                // P3.4: tura özel bloklar (hafıza notu, süzgeç, kip, uzman, canlı ses notu) transcript'ten ayıklanır; eski görseller yer tutucuya döner.
                if ayarlar.aracGruplama, let temizMetin {
                    let sade = Self.sonIstemiSadelestir(oturum.transcript, temiz: temizMetin, gorselKoru: true)
                    self.oturum = LanguageModelSession(model: claudeModeli(adim, caba: ClaudeModel.Effort(rawValue: caba.rawValue)!, timeout: Self.yanitZamanAsimi(caba, canliSes: canliSes)), tools: secilenAraclar(sade), transcript: sade)
                }
                KullanimDefteri.ortak.say(adim.model, .basari)
                modelVitesi.basari(adim.model, caba: caba, ilkSn: ilkMetin ?? Date().timeIntervalSince(baslangic), yol: adim.yol)
                SaglikMerkezi.ortak.kaydet("model_toplam", sure: Date().timeIntervalSince(baslangic), etiket: adim.model)
                tamamla(son, nesil: buNesil)
                return
            } catch {
                if Task.isCancelled || buNesil != nesil || error is CancellationError { return }
                sonHata = error
                sonYol = adim.yol
                KullanimDefteri.ortak.say(adim.model, .hata)
                // 127.0.0.1 reddi: iOS yerel sunucuyu kapatmış; yeniden kur, sıradaki adım çalışan sunucuyla denenir.
                let agHatasi = (error as NSError).domain == NSURLErrorDomain
                var sunucuYenilendi = false
                if agHatasi, [NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost].contains((error as NSError).code),
                   adim.yol == .telefon {
                    await TelefonProxy.ortak.zorlaDogrula()
                    sunucuYenilendi = TelefonProxy.ortak.hazir   // yerel sunucu yeniden kuruldu: rota askıya alınmaz
                    denemeler -= 1
                }
                // P3.7: hata türle sınıflanır; askı kapsamı istek (askı yok) / model|yol / rota.
                // Sunucuda olmayan model (404) ve yapılandırma iletileri gerçek bir deneme sayılmaz (hakDusmez).
                let karar = error is IlkMetinZamanAsimi
                    ? ModelZinciri.Karar(gec: true, kapsam: .modelYol(120))
                    : ModelZinciri.sinifla(error, yol: adim.yol)
                if karar.hakDusmez { denemeler -= 1 }
                if agHatasi { BaglantiDurumu.ortak.agHatasiGoruldu() }
                TaniGunlugu.yaz("MODEL HATA \(adim.model) \(Int(Date().timeIntervalSince(baslangic))) sn: \(type(of: error)) \(error)")
                SaglikMerkezi.ortak.kaydet("model_toplam", sure: Date().timeIntervalSince(baslangic), basarili: false, etiket: adim.model)
                // Kısa kopma türü hatada aynı adım bir kez yeniden denenir ve rota/model askıya alınmaz.
                var yenidenDene = false
                if !(error is IlkMetinZamanAsimi), GeciciHata.mi(error), yenidenDenenen.insert("\(adim.model)|\(adim.yol)").inserted {
                    adimlar.insert(adim, at: i + 1); denemeler -= 1; yenidenDene = true
                    TaniGunlugu.yaz("GEÇİCİ HATA → aynı adım yeniden denenecek: \(adim.model) \(adim.yol)")
                    try? await Task.sleep(for: .milliseconds(700))
                }
                if karar.gec, !yenidenDene {
                    switch karar.kapsam {
                    case .rota(let sn):
                        if sunucuYenilendi { break }
                        let bitis = Date().addingTimeInterval(sn)
                        askilar[adim.yol] = max(askilar[adim.yol] ?? .distantPast, bitis)
                    case .modelYol(let sn): modelVitesi.beklet(adim.model, yol: adim.yol, saniye: sn)
                    case .yok, .istek: break
                    }
                }
                if case LanguageModelError.rateLimited = error {
                    sinirliAileler.insert(aile)
                    for model in modeller where model.hasPrefix(aile) { modelVitesi.beklet(model, saniye: 60) }
                }
                let guvenliTekrar = ModelVitesi.tekrarGuvenli(kismiMetin: akanMetin, aracSayisiOnce: aracSayisi, aracSayisiSonra: gorevler.yanEtkiliBaslatilan) ||
                    ModelVitesi.eksikKisaYanitGuvenli(kismiMetin: akanMetin, aracSayisiOnce: aracSayisi, aracSayisiSonra: gorevler.yanEtkiliBaslatilan)
                TaniGunlugu.yaz("ZİNCİR i=\(i)/\(adimlar.map { "\($0.model):\($0.yol)" }) gec=\(karar.gec) kapsam=\(karar.kapsam) guvenliTekrar=\(guvenliTekrar) metin=\(akanMetin.count) arac=\(aracSayisi)->\(gorevler.yanEtkiliBaslatilan) sira=\(modeller)")
                if karar.gec, i < adimlar.count - 1, guvenliTekrar {
                    // Başlamış telefon işlemi veya görünmüş yanıt asla yeniden yürütülmez.
                    // Yalnız güvenli yarım kısa metni düşür; daha önceki tam
                    // bağlamı koruyarak yedek modelden temiz yanıt al.
                    self.akanMetin = ""
                    self.oturum = LanguageModelSession(model: claudeModeli(adim, caba: ClaudeModel.Effort(rawValue: caba.rawValue)!, timeout: Self.yanitZamanAsimi(caba, canliSes: canliSes)), tools: ayarlar.aracGruplama ? secilenAraclar(oncekiTranscript) : araclar, transcript: oncekiTranscript)
                    self.oturumAyarImzasi = nil
                    modelSecimNotu = "Önceki model kullanılamadı; uygun yedek modele geçildi"
                    continue
                }
                break
            }
        }
        bitir(hata: Beyin.hataMetni(sonHata, sonYol: sonYol), tur: sonHata.map(HataSozlugu.tur) ?? .bilinmeyen, nesil: buNesil)
    }
}
