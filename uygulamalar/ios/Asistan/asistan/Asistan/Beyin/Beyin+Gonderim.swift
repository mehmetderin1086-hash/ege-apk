import Foundation
import FoundationModels
import CoreGraphics

/// P3.4: yarış ile süzgeç kollayıcısının paylaştığı durum (yalnız ana aktörde okunur/yazılır).
@MainActor final class YarisKollamasi {
    /// Kullanıcıya görünen ilk parça yazıldı (bundan sonra süzgeç yarışı kesmez, yalnız günlüğe yazar).
    var ilkParca = false
    /// Yarış sonuçlandı (başarı ya da hata).
    var bitti = false
    /// Yarışı süzgecin "araç gerekli" kararı iptal etti.
    var suzgecIptali = false
}

/// Bir isteğin yönlendirme aşamalarında paylaştığı bağlam.
struct IstekBaglami {
    let hamIstek: String
    let gorsel: CGImage?
    let belge: String?
    /// Süzgeç ölçülü bir düzeltme verince düzeltilmiş metinle yeniden seçilebilir (bu yüzden `var`).
    var kip: CalismaKipi
    var caba: DusunmeSecimi.Caba
    let canliSes: Bool
    let nesil: Int
    let oncekiKip: CalismaKipi
    let oncekiIstek: String
    let cabaAyari: String
    /// Yeniden üretimde zorunlu model: yarış, yerel ve doğrudan araştırma yolları atlanır.
    var zorlaModel: String? = nil
    /// İstem süzgecinin ölçülü dikte düzeltmesi (`IstemSuzgeci.olculuDuzeltme`); yoksa nil.
    var yonlendirmeMetni: String? = nil
    /// İsteğin bütün görselleri (sırası korunur; `gorsel` ilkidir). Oylamalı çözüm her modele hepsini ek olarak verir.
    var gorseller: [CGImage] = []
    /// Yönlendirme kararlarında (yarış uygunluğu, hafıza, uzman bağlamı) kullanılan metin.
    var yonMetni: String { yonlendirmeMetni ?? hamIstek }
}

/// `gonder()` yönlendirme aşamaları: her aşama isteği işlediyse true döner (sonrakilere geçilmez).
extension Beyin {
    /// Model gerektirmeyen kısa yanıtlar ve yerel saat.
    func yerelYanitDene(_ b: IstekBaglami) -> Bool {
        if b.zorlaModel != nil { return false }
        if b.gorsel == nil, b.belge == nil, let kisa = HizliModelSecimi.yerelKisaYanit(b.hamIstek) {
            self.aktifModel = "iPhone · hızlı yanıt"; self.aktifYol = nil
            self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.hamIstek))])), .response(.init(segments: [.text(.init(content: kisa))]))]
            self.tamamla(kisa, nesil: b.nesil); return true
        }
        if b.gorsel == nil, b.belge == nil, let saat = HizliModelSecimi.yerelSaat(b.hamIstek) {
            self.aktifModel = "iPhone · yerel saat"; self.aktifYol = nil
            self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.hamIstek))])), .response(.init(segments: [.text(.init(content: saat))]))]
            self.tamamla(saat, nesil: b.nesil); return true
        }
        return false
    }

    /// Çevrimdışı karar: istek bağlantısız, olağan akışta yerelde yanıtlanır mı (kuyruğa girmez).
    /// Ekli istek, zorunlu model ve izni "otomatik" olmayan yerel komut kuyruğa gider.
    func yereldeYanitlanir(_ t: String, ekVar: Bool, disKaynak: Bool) -> Bool {
        guard !ekVar, zorlananModel == nil, YerelKomut.cevrimdisiYanitlanir(t) else { return false }
        guard let k = YerelKomut.coz(t) else { return true }
        return yerelKomutIzinli(k, disKaynak: disKaynak)
    }

    /// Yerel komut kısa yoldan çalışabilir mi: aracın politikası "otomatik" olmalı (aksi hâlde onaylı zincire düşer);
    /// dış kaynaklı turda yan etkili komut (fener, zamanlayıcı, alarm) kısa yoldan çalışmaz.
    func yerelKomutIzinli(_ k: YerelKomut.Komut, disKaynak: Bool) -> Bool {
        if disKaynak, YerelKomut.yanEtkili(k) { return false }
        guard let ad = YerelKomut.aracAdi(k) else { return true }
        return AjanDefteri.ortak.politika(ad) == .otomatik
    }

    /// Model gerektirmeyen telefon komutları (YerelKomut): fener, zamanlayıcı, alarm, bugün/yarın takvimi, tarih.
    /// Var olan araçları doğrudan çağırır; bağlantı olmadan da çalışır. Araç hata metni dönerse de yanıt odur (model yoluna düşülmez).
    func yerelKomutDene(_ b: IstekBaglami) async -> Bool {
        guard b.zorlaModel == nil, b.gorsel == nil, b.belge == nil, let k = YerelKomut.coz(b.hamIstek),
              yerelKomutIzinli(k, disKaynak: self.onay.disKaynakTuru) else { return false }
        let adim = YerelKomut.aracAdi(k).map { self.gorevler.baslat($0, yanEtkili: YerelKomut.yanEtkili(k)) }
        let sonuc: String
        do { sonuc = try await Self.yerelKomutCalistir(k) } catch { sonuc = "Komut çalıştırılamadı: \(error.localizedDescription)" }
        if let adim { self.gorevler.bitir(adim, durum: "Araç yanıtladı") }
        guard !Task.isCancelled, b.nesil == self.nesil else { return true }
        self.aktifModel = "iPhone · yerel komut"; self.aktifYol = nil
        self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.hamIstek))])), .response(.init(segments: [.text(.init(content: sonuc))]))]
        self.tamamla(sonuc, nesil: b.nesil)
        return true
    }

    /// Kısa indirme devamları normalde istem süzgecinin 8 karakter/3 sözcük eşiğinin altında
    /// kalır; son kullanıcı isteği indirme ise yerel olarak gerçek kayıtla eşleştir.
    func indirmeDevaminiDene(_ b: IstekBaglami) async -> Bool {
        guard b.zorlaModel == nil, b.gorsel == nil, b.belge == nil else { return false }
        let metin = AtolyeYonlendirme.normalize(b.hamIstek)
        let tekrar = ["tekrar dene", "yeniden dene", "tekrar baslat", "yeniden baslat"].contains { metin.contains($0) }
        let durum = ["indirmiyor", "gelmedi", "sorun mu var", "indirme durumu", "ilerleme"].contains { metin.contains($0) }
        guard tekrar || durum else { return false }
        let oncekiKullanicilar = Array(mesajlar.dropLast().filter { $0.rol == .kullanici }.suffix(8))
        let sonKullanici = oncekiKullanicilar.last
        let indirmeIstegi = oncekiKullanicilar.last(where: {
            AtolyeYonlendirme.normalize($0.istek ?? $0.metin).range(of: #"\b(indir\w*|download\w*|youtube|mp4|m4a)\b"#, options: .regularExpression) != nil
        })
        let secim: Beyin.Goruntu? = {
            guard let id = indirmeIstegi?.id, let ix = oncekiKullanicilar.firstIndex(where: { $0.id == id }),
                  oncekiKullanicilar.indices.contains(ix + 1) else { return nil }
            return oncekiKullanicilar[ix + 1]
        }()
        let baglam = oncekiKullanicilar.map { $0.istek ?? $0.metin }.joined(separator: " ") + " " + (mesajlar.last(where: { $0.rol == .asistan })?.metin ?? "")
        let baglamNorm = AtolyeYonlendirme.normalize(baglam)
        guard baglamNorm.range(of: #"\b(indir\w*|indirme\w*|youtube|mp4|m4a)\b"#, options: .regularExpression) != nil else { return false }

        let yonetici = IndirmeYoneticisi.ortak
        // Eşleştirmede önce bu sohbetten gelen özel adı kullan; alakasız eski indirmeyi asla tekrar başlatma.
        let aranacak = ([indirmeIstegi?.istek ?? indirmeIstegi?.metin, secim?.istek ?? secim?.metin].compactMap { $0 }).joined(separator: " ")
        let kelimeler = AtolyeYonlendirme.normalize(aranacak).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count >= 4 && !["indir", "mp4", "video", "indiriliyor", "tekrar", "dene"].contains(String($0)) }
        let aday = yonetici.kayitlar.first { kayit in
            let ad = AtolyeYonlendirme.normalize(kayit.ad)
            return !kelimeler.isEmpty && kelimeler.contains(where: { ad.contains($0) })
        }
        let cevap: String
        if let aday, tekrar, !aday.yerel, !aday.etkin, aday.durum != "done" {
            do {
                if aday.motor == true { try yonetici.motorluTekrar(aday) }
                else { _ = try await yonetici.ekle(aday.adres, tur: aday.tur) }
                EkDefteri.ortak.ekle(MesajEki(tur: .indirme(aday.id)))
                cevap = "Gerçek indirme kaydını buldum (\(aday.ad)). Yeniden deneme başlatıldı; İndirme kartında kimliği \(aday.id) ile ilerlemeyi izleyebilirsin."
            } catch {
                cevap = "Yeniden deneme başlatılamadı (\(aday.ad)): \(error.localizedDescription)"
            }
        } else if let aday, aday.etkin {
            cevap = "\(aday.ad) zaten indiriliyor: \(aday.durumMetni) (\(aday.alinan)/\(aday.toplam) bayt). Yeni kopya başlatmadım."
        } else if let aday, aday.durum == "done" {
            cevap = "\(aday.ad) indirmesi tamamlanmış. İndirmeler ekranında dosyayı açıp Paylaş'ı seçebilirsin."
        } else if tekrar, !aranacak.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let sonuc = try await IndirmeAraci().call(arguments: .init(islem: "ekle", deger: aranacak, tur: "video"))
                cevap = sonuc
            } catch {
                cevap = "Yeni indirme denemesi başlatılamadı: \(error.localizedDescription)"
            }
        } else {
            cevap = "Bu istek için indirme kaydı bulamadım; önceki ‘başlatıldı’ yanıtı gerçek indirme oluşturmamış. Otomatik olarak yeni kopya başlatmadım. Dosyanın adını veya bağlantısını yeniden gönder."
        }
        self.aktifModel = "iPhone · indirme durumu"; self.aktifYol = nil
        self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.hamIstek))])), .response(.init(segments: [.text(.init(content: cevap))]))]
        self.tamamla(cevap, nesil: b.nesil)
        return true
    }

    /// Yerel komutu var olan araçla yürütür; aracın hata metni (izin yok vb.) olduğu gibi döner.
    nonisolated static func yerelKomutCalistir(_ k: YerelKomut.Komut) async throws -> String {
        switch k {
        case .fener(let ac):
            return try await CihazAraci().call(arguments: .init(islem: "fener", deger: ac ? "ac" : "kapat"))
        case .zamanlayici(let saniye, let etiket):
            return try await ZamanlayiciAraci().call(arguments: .init(islem: "zamanlayici", saniye: saniye, zaman: nil, baslik: etiket))
        case .alarm(let saat, let dakika):
            guard let z = YerelKomut.alarmZamani(saat: saat, dakika: dakika) else { return "Alarm saati anlaşılmadı." }
            return try await ZamanlayiciAraci().call(arguments: .init(islem: "alarm", saniye: nil, zaman: z.iso, baslik: nil))
        case .takvim(let gun):
            let a = YerelKomut.gunAraligi(gun: gun)
            let liste = try await TakvimAraci().call(arguments: .init(islem: "listele", baslangic: a.baslangic, bitis: a.bitis, baslik: nil, yer: nil,
                                                                      not: nil, haftalik: nil, tekrarBitis: nil, uyariDakika: nil, toplu: nil))
            return liste.hasPrefix("•") ? (gun == 0 ? "Bugün takviminde:\n" : "Yarın takviminde:\n") + liste : liste
        case .tarih:
            return YerelKomut.tarihMetni()
        case .sistem(let s):
            return try await CihazAraci.sistem(s, onay: nil, yerel: true)
        }
    }

    /// Yarış modelinin "güncel bilgi gerekiyor, ara" işareti.
    nonisolated static let yarisAramaIsareti = "[ARAMA]"

    /// Saf karar: yarış yanıtı arama işareti mi (yanıt yerine araçlı zincire geçilir).
    nonisolated static func aramaIsaretiMi(_ metin: String) -> Bool {
        metin.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[ARAMA")
    }

    /// Saf karar: akan kısmi metin arama işaretinin başı olabilir mi (ekrana/sese yazılmaz). Boş metin de yazılmaz.
    nonisolated static func aramaIsaretiOlabilir(_ metin: String) -> Bool {
        let bas = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        return bas.isEmpty || aramaIsaretiMi(bas) || yarisAramaIsareti.hasPrefix(bas)
    }

    /// Saf karar: istek güncel bilgi (skor, kur, kripto, haber, fiyat, dünkü maç) istiyor mu. Bu istekler araçsız yarışa girmez.
    /// Türkçe karakterler korunarak bakılır: "göl" (gölü, göller) "gol" ile karışmasın; "haberleşme" (biyoloji) haber sayılmaz.
    nonisolated static func guncelBilgiIstegi(_ metin: String) -> Bool {
        let s = metin.lowercased(with: Locale(identifier: "tr_TR"))
        let desen = #"\b(kaç kaç|kac kac|kaç bitti|kac bitti|kim kazandı|kim kazandi|kim attı|kim atti|gol|golü|golleri|goller|golcü\w*|bitcoin\w*|btc|ethereum\w*|kripto\w*|döviz\w*|doviz\w*|sterlin\w*|hisse(si|leri|ler)?|fiyat\w*|haberler\w*|haberi|dün akşam\w*|dun aksam\w*|dün gece\w*|dun gece\w*|dünkü|dunku)\b"#
        return s.range(of: desen, options: .regularExpression) != nil
    }

    /// Saf karar: istek araçsız paralel yarışa girer mi. `paralelYarisDene` ve `gonder` (süzgeci atlama kararı) bu tek kopyayı kullanır.
    /// Otomatik model, sohbet kipi, ek yok, yüksek çaba değil, araç/yan etki gerektirmiyor ve güncel bilgi istemiyor.
    nonisolated static func yarisAdayiMi(_ metin: String, kip: CalismaKipi, caba: DusunmeSecimi.Caba, ekVar: Bool,
                                          otomatik: Bool, yalnizAnahtar: Bool) -> Bool {
        otomatik && kip == .sohbet && !ekVar && caba != .high
            && CanliHizliIstemci.uygun(metin) && !yalnizAnahtar && !guncelBilgiIstegi(metin)
    }

    /// Saf karar: süzgecin düzeltilmiş metniyle yeniden seçilen kip. Yalnız sohbet/yazı/araştırma/kod kiplerinde
    /// ve yalnız sohbet/yazı/araştırma kiplerine geçilir: atölye ve sunucu kod aşamaları geçildiği için o kipler zincirde yanlış talimat olurdu.
    nonisolated static func yonlendirmeKipi(eski: CalismaKipi, aday: CalismaKipi) -> CalismaKipi {
        let kaynak: [CalismaKipi] = [.sohbet, .yazi, .arastirma, .kod]
        let hedef: [CalismaKipi] = [.sohbet, .yazi, .arastirma]
        return kaynak.contains(eski) && hedef.contains(aday) ? aday : eski
    }

    /// Araçsız sohbet: üç model paralel yarışır, ilk metni üreten kazanır.
    /// Süzgecin ölçülü düzeltmesi varsa (`b.yonlendirmeMetni`) karar, hafıza, uzman bağlamı ve yarış mesajı düzeltilmiş metni kullanır.
    /// `suzgec` (P3.4, yalnız `Ayarlar.aracGruplama` açıkken): yarışla aynı anda çalışan istem süzgeci; `aracGerekli` derse ve
    /// henüz görünür parça yoksa yarış iptal edilir, false döner (araçlı zincir devralır).
    func paralelYarisDene(_ b: IstekBaglami, suzgec: Task<IstemSuzgeci.Cozumleme?, Never>? = nil) async -> Bool {
        if b.zorlaModel != nil { return false }
        // P4.2: yarış iPhone CLIProxy'ye (TelefonProxy.taban) gider; arka planda (bas-konuş, kilitliyken Live) yerel sunucu
        // askıda olabilir, istek doğrudan araçlı zincire (vekil → anahtar) düşer.
        if Self.arkaPlanda { return false }
        // Otomatik modda araçsız sohbet: üç model aynı anda akışlı denenir, ilk metni üreten kazanır.
        // Araç/yan etki gerektiren istekler buraya girmez (aynı işlem iki kez çalışabilir).
        // Etkin proje talimatı ve uzman bağlamı yarışın sistem istemine eklenir (yarış kapanmaz; sohbet/Live gecikmesi artmaz).
        // Güncel bilgi (skor, kur, haber, fiyat) isteyen istekler yarışa girmez: araçsız model aranmamış yanıt verirdi.
        if Self.yarisAdayiMi(b.yonMetni, kip: b.kip, caba: b.caba, ekVar: b.gorsel != nil || b.belge != nil,
                             otomatik: self.ayarlar.otomatikModel, yalnizAnahtar: self.ayarlar.yalnizAnahtar) {
            await TelefonProxy.ortak.hazirla()
            guard !Task.isCancelled, b.nesil == self.nesil else { return true }
            if TelefonProxy.ortak.kasaHazir {
                let gecmis = self.mesajlar.dropLast().suffix(16).map { m -> ParalelYaris.Mesaj in
                    let ek = m.ekler.isEmpty ? "" : "\n[Gösterilen: " + m.ekler.compactMap { e -> String? in
                        switch e.tur { case .dosya(_, let ad): "dosya \(ad)"; case .tablo(let t, _, let r, _, _): "tablo \(t) (\(r.count) satır)"; case .medya(let o): "\(o.count) medya"; case .kaynaklar(let k): "\(k.count) kaynak"; case .indirme: nil; case .eylem(let k): "eylem kartı \(k.baslik)"; case .hava(let h): "hava \(h.ad)"; case .izin(let t): "\(t.ad) izin kartı" }
                    }.joined(separator: ", ") + "]"
                    return ParalelYaris.Mesaj(rol: m.rol == .kullanici ? "user" : "assistant", metin: String(m.metin.prefix(3000)) + ek)
                }
                var sistem = Talimatlar.olustur(olgular: self.depo.talimatOlgulari()) + "\n\n" + self.ayarlar.dostBaglami + HafizaDeposu.geriCagirmaMetni(self.depo.geriCagir(b.yonMetni, haricSohbet: self.sohbet?.kimlik))
                if let proje = ProjeDeposu.ortak.aktif { sistem += "\n\n" + proje.talimat }
                if let uzman = UzmanTakimi.ortak.baglam(istek: b.yonMetni) { sistem += "\n\n" + uzman }
                // Araç yasağı sonda kalır: proje/uzman metnindeki araç beklentisini bu yanıt için geçersiz kılar.
                sistem += "\nBu yanıtta araç çağıramazsın; yukarıdaki araç talimatları bu yanıt için geçersiz. Şimdiki tarih ve saat 'Oturum başlangıcı' satırındadır. Aracı kullanıyormuş gibi anlatma ('bakıyorum', 'arıyorum' deme); telefonda işlem yaptığını veya bir şeyi kaydettiğini iddia etme. Soru canlı skor, maç sonucu, haber, fiyat/kur gibi güncel bilgi ya da bunların devam sorusu ise ('goller', 'kim attı', 'kaç kaç') yanıt yazma; yalnız \(Self.yarisAramaIsareti) yaz."
                if b.canliSes { sistem += "\n[Canlı sesli diyalog: kullanıcı daha fazla ayrıntı istemedikçe 1-3 kısa, doğal cümleyle yanıtla. Tablo ve uzun başlık kullanma.]" }
                sistem += Self.surusTalimati(aktif: SurusKipi.ortak.aktif)   // P4.7
                let bas = Date()
                // Kota/erişim nedeniyle askıdaki modeller yarışa girmez; hepsi askıdaysa varsayılan liste denenir.
                let mevcut = TelefonProxy.ortak.modeller.map(\.id)
                let aday = b.canliSes && ayarlar.canliClaude
                    ? ParalelYaris.canliClaudeYarisi(antigravity: ayarlar.antigravityOncelik, mevcut: mevcut)
                    : ParalelYaris.yarisModelleri(antigravity: ayarlar.antigravityOncelik, mevcut: mevcut)
                // Yarış iPhone CLIProxy'den gider: model geneli ya da telefon yoluna özgü askı yarıştan düşürür (P3.7).
                let acikModeller = aday.filter { !self.modelVitesi.askida($0, yol: .telefon) }
                // P3.9: ağır termal durumda tek model, Düşük Güç'te en çok iki (GucPolitikasi).
                let genislik = ParalelYaris.genislik(ayar: ayarlar.yarisSaglayici, dusukVeri: AgIzleyici.ortak.dusukVeri,
                                                     termalAgir: GucPolitikasi.ortak.termalAgir, dusukGuc: GucPolitikasi.ortak.dusukGuc)
                let yarisModelleri = Array((acikModeller.isEmpty ? aday : acikModeller).prefix(genislik))
                self.yarisSonYazim = nil
                // P3.4: süzgeç yarışla aynı anda çalışır (yalnız gruplama açıkken `suzgec` dolu); ilk görünür parçadan önce
                // "araç gerekli" derse yarış kesilir ve istek araçlı zincire geçer.
                let kollama = YarisKollamasi()
                let akis: @Sendable (String, String) async -> Void = { [weak self] model, metin in
                    await MainActor.run {
                        guard let self, b.nesil == self.nesil else { return }
                        // Arama işareti ne ekranda görünür ne seslendirilir; yarış sonunda araçlı zincire geçilir.
                        if Beyin.aramaIsaretiOlabilir(metin) { return }
                        // "Yaptım" bekçisi: iş iddiası (ya da bitmemiş şüpheli cümle) ekrana/sese yazılmaz.
                        if !self.eylemYonlendirildi, !EylemIddiasi.anlatiIstegi(b.hamIstek), EylemIddiasi.akistaTut(metin) { return }
                        kollama.ilkParca = true
                        // P3.9: ekrana en çok ~30/sn yazılır (her parçada balon yeniden çizilmesin); ilk parça hemen.
                        // Seyreltilmemiş tam metin tamponda (Durdur arşivi); son tam metni tamamla(r.metin) yazar.
                        self.akisTamponu = metin
                        let simdi = ContinuousClock.now
                        if let son = self.yarisSonYazim, simdi - son < .milliseconds(33) { return }
                        self.yarisSonYazim = simdi
                        self.aktifModel = model; self.aktifYol = .telefon
                        self.akanMetin = metin
                        if self.durum != .yaziyor { self.durum = .yaziyor }
                    }
                }
                do {
                    let taban = TelefonProxy.ortak.taban, anahtar = TelefonProxy.ortak.yerelAnahtar
                    let yarisMesajlari: [ParalelYaris.Mesaj] = gecmis + [.init(rol: "user", metin: b.yonMetni)]
                    let yarisSistemi = sistem
                    let r: ParalelYaris.Sonuc
                    if let suzgec {
                        let yarisIsi = Task {
                            try await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: yarisModelleri, sistem: yarisSistemi,
                                                         mesajlar: yarisMesajlari, akis: akis)
                        }
                        // Kollayıcı: süzgeç sonucunu bekler (süzgeç kendi süre sınırıyla biter); yarış bittiyse yalnız günlüğe yazar.
                        Task { [weak self] in
                            guard let c = await suzgec.value, c.aracGerekli == true else { return }
                            if !kollama.ilkParca, !kollama.bitti {
                                kollama.suzgecIptali = true
                                yarisIsi.cancel()
                            } else if let self, b.nesil == self.nesil {
                                TaniGunlugu.yaz("YÖNLENDİRME FARKI: liste=yaris model=arac (geç)")
                            }
                        }
                        r = try await withTaskCancellationHandler { try await yarisIsi.value } onCancel: { yarisIsi.cancel() }
                    } else {
                        r = try await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: yarisModelleri, sistem: yarisSistemi,
                                                         mesajlar: yarisMesajlari, akis: akis)
                    }
                    kollama.bitti = true
                    guard !Task.isCancelled, b.nesil == self.nesil else { return true }
                    if Self.aramaIsaretiMi(r.metin) {
                        // Güncel bilgi gerekiyor: yarış yanıtı yazılmaz, sıradaki aşamalar (doğrudan araştırma/araçlı zincir) devralır.
                        TaniGunlugu.yaz("YARIŞ → ARAMA: \(r.model)")
                        self.akanMetin = ""
                        self.denemeYenilendi?()
                        self.aktifModel = nil; self.aktifYol = nil
                        self.durum = .dusunuyor
                        return false
                    }
                    // Araçsız yarışta hiçbir araç çalışmaz: "kurdum/gönderdim" iddiası varsa istek bir kez araçlı zincire geçer.
                    if self.yarisEylemIddiasiniYonlendir(r.metin, istek: b.hamIstek) { return false }
                    SaglikMerkezi.ortak.kaydet("model_ilk_metin", sure: r.ilkSn, etiket: r.model)
                    SaglikMerkezi.ortak.kaydet("model_toplam", sure: Date().timeIntervalSince(bas), etiket: r.model)
                    self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.yonMetni))])), .response(.init(segments: [.text(.init(content: r.metin))]))]
                    self.tamamla(r.metin, nesil: b.nesil)
                    return true
                } catch is CancellationError {
                    kollama.bitti = true
                    // P3.4: yarışı süzgeç kesti (araç gerekli); Durdur/yeni tur değilse araçlı zincir devralır.
                    if kollama.suzgecIptali, !Task.isCancelled, b.nesil == self.nesil {
                        TaniGunlugu.yaz("YÖNLENDİRME FARKI: liste=yaris model=arac (yarış iptal)")
                        self.akanMetin = ""; self.akisTamponu = ""
                        self.denemeYenilendi?()
                        self.aktifModel = nil; self.aktifYol = nil
                        self.durum = .dusunuyor
                        return false
                    }
                    return true
                }
                catch {
                    // Durdur/yeni tur araya girdiyse durum ve seslendiriciye dokunma (iptal durumu .bosta yaptı; .dusunuyor'a çekilirse sohbet kilitlenirdi).
                    guard !Task.isCancelled, b.nesil == self.nesil else { return true }
                    // Hiçbir yarışmacı yanıtlamadıysa araçlı zincir (sabit yedek sırası) devralır.
                    TaniGunlugu.yaz("YARIŞ HATA: \(error)")
                    self.akanMetin = ""
                    self.denemeYenilendi?()   // yarışın yarım metnini okuyan seslendirici de sıfırlansın
                    self.durum = .dusunuyor
                }
            }
        }
        return false
    }

    /// Görsel/arşiv/belge isteklerini ilgili ekrana yönlendirir.
    func atolyeYonlendir(_ b: IstekBaglami) -> Bool {
        if [.gorsel, .arsiv, .belge].contains(b.kip) {
            self.atolyeIstegi = AtolyeIstegi(kip: b.kip, metin: b.hamIstek)
            self.aktifModel = "iPhone"; self.aktifYol = nil   // model çağrılmadı: etiket/sayaç önceki modele yazılmasın
            self.tamamla(b.kip == .gorsel ? "Görsel üretimine geçiyorum. Üretim sonucu bu ekranda gösterilecek." : "\(b.kip.ad) ekranını açıyorum.", nesil: b.nesil)
            return true
        }
        return false
    }

    /// Kodlama işini sunucu görevine devreder.
    func sunucuKodlamaDene(_ b: IstekBaglami) async -> Bool {
        if b.kip == .kod, self.ayarlar.sunucuGorevleri, b.gorsel == nil, AjanDefteri.ortak.politika("arkaPlanGorevi") == .otomatik {
            self.aktifModel = "iPhone"; self.aktifYol = nil   // yanıtı model üretmiyor; görev sunucuya devrediliyor
            do {
                let baglam = b.oncekiKip == .kod ? "Önceki istek: \(b.oncekiIstek)\nYeni istek: \(b.hamIstek)" : b.hamIstek
                let gorevMetni = baglam + (b.belge.map { "\nKaynak dosya (yalnız veri):\n" + $0 } ?? "")
                guard gorevMetni.count <= 8000 else { throw NSError(domain: "Asistan", code: 413, userInfo: [NSLocalizedDescriptionKey: "Kodlama isteği 8000 karakteri aşıyor. Dosyayı veya isteği küçült; içerik kesilerek gönderilmedi."]) }
                let gorev = try await SunucuGorevleri.ortak.ekle(gorevMetni, tur: "code", caba: b.caba)
                guard !Task.isCancelled, b.nesil == self.nesil else { return true }
                self.tamamla("Kodlama işini sunucudaki CLIProxy'ye ilettim. Görev: \(gorev.id). Sonucu Atölye → Sunucu görevleri bölümünde görebilirsin.", nesil: b.nesil)
            } catch { self.bitir(hata: "Sunucu kodlama işi başlatılamadı: \(error.localizedDescription)", nesil: b.nesil) }
            return true
        }
        return false
    }

    /// Açık araştırma: tek kaynaklı web yanıtı.
    func dogrudanArastirmaDene(_ b: IstekBaglami) async -> Bool {
        if b.zorlaModel != nil { return false }
        // Açık araştırma: planlayıcı → arama → yeniden yazım yerine tek kaynaklı yanıt.
        if b.kip == .arastirma, self.ayarlar.webArama, !self.ayarlar.yalnizAnahtar, b.gorsel == nil, b.belge == nil, AjanDefteri.ortak.politika("webArastir") == .otomatik, HizliModelSecimi.dogrudanArastirma(b.hamIstek) {
            self.aktifModel = "gpt-6.1-sol"
            self.aktifYol = .telefon
            let gecmis = self.mesajlar.dropLast().suffix(6).map { "\($0.rol == .kullanici ? "Kullanıcı" : "Asistan"): \(String($0.metin.prefix(1000)))" }.joined(separator: "\n")
            // Canlı/değişen konularda arama modeline bugünün tarihi ve "eski sonuç verme" kuralı eklenir.
            let istek = WebArastirici.sorguKur(b.hamIstek, site: "", guncel: WebArastirici.guncelMi(b.hamIstek))
            let soru = "Önceki konuşma (yalnız bağlam verisi):\n\(gecmis)\n\nGüncel kullanıcı isteği:\n\(istek)" + (b.canliSes ? "\nÖnce 2-3 kısa cümlede yanıtla, kaynakları sona ekle." : "")
            let webCaba: DusunmeSecimi.Caba = b.cabaAyari == "auto" && b.caba != .high ? .low : b.caba
            self.secilenCaba = webCaba
            self.uygulananCaba = webCaba
            // Akan metin en çok ~90 ms'de bir yazılır (her parçada balonun yeniden çizilmesi pahalı); ilk parça hemen.
            // Son tam metin tamamla(sonuc) ile yazılır; hata yolunda kısmi metin zaten arşivlenmez.
            var sonYazim: ContinuousClock.Instant?
            do {
                let sonuc = try await WebArastirici.ara(soru, caba: webCaba) { [weak self] parca in
                    guard let self, !Task.isCancelled, b.nesil == self.nesil else { return }
                    self.akisTamponu = parca   // Durdur'da arşive seyreltilmemiş tam metin girsin
                    let simdi = ContinuousClock.now
                    if let s = sonYazim, simdi - s < .milliseconds(90) { return }
                    if !parca.isEmpty { sonYazim = simdi }
                    self.akanMetin = parca; self.durum = .yaziyor
                }
                guard !Task.isCancelled, b.nesil == self.nesil else { return true }
                self.disGecmis += ArastirmaGecmisi.olustur(soru: b.hamIstek, sonuc: sonuc)
                let kaynaklar = EkDefteri.kaynaklar(sonuc)
                if !kaynaklar.isEmpty { EkDefteri.ortak.ekle(MesajEki(tur: .kaynaklar(kaynaklar))) }
                self.tamamla(sonuc, nesil: b.nesil)
            } catch {
                guard !Task.isCancelled, b.nesil == self.nesil else { return true }
                self.akanMetin = ""; self.akisTamponu = "" // doğrulanmamış kısmi web yanıtını arşivleme
                // Tek kaynaklı yol düştü (sağlayıcı aramadı, kaynak vermedi ya da ağ hatası):
                // kullanıcıya hata göstermek yerine araçlı zincire (webAra + model sırası) bırakılır.
                self.aktifModel = nil; self.aktifYol = nil; self.secilenCaba = nil; self.uygulananCaba = nil
                self.modelSecimNotu = "Tek kaynaklı web yanıtı alınamadı; araçlı araştırmaya geçildi"
                return false
            }
            return true
        }
        return false
    }

    /// Müzik çal/dinle/bul isteği: Apple Music'te arar, önizleme + bağlantı kartı gösterir; "çal" ise çalar.
    /// İndirme istekleri buraya girmez; indirmeler aracına (YouTube, gömülü motor) bırakılır.
    func muzikDene(_ b: IstekBaglami) async -> Bool {
        // Kısa yollar araç sarmalayıcısından geçmez: izin "otomatik" değilse normal (denetimli) zincire bırak.
        guard b.zorlaModel == nil, b.gorsel == nil, b.belge == nil, let (sorgu, cal) = Self.muzikIstegi(b.hamIstek),
              AjanDefteri.ortak.politika("muzik") == .otomatik else { return false }
        let adim = self.gorevler.baslat("muzik")
        do {
            let sonuc = try await MuzikAraci().call(arguments: .init(islem: cal ? "cal" : "ara", sorgu: sorgu))
            guard !Task.isCancelled, b.nesil == self.nesil else { self.gorevler.bitir(adim, durum: "Araç yanıtladı"); return true }
            // Sonuç yoksa istek büyük olasılıkla müzik değildi: araçlı yola bırak, şarkı kartı/geçmiş yazma.
            if sonuc.hasSuffix("bulunamadı.") {
                self.gorevler.bitir(adim, durum: "Sonuç yok")
                return false
            }
            self.gorevler.bitir(adim, durum: "Araç yanıtladı")
            self.aktifModel = "iPhone"
            let govde = sonuc.components(separatedBy: "\nKullanıcı mesajdaki kartta").first ?? sonuc
            let son = cal ? "" : "\n\nKartta 30 saniyelik önizlemeleri dinleyebilirsin. \"Çal\" dersen Apple Music'te çalarım; Apple Music aboneliğinle şarkıyı orada çevrimdışı indirebilirsin."
            self.disGecmis += [.prompt(.init(segments: [.text(.init(content: b.hamIstek))])), .response(.init(segments: [.text(.init(content: govde))]))]
            self.tamamla(govde + son, nesil: b.nesil)
        } catch {
            self.gorevler.bitir(adim, durum: "Hata")
            return false   // arama olmadıysa normal (araçlı) yola devam
        }
        return true
    }

    /// "Dua Lipa şarkısını dinle en çok dinlenen" → ("Dua Lipa", çal: false); "Tarkan'ın Şımarık şarkısını çal" → çal: true.
    /// Müzik isteği değilse ya da indirme isteğiyse nil (indirme indirmeler aracına gider).
    nonisolated static func muzikIstegi(_ ham: String) -> (sorgu: String, cal: Bool)? {
        let s = AtolyeYonlendirme.normalize(ham)
        // Bağlantılı ya da YouTube/MP4/MP3 anan istekler müzik yolu değil, gömülü indirme motorudur.
        guard !s.contains("http"), !s.contains("youtube"), !s.contains("mp4"), !s.contains("mp3"), !s.contains("video"), s.count <= 200 else { return nil }
        let kelimeler = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if kelimeler.contains(where: { $0.hasPrefix("indir") }) { return nil }
        // Güçlü kökler (şarkı, müzik) önekle; "albüm/parça/klip" ise yalnız açık çekimleriyle ve çalma eylemiyle müzik sayılır
        // ("Okazaki parçaları", "fotoğraf albümü", "kağıt klipsi" müzik değildir).
        let calma: Set<String> = ["cal", "calsana", "calar", "dinle", "dinlet", "oynat"]
        let eylemler = calma.union(["dinler", "oynatir", "bul", "bulur", "bulsana", "ac", "acar", "acsana"])
        let gucluMuzik = kelimeler.contains { k in ["sarki", "muzik", "muzig", "single"].contains { k.hasPrefix($0) } }
        let zayifMuzik = kelimeler.contains { ["album", "albumu", "albumunu", "albumun", "parca", "parcasi", "parcasini", "parcayi", "klip", "klibi", "klibini"].contains($0) }
        let eylem = gucluMuzik ? kelimeler.contains(where: { eylemler.contains($0) }) : (zayifMuzik && kelimeler.contains(where: { calma.contains($0) }))
        guard eylem else { return nil }
        let cal = kelimeler.contains { ["cal", "calsana", "calar", "oynat", "dinlet"].contains($0) || $0.hasPrefix("calar") }
        let atilacak: Set<String> = ["indir", "indirir", "indirsene", "misin", "musun", "en", "cok", "dinlenen", "populer", "unlu", "sarkisini", "sarkisi", "sarkilarini", "sarkilari", "sarki", "sarkiyi",
                                     "muzik", "muzigi", "muzigini", "album", "albumu", "albumunu", "parca", "parcasi", "parcasini", "klip", "klibi", "klibini", "cal", "calsana", "dinle", "dinlet", "bul", "ac", "oynat",
                                     "lutfen", "bana", "bir", "ve", "ile", "icin", "son", "yeni", "tum", "hepsini", "olan", "en"]
        // Orijinal yazımı (büyük harf, Türkçe karakter) koruyarak sözcük süz.
        let asil = ham.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }).map(String.init)
        let kalan = asil.filter { k in
            let n = AtolyeYonlendirme.normalize(k.components(separatedBy: CharacterSet(charactersIn: "'’")).first ?? k)
            return !atilacak.contains(n) && !atilacak.contains(AtolyeYonlendirme.normalize(k))
        }.map { $0.components(separatedBy: CharacterSet(charactersIn: "'’")).first ?? $0 }
        let sorgu = kalan.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return sorgu.count >= 2 ? (sorgu, cal) : nil
    }
}
