import Foundation

/// Kepçe'nin gömülü motoru (yt-dlp + JavaScriptCore + AVFoundation birleştirme) ile uygulama içinde video/ses indirir.
/// İlerleme ve sonuç `IndirmeYoneticisi` kaydına yazılır; böylece sohbet kartı ve bildirim akışı aynı kalır.
extension IndirmeYoneticisi {
    /// Sayfa/video adresini (YouTube vb.) indirir; kayıt kimliğini hemen döndürür, iş arka planda sürer.
    @discardableResult func motorluEkle(_ adres: String, tur: String) throws -> UUID {
        let url = try Self.dogrula(adres)
        guard ["video", "audio"].contains(tur) else { throw IndirmeHatasi.metin("Motorlu indirme yalnız video ya da ses içindir.") }
        guard kayitlar.filter(\.etkin).count < Self.enFazlaEtkin else { throw IndirmeHatasi.metin("En fazla \(Self.enFazlaEtkin) etkin indirme olabilir.") }
        var k = IndirmeKaydi(adres: url.absoluteString, tur: tur, ad: url.host ?? "Medya")
        k.motor = true; k.durum = "running"
        kaydiEkle(k)
        motorBaslat(k.id, url: url, tur: tur)
        return k.id
    }

    /// Başarısız motorlu kaydı AYNI kimlikle yeniden başlatır: çalışma klasörü (Caches/MotorIsleri/<id>) korunduğu için
    /// AkisIndirici kaldığı yerden sürer. `tekrar` motorlu kayıtta bunu çağırmalı. İptal edilen kayıt yeni kimlik alır:
    /// klasörü zaten silinmiştir ve iptal edilen eski görev hâlâ kapanıyor olabilir (aynı klasörü silmesin).
    func motorluTekrar(_ k: IndirmeKaydi) throws {
        guard k.motor == true, k.durum == "failed", motorGorevleri[k.id] == nil, kayitlar.contains(where: { $0.id == k.id && $0.durum == "failed" }) else {
            try motorluEkle(k.adres, tur: k.tur)
            return
        }
        let url = try Self.dogrula(k.adres)
        guard ["video", "audio"].contains(k.tur) else { throw IndirmeHatasi.metin("Motorlu indirme yalnız video ya da ses içindir.") }
        guard kayitlar.filter(\.etkin).count < Self.enFazlaEtkin else { throw IndirmeHatasi.metin("En fazla \(Self.enFazlaEtkin) etkin indirme olabilir.") }
        degistir(k.id) { $0.durum = "running"; $0.hata = nil; $0.alinan = 0; $0.toplam = 0; $0.dosya = nil }
        motorBaslat(k.id, url: url, tur: k.tur)
    }

    private func motorBaslat(_ id: UUID, url: URL, tur: String) {
        // Uygulama öldürülünce kalan sahipsiz çalışma klasörlerini temizle (ana iş parçacığını bekletmeden).
        let motorlu = kayitlar.filter { $0.motor == true }
        let etkin = Set(motorlu.filter(\.etkin).map(\.id)), bekleyen = Set(motorlu.filter { $0.durum == "failed" }.map(\.id))
        // Görüntü anı da geçer: temizlik gecikirse bu arada başlayan başka işin (görüntüde olmayan) klasörü silinmesin.
        let an = Date.now
        Task.detached(priority: .utility) { MotorluIndirici.sahipsizleriTemizle(etkin: etkin, bekleyen: bekleyen, simdi: an) }
        // Ekran kilitlenince ya da başka uygulamaya geçilince ~30 sn daha çalışsın: süren birleştirme ve kısa indirmeler biter.
        let arka = ArkaPlanGorevi()
        arka.baslat("Kepçe indirme")
        // Uzun indirmeler için sistemden "sürdürülen işlem" iste (O2); verilmezse yukarıdaki ~30 sn yedeği kalır.
        IndirmeSurdurucu.ortak.baslat(id, ad: kayitlar.first { $0.id == id }?.ad ?? "Medya")
        motorGorevleri[id] = Task { [weak self] in
            var basarili = false
            // Task MainActor'dan miras alır; defer de MainActor'da çalışır (iptal dalında da görev kapanır).
            defer { arka.bitir(); IndirmeSurdurucu.ortak.bitir(id, basarili: basarili) }
            let sonuc: Result<(ad: String, baslik: String), Error>
            do { sonuc = .success(try await MotorluIndirici.indir(url: url, tur: tur, id: id) { alinan, toplam in
                Task { @MainActor in
                    self?.ilerleme(id, alinan: alinan, toplam: toplam)
                    IndirmeSurdurucu.ortak.ilerle(id, alinan: alinan, toplam: toplam)
                }
            } adAyarla: { baslik in
                Task { @MainActor in
                    self?.degistir(id) { $0.ad = baslik }
                    IndirmeSurdurucu.ortak.adiGuncelle(id, baslik)
                }
            } asama: { metin in
                Task { @MainActor in IndirmeSurdurucu.ortak.asama(id, metin) }
            } birlestirmeIlerleme: { oran in
                Task { @MainActor in IndirmeSurdurucu.ortak.birlestirmeIlerle(id, oran: oran) }
            }) }
            catch { sonuc = .failure(error) }
            self?.motorGorevleri[id] = nil
            switch sonuc {
            case .success(let s):
                basarili = true
                self?.tamam(id, ad: s.ad, hata: nil, gorunenAd: s.baslik)
            case .failure(let e):
                if Task.isCancelled || (e as? CancellationError) != nil { return }
                // anlasilir yinelenmeye dayanıklıdır: ayristir'de çevrilmiş ileti ikinci kez açıklama almaz.
                self?.tamam(id, ad: nil, hata: PythonMotoru.anlasilir(e.localizedDescription))
            }
        }
    }
}

nonisolated enum MotorluIndirici {
    /// En yüksek video çözünürlüğü: telefonda boyutu makul tutar.
    static let enFazlaYukseklik = 1080
    static let sinirBayt: Int64 = 3_000_000_000
    /// Başarısız işin parçaları bu süre "Yeniden dene" için tutulur.
    static let bekletmeSuresi: TimeInterval = 3 * 24 * 3600

    static var islerKlasoru: URL { URL.cachesDirectory.appending(path: "MotorIsleri") }
    static func calismaKlasoru(_ id: UUID) -> URL { islerKlasoru.appending(path: id.uuidString) }

    // @concurrent: klasör oluşturma/silme/taşıma ana iş parçacığında çalışmasın (çağıran Task MainActor'dan miras alır).
    @concurrent static func indir(url: URL, tur: String, id: UUID, ilerleme: @escaping @Sendable (Int64, Int64) -> Void,
                                  adAyarla: @escaping @Sendable (String) -> Void,
                                  asama: (@Sendable (String) -> Void)? = nil,
                                  birlestirmeIlerleme: (@Sendable (Double) -> Void)? = nil) async throws -> (ad: String, baslik: String) {
        let calisma = calismaKlasoru(id)
        try FileManager.default.createDirectory(at: calisma, withIntermediateDirectories: true)
        do {
            let sonuc = try await isle(url: url, tur: tur, id: id, calisma: calisma, ilerleme: ilerleme, adAyarla: adAyarla, asama: asama, birlestirmeIlerleme: birlestirmeIlerleme)
            try? FileManager.default.removeItem(at: calisma)
            return sonuc
        } catch {
            // İptal dışındaki hatalarda parçalar tutulur: "Yeniden dene" aynı klasörle kaldığı yerden sürer
            // (sahipsiz/eski klasörleri `sahipsizleriTemizle` siler).
            if klasorSilinmeli(error) || Task.isCancelled { try? FileManager.default.removeItem(at: calisma) }
            throw error
        }
    }

    /// Hata sonrası çalışma klasörü silinsin mi? Yalnız iptalde: kullanıcı işi bıraktı.
    static func klasorSilinmeli(_ hata: Error) -> Bool { hata is CancellationError }

    /// Birleştirme (AVAssetExportSession) girdilerin bir tam kopyasını daha yazar; yalnız mp3 sesi doğrudan taşınır.
    static func birlesecek(_ plan: IndirmePlani) -> Bool { !(plan.tur == .ses && plan.uzanti == "mp3") }

    @concurrent private static func isle(url: URL, tur: String, id: UUID, calisma: URL, ilerleme: @escaping @Sendable (Int64, Int64) -> Void,
                                         adAyarla: @escaping @Sendable (String) -> Void,
                                         asama: (@Sendable (String) -> Void)? = nil,
                                         birlestirmeIlerleme: (@Sendable (Double) -> Void)? = nil) async throws -> (ad: String, baslik: String) {
        var bilgi = try await PythonMotoru.shared.coz(url.absoluteString)
        if let canli = bilgi.liveStatus, canli == "is_live" || canli == "is_upcoming" {
            throw PythonMotoru.Hata.cozum("Canlı yayınlar indirilemez; yayın bitince yeniden dene.")
        }
        let istek: IndirmeTuru = tur == "audio" ? .ses : .video
        func planla(_ b: MedyaBilgisi) -> IndirmePlani? { BicimSecici.plan(b, tur: istek, enFazla: enFazlaYukseklik) }
        guard var plan = planla(bilgi) else {
            throw PythonMotoru.Hata.cozum("Bu içerik için iPhone'da oynatılabilir bir biçim bulunamadı.")
        }
        if let boyut = plan.tahminiBoyut {
            guard boyut <= sinirBayt else { throw PythonMotoru.Hata.cozum("Dosya çok büyük (\(BicimSecici.boyutMetni(boyut))); sınır 3 GB.") }
            // Birleştirme çıktısı için de yer gerekir: indirme bittikten sonra disk dolmasın. "Yeniden dene"de
            // klasörde duran parçalar düşülür (yalnız kalan kısım + çıktı); ilk denemede klasör boş, pay değişmez.
            let eldeki = eldekiBayt([plan.video.map { calismaDosyasi(calisma, "video", $0) }, plan.ses.map { calismaDosyasi(calisma, "ses", $0) }].compactMap { $0 })
            try AkisIndirici.yerVarMi(onDenetimPayi(boyut: boyut, birlesecek: birlesecek(plan), eldeki: eldeki), hedef: calisma)
        }
        let baslik = bilgi.title ?? url.host ?? "Medya"
        adAyarla(baslik)

        var yenilendi = false
        while true {
            let video = IlerlemeSayaci(), ses = IlerlemeSayaci()
            let sayaclar = [plan.video != nil ? video : nil, plan.ses != nil ? ses : nil].compactMap { $0 }
            let toplam = plan.tahminiBoyut ?? 0
            let izleyici = Task {
                while !Task.isCancelled {
                    ilerleme(sayaclar.reduce(0) { $0 + $1.alinan }, toplam)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { izleyici.cancel() }
            do {
                let sure = bilgi.duration, kaydet = plan
                try await withThrowingTaskGroup(of: Void.self) { grup in
                    if let v = kaydet.video {
                        grup.addTask { try await AkisIndirici.indir(v, hedef: calismaDosyasi(calisma, "video", v), baglanti: 6, sayac: video, sure: sure) }
                    }
                    if let s = kaydet.ses {
                        grup.addTask { try await AkisIndirici.indir(s, hedef: calismaDosyasi(calisma, "ses", s), baglanti: 3, sayac: ses, sure: sure) }
                    }
                    try await grup.waitForAll()
                }
                break
            } catch let hata as AkisHatasi where hata.yenilenebilir && !yenilendi {
                // Adresin süresi doldu ya da sunucudaki dosya değişti: bir kez yeniden çöz ve sür
                // (değişen akış baştan, tamamlanmış akış `.tamam` işaretiyle atlanır).
                yenilendi = true
                bilgi = try await PythonMotoru.shared.coz(url.absoluteString)
                guard let yeni = planla(bilgi) else { throw hata }
                plan = yeni
            }
        }
        try Task.checkCancellation()

        let videoDosyasi = plan.video.map { calismaDosyasi(calisma, "video", $0) }
        let sesDosyasi = plan.ses.map { calismaDosyasi(calisma, "ses", $0) }
        let kapak = await Birlestirici.kapak(bilgi.thumbnail, kare: plan.tur == .ses)
        var uzanti = plan.uzanti
        let ara: URL
        if !birlesecek(plan) {
            guard let kaynak = sesDosyasi ?? videoDosyasi else { throw BirlestirmeHatasi.izYok }
            ara = kaynak
        } else {
            if uzanti == "mp3" { uzanti = "m4a" }
            let etiket = MedyaEtiketi(baslik: baslik, sanatci: bilgi.yazar, aciklama: bilgi.description, tarih: nil, kapak: kapak)
            ara = calisma.appending(path: "cikti.\(uzanti)")
            // Gerçek girdi boyutlarıyla son denetim: tahmin sapmışsa ya da yoksa dışa aktarma diski doldurmasın.
            let girdiToplam = [videoDosyasi, sesDosyasi].compactMap { $0 }.reduce(Int64(0)) { t, u in
                t + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            try AkisIndirici.yerVarMi(girdiToplam, hedef: ara)
            // Birleştirme bayt ilerlemesi bildirmez: sistem görevi bayat sayılmasın diye aşamayı duyur.
            asama?("Birleştiriliyor…")
            try await Birlestirici.birlestir(video: videoDosyasi, ses: sesDosyasi, cikis: ara, yalnizSes: plan.tur == .ses, etiket: etiket, kesit: nil, ilerleme: birlestirmeIlerleme)
        }
        let ad = id.uuidString + "-" + IndirmeYoneticisi.dosyaAdi(baslik) + "." + uzanti
        let hedef = URL.documentsDirectory.appending(path: "Indirmeler", directoryHint: .isDirectory).appending(path: ad)
        try FileManager.default.moveItem(at: ara, to: hedef)
        return (ad, baslik)
    }

    static func calismaDosyasi(_ calisma: URL, _ ad: String, _ bicim: Bicim) -> URL {
        var ext = (bicim.ext ?? "").lowercased()
        if ext.isEmpty || ext == "unknown_video" || ext.count > 5 { ext = bicim.videoVar ? "mp4" : "m4a" }
        if ext == "mp4" && !bicim.videoVar { ext = "m4a" }
        return calisma.appending(path: "\(ad).\(ext)")
    }

    // MARK: Çalışma klasörü temizliği

    /// Caches/MotorIsleri altında artık hiçbir kayda ait olmayan (uygulama öldürülünce ya da kayıt silinince kalan) klasörleri siler.
    static func sahipsizleriTemizle(etkin: Set<UUID>, bekleyen: Set<UUID>, simdi: Date = .now) {
        let fm = FileManager.default
        guard let ogeler = try? fm.contentsOfDirectory(at: islerKlasoru, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for oge in ogeler {
            let tarih = (try? oge.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if silinmeli(UUID(uuidString: oge.lastPathComponent), etkin: etkin, bekleyen: bekleyen, tarih: tarih, simdi: simdi) {
                try? fm.removeItem(at: oge)
            }
        }
    }

    /// Süren işin klasörüne dokunulmaz; başarısız kaydın klasörü `bekletmeSuresi` boyunca devam için tutulur; gerisi silinir.
    /// `simdi` kayıt görüntüsünün alındığı andır: ondan sonra açılmış/değişmiş klasör o anda bilinmeyen yeni bir işe
    /// ait olabilir, bu turda dokunulmaz (uygulama öldürülünce kalan gerçek sahipsizlerin tarihi geçmiştedir).
    static func silinmeli(_ id: UUID?, etkin: Set<UUID>, bekleyen: Set<UUID>, tarih: Date, simdi: Date) -> Bool {
        guard let id else { return true }
        if etkin.contains(id) { return false }
        if bekleyen.contains(id) { return simdi.timeIntervalSince(tarih) > bekletmeSuresi }
        return tarih <= simdi
    }

    /// Ön yer denetiminin istediği bayt: kalan indirme + (birleşecekse) dışa aktarma çıktısı. "Yeniden dene"de
    /// çalışma klasöründe duran yarım/tam parçalar (`eldeki`) zaten diskte olduğu için yeniden yer istemez.
    static func onDenetimPayi(boyut: Int64, birlesecek: Bool, eldeki: Int64) -> Int64 {
        max(0, boyut - max(0, eldeki)) + (birlesecek ? boyut : 0)
    }

    /// Dosyaların diskte gerçekten kapladığı yer: `pwrite` ile ofsetlere yazılan parça dosyası seyrek olabilir,
    /// bu yüzden mantıksal boyut değil ayrılmış boyut toplanır. Olmayan dosya 0 sayılır.
    static func eldekiBayt(_ dosyalar: [URL]) -> Int64 {
        dosyalar.reduce(Int64(0)) { t, u in
            t + Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
    }
}
