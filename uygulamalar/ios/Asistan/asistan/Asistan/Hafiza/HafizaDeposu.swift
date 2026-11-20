import Foundation
import SwiftData

/// SwiftData üstünde ince katman. Ana aktörde çalışır; araçlar `await` ile gelir.
@MainActor
final class HafizaDeposu {
    let baglam: ModelContext

    init(baglam: ModelContext) { self.baglam = baglam }

    /// Paylaşılan kabın nasıl açıldığı; `.normal` değilse sohbet ekranının üstünde şerit görünür (`HafizaAcilisSeridi`).
    nonisolated enum AcilisDurumu: Equatable, Sendable {
        case normal
        /// Bozuk depo `Kurtarma/<klasor>/`'e taşındı, boş depo açıldı.
        case kurtarildi(klasor: String)
        /// Kap bellekte açıldı: bu oturumun konuşmaları kaydedilmez; disk dosyaları korunuyor.
        case bellekte(hata: String)
        /// Bekleyen geri yükleme bu açılışta uygulandı.
        case geriYuklendi
    }

    /// Paylaşılan kabın açılış durumu (açılışta bir kez belirlenir).
    static private(set) var acilisDurumu: AcilisDurumu = .normal
    /// Diskteki asıl deponun yolu (kap bellekte açılmak zorunda kalsa da bu yol; yedek/geri yükleme buna göre çalışır).
    /// Test ortamında (ASISTAN_TEST) nil: diske dokunulmaz. Yol `ModelConfiguration("Asistan").url`'den türer
    /// (App Group kabı otomatik seçimiyle aynı yer); Kurtarma/ ve Yedekler/ bunun yanında açılır.
    static private(set) var depoURL: URL?

    /// Uygulama ve arka plan niyetleri (Siri) aynı kabı paylaşır; aynı depoya iki ayrı kap açılmaz.
    static let paylasilanKap: ModelContainer = {
        guard ProcessInfo.processInfo.environment["ASISTAN_TEST"] != "1" else { return bellekKabi() }
        let ayar = varsayilanAyar()
        depoURL = ayar.url
        let sonuc = kapAc(ayar: ayar)
        acilisDurumu = sonuc.durum
        if sonuc.durum != .normal { TaniGunlugu.yaz("HAFIZA AÇILIŞI: \(sonuc.durum)") }
        return sonuc.kap
    }()

    /// Güncel sürümlü şema (bkz. `SemaSurumleri.swift`).
    static func guncelSema() -> Schema { Schema(versionedSchema: AsistanSemaV3.self) }

    /// Bugünkü depoyla birebir aynı yol: ad "Asistan", varsayılan grup kabı seçimi.
    static func varsayilanAyar() -> ModelConfiguration { ModelConfiguration("Asistan", schema: guncelSema(), isStoredInMemoryOnly: false) }

    /// Verilen klasördeki `Asistan.store` (testler, geçici klasörler).
    static func diskAyari(klasor: URL) -> ModelConfiguration { ModelConfiguration("Asistan", schema: guncelSema(), url: klasor.appending(path: "Asistan.store")) }

    /// Bellek içi kap. Yalnız şema tanımı bozuksa açılmaz (programlama hatası; ilk birim testinde görünür).
    static func bellekKabi() -> ModelContainer {
        let sema = guncelSema()
        let ayar = ModelConfiguration("bellek-\(UUID().uuidString)", schema: sema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: sema, configurations: [ayar])
    }

    /// Bellekte ya da test ortamında (klasor nil iken) bellek içi kap; aksi hâlde disk kabı (kurtarmalı, çökmez).
    static func kapOlustur(bellekte: Bool = false, klasor: URL? = nil) -> ModelContainer {
        let test = ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1"
        if bellekte || (test && klasor == nil) { return bellekKabi() }
        return kapAc(ayar: klasor.map { diskAyari(klasor: $0) } ?? varsayilanAyar()).kap
    }

    typealias Kurucu = (Schema, ModelConfiguration) throws -> ModelContainer

    /// Sınanabilir çekirdek. Sıra: bekleyen geri yükleme → sürümlü kap → açılmazsa tanı:
    /// `.erisilemez` (telefon kilitli vb.) dosyalara dokunmaz, kap bellekte; `.bozuk` depo Kurtarma'ya taşınır, boş depo
    /// denenir; `.semaUyumsuz`/`.bilinmeyen` dosyalar Kurtarma'ya KOPYALANIR, kap bellekte. Hiçbir yolda `fatalError` yok.
    static func kapAc(ayar: ModelConfiguration, kurucu: Kurucu? = nil,
                      tani: ((URL, any Error) -> HafizaKurtarma.Tani)? = nil) -> (kap: ModelContainer, durum: AcilisDurumu) {
        let sema = ayar.schema ?? guncelSema()
        let store = ayar.url
        let kur: Kurucu = kurucu ?? { try ModelContainer(for: $0, migrationPlan: AsistanGocPlani.self, configurations: [$1]) }
        let geriYuklendi = HafizaKurtarma.bekleyenGeriYuklemeyiUygula(store: store)
        // P3.9: arama indeksi artımlı senkronlanır; geri yüklenen eski depo için bir kez tam tarama istenir.
        if geriYuklendi { UserDefaults.standard.set(true, forKey: HafizaDeposu.indeksTamTaramaAnahtari) }
        do { return (try kur(sema, ayar), geriYuklendi ? .geriYuklendi : .normal) }
        catch {
            let teshis = tani?(store, error) ?? HafizaKurtarma.tani(store: store, hata: error)
            let n = error as NSError
            TaniGunlugu.yaz("HAFIZA AÇILAMADI: \(teshis.rawValue) · \(n.domain) \(n.code)")
            switch teshis {
            case .erisilemez:
                return (bellekKabi(), .bellekte(hata: "Telefon kilidi açılınca yeniden aç"))
            case .bozuk:
                guard let klasor = try? HafizaKurtarma.karantinaya(store, neden: "bozuk") else {
                    return (bellekKabi(), .bellekte(hata: "Bozuk hafıza kenara alınamadı"))
                }
                if let kap = try? kur(sema, ayar) {
                    UserDefaults.standard.set(true, forKey: HafizaDeposu.indeksTamTaramaAnahtari)   // P3.9: eski depo kayıtları indeksten düşsün
                    return (kap, .kurtarildi(klasor: klasor.lastPathComponent))
                }
                return (bellekKabi(), .bellekte(hata: "Yeni hafıza da açılamadı"))
            case .semaUyumsuz:
                HafizaKurtarma.kopyalaGerekirse(store, neden: "sema-uyumsuz")
                return (bellekKabi(), .bellekte(hata: "Hafıza şeması açılamadı; veriler korunuyor"))
            case .bilinmeyen:
                HafizaKurtarma.kopyalaGerekirse(store, neden: "bilinmeyen")
                return (bellekKabi(), .bellekte(hata: "Hafıza açılamadı; veriler korunuyor"))
            }
        }
    }

    /// Günlük yedeği arka planda alır (günde bir; kap bellekte açıldıysa ya da test ortamında çalışmaz).
    static func gunlukYedegiBaslat() {
        guard let depo = depoURL else { return }
        if case .bellekte = acilisDurumu { return }
        Task.detached(priority: .utility) { HafizaKurtarma.gunlukYedek(store: depo, klasor: HafizaKurtarma.yedekKlasoru(depo)) }
    }

    // MARK: Olgular
    func olgular() -> [Olgu] {
        let tanim = FetchDescriptor<Olgu>(sortBy: [SortDescriptor(\.olusturma)])
        return (try? baglam.fetch(tanim)) ?? []
    }

    @discardableResult
    func hatirla(_ metin: String, kaynak: String = "kullanici") -> Olgu? {
        let temiz = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !temiz.isEmpty, temiz.count <= 300 else { return nil }
        if let ayni = olgular().first(where: { $0.metin.compare(temiz, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return ayni
        }
        // Gömleme (vekildeki bge-m3) ana iş parçacığını bekletmez: anlamsal hafıza açıksa arka planda doldurulur.
        let o = Olgu(metin: temiz, kaynak: kaynak)
        baglam.insert(o)
        do { try baglam.save() } catch { baglam.delete(o); return nil }  // "Hatırlandı" deyip kaybetme
        HafizaIndeksi.ortak.ekle(tur: .olgu, kimlik: o.kimlik.uuidString, zaman: o.olusturma, metin: o.metin)
        vektorDoldurArkada([o.kimlik])
        return o
    }

    /// Etkin olguların en yenileri. Cihaz içi NL gömmesi ayırt edici olmadığı için (19 Eki ölçümü) kosinüs yolu kapalıdır;
    /// anlamsal sıralama `geriCagirMelez` (bge-m3) ile yapılır. `esik` geriye uyum için durur.
    func ilgili(_ sorgu: String, k: Int = 8, esik: Float = 0.45) -> [Olgu] {
        Array(etkinOlgular().suffix(k))
    }

    /// Gömmesi olmayan (ya da eski 512 boyutlu NL gömmesi taşıyan) olguları 32'lik toplu isteklerle tamamlar; anlamsal hafıza
    /// kapalıysa hiçbir şey yapmaz, ilk hatada sessizce durur.
    func vektorleriTamamla() async {
        guard UzakGomlemci.etkin else { return }
        let eksik = olgular().filter { UzakGomlemci.gecerli($0.vektor) == nil }.map(\.kimlik)
        var i = 0
        while i < eksik.count {
            let parca = Array(eksik[i..<min(eksik.count, i + UzakGomlemci.enFazlaMetin)])
            guard await vektorDoldur(parca) else { return }
            i += parca.count
        }
    }

    /// 'unut' sonucu. Birden çok olgu eşleşirse hiçbiri silinmez; adaylar listelenir (hangisi olduğu sorulur).
    nonisolated enum UnutSonucu: Equatable, Sendable {
        case silindi(String)
        case cokEslesme([String])
        case sabitKorundu
        case kaydedilemedi
        case yok
    }

    /// Tek olguyu unutur: önce tam metin eşleşmesi, yoksa parça (en az 3 karakter) eşleşmesi. Sabitlenmiş olgu silinmez;
    /// parça birden çok olguya uyuyorsa hiçbir şey silinmez ("Kullanıcı" ya da tek harf bütün hafızayı götürmez).
    func unutTekil(_ parca: String) -> UnutSonucu {
        let p = parca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.count >= 3 else { return .yok }
        let secenek: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let hepsi = olgular()
        let birebir = hepsi.filter { $0.metin.compare(p, options: secenek) == .orderedSame }
        let eslesen = birebir.isEmpty ? hepsi.filter { $0.metin.range(of: p, options: secenek) != nil } : birebir
        let silinebilir = eslesen.filter { $0.sabit != true }
        if silinebilir.isEmpty { return eslesen.isEmpty ? .yok : .sabitKorundu }
        guard silinebilir.count == 1, let o = silinebilir.first else { return .cokEslesme(silinebilir.map(\.metin)) }
        let metin = o.metin
        return olguSil(o.kimlik) ? .silindi(metin) : .kaydedilemedi
    }

    /// Yalnız tek olgu eşleşirse onu siler (bkz. `unutTekil`); silinen sayısını (0/1) döndürür.
    func unut(iceren parca: String) -> Int {
        if case .silindi = unutTekil(parca) { return 1 }
        return 0
    }

    /// Kimliğe göre tek olguyu siler.
    @discardableResult
    func olguSil(_ kimlik: UUID) -> Bool {
        guard let o = olgular().first(where: { $0.kimlik == kimlik }) else { return false }
        HafizaIndeksi.ortak.sil(kimlik: kimlik.uuidString)
        baglam.delete(o)
        return (try? baglam.save()) != nil
    }

    /// Olgu metnini düzenler (en çok 300 karakter, boş olamaz); anlamsal vektör yenilenir. Başarı: true.
    @discardableResult
    func olguDuzenle(_ kimlik: UUID, metin: String) -> Bool {
        let temiz = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !temiz.isEmpty, temiz.count <= 300, let o = olgular().first(where: { $0.kimlik == kimlik }) else { return false }
        o.metin = temiz
        HafizaIndeksi.ortak.ekle(tur: .olgu, kimlik: o.kimlik.uuidString, zaman: o.olusturma, metin: temiz)
        // Metin değişti: eski vektör geçersiz; anlamsal hafıza açıksa arka planda yeniden gömülür.
        o.vektor = nil
        let tamam = (try? baglam.save()) != nil
        if tamam { vektorDoldurArkada([o.kimlik]) }
        return tamam
    }

    /// Tüm olguları siler; silinen sayısını döndürür.
    @discardableResult
    func olgulariTemizle() -> Int {
        let hepsi = olgular()
        hepsi.forEach { baglam.delete($0) }
        try? baglam.save()
        HafizaIndeksi.ortak.temizle(tur: .olgu)
        return hepsi.count
    }

    // MARK: Sohbet yönetimi (çekmece)

    func sohbetSil(_ s: Sohbet) {
        let kimlik = s.kimlik
        HafizaIndeksi.ortak.sohbetiSil(kimlik.uuidString); baglam.delete(s); try? baglam.save()
        AsistanSpotlight.sohbetSilindi(kimlik)   // P4.4 (testte yazmaz)
    }

    func tumSohbetler() -> [Sohbet] {
        (try? baglam.fetch(FetchDescriptor<Sohbet>(sortBy: [SortDescriptor(\.olusturma, order: .reverse)]))) ?? []
    }

    @discardableResult
    func sohbetleriSil(_ sohbetler: [Sohbet]) -> Int {
        var tekil: [UUID: Sohbet] = [:]
        for sohbet in sohbetler { tekil[sohbet.kimlik] = sohbet }
        let secilen = Array(tekil.values)
        guard !secilen.isEmpty else { return 0 }
        for sohbet in secilen { baglam.delete(sohbet) }
        do { try baglam.save() }
        catch { baglam.rollback(); return 0 }
        let kimlikler = secilen.map(\.kimlik)
        HafizaIndeksi.ortak.sohbetleriSil(kimlikler.map(\.uuidString))
        AsistanSpotlight.sohbetlerSilindi(kimlikler)
        return secilen.count
    }

    /// Başlığı düzenler (boş olamaz, en çok 80 karakter).
    @discardableResult
    func sohbetAdlandir(_ s: Sohbet, _ baslik: String) -> Bool {
        let t = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        s.baslik = String(t.prefix(80))
        guard (try? baglam.save()) != nil else { return false }
        AsistanSpotlight.sohbetDegisti(s)   // P4.4
        return true
    }

    func sohbetSabitle(_ s: Sohbet, _ sabit: Bool) { s.sabit = sabit; try? baglam.save() }

    /// Sohbetin son mesaj zamanı (mesaj yoksa oluşturma zamanı).
    nonisolated static func sonZaman(_ s: Sohbet) -> Date { s.mesajlar.map(\.zaman).max() ?? s.olusturma }

    // MARK: Sohbet
    func sohbetOlustur() -> Sohbet {
        let s = Sohbet(); baglam.insert(s); try? baglam.save()
        AsistanSpotlight.sohbetDegisti(s)   // P4.4: boş "Yeni sohbet" yazılmaz; başlık ilk mesajda konunca `ekle` yazar.
        return s
    }

    /// Kaydedilen mesajı döndürür (P3.5: denetim notu sonradan `kontrolYaz` ile bu kimliğe yazılır).
    @discardableResult
    func ekle(_ rol: Mesaj.Rol, _ metin: String, sohbet: Sohbet, ekler: [MesajEki] = [], gorselAdlari: [String] = []) -> Mesaj {
        let m = Mesaj(rol: rol, metin: metin, sohbet: sohbet)
        m.ekVerisi = EkKalici.kodla(ekler, gorselAdlari: gorselAdlari)
        baglam.insert(m)
        // Mesaj gömmesi (bge-m3) arka planda; ana iş parçacığında eşzamanlı gömme yapılmaz.
        if rol != .arac, metin.count >= Self.anlamsalEnKisa, UzakGomlemci.etkin {
            let cift = (m.kimlik, String(metin.prefix(UzakGomlemci.enFazlaKarakter)))
            Task.detached(priority: .utility) { await Self.mesajlariGom([cift]) }
        }
        // Mesaj kimliği her zaman taze UUID: önceki kaydı silme taraması gereksiz.
        if rol != .arac { HafizaIndeksi.ortak.ekle(tur: .mesaj, kimlik: m.kimlik.uuidString, sohbet: sohbet.kimlik.uuidString, zaman: m.zaman, metin: metin, yeni: true) }
        var baslikKondu = false
        if sohbet.baslik == "Yeni sohbet", rol == .kullanici {
            sohbet.baslik = String(metin.prefix(40))
            baslikKondu = true
        }
        try? baglam.save()
        // P4.4: başlık ilk kullanıcı mesajıyla konunca sohbet Spotlight'a yazılır (her mesajda değil).
        if baslikKondu { AsistanSpotlight.sohbetDegisti(sohbet, ilkMesaj: metin) }
        return m
    }

    /// P3.5: mesajın denetim notunu kalıcı yazar (sohbet yeniden açılınca not görünür). Mesaj yoksa sessizce geçer.
    func kontrolYaz(_ kimlik: UUID, _ not: String) {
        var tanim = FetchDescriptor<Mesaj>(predicate: #Predicate { $0.kimlik == kimlik })
        tanim.fetchLimit = 1
        guard let m = (try? baglam.fetch(tanim))?.first else { return }
        m.kontrol = not
        try? baglam.save()
    }

    func sonSohbetler(_ sayi: Int = 20) -> [Sohbet] {
        var t = FetchDescriptor<Sohbet>(sortBy: [SortDescriptor(\.olusturma, order: .reverse)])
        t.fetchLimit = sayi
        return (try? baglam.fetch(t)) ?? []
    }

    /// P3.9: sohbetin araç dışı mesajları, zamana göre artan. `once` verilirse yalnız ondan eskiler; `sinir` verilirse
    /// en yeni `sinir` tanesi (sayfalı sohbet açılışı: bütün `Sohbet.mesajlar` ilişkisi çözülmez).
    func sohbetMesajlari(_ kimlik: UUID, once: Date? = nil, sinir: Int? = nil) -> [Mesaj] {
        let arac = Mesaj.Rol.arac.rawValue
        let esik = once ?? .distantFuture
        var t = FetchDescriptor<Mesaj>(predicate: #Predicate { $0.sohbet?.kimlik == kimlik && $0.rolHam != arac && $0.zaman < esik },
                                       sortBy: [SortDescriptor(\.zaman, order: .reverse)])
        if let sinir { t.fetchLimit = sinir }
        return ((try? baglam.fetch(t)) ?? []).reversed()
    }

    /// P3.9: 'Sohbeti paylaş' metni bütün sohbetten kurulur (sayfalı açılışta yalnız yüklü 60 mesaj değil).
    func sohbetMetni(_ s: Sohbet, gorunenAd: String) -> String {
        sohbetMesajlari(s.kimlik).map { ($0.rol == .kullanici ? "Sen" : gorunenAd) + ":\n" + $0.metin }.joined(separator: "\n\n")
    }
}
