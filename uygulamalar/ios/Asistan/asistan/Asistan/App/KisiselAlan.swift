import Foundation
import Observation
import UIKit

nonisolated struct HazirKomut: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var baslik: String
    var metin: String
    var simge: String = "sparkles"
    static let ornekler = [
        Self(baslik: "Günümü planla", metin: "Bugün yapacaklarımı birlikte önceliklendirelim. Önce bana hangi işleri bitirmem gerektiğini sor.", simge: "calendar"),
        Self(baslik: "Kısa özet", metin: "Aşağıdaki metni ana fikirleri koruyarak kısa maddelerle özetle:\n", simge: "text.alignleft"),
        Self(baslik: "Kod incele", metin: "Aşağıdaki kodu hata ve güvenlik sorunları açısından incele; düzeltmeleri ve test önerilerini açıkla:\n", simge: "chevron.left.forwardslash.chevron.right"),
        Self(baslik: "Birlikte öğren", metin: "Bir konuyu öğrenmeme yardım et. Önce konuyu ve seviyemi sor, sonra kısa açıklama ve bir alıştırmayla ilerle.", simge: "book"),
        Self(baslik: "Mesaj taslağı", metin: "Bir mesaj taslağı hazırlayalım. Kime, hangi konuda ve nasıl bir üslupla yazacağımı sor.", simge: "text.bubble"),
        Self(baslik: "Fikir üret", metin: "Bir fikir üzerinde çalışalım. Önce hedefimi ve kısıtlarımı sor, sonra üç uygulanabilir seçenek öner.", simge: "lightbulb")
    ]
    /// Kaldırılan öğretmen şablonları (29 Ekim 2026: okul/öğretmen özellikleri silindi). Eski kurulumlara bir kez eklenmişlerdi;
    /// yalnız temizlik göçü (`KisiselAlan.ogretmenTemizlikAnahtari`) birebir aynı kalanları silmek için tutulur.
    static let kaldirilanOgretmenSablonlari = [
        Self(baslik: "Ders planı hazırla", metin: "'ders-plani' becerisiyle Maarif Modeli'ne uygun bir ders planı hazırla. Önce sınıfı, üniteyi/konuyu ve ders saatini sor; kazanım kodlarını müfredat aracından al.", simge: "list.bullet.clipboard"),
        Self(baslik: "Sınav hazırla", metin: "'sinav-hazirla' becerisiyle bir sınav hazırla. Önce sınıfı, konuları, soru sayısını ve türünü sor; kapsam tablosu ve cevap anahtarını da ver.", simge: "doc.text"),
        Self(baslik: "Yoklama al", metin: "'yoklama' becerisiyle yoklama alalım. Önce hangi sınıf ve ders saati olduğunu sor.", simge: "checklist"),
        Self(baslik: "Veliye mesaj", metin: "'veli-mesaji' becerisiyle veliye kısa ve nazik bir mesaj taslağı hazırla. Önce öğrenciyi, konuyu ve üslubu sor; göndermeden önce taslağı bana göster.", simge: "envelope"),
        Self(baslik: "Resmî yazı", metin: "'resmi-yazi' becerisiyle Resmî Yazışma Yönetmeliği düzeninde bir resmî yazı taslağı (DOCX) hazırla. Önce muhatabı, konuyu ve ilgiyi sor; okul ve imza bilgisini öğretmen profilimden al.", simge: "doc.richtext"),
        Self(baslik: "Tutanak yaz", metin: "'tutanak' becerisiyle zümre ya da şube öğretmenler kurulu tutanağı hazırla. Önce toplantı türünü, tarihini, yerini, katılanları ve gündemi sor.", simge: "person.3")
    ]
    /// Yeni kurulumun hazır komutları.
    static var varsayilanlar: [HazirKomut] { ornekler }

    /// Saf göç: kullanıcının hiç değiştirmediği (başlığı ve metni birebir aynı) eski öğretmen şablonlarını çıkarır;
    /// düzenlenmiş komut ve kullanıcının kendi komutları kalır.
    static func ogretmenSablonlariniTemizle(_ komutlar: [HazirKomut]) -> [HazirKomut] {
        komutlar.filter { k in !kaldirilanOgretmenSablonlari.contains { $0.baslik == k.baslik && $0.metin == k.metin } }
    }
}
nonisolated struct KayitliYanit: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var metin: String
    var tarih = Date()
    var baslik: String { String(metin.prefix(80)).replacingOccurrences(of: "\n", with: " ") }
}

/// Sohbet veritabanından ayrı; yalnız kullanıcının seçtiği komut ve yanıtlar telefonda saklanır.
@MainActor @Observable final class KisiselAlan {
    nonisolated struct Icerik: Codable, Equatable { var komutlar = HazirKomut.ornekler; var yanitlar: [KayitliYanit] = [] }
    nonisolated struct Yedek: Codable, Equatable {
        let surum: Int
        let icerik: Icerik
        init(icerik: Icerik) { surum = 1; self.icerik = icerik }
    }
    /// Yedeğin dışa ve içe aktarımda ortak boyut sınırı (200 × 64.000 karakterlik Türkçe yanıt ≈ 14 MB; 4 baytlık
    /// karakterlerle ≈ 51 MB). Uygulama geri yükleyemeyeceği bir yedek üretmez.
    nonisolated static let azamiYedekBayti = 64 << 20
    nonisolated static func yedekBoyutuUygun(_ bayt: Int) -> Bool { bayt <= azamiYedekBayti }
    nonisolated struct YedekHatasi: LocalizedError { let errorDescription: String? }

    private(set) var icerik = Icerik()
    private(set) var hata: String?
    /// Son geri yüklemeden önceki içerik; diskteki `<ad>.onceki.json`dan açılışta yüklenir, geri alınınca silinir.
    private(set) var oncekiIcerik: Icerik?
    private let dosya: URL
    private var okunamadi = false
    /// Okuma, telefon kilitliyken (veri koruması) başarısız olduysa true: kilit açılınca yeniden denenir.
    private var kilitYuzunden = false
    var oncekiDosya: URL { dosya.deletingLastPathComponent().appending(path: dosya.deletingPathExtension().lastPathComponent + ".onceki.json") }
    /// Eski öğretmen şablonlarının tek seferlik temizliği: kayıt başarılıysa anahtar yazılır.
    nonisolated static let ogretmenTemizlikAnahtari = "kisiselAlan.ogretmenKomutlariTemizlendi.v1"
    /// Göçün işaret deposu: uygulamanın kendi dosyasında `.standard`; önizleme/sahte/test dosyalarında yalnız açıkça verilirse.
    private let gocAyarlari: UserDefaults?
    init(dosya: URL? = nil, gocAyarlari: UserDefaults? = nil) {
        self.dosya = dosya ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "kisisel-alan-v1.json")
        self.gocAyarlari = gocAyarlari ?? (dosya == nil ? UserDefaults.standard : nil)
        oku()
        ogretmenTemizligi()
        oncekiyiOku()
        // Arka planda (kilitliyken) açılan süreç bütün oturum boyunca "okunamadı" kipinde kalmasın.
        if kilitYuzunden {
            _ = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.yenidenDene() }
            }
        }
    }
    private func oku() {
        guard FileManager.default.fileExists(atPath: dosya.path) else { return }
        do {
            icerik = try JSONDecoder().decode(Icerik.self, from: Data(contentsOf: dosya))
            okunamadi = false; kilitYuzunden = false; hata = nil
            // Eski (kilitliyken okunamayan sınıftaki) dosya bir sonraki yazımı beklemeden taşınır.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: dosya.path)
        } catch {
            okunamadi = true
            if Self.kilitHatasi(error) {
                kilitYuzunden = true; hata = "Kişisel alan telefonun kilidi açılınca yüklenecek."
            } else {
                kilitYuzunden = false; hata = "Kişisel alan okunamadı. Mevcut dosya korunuyor; değişiklik kaydedilmeyecek."
            }
        }
    }
    /// Önceki süreçte yapılan geri yüklemenin geri alınabilmesi için `oncekiDosya`yı okur. Ana alan okunamıyorsa
    /// (bozuk/kilitli) geri alma sunulmaz; önceki dosyası çözülemezse `oncekiIcerik` nil kalır, dosya SİLİNMEZ.
    private func oncekiyiOku() {
        guard !okunamadi, FileManager.default.fileExists(atPath: oncekiDosya.path) else { return }
        oncekiIcerik = try? JSONDecoder().decode(Icerik.self, from: Data(contentsOf: oncekiDosya))
    }
    /// Kilit yüzünden okunamadıysa yeniden okur (bozuk dosyada kalıcı koruma sürer).
    func yenidenDene() {
        guard kilitYuzunden else { return }
        oku()
        // Kilitliyken açılan süreçte de son geri yükleme geri alınabilir görünsün; göç da kilit açılınca yapılır.
        if !okunamadi { ogretmenTemizligi(); oncekiyiOku() }
    }
    /// Eski öğretmen şablonlarını bir kez temizler. Okunamayan (kilitli/bozuk) dosyada hiçbir şey yazılmaz ve anahtar
    /// yazılmaz (sonra yeniden denenir); kayıt başarısızsa da anahtar yazılmaz, eski hata metni korunur.
    private func ogretmenTemizligi() {
        guard !okunamadi, let d = gocAyarlari, d.object(forKey: Self.ogretmenTemizlikAnahtari) == nil else { return }
        let komutlar = HazirKomut.ogretmenSablonlariniTemizle(icerik.komutlar)
        guard komutlar != icerik.komutlar else { d.set(true, forKey: Self.ogretmenTemizlikAnahtari); return }
        var yeni = icerik
        yeni.komutlar = komutlar
        let eskiHata = hata
        if kaydet(yeni) { d.set(true, forKey: Self.ogretmenTemizlikAnahtari) } else { hata = eskiHata }
    }
    /// Veri korumasından gelen izin hatası mı (bozuk JSON değil)?
    nonisolated static func kilitHatasi(_ e: any Error) -> Bool {
        let n = e as NSError
        if n.domain == NSCocoaErrorDomain, n.code == NSFileReadNoPermissionError { return true }
        if n.domain == NSPOSIXErrorDomain, n.code == Int(EPERM) || n.code == Int(EACCES) { return true }
        if let alt = n.userInfo[NSUnderlyingErrorKey] as? NSError { return kilitHatasi(alt) }
        return false
    }
    @discardableResult private func kaydet(_ yeni: Icerik) -> Bool {
        guard !okunamadi else { return false }
        do {
            try JSONEncoder().encode(yeni).write(to: dosya, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            icerik = yeni; hata = nil; return true
        } catch { hata = "Değişiklik kaydedilemedi: \(error.localizedDescription)"; return false }
    }
    @discardableResult func komutKaydet(_ komut: HazirKomut) -> Bool {
        var k = komut
        k.baslik = k.baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.baslik.isEmpty, k.baslik.count <= 40, !k.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              k.metin.count <= 4000 else { hata = "Başlık 1–40, komut 1–4000 karakter olmalı."; return false }
        var yeni = icerik
        if let i = yeni.komutlar.firstIndex(where: { $0.id == k.id }) { yeni.komutlar[i] = k }
        else { guard yeni.komutlar.count < 40 else { hata = "En fazla 40 hızlı komut saklanabilir."; return false }; yeni.komutlar.append(k) }
        return kaydet(yeni)
    }
    func komutSil(_ id: UUID) { var yeni = icerik; yeni.komutlar.removeAll { $0.id == id }; kaydet(yeni) }
    func tasi(_ kaynak: IndexSet, hedef: Int) {
        var yeni = icerik
        guard kaynak.allSatisfy({ yeni.komutlar.indices.contains($0) }), (0...yeni.komutlar.count).contains(hedef) else { return }
        let secilen = kaynak.sorted().map { yeni.komutlar[$0] }
        for i in kaynak.sorted(by: >) { yeni.komutlar.remove(at: i) }
        yeni.komutlar.insert(contentsOf: secilen, at: hedef - kaynak.filter { $0 < hedef }.count)
        kaydet(yeni)
    }
    func kayitli(_ metin: String) -> Bool { icerik.yanitlar.contains { $0.metin == metin } }
    @discardableResult func yanitKaydet(_ metin: String) -> Bool {
        guard !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, metin.count <= 64000 else { hata = "Yanıt boş veya kaydetmek için fazla uzun."; return false }
        if kayitli(metin) { return true }
        guard icerik.yanitlar.count < 200 else { hata = "En fazla 200 yanıt saklanabilir."; return false }
        var yeni = icerik; yeni.yanitlar.insert(KayitliYanit(metin: metin), at: 0); return kaydet(yeni)
    }
    func yanitSil(_ id: UUID) { var yeni = icerik; yeni.yanitlar.removeAll { $0.id == id }; kaydet(yeni) }

    func yedekVerisi() throws -> Data {
        let veri = try JSONEncoder().encode(Yedek(icerik: icerik))
        guard Self.yedekBoyutuUygun(veri.count) else {
            throw YedekHatasi(errorDescription: "Yedek çok büyük (\(veri.count >> 20) MB); bazı kayıtlı yanıtları silip yeniden dene.")
        }
        return veri
    }

    /// Yedeği doğrular ve çözer; geçersizse nil döner ve hata metnini atar. Mevcut içeriğe dokunmaz.
    func yedegiCoz(_ veri: Data) -> Icerik? {
        guard Self.yedekBoyutuUygun(veri.count) else {
            hata = "Yedek dosyası çok büyük (\(veri.count >> 20) MB); mevcut içerik korunuyor."; return nil
        }
        guard let yedek = try? JSONDecoder().decode(Yedek.self, from: veri),
              yedek.surum == 1,
              yedek.icerik.komutlar.count <= 40,
              yedek.icerik.yanitlar.count <= 200,
              yedek.icerik.komutlar.allSatisfy({ !$0.baslik.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.baslik.count <= 40 && !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.metin.count <= 4000 }),
              yedek.icerik.yanitlar.allSatisfy({ !$0.metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.metin.count <= 64_000 }),
              Set(yedek.icerik.komutlar.map(\.id)).count == yedek.icerik.komutlar.count,
              Set(yedek.icerik.yanitlar.map(\.id)).count == yedek.icerik.yanitlar.count
        else { hata = "Kişisel alan yedeği geçersiz; mevcut içerik korunuyor."; return nil }
        return yedek.icerik
    }

    /// Yedeği geri yükler. Önce mevcut içerik `oncekiDosya`ya yazılır; bu yapılamazsa geri yükleme yapılmaz.
    @discardableResult func yedegiYukle(_ veri: Data) -> Bool {
        guard let yeni = yedegiCoz(veri), !okunamadi else { return false }
        let eski = icerik
        do { try JSONEncoder().encode(eski).write(to: oncekiDosya, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { hata = "Mevcut içerik saklanamadığı için yedek geri yüklenmedi: \(error.localizedDescription)"; return false }
        guard kaydet(yeni) else {
            // Yarım kalan geri yüklemenin kopyası diskte kalmasın: bir sonraki açılışta etkisiz (ya da ileride eski
            // görüntüye döndüren) bir "geri al" sunulurdu. Bellekte önceki başarılı geri yüklemeden kalan geri alma
            // varsa disk onunla eşitlenir.
            if let o = oncekiIcerik {
                try? JSONEncoder().encode(o).write(to: oncekiDosya, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else {
                try? FileManager.default.removeItem(at: oncekiDosya)
            }
            return false
        }
        oncekiIcerik = eski
        return true
    }

    /// Son geri yüklemeyi geri alır (uygulama yeniden açıldıktan sonra da); başarı: true. Başarıda önceki kopya
    /// diskten silinir (aynı geri alma bir sonraki açılışta yeniden sunulmaz); başarısızlıkta korunur.
    @discardableResult func geriYuklemeyiGeriAl() -> Bool {
        guard let o = oncekiIcerik, kaydet(o) else { return false }
        oncekiIcerik = nil
        try? FileManager.default.removeItem(at: oncekiDosya)
        return true
    }
}
