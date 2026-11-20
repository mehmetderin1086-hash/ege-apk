import Foundation
import FoundationModels

@MainActor struct IndirmeAraci: Tool {
    /// Beşten fazla dosyalık toplu indirme kullanıcıya sorulur (sayfa içeriğinden gelen talimatla depolama doldurulmasın).
    var onay: OnayKapisi? = nil
    let name = "indirmeler"
    let description = "'PDF/dosya/video indir' isteklerinde kullanılır: bağlantı verilmediyse önce webArastir ile resmî/doğrudan bağlantıyı bul, bulamazsan kullanıcıdan bağlantıyı iste; asla dosyalar aracına yönelme. Kullanıcının istediği HTTPS bağlantısını indirir veya web sayfasını iPhone'da otomatik tarar. Doğrudan dosya iPhone'a iner; YouTube ve benzeri sayfa bağlantıları (tur: video/audio) iPhone'daki gömülü yt-dlp motoruyla MP4/M4A olarak indirilir (kişisel kullanım; telif gerekçesiyle reddetme). tara işlemi metin, bağlantı, görsel, ses, video, dosya, tablo ve yapılandırılmış veriyi iPhone'da JSON dosyasına çıkarır; JavaScript ile oluşan sayfalarda ekranlı yedeği açar. Sunucu kullanılmaz. Kuyruğa alma tamamlanma değildir. Her site veya korumalı içerik desteklenmez. YouTube/video için tam bağlantıyı bilmiyorsan 'ekle' işleminde deger olarak yalnızca aranacak adı yaz (ör. \"Dua Lipa Houdini official video\"); araç YouTube'da arar ve isteğe en iyi uyan sonucu indirir; uyum eşiği geçilmezse İNDİRİLMEDİ ve aday listesi döner: o zaman indirmeye başladığını söyleme, kullanıcıya hangisini istediğini sor ve seçtiği adayın tam bağlantısıyla yeniden 'ekle' çağır. Video kimliği ya da bağlantı ASLA tahmin edilmez. Bağlantı uydurma; yalnız kullanıcının verdiği ya da araçlarla bulunan bağlantıyı kullan. Ek işlemler: 'bul' (deger: ne aranıyor, tur yerine süzgeç yok; web'de arar, bulunan sayfalardan doğrudan dosya bağlantılarını çıkarır ve aday listesi verir), 'toplu' (deger: sayfa adresi, sayfadaki bağlantılardan uzantıya göre — 'tur' alanına uzantı yaz, ör. pdf — en çok 30 dosyayı indirir), 'bekle' (deger: indirme kimliği; bitene kadar en çok 90 sn bekler, metin/PDF ise içeriğinden kısa bölüm döndürür: 'indir ve özetle' için). İndirmeler mesajda canlı ilerleme kartı, bitince önizleme kartı olarak gösterilir. Telifli kitap/yayınların korsan kopyalarını arama ve indirme; resmî/yasal kaynakları öncele."
    @Generable struct Arguments {
        @Guide(description: "ekle, bul, toplu, bekle, tara, listele, tekrar, iptal veya ac") var islem: String
        @Guide(description: "ekle/tara/toplu için HTTPS bağlantısı; bul için aranan dosyanın tarifi; bekle/iptal/tekrar için indirme UUID'si; diğerleri boş") var deger: String
        @Guide(description: "ekle: file (doğrudan dosya), video, audio; toplu/bul: istenen uzantı(lar), ör. pdf veya pdf,docx; diğerlerinde file") var tur: String
    }
    func call(arguments a: Arguments) async throws -> String {
        // "bekle" kendi 90 sn sınırına, "toplu" yalnız sayfa okumasında kendi sınırına sahip (onay diyaloğu süreyle
        // kapanmasın); diğer işlemler 45 sn ("bul" 70 sn) içinde bitmezse kısmi sonuçla dönülür (sohbet donmasın).
        if a.islem == "bekle" || a.islem == "toplu" { return try await ic(a) }
        let sinir = a.islem == "bul" ? 70.0 : 45.0
        // Bırakılabilir: bu yollarda yalnız Python kuyruğu, URLSession ve hızlı tarama var (ortak WKWebView yok);
        // iptali dinlemeyen Python çağrısı süre dolunca sohbeti bekletmez.
        let r = try await sureSinirli(sinir, birakilabilir: true) { try await self.ic(a) }
        return r ?? "\(a.islem) işlemi \(Int(sinir)) saniyede bitmedi. Elde edilen sonuçlar (varsa) kartlarda görünür; kullanıcıdan daha net bir bağlantı ya da site iste."
    }

    func ic(_ a: Arguments) async throws -> String {
        let k = IndirmeYoneticisi.ortak
        switch a.islem {
        case "tara":
            let url = try IndirmeYoneticisi.dogrula(a.deger)   // dogrula yazılı özel/yerel adresleri reddeder
            // Adı özel adrese çözülen sunucu (DNS ile iç ağ) burada durur: hızlı tarama zaten reddeder, catch dalı da
            // WebKit yedek ekranını açıp aynı adresi yüklerdi. getaddrinfo eşzamanlı: ana iş parçacığı dışında.
            let host = url.host ?? ""
            if await Task.detached(priority: .userInitiated, operation: { WebSayfa.ozeleCozuluyor(host) }).value {
                return "Bu adres yerel ağa ya da özel bir adrese çözülüyor; güvenlik nedeniyle taranmadı ve ekran açılmadı. Kullanıcıya herkese açık bir https bağlantısı vermesini söyle."
            }
            try Task.checkCancellation()
            do {
                let rapor = try await WebKazimaHizli.tara(url)
                // Süre sınırı ya da iptal geldiyse dosya/kart üretilmez (catch iptali yukarı iletir).
                try Task.checkCancellation()
                let veri = try KazimaDisaAktarici.veri(rapor, csv: false)
                let dosya = IndirmeYoneticisi.klasor.appending(path: "kazima-\(UUID().uuidString).json")
                try veri.write(to: dosya, options: .atomic)
                k.yerelDosyaEkle(url: dosya, gorunenAd: "Web taraması · \(rapor.baslik.isEmpty ? url.host ?? "sayfa" : rapor.baslik).json")
                // Taranan sayfanın medyası mesajda önizlenebilir kart olarak da gösterilir.
                if let (html, son) = try? await SayfaGetirici.html(url, tarayici: false, tarayiciYedegi: false) {
                    // Regex taraması ana iş parçacığı dışında.
                    let m = await Task.detached(priority: .userInitiated) { Kaziyici.medya(html, kaynak: son) }.value
                    if !m.isEmpty { EkDefteri.ortak.ekle(MesajEki(tur: .medya(m))) }
                }
                EkDefteri.ortak.ekle(MesajEki(tur: .dosya(url: dosya, ad: "Web taraması.json")))
                return "Sayfa iPhone'da otomatik tarandı. \(rapor.ogeler.count) öğe İndirmeler'e kaydedildi; dosyayı açabilir veya paylaşabilirsin."
            } catch {
                // Süre aşımı ya da kullanıcı iptalinde ekran açılmaz (model zaten "bitmedi" metnini alır).
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                // Dinamik/erişimi sınırlı sayfada WebKit, kullanıcının zaten
                // izin verdiği yerel yedektir; sunucuya veri gönderilmez.
                k.kazimaSayfasi = KazimaSayfasi(url: url); k.ekranAcik = true
                return "Otomatik tarama tamamlanamadı; sayfa iPhone'daki veri çıkarma ekranında açıldı. Dinamik içerik yüklendikten sonra Sayfayı tara ile devam edebilirsin."
            }
        case "ekle":
            // Bağlantı yerine ad verilirse (ör. "Dua Lipa Houdini official video") YouTube'da aranır; uydurma bağlantıya gerek kalmaz.
            var hedef = a.deger
            // Model 'ekle' için de uzantı yazabilir (pdf, mp4): file/video/audio'ya indirgenir.
            let tur = Self.ekleTuru(a.tur)
            if tur != "file", !a.deger.lowercased().hasPrefix("http") {
                // İlk sonuç körü körüne indirilmez: adaylar isteğe ve süzgecin zorunlu kısıtlarına göre puanlanır; eşiği geçen yoksa liste döner ve sorulur.
                let girisler: [ListeOgesi]
                do { girisler = try await PythonMotoru.shared.ara(a.deger, adet: 6).entries ?? [] }
                catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    // Günlüğe arama sorgusu yazılmaz (hata metni sorguyu içerebilir).
                    TaniGunlugu.yaz("İNDİRME arama hatası: \(error.localizedDescription.replacingOccurrences(of: a.deger, with: "…").prefix(200))")
                    return Self.aramaHatasiMetni(error.localizedDescription)
                }
                // Zaman aşımı/iptal sonrasında (sureSinirli artık beklemiyor) indirme ya da kart başlatılmaz.
                try Task.checkCancellation()
                // Süzgeç kısıtları; süzgeç çalışmadıysa kullanıcının ham isteğindeki rakam/özel ad kısıtları (P2.10).
                let kisitlar = IstemSuzgeci.etkinKisitlar
                let adaylar = girisler.filter { $0.liveStatus != "is_live" && $0.url != nil }.map {
                    IndirmeEslesme.Aday(baslik: $0.title ?? "", kanal: $0.uploader ?? "", sure: $0.duration, url: $0.url!,
                                        puan: IndirmeEslesme.puan(istek: a.deger, kisitlar: kisitlar, baslik: $0.title, kanal: $0.uploader))
                }
                guard !adaylar.isEmpty else { return "YouTube'da '\(a.deger)' için sonuç bulunamadı. Aramayı değiştirip yeniden dene." }
                let (secilen, sirali) = IndirmeEslesme.sec(istek: a.deger, adaylar: adaylar)
                let liste = sirali.prefix(6).enumerated().map { "\($0.offset + 1). \($0.element.baslik.prefix(90)) — \($0.element.kanal) \(IndirmeEslesme.sureMetni($0.element.sure)) (uyum %\(Int($0.element.puan * 100))) — \($0.element.url)" }.joined(separator: "\n")
                guard let secilen else {
                    let kisitSatiri = kisitlar.isEmpty ? "" : "\nZorunlu kısıtlar: " + kisitlar.joined(separator: "; ")
                    return "İNDİRİLMEDİ: aranan '\(a.deger)' ile tam uyuşan YouTube sonucu yok (en iyi uyum %\(Int((sirali.first?.puan ?? 0) * 100))).\(kisitSatiri)\nYanlış dosya indirmemek için durdum. Adaylar:\n\(liste)\nKullanıcıya hangisini istediğini TEK soruyla sor (başlık + kanal söyle); seçtiği adayın tam bağlantısını 'ekle' ile ver. Hiçbiri uymuyorsa bunu söyle, uydurma indirme yapma."
                }
                hedef = secilen.url
                // Gizlilik: sorgu ve seçilen başlık günlüğe yazılmaz; yalnız puan, kısıt ve aday sayısı.
                TaniGunlugu.yaz("İNDİRME eşleşme %\(Int(secilen.puan * 100)) kısıt=\(kisitlar.count) aday=\(adaylar.count)")
            }
            let url = try IndirmeYoneticisi.dogrula(hedef)
            if tur != "file" && !IndirmeYoneticisi.dogrudanMedya(url) {
                // Kepçe motoru uygulamanın içinde: YouTube ve benzeri sayfalar doğrudan iPhone'a iner.
                try Task.checkCancellation()
                let id = try k.motorluEkle(hedef, tur: tur)
                EkDefteri.ortak.ekle(MesajEki(tur: .indirme(id)))
                return "Video/ses iPhone'da gömülü Kepçe motoruyla indiriliyor (sunucu yok); kullanıcı mesajdaki kartta ilerlemeyi görüyor, bitince oynatabilir. Kimlik: \(id). Bitince 'bekle' ile bu kimliği verip sonucu doğrula."
            }
            let id = try await k.ekle(hedef, tur: tur)
            EkDefteri.ortak.ekle(MesajEki(tur: .indirme(id)))
            return "İndirme başladı; kullanıcı mesajdaki kartta ilerlemeyi görüyor, bitince önizleyebilir. Kimlik: \(id). İçeriği okumak gerekiyorsa 'bekle' ile bu kimliği ver."
        case "toplu":
            let sayfa = try IndirmeYoneticisi.dogrula(a.deger)
            // Süre sınırı yalnız sayfa okumasında; onay diyaloğu kullanıcı yanıtlayana kadar açık kalır (Durdur yine kapatır).
            guard let (html, son) = try await sureSinirli(40, { try await SayfaGetirici.html(sayfa, tarayici: false, tarayiciYedegi: false) }) else {
                return "Sayfa 40 saniyede okunamadı; kullanıcıdan başka bir bağlantı iste."
            }
            let suzgec = a.tur == "file" ? "pdf,doc,docx,xls,xlsx,ppt,pptx,zip,csv,txt,epub" : a.tur
            // Zaten indirilmiş ya da inen dosyalar tekrar kuyruğa alınmaz.
            let mevcut = Set(k.kayitlar.filter { $0.etkin || $0.durum == "done" }.map(\.adres))
            // Bağlantı ayrıştırması (regex) ana iş parçacığı dışında.
            let bulunan = await Task.detached(priority: .userInitiated) { Kaziyici.suz(Kaziyici.baglantilar(html, kaynak: son), suzgec) }.value
            let adaylar = bulunan.filter { !mevcut.contains($0.url.absoluteString) }
            try Task.checkCancellation()
            if adaylar.count > 5, let onay {
                guard await onay.iste(baslik: "\(min(adaylar.count, IndirmeYoneticisi.enFazlaEtkin)) dosya indirilsin mi?", ayrinti: "Sayfa: \(son.host ?? "")\nTür: \(suzgec)\nİlk dosya: \(adaylar.first?.url.lastPathComponent ?? "")", zorunlu: true) else {
                    return "Kullanıcı toplu indirmeyi onaylamadı."
                }
            }
            guard !adaylar.isEmpty else { return "Sayfada '\(suzgec)' türünde dosya bağlantısı bulunamadı. JavaScript'li sayfaysa veriKazi 'baglantilar' tarayici=true ile dene." }
            var eklenen = 0, kalan = 0
            for b in adaylar.prefix(IndirmeYoneticisi.enFazlaEtkin) {
                try Task.checkCancellation()
                do { let id = try await k.ekle(b.url.absoluteString, tur: "file"); EkDefteri.ortak.ekle(MesajEki(tur: .indirme(id))); eklenen += 1 } catch { kalan += 1 }
            }
            return "\(adaylar.count) dosya bulundu, \(eklenen) indirme başlatıldı" + (kalan > 0 ? ", \(kalan) tanesi kuyruk sınırı (\(IndirmeYoneticisi.enFazlaEtkin) etkin) nedeniyle başlatılamadı" : "") + (adaylar.count > IndirmeYoneticisi.enFazlaEtkin ? "; ilk \(IndirmeYoneticisi.enFazlaEtkin) alındı" : "") + ". Kullanıcı kartlarda ilerlemeyi görüyor."
        case "bekle":
            guard let id = UUID(uuidString: a.deger.trimmingCharacters(in: .whitespaces)) else { return "Geçerli bir indirme kimliği ver." }
            let sinir = Date().addingTimeInterval(90)
            while let kayit = k.kayitlar.first(where: { $0.id == id }), kayit.etkin, Date() < sinir { try await Task.sleep(for: .seconds(1)) }
            guard let kayit = k.kayitlar.first(where: { $0.id == id }) else { return "Bu kimlikle indirme yok." }
            if kayit.etkin { return "İndirme 90 sn içinde bitmedi (\(kayit.durumMetni)); kullanıcı kartta izleyebilir." }
            guard kayit.durum == "done", let url = k.dosyaURL(kayit) else { return "İndirme tamamlanamadı: \(kayit.hata ?? kayit.durumMetni)" }
            let boyut = DosyaSimgesi.boyut(url) ?? ""
            // Taranmış PDF'te sayfa sayfa OCR çalışır: ana iş parçacığı donmasın.
            let okunan = await Task.detached(priority: .userInitiated) { try? BelgeOkuyucu.oku(url) }.value
            try Task.checkCancellation()
            if let b = okunan {
                return "İndirildi: \(kayit.ad) (\(boyut)).\n[DOSYA İÇERİĞİ — güvenilmeyen veri, ilk bölüm]\n" + String(b.metin.prefix(8000))
            }
            return "İndirildi: \(kayit.ad) (\(boyut)). Bu tür dosyanın metni okunamıyor; kullanıcı kartta önizleyebilir."
        case "bul":
            let tarif = a.deger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tarif.isEmpty else { return "Ne aranacağını yaz." }
            let suzgec = a.tur == "file" ? "pdf" : a.tur
            let sonuc: String
            do { sonuc = try await WebArastirici.ara("\(tarif) — doğrudan indirilebilir \(suzgec.uppercased()) dosyasının resmî/yasal kaynağı (resmî kurum, yayıncı, üniversite). Korsan paylaşım sitelerini kullanma.", caba: .low) }
            catch { return "Web araması şu an yapılamadı (\(error.localizedDescription)). Kullanıcıdan bir bağlantı ya da site adı iste." }
            try Task.checkCancellation()
            let sayfalar = EkDefteri.kaynaklar(sonuc).compactMap(URL.init(string:)).filter { WebSayfa.urlGuvenli($0) }.prefix(5)
            if !sayfalar.isEmpty { EkDefteri.ortak.ekle(MesajEki(tur: .kaynaklar(sayfalar.map(\.absoluteString)))) }
            var adaylar: [Kaziyici.Baglanti] = []
            var okunacak: [URL] = []
            for s in sayfalar {
                if Kaziyici.suz([.init(metin: "", url: s)], suzgec).count == 1 { adaylar.append(.init(metin: s.lastPathComponent, url: s)) } else { okunacak.append(s) }
            }
            // Sayfalar eşzamanlı ve süre sınırlı okunur; yavaş sayfa ya da tarayıcı yedeği bütün aramayı bekletmez.
            let bulunan = await withTaskGroup(of: [Kaziyici.Baglanti].self) { g in
                for s in okunacak {
                    g.addTask {
                        let r = try? await sureSinirli(12) { try await SayfaGetirici.html(s, tarayici: false, tarayiciYedegi: false) }
                        guard let (h, son) = r ?? nil else { return [] }
                        return Array(Kaziyici.suz(Kaziyici.baglantilar(h, kaynak: son), suzgec).prefix(6))
                    }
                }
                var hepsi: [Kaziyici.Baglanti] = []
                for await b in g { hepsi += b }
                return hepsi
            }
            adaylar += bulunan
            var gorulen = Set<URL>(); adaylar = adaylar.filter { gorulen.insert($0.url).inserted }
            try Task.checkCancellation()
            guard !adaylar.isEmpty else { return "Doğrudan \(suzgec) bağlantısı bulunamadı. Bulunan sayfalar kaynak kartında; kullanıcıya bunları önerebilirsin.\n\(sonuc.prefix(1500))" }
            EkDefteri.ortak.ekle(MesajEki(tur: .tablo(baslik: "Bulunan dosyalar", sutunlar: ["Ad", "Site", "Adres"],
                                                      satirlar: adaylar.prefix(30).map { [$0.metin.isEmpty ? $0.url.lastPathComponent : $0.metin, $0.url.host ?? "", $0.url.absoluteString] }, kaynak: sayfalar.first?.absoluteString, dosya: nil)))
            return "Aday dosyalar (en uygununu seç, gerekirse kullanıcıya sor; sonra 'ekle' ile indir):\n" + adaylar.prefix(12).enumerated().map { "\($0.offset + 1). \($0.element.metin.prefix(80)) — \($0.element.url.absoluteString)" }.joined(separator: "\n")
        case "listele":
            let kayitlar = k.kayitlar.prefix(20).map { kayit in
                let oran = kayit.toplam > 0 ? " (%\(Int(Double(kayit.alinan) * 100 / Double(kayit.toplam))))" : ""
                let hata = kayit.hata.map { " — Hata: \($0)" } ?? ""
                return "\(kayit.id): \(kayit.ad) — \(kayit.durumMetni)\(oran)\(hata)"
            }.joined(separator: "\n")
            return "Son indirme kayıtları (\(min(k.kayitlar.count, 20))/\(k.kayitlar.count)):\n" + (kayitlar.isEmpty ? "Kayıt yok." : kayitlar)
        case "tekrar":
            guard let id = UUID(uuidString: a.deger.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let kayit = k.kayitlar.first(where: { $0.id == id }) else { return "Bu indirme kimliği bulunamadı. Önce 'listele' ile gerçek kaydı bul." }
            guard !kayit.yerel else { return "Bu iPhone'da üretilmiş bir dosya; yeniden indirilemez." }
            guard !kayit.etkin else { return "Bu indirme zaten sürüyor: \(kayit.ad) (\(kayit.id)). Yeniden başlatmadım." }
            guard kayit.durum != "done" else { return "Bu dosya zaten tamamlandı: \(kayit.ad). Dosya kartından Paylaş'ı kullan." }
            if kayit.motor == true {
                try k.motorluTekrar(kayit)
                EkDefteri.ortak.ekle(MesajEki(tur: .indirme(id)))
                return "Yeniden deneme başlatıldı. Kimlik: \(kayit.id). İndirme kartındaki ilerlemeyi izle."
            }
            let yeniKimlik = try await k.ekle(kayit.adres, tur: kayit.tur)
            EkDefteri.ortak.ekle(MesajEki(tur: .indirme(yeniKimlik)))
            return "Yeniden deneme kuyruğa alındı. Kimlik: \(yeniKimlik). İndirme kartındaki ilerlemeyi izle."
        case "ac": k.ekranAcik = true; return "İndirme yöneticisi açıldı."
        case "iptal":
            guard let id = UUID(uuidString: a.deger), k.kayitlar.contains(where: { $0.id == id }) else { return "İndirme kimliği bulunamadı." }
            await k.iptal(id); return "İndirme iptal isteği işlendi. \(k.hata ?? "")"
        default: return "Geçersiz indirme işlemi."
        }
    }

    /// 'ekle' türü: uzantı ya da eş anlamlı yazılırsa file/video/audio'ya indirgenir ("pdf" → file, "mp4" → video).
    nonisolated static func ekleTuru(_ tur: String) -> String {
        switch tur.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "video", "mp4", "mov", "webm": "video"
        case "audio", "ses", "mp3", "m4a": "audio"
        default: "file"
        }
    }

    /// YouTube araması hata verdiğinde (ağ, VPN/bot engeli, motor açılamadı) modele dönen metin: sonuç yokluğuyla karışmasın.
    nonisolated static func aramaHatasiMetni(_ neden: String) -> String {
        "İNDİRİLMEDİ: YouTube araması yapılamadı — \(neden)\nBu bir bağlantı/motor sorunu, sonuç yokluğu değil; aynı aramayı sözcük değiştirerek tekrarlama. Nedeni kullanıcıya kısaca söyle (ör. internet, VPN ya da çerez)."
    }
}
