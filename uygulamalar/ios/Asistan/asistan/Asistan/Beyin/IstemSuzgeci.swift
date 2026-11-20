import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// İstem süzgeci: her kullanıcı isteği ana modele gitmeden önce hızlı bir modelle çözümlenir.
/// Amaç: dikte/yazım hatalarını düzeltmek, gerçek niyeti ve ZORUNLU kısıtları (kaynak, kişi,
/// numara, biçim) ayrıştırmak ve araç çalıştırmadan önce neyin doğrulanacağını ana modele söylemek.
/// Örnek: "Vav radyo kuran meali Ayhan kaya 15. Çöz indir" → "Çöz" = "cüz" (dikte hatası);
/// kısıtlar: Vav Radyo, Ayhan Kaya, 15. cüz; eşleşmeyen aday indirilmez, kullanıcıya sorulur.
@MainActor
final class IstemSuzgeci {
    @Generable
    nonisolated struct Cozumleme {
        @Guide(description: "Kullanıcının isteğinin dikte/yazım hataları düzeltilmiş, anlamı korunmuş hâli. Emin olmadığın düzeltmeyi yapma; metni genişletme.")
        var duzeltilmisIstek: String
        @Guide(description: "Tek cümlelik gerçek amaç: kullanıcı sonuçta neyi elde etmek istiyor?")
        var niyet: String
        @Guide(description: "Sonucun MUTLAKA sağlaması gereken kısıtlar: kaynak/site/kanal, kişi/okuyucu/sanatçı adı, bölüm/cüz/sayı, tarih, dosya türü, dil. Her biri kısa. İstekte yoksa boş liste.", .count(0...6))
        var kisitlar: [String]
        @Guide(description: "Yalnız gerçekten iki anlama gelebilen ya da düzelttiğin sözcükler, 'yanlış → doğru' biçiminde, en çok 5 kelime. Büyük/küçük harf farkı yazılmaz. Yoksa boş liste.", .count(0...3))
        var belirsizlikler: [String]
        @Guide(description: "Araç çalıştırmadan ya da sonuç vermeden önce ana modelin doğrulaması gereken şey (ör. 'adayın başlığında 15. cüz ve okuyucu adı geçmeli'). Doğrulama gerekmiyorsa boş.")
        var dogrulama: String
        @Guide(description: "İstek, kullanıcıya tek bir soru sorulmadan güvenle yerine getirilemiyorsa true.")
        var soruGerekli: Bool
        /// P3.5: isteğe bağlı (eski kurucu çağrıları ve alanı atlayan model çıktısı nil verir); en çok 5 kullanılır (`teslimListesi`).
        @Guide(description: "Kullanıcının açıkça istediği ayrı teslimler (ör. 'PDF dosyası', 'takvime ekleme', 'veliye mesaj'), en çok 5, her biri 2-4 kelime; tek iş ya da sohbetse boş liste.")
        var teslimler: [String]?
        /// P3.4: model kararıyla yönlendirme (isteğe bağlı; eski kurucular nil verir). Yalnız `Ayarlar.aracGruplama` açıkken kullanılır.
        @Guide(description: "İstek bir telefon/uygulama aracı (takvim, hatırlatıcı, mesaj, arama, indirme, dosya/belge üretimi, web sayfası, uygulama açma) çalıştırılmadan doğru yerine getirilemiyorsa true; bilgi sorusu, sohbet, açıklama ya da metin yazımı için false.")
        var aracGerekli: Bool?
        @Guide(description: "Çalışma kipi, yalnız biri: sohbet, arastirma, kod, yazi.")
        var kip: String?
        @Guide(description: "İşin gerektirdiği araç grupları, en çok 4, yalnız şu adlar: iletisim, zaman, dosya, web, cihaz, hafiza. Araç gerekmiyorsa ya da emin değilsen boş liste.")
        var aracGruplari: [String]?
    }

    /// P3.4: süzgecin seçtiği kip (yalnız sohbet/arastirma/kod/yazi; görsel/arşiv/belge modelden alınmaz).
    nonisolated static func modelKipi(_ c: Cozumleme) -> CalismaKipi? {
        guard let k = c.kip.flatMap(AtolyeYonlendirme.coz), AtolyeYonlendirme.suzgecKipleri.contains(k) else { return nil }
        return k
    }

    /// P3.5: süzgecin teslim listesi (boşlar atılır, en çok 5).
    nonisolated static func teslimListesi(_ c: Cozumleme) -> [String] {
        Array((c.teslimler ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(5))
    }

    static let talimat = """
    Sen bir istem süzgecisin. Kullanıcının Türkçe isteğini (çoğu zaman sesle dikte edilmiştir) ana asistana geçmeden önce çözümlersin. \
    Dikte hatalarını bağlamdan düzelt ("Çöz indir" bir Kur'an meali bağlamında "cüz indir"dir; "on beş" = 15). \
    Kişi, kaynak, kanal, numara, tarih, tür gibi her somut ayrıntı zorunlu bir kısıttır; bunları eksiksiz listele. \
    "Üçüncüsü", "bunu", "bu soru" gibi göndermeler asistanın son yanıtında çözülüyorsa belirsiz sayma; soruGerekli yalnız bağlamda hiçbir ipucu yoksa true olsun. \
    Yorum katma, isteği genişletme, yeni iş ekleme. Her alan telgraf kısalığında olsun: niyet ve doğrulama en çok 15 kelime, \
    her kısıt 2-4 kelime ("kaynak: Vav Radyo", "okuyucu: Ayhan Kaya", "15. cüz"). Açıklama cümlesi yazma.
    """ + "\n" + AtolyeYonlendirme.suzgecKipTanimi + "\n" + """
    aracGruplari: iletisim = arama, SMS, WhatsApp, kişiler, gelen kutusu; zaman = takvim, hatırlatıcı, alarm, zamanlayıcı, sunucu rutini; \
    dosya = Word/PDF/Excel/ZIP belgesi, dosyalar, galeri fotoğrafları; web = sayfa okuma, veri kazıma, indirme, YouTube, tarayıcı, alt ajanlar, MCP, sunucu görevi; \
    cihaz = uygulama açma, kestirme, müzik, harita, hava, ev, fener, telefon ayarları; hafiza = çalışma alanı, eski sohbetler, proje. \
    Web araması, saat, plan, beceri ve hafıza kaydı her zaman açıktır, grup gerektirmez.
    """

    /// Son isteğin süzgeç çözümlemesi; her yeni gönderimde nil olur, süzgeç sonuç verince atanır (indirme aracı kısıtları buradan okur).
    @MainActor static var son: Cozumleme?
    /// Son kabul edilen isteğin ham (kullanıcının yazdığı/dikte ettiği) metni; süzgeç yokken yerel kısıtlar buradan çıkar.
    @MainActor static var sonHam: String = ""

    /// Eşleşme ve yanıt sonu denetiminin kullandığı kısıtlar (P2.10): süzgeç kısıt verdiyse YALNIZ onlar (süzgeç dikteyi
    /// düzeltmiştir: "Çöz" → "cüz"), süzgeç yoksa ya da boşsa ham istekteki rakam/özel ad kısıtları (`KisitDenetimi.yerelKisitlar`).
    @MainActor static var etkinKisitlar: [String] { etkinKisitlariSec(suzgec: son?.kisitlar ?? [], ham: sonHam) }

    nonisolated static func etkinKisitlariSec(suzgec: [String], ham: String) -> [String] {
        var gorulen = Set<String>()
        let temiz = suzgec.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !KisitDenetimi.birimliMiktarMi($0) && gorulen.insert($0).inserted }
        return temiz.isEmpty ? KisitDenetimi.yerelKisitlar(ham) : temiz
    }

    /// İş isteyen sözcükler: kök biçimleri (önek eşleşmesi, en az 5 harf) ve kısa emirler (tam eşleşme).
    nonisolated static let isKokleri = ["indir", "hatirlat", "takvim", "etkinlik", "randevu", "mesaj", "gonder", "kaydet", "olustur", "donustur",
                                        "whatsapp", "zamanla", "kisayol", "kestirme", "youtube", "alarm", "excel", "planla", "listele", "telefon"]
    nonisolated static let kisaEmirler: Set<String> = ["ac", "acsana", "ara", "arasana", "bul", "bulsana", "cal", "sil", "ekle", "kur", "yaz", "yazsana",
                                                       "pdf", "sms", "mp3", "mp4", "tara", "oynat", "indir"]

    /// Süzgeç yalnız iş isteyen (eylem/arama/indirme/hatırlatma/takvim/mesaj) ya da özel ad/sayı içeren isteklerde çalışır.
    /// Ekli istekler, canlı ses, selamlaşma ve düz sohbet ("Mitoz ile mayoz farkı ne") atlanır.
    /// `yarisAdayi`: istek araçsız paralel yarışa girecekse süzgeç hiç başlamaz (yarış onu beklemez; çağrı boşa giderdi).
    /// P3.4 `modelYonlendirme` (yalnız `Ayarlar.aracGruplama` açıkken yarış adayında true): sözcük sezgilerine bakılmaz; yalnız ek,
    /// canlı ses, yerel kısa yanıt, yerel saat ve slash komutu atlanır (süzgeç yarışla aynı anda araç gereksinimini söyler).
    nonisolated static func gerekliMi(_ metin: String, ekVar: Bool = false, canliSes: Bool = false, yarisAdayi: Bool = false,
                                      modelYonlendirme: Bool = false) -> Bool {
        if ekVar || canliSes { return false }
        if yarisAdayi && !modelYonlendirme { return false }
        let t = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelYonlendirme {
            guard !t.isEmpty else { return false }
            if HizliModelSecimi.yerelKisaYanit(t) != nil || HizliModelSecimi.yerelSaat(t) != nil { return false }
            return SlashKomutlari.coz(t) == nil
        }
        guard t.count >= 8 else { return false }
        if HizliModelSecimi.yerelKisaYanit(t) != nil || HizliModelSecimi.yerelSaat(t) != nil { return false }
        if SlashKomutlari.coz(t) != nil { return false }
        let asil = t.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard asil.count >= 3 else { return false }
        if t.contains(where: \.isNumber) { return true }
        // İlk sözcükten sonra büyük harfle başlayan sözcük: özel ad (kişi, kanal, yer).
        if asil.dropFirst().contains(where: { $0.first?.isUppercase == true }) { return true }
        let kelimeler = AtolyeYonlendirme.normalize(t).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return kelimeler.contains { k in kisaEmirler.contains(k) || isKokleri.contains { k.hasPrefix($0) } }
    }

    /// Önceki kullanıcı isteğinin modele giden özgün metni: balondaki "📷 " / "↻ … ile yeniden" görünümü değil.
    nonisolated static func oncekiIstekMetni(istek: String?, metin: String) -> String {
        if let istek, !istek.isEmpty { return istek }
        return metin.replacingOccurrences(of: "📷 ", with: "")
    }

    /// Süzgeç modeline giden girdi: asistanın son yanıtı (ilk 300 karakter) ve önceki istek bağlam olarak önde.
    nonisolated static func girdi(_ ham: String, oncekiIstek: String, oncekiYanit: String) -> String {
        let yanit = oncekiYanit.trimmingCharacters(in: .whitespacesAndNewlines)
        return (yanit.isEmpty ? "" : "Asistanın son yanıtı (bağlam; adaylar/sorular burada olabilir): \(yanit.prefix(300))\n\n")
            + (oncekiIstek.isEmpty ? "" : "Önceki istek (bağlam): \(oncekiIstek.prefix(300))\n\n") + "İstek: \(ham)"
    }

    /// Araçlı zincirden hemen önce süzgeç sonucunu en geç `sonTarih`e kadar bekler; yetişmezse işi iptal eder (nil, akış bloksuz sürer).
    /// Üstteki görev iptal edilirse süzgeç işi de iptal edilir.
    static func sonucuBekle(_ is_: Task<Cozumleme?, Never>, sonTarih: Date) async -> Cozumleme? {
        let bekci = Task {
            do { try await Task.sleep(for: .seconds(max(0, sonTarih.timeIntervalSinceNow))); is_.cancel() } catch {}
        }
        defer { bekci.cancel() }
        return await withTaskCancellationHandler { await is_.value } onCancel: { is_.cancel() }
    }

    /// Ana modele eklenen blok. Boş çözümlemede (hiçbir düzeltme/kısıt yok) nil döner.
    nonisolated static func blok(_ c: Cozumleme, ham: String) -> String? {
        var satirlar: [String] = []
        let duz = c.duzeltilmisIstek.trimmingCharacters(in: .whitespacesAndNewlines)
        if !duz.isEmpty, AtolyeYonlendirme.normalize(duz) != AtolyeYonlendirme.normalize(ham) { satirlar.append("Düzeltilmiş istek: \(duz)") }
        let niyet = c.niyet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !niyet.isEmpty { satirlar.append("Amaç: \(niyet)") }
        let kisitlar = c.kisitlar.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !kisitlar.isEmpty { satirlar.append("Zorunlu kısıtlar (hepsi sağlanmalı): " + kisitlar.joined(separator: "; ")) }
        let belirsiz = c.belirsizlikler.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !belirsiz.isEmpty { satirlar.append("Belirsiz sözcükler: " + belirsiz.joined(separator: "; ")) }
        let dogrulama = c.dogrulama.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dogrulama.isEmpty { satirlar.append("İşlemden önce doğrula: \(dogrulama)") }
        if c.soruGerekli { satirlar.append("Bağlam ve ekler isteği netleştirmiyorsa: gerekiyorsa araç çalıştırmadan önce tek, net bir soru sor.") }
        guard !satirlar.isEmpty else { return nil }
        return "\n\n[İstem çözümlemesi — uygulamanın süzgeci üretti, kullanıcı yazmadı; kısıtlar bağlayıcıdır]\n" + satirlar.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Yönlendirmeye (kip, çaba, yarış uygunluğu, hafıza) girecek ölçülü dikte düzeltmesi; yoksa nil.
    /// Aynı metin (büyük/küçük harf ve aksan farkı dahil) ya da boş düzeltme nil döner. Sözcük sayısı 2'den fazla değiştiyse ya da
    /// karakter düzeyinde düzenleme uzaklığı max(3, ham uzunluğu / 4)'ü aşıyorsa süzgeç metni yeniden yazmış sayılır: nil.
    nonisolated static func olculuDuzeltme(ham: String, duz: String) -> String? {
        let d = duz.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = ham.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty else { return nil }
        let nh = AtolyeYonlendirme.normalize(h), nd = AtolyeYonlendirme.normalize(d)
        guard nh != nd else { return nil }
        let sozcukH = nh.split(whereSeparator: \.isWhitespace).count
        let sozcukD = nd.split(whereSeparator: \.isWhitespace).count
        guard abs(sozcukH - sozcukD) <= 2 else { return nil }
        guard duzenlemeUzakligi(nh, nd) <= max(3, h.count / 4) else { return nil }
        return d
    }

    /// Levenshtein (karakter düzeyinde ekleme/silme/değiştirme) uzaklığı; iki satırlık bellekle.
    nonisolated static func duzenlemeUzakligi(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var onceki = Array(0...y.count)
        var simdiki = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            simdiki[0] = i
            for j in 1...y.count {
                let bedel = x[i - 1] == y[j - 1] ? 0 : 1
                simdiki[j] = min(onceki[j] + 1, simdiki[j - 1] + 1, onceki[j - 1] + bedel)
            }
            swap(&onceki, &simdiki)
        }
        return onceki[y.count]
    }

    /// Süre sınırlı çözümleme; hata ya da zaman aşımında nil (ana akış değişmeden sürer).
    /// `kimlik`: süzgeç modelinin kimliği; çağrı KullanimDefteri'ne (istek/başarı/hata), süresi SaglikMerkezi'ne 'istem_suzgeci' olarak yazılır.
    /// İptal edilen çağrı (kısa yol işi aldı, kullanıcı durdurdu) ne sayaca ne sağlık ölçümüne girer.
    func coz(_ ham: String, oncekiIstek: String, oncekiYanit: String = "", model: ClaudeLanguageModel, saniye: Double,
             kimlik: String = "claude-haiku-5-5") async -> Cozumleme? {
        let oturum = LanguageModelSession(model: model, instructions: Self.talimat)
        let girdi = Self.girdi(ham, oncekiIstek: oncekiIstek, oncekiYanit: oncekiYanit)
        let baslangic = Date()
        KullanimDefteri.ortak.say(kimlik, .istek)
        var hata = "zaman aşımı"
        var iptal = false
        var sonuc: Cozumleme?
        do { sonuc = try await sureSinirli(saniye) { try await oturum.respond(to: girdi, generating: Cozumleme.self).content } }
        catch {
            // Son tarihte bekçinin iptali (sonucuBekle) zaman aşımıdır ve ölçülür; daha önceki iptal ölçülmez.
            iptal = Task.isCancelled && Date().timeIntervalSince(baslangic) < saniye * 0.95
            hata = iptal ? "iptal" : (Task.isCancelled ? "zaman aşımı" : String(describing: type(of: error)))
        }
        let gecen = Date().timeIntervalSince(baslangic)
        let sure = Int(gecen * 1000)
        if !iptal {
            KullanimDefteri.ortak.say(kimlik, sonuc != nil ? .basari : .hata)
            SaglikMerkezi.ortak.kaydet("istem_suzgeci", sure: gecen, basarili: sonuc != nil, etiket: kimlik)
        }
        // Tanı günlüğüne kullanıcı metni yazılmaz: yalnız süre, kısıt sayısı ve düzeltme yapıldı mı.
        if let s = sonuc {
            let duzeltildi = AtolyeYonlendirme.normalize(s.duzeltilmisIstek) != AtolyeYonlendirme.normalize(ham)
            TaniGunlugu.yaz("SÜZGEÇ \(sure) ms: kısıt=\(s.kisitlar.count) düzeltme=\(duzeltildi) soru=\(s.soruGerekli)")
            // Dikte sözlüğü yalnız sesli istekte öğrenir (yazılı isteğin yazım düzeltmesi sözlüğü kirletmez); metin günlüğe yazılmaz.
            if duzeltildi { DikteDuzeltmeDefteri.ortak.suzgectenOgren(ham: ham, duzeltilmis: s.duzeltilmisIstek) }
            return s
        }
        TaniGunlugu.yaz("SÜZGEÇ atlandı (\(sure) ms): \(hata)")
        #if DEBUG
        print("SÜZGEÇ atlandı (\(sure) ms): \(hata)")
        #endif
        return nil
    }
}
