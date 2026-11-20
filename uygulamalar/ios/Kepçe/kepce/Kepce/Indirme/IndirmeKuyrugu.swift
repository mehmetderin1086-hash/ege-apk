import Foundation
import Observation
import UIKit

nonisolated struct IndirmeSecimi: Codable, Sendable, Hashable {
    var tur: IndirmeTuru
    /// Seçilen kalite ("1080p60"); boşsa `enFazla` sınırındaki en iyi kalite.
    var kaliteID: String?
    var enFazla: Int = 0
    var sesID: String?
    var dil: String?
    /// Altyazı dili; boş/nil = altyazı yok.
    var altyazi: String?
    var otomatikAltyazi = true
    var kesit: ClosedRange<Double>?
    /// Listeden gelen işler: liste adı (kütüphanede gruplama), alt klasör ve sıra numarası (dosya adı öneki).
    var liste: String?
    var altKlasor: String?
    var siraNo: Int?

    @MainActor static func hizli(_ tur: IndirmeTuru, ayarlar: Ayarlar = .shared) -> IndirmeSecimi {
        IndirmeSecimi(tur: tur, enFazla: ayarlar.enFazlaCozunurluk, dil: ayarlar.tercihEdilenSesDili.isEmpty ? nil : ayarlar.tercihEdilenSesDili,
                      altyazi: ayarlar.altyaziDili.isEmpty ? nil : ayarlar.altyaziDili, otomatikAltyazi: ayarlar.otomatikAltyazi)
    }
}

nonisolated enum IsDurumu: String, Codable, Sendable {
    case bekliyor, hazirlaniyor, indiriliyor, isleniyor, tamam, hata, duraklatildi

    var ad: String {
        switch self {
        case .bekliyor: "Sırada"
        case .hazirlaniyor: "Bağlantı çözülüyor…"
        case .indiriliyor: "İndiriliyor"
        case .isleniyor: "Dosya hazırlanıyor…"
        case .tamam: "Tamamlandı"
        case .hata: "Hata"
        case .duraklatildi: "Duraklatıldı"
        }
    }
    var etkin: Bool { [.hazirlaniyor, .indiriliyor, .isleniyor].contains(self) }
}

nonisolated struct IndirmeIsi: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var adres: String
    var baslik: String
    var yazar: String?
    var kapak: String?
    var sure: Double?
    var secim: IndirmeSecimi
    var durum: IsDurumu = .bekliyor
    var hata: String?
    var etiket: String?
    var tarih = Date()
    var alinan: Int64 = 0
    var toplam: Int64?
    var hiz: Double = 0
    var kutuphaneID: UUID?
    /// Geçici hatalarda kendiliğinden yeniden deneme sayısı.
    var deneme: Int?

    var ilerleme: Double {
        guard let toplam, toplam > 0 else { return 0 }
        return min(1, Double(alinan) / Double(toplam))
    }
    var kalanSure: Double? {
        guard let toplam, hiz > 1 else { return nil }
        return Double(max(0, toplam - alinan)) / hiz
    }
}

/// İndirme sırası: çözme → indirme (paralel aralıklar) → birleştirme → kütüphane.
@Observable final class IndirmeKuyrugu {
    static let shared = IndirmeKuyrugu()

    private(set) var isler: [IndirmeIsi] = []
    /// Her çalıştırmanın kuşak kimliği: iptal edilmiş eski görev, yerine başlayan yeni görevin kaydına dokunmaz.
    private var gorevler: [UUID: (kusak: UUID, gorev: Task<Void, Never>)] = [:]
    private var sayaclar: [UUID: [IlerlemeSayaci]] = [:]
    private var tahminler: [UUID: Int64] = [:]
    private var bilgiOnbellegi: [String: (bilgi: MedyaBilgisi, tarih: Date)] = [:]
    private var yenileyici: Task<Void, Never>?
    /// YouTube hız sınırı/bot denetimi görülünce yeni işler bu ana kadar başlamaz.
    private(set) var beklemeBitis: Date?
    private var beklemeSayisi = 0
    private var uyandirici: Task<Void, Never>?
    private var sonCozum = Date.distantPast
    private let dosya: URL
    private let ayarlar: Ayarlar
    private let kutuphane: Kutuphane

    static var calismaKoku: URL { URL.cachesDirectory.appending(path: "Isler") }

    init(dosya: URL = PythonMotoru.destek.appending(path: "kuyruk.json"), ayarlar: Ayarlar = .shared, kutuphane: Kutuphane = .shared) {
        self.dosya = dosya
        self.ayarlar = ayarlar
        self.kutuphane = kutuphane
        if let veri = try? Data(contentsOf: dosya), var liste = try? JSONDecoder().decode([IndirmeIsi].self, from: veri) {
            liste.removeAll { $0.durum == .tamam }
            for i in liste.indices where liste[i].durum.etkin {
                liste[i].durum = .bekliyor
                liste[i].hiz = 0
            }
            isler = liste
        }
        ArkaPlan.shared.durdurulsun = { [weak self] in self?.hepsiniDuraklat() }
        ArkaPlan.shared.etkinIsVar = { [weak self] in self?.isler.contains { $0.durum.etkin } ?? false }
    }

    func baslat() { isle() }

    // MARK: Dışarıdan işlemler

    /// Bilgisi önceden alınmış (ya da alınmamış) bağlantıyı sıraya ekler.
    @discardableResult
    func ekle(adres: String, bilgi: MedyaBilgisi? = nil, secim: IndirmeSecimi, baslik: String? = nil, kapak: String? = nil, sure: Double? = nil) -> UUID {
        if let bilgi { onbellegeKoy(adres, bilgi) }
        let is_ = IndirmeIsi(adres: adres, baslik: bilgi?.title ?? baslik ?? adres, yazar: bilgi?.yazar, kapak: bilgi?.thumbnail ?? kapak,
                             sure: bilgi?.duration ?? sure, secim: secim)
        isler.append(is_)
        kaydet()
        if ayarlar.bildirim { ArkaPlan.shared.bildirimIzni() }
        isle()
        return is_.id
    }

    nonisolated struct TopluOge: Sendable {
        var adres: String
        var baslik: String?
        var kapak: String?
        var sure: Double?
    }

    /// Yüzlerce öğeyi tek seferde ekler (tek kayıt, tek zamanlama). Zaten kütüphanede/sırada olanlar istenirse atlanır.
    @discardableResult
    func topluEkle(_ ogeler: [TopluOge], secim: IndirmeSecimi, numarala: Bool = false, atla: Bool = true) -> (eklenen: Int, atlanan: Int) {
        var mevcut = atla ? mevcutAnahtarlar() : []
        var eklenen = 0, atlanan = 0
        for (i, oge) in ogeler.enumerated() {
            let anahtar = Self.anahtar(oge.adres)
            if atla && mevcut.contains(anahtar) { atlanan += 1; continue }
            mevcut.insert(anahtar)
            var s = secim
            if numarala { s.siraNo = i + 1 }
            isler.append(IndirmeIsi(adres: oge.adres, baslik: oge.baslik ?? oge.adres, kapak: oge.kapak, sure: oge.sure, secim: s))
            eklenen += 1
        }
        if eklenen > 0 {
            kaydet()
            if ayarlar.bildirim { ArkaPlan.shared.bildirimIzni() }
            isle()
        }
        return (eklenen, atlanan)
    }

    /// Video kimliği (YouTube'da 11 karakter), yoksa sorgusuz adres: aynı videonun iki kez indirilmesini önler.
    nonisolated static func anahtar(_ adres: String) -> String {
        guard let bilesen = URLComponents(string: adres) else { return adres }
        let host = bilesen.host?.lowercased() ?? ""
        if host.contains("youtube.com") || host.contains("youtu.be") {
            if let v = bilesen.queryItems?.first(where: { $0.name == "v" })?.value { return "yt:\(v)" }
            let parcalar = bilesen.path.split(separator: "/")
            if host.contains("youtu.be"), let ilk = parcalar.first { return "yt:\(ilk)" }
            if let i = parcalar.firstIndex(where: { ["shorts", "live", "embed"].contains($0) }), i + 1 < parcalar.count { return "yt:\(parcalar[i + 1])" }
        }
        return "\(host)\(bilesen.path)"
    }

    func mevcutAnahtarlar() -> Set<String> {
        var kume = Set(isler.filter { $0.durum != .hata }.map { Self.anahtar($0.adres) })
        for oge in kutuphane.ogeler where !oge.kaynak.isEmpty { kume.insert(Self.anahtar(oge.kaynak)) }
        return kume
    }

    func hepsiniSurdur() {
        for i in isler.indices where isler[i].durum == .duraklatildi { isler[i].durum = .bekliyor; isler[i].hata = nil }
        isle()
    }

    func hatalilariYenidenDene() {
        for i in isler.indices where isler[i].durum == .hata {
            bilgiOnbellegi[isler[i].adres] = nil
            isler[i].durum = .bekliyor; isler[i].hata = nil; isler[i].deneme = 0
        }
        isle()
    }

    func bekleyenleriKaldir() {
        let silinecek = isler.filter { $0.durum == .bekliyor || $0.durum == .duraklatildi || $0.durum == .hata }.map(\.id)
        isler.removeAll { silinecek.contains($0.id) }
        for id in silinecek { try? FileManager.default.removeItem(at: Self.calismaKoku.appending(path: id.uuidString)) }
        kaydet()
        isle()
    }

    /// Sıradaki bir işi en öne alır.
    func oneAl(_ id: UUID) {
        guard let i = isler.firstIndex(where: { $0.id == id }) else { return }
        let is_ = isler.remove(at: i)
        let hedef = isler.firstIndex { $0.durum == .bekliyor } ?? isler.endIndex
        isler.insert(is_, at: hedef)
        kaydet()
    }

    func beklemeyiBitir() {
        beklemeBitis = nil
        isle()
    }

    func duraklat(_ id: UUID) {
        // Dosya hazırlanırken (birleştirme) duraklatılmaz; birkaç saniyede biter.
        guard isler.first(where: { $0.id == id })?.durum != .isleniyor else { return }
        gorevler[id]?.gorev.cancel()
        gorevler[id] = nil
        guncelle(id) { $0.durum = .duraklatildi; $0.hiz = 0 }
        isle()
    }

    func hepsiniDuraklat() {
        for is_ in isler where is_.durum.etkin || is_.durum == .bekliyor { duraklat(is_.id) }
    }

    func surdur(_ id: UUID) {
        guncelle(id) { $0.durum = .bekliyor; $0.hata = nil }
        isle()
    }

    func yenidenDene(_ id: UUID) {
        if let adres = isler.first(where: { $0.id == id })?.adres { bilgiOnbellegi[adres] = nil }
        surdur(id)
    }

    func kaldir(_ id: UUID) {
        gorevler[id]?.gorev.cancel()
        gorevler[id] = nil
        isler.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.calismaKoku.appending(path: id.uuidString))
        kaydet()
        isle()
    }

    func bitenleriTemizle() {
        isler.removeAll { $0.durum == .tamam }
        kaydet()
    }

    var etkinSayisi: Int { isler.filter { $0.durum.etkin || $0.durum == .bekliyor }.count }

    // MARK: Sıra yönetimi

    private func isle() {
        let calisan = isler.filter { $0.durum.etkin }.count
        var bos = max(0, ayarlar.esZamanli - calisan)
        if let beklemeBitis, beklemeBitis > Date() {
            bos = 0
            if uyandirici == nil {
                uyandirici = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(max(1, beklemeBitis.timeIntervalSinceNow)))
                    guard let self, !Task.isCancelled else { return }
                    self.uyandirici = nil
                    self.beklemeBitis = nil
                    self.isle()
                }
            }
        } else if beklemeBitis != nil {
            beklemeBitis = nil
        }
        for is_ in isler.filter({ $0.durum == .bekliyor }).prefix(bos) {
            guncelle(is_.id) { $0.durum = .hazirlaniyor }
            let id = is_.id, kusak = UUID()
            gorevler[id] = (kusak, Task { [weak self] in await self?.calistir(id, kusak: kusak) })
        }
        let etkin = isler.contains { $0.durum.etkin }
        if etkin {
            ArkaPlan.shared.basla(baslik: isler.first { $0.durum.etkin }?.baslik ?? "")
            if yenileyici == nil { yenileyici = Task { [weak self] in await self?.ilerlemeDongusu() } }
        } else {
            yenileyici?.cancel()
            yenileyici = nil
            ArkaPlan.shared.bitir()
        }
        kaydet()
    }

    private func ilerlemeDongusu() async {
        var oncekiler: [UUID: (Int64, Date)] = [:]
        while !Task.isCancelled {
            for is_ in isler where is_.durum == .indiriliyor {
                guard let liste = sayaclar[is_.id] else { continue }
                let alinan = liste.reduce(0) { $0 + $1.alinan }
                let bilinen = liste.compactMap(\.toplam)
                let toplam: Int64? = bilinen.count == liste.count ? bilinen.reduce(0, +) : (tahminler[is_.id] ?? bilinen.reduce(0, +))
                let simdi = Date()
                var hiz = is_.hiz
                if let (onceki, zaman) = oncekiler[is_.id] {
                    let anlik = Double(alinan - onceki) / max(0.1, simdi.timeIntervalSince(zaman))
                    hiz = hiz == 0 ? anlik : hiz * 0.7 + anlik * 0.3
                }
                oncekiler[is_.id] = (alinan, simdi)
                guncelle(is_.id) { $0.alinan = alinan; $0.toplam = toplam; $0.hiz = max(0, hiz) }
            }
            let etkinler = isler.filter { $0.durum.etkin }
            if !etkinler.isEmpty {
                let toplam = etkinler.reduce(0.0) { $0 + $1.ilerleme } / Double(etkinler.count)
                let hiz = etkinler.reduce(0.0) { $0 + $1.hiz }
                ArkaPlan.shared.guncelle(ilerleme: toplam, baslik: etkinler.count == 1 ? etkinler[0].baslik : "\(etkinler.count) indirme sürüyor",
                                         altBaslik: "\(Int(toplam * 100))% · \(BicimSecici.boyutMetni(Int64(hiz)))/sn")
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func guncelle(_ id: UUID, _ degistir: (inout IndirmeIsi) -> Void) {
        guard let i = isler.firstIndex(where: { $0.id == id }) else { return }
        degistir(&isler[i])
    }

    private func kaydet() {
        guard let veri = try? JSONEncoder().encode(isler) else { return }
        try? veri.write(to: dosya, options: .atomic)
    }

    private func bilgiAl(_ adres: String, taze: Bool) async throws -> MedyaBilgisi {
        if !taze, let onbellek = bilgiOnbellegi[adres], Date().timeIntervalSince(onbellek.tarih) < 1800 { return onbellek.bilgi }
        // Art arda yüzlerce çözme YouTube'un hız sınırına takılır: çözmeler arasında kısa ara.
        let ara = 0.7 - Date().timeIntervalSince(sonCozum)
        sonCozum = Date().addingTimeInterval(max(0, ara))
        if ara > 0 { try await Task.sleep(for: .seconds(ara)) }
        let bilgi = try await PythonMotoru.shared.coz(adres)
        try Task.checkCancellation()
        if bilgi.liste { throw PythonMotoru.Hata.cozum("Bu bağlantı bir liste; listeyi açıp videoları seç.") }
        onbellegeKoy(adres, bilgi)
        return bilgi
    }

    private func onbellegeKoy(_ adres: String, _ bilgi: MedyaBilgisi) {
        let simdi = Date()
        bilgiOnbellegi = bilgiOnbellegi.filter { simdi.timeIntervalSince($0.value.tarih) < 1800 }
        bilgiOnbellegi[adres] = (bilgi, simdi)
    }

    nonisolated static func hizSiniri(_ hata: Error) -> Bool {
        let metin = hata.localizedDescription.lowercased()
        return metin.contains("not a bot") || metin.contains("oturum doğrulaması") || metin.contains("429") || metin.contains("too many requests")
    }

    nonisolated static func gecici(_ hata: Error) -> Bool {
        if hata is URLError { return true }
        if let h = hata as? IndirmeHatasi {
            switch h {
            case .http(let kod): return kod >= 500 || kod == 403
            case .bosYanit, .eksik, .suresiDoldu, .dosyaDegisti: return true
            default: return false
            }
        }
        let metin = hata.localizedDescription.lowercased()
        return metin.contains("timed out") || metin.contains("bağlantı hatası") || metin.contains("connection")
    }

    static func iptalMi(_ hata: Error) -> Bool {
        hata is CancellationError || (hata as? URLError)?.code == .cancelled
    }

    // MARK: Tek işin akışı

    private func calistir(_ id: UUID, kusak: UUID) async {
        guard let is_ = isler.first(where: { $0.id == id }) else { return }
        let calisma = Self.calismaKoku.appending(path: id.uuidString)
        try? FileManager.default.createDirectory(at: calisma, withIntermediateDirectories: true)
        do {
            var bilgi = try await bilgiAl(is_.adres, taze: false)
            if let canli = bilgi.liveStatus, canli == "is_live" || canli == "is_upcoming" {
                throw PythonMotoru.Hata.cozum("Canlı yayınlar indirilemez; yayın bitince yeniden dene.")
            }
            guard var plan = planla(bilgi, is_.secim) else {
                throw PythonMotoru.Hata.cozum("Bu video için iPhone'da oynatılabilir bir biçim bulunamadı. \"Özgün dosya\" seçeneğini dene.")
            }
            guncelle(id) {
                $0.baslik = bilgi.title ?? $0.baslik; $0.yazar = bilgi.yazar; $0.kapak = bilgi.thumbnail; $0.sure = bilgi.duration
                $0.etiket = plan.etiket; $0.durum = .indiriliyor; $0.toplam = plan.tahminiBoyut
            }
            tahminler[id] = plan.tahminiBoyut
            if let boyut = plan.tahminiBoyut { try AkisIndirici.yerVarMi(boyut, hedef: calisma) }

            // İndir; adresin süresi dolarsa bir kez yeniden çöz ve kaldığı yerden sür.
            var yenilendi = false
            while true {
                do {
                    try await indir(plan, bilgi: bilgi, calisma: calisma, id: id)
                    break
                } catch let hata as IndirmeHatasi where hata == .suresiDoldu && !yenilendi {
                    yenilendi = true
                    bilgi = try await bilgiAl(is_.adres, taze: true)
                    guard let yeni = planla(bilgi, is_.secim) else { throw hata }
                    plan = yeni
                }
            }
            try Task.checkCancellation()

            guncelle(id) { $0.durum = .isleniyor; $0.hiz = 0 }
            sayaclar[id] = nil
            let oge = try await sonlandir(plan, bilgi: bilgi, secim: is_.secim, calisma: calisma, id: id)
            kutuphane.ekle(oge)
            try? FileManager.default.removeItem(at: calisma)
            guncelle(id) { $0.durum = .tamam; $0.kutuphaneID = oge.id; $0.hata = nil; if let t = $0.toplam { $0.alinan = t } }
            beklemeSayisi = 0
            ArkaPlan.shared.bildir(baslik: "İndirildi", metin: oge.baslik)
            if ayarlar.fotograflaraKaydet, oge.tur == .video {
                do { try await Kutuphane.fotograflaraKaydet(kutuphane.url(oge)) }
                catch { guncelle(id) { $0.hata = "Fotoğraflar'a kaydedilemedi: \(error.localizedDescription)" } }
            }
        } catch {
            // Duraklatma/kaldırma durumu orada ayarlandı; iptal edilmiş görev durum yazmaz.
            if !Task.isCancelled && !Self.iptalMi(error) {
                let deneme = isler.first { $0.id == id }?.deneme ?? 0
                if Self.hizSiniri(error) {
                    // YouTube yavaşlattı: iş sıraya döner, bütün sıra bir süre bekler (5, 10, 20… dk).
                    beklemeSayisi += 1
                    let dakika = min(60, 5 * (1 << min(beklemeSayisi - 1, 4)))
                    beklemeBitis = Date().addingTimeInterval(Double(dakika) * 60)
                    guncelle(id) { $0.durum = .bekliyor; $0.hata = "YouTube yavaşlattı; \(dakika) dk sonra sürecek."; $0.hiz = 0 }
                } else if deneme < 2 && Self.gecici(error) {
                    guncelle(id) { $0.durum = .bekliyor; $0.deneme = deneme + 1; $0.hata = "Yeniden denenecek (\(deneme + 1)/2)…"; $0.hiz = 0 }
                } else {
                    guncelle(id) { $0.durum = .hata; $0.hata = error.localizedDescription; $0.hiz = 0 }
                    ArkaPlan.shared.bildir(baslik: "İndirilemedi", metin: "\(is_.baslik): \(error.localizedDescription)")
                }
            }
        }
        guard gorevler[id]?.kusak == kusak else { return }
        sayaclar[id] = nil
        tahminler[id] = nil
        gorevler[id] = nil
        isle()
    }

    private func planla(_ bilgi: MedyaBilgisi, _ secim: IndirmeSecimi) -> IndirmePlani? {
        BicimSecici.plan(bilgi, tur: secim.tur, enFazla: secim.enFazla, kaliteID: secim.kaliteID, sesID: secim.sesID, dil: secim.dil)
    }

    private func indir(_ plan: IndirmePlani, bilgi: MedyaBilgisi, calisma: URL, id: UUID) async throws {
        let baglanti = ayarlar.baglantiSayisi
        let videoSayaci = IlerlemeSayaci(), sesSayaci = IlerlemeSayaci()
        sayaclar[id] = [plan.video != nil ? videoSayaci : nil, plan.ses != nil ? sesSayaci : nil].compactMap { $0 }
        let sure = bilgi.duration
        let tsKabul = plan.tur == .ham
        // İki akış birlikte; biri düşerse öbürü hemen iptal edilir.
        try await withThrowingTaskGroup(of: Void.self) { grup in
            if let v = plan.video {
                grup.addTask {
                    try await AkisIndirici.indir(v, hedef: Self.calismaDosyasi(calisma, "video", v), baglanti: baglanti, sayac: videoSayaci, sure: sure, mpegTSKabul: tsKabul)
                }
            }
            if let s = plan.ses {
                grup.addTask {
                    try await AkisIndirici.indir(s, hedef: Self.calismaDosyasi(calisma, "ses", s), baglanti: max(1, baglanti / 2), sayac: sesSayaci, sure: sure, mpegTSKabul: tsKabul)
                }
            }
            try await grup.waitForAll()
        }
    }

    /// İndirilen akışlardan son dosyayı üretir, altyazı ve kapağı kaydeder, kütüphane öğesini döndürür.
    private func sonlandir(_ plan: IndirmePlani, bilgi: MedyaBilgisi, secim: IndirmeSecimi, calisma: URL, id: UUID) async throws -> KutuphaneOgesi {
        let baslik = bilgi.title ?? "Kepçe"
        let videoDosyasi = plan.video.map { Self.calismaDosyasi(calisma, "video", $0) }
        let sesDosyasi = plan.ses.map { Self.calismaDosyasi(calisma, "ses", $0) }
        let kapak = await Birlestirici.kapak(bilgi.thumbnail, kare: plan.tur == .ses)
        var klasor = Kutuphane.klasor(plan.tur)
        if let alt = secim.altKlasor, !alt.isEmpty {
            klasor = klasor.appending(path: Kutuphane.temizAd(alt))
            try? FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        }
        let dosyaAdi = secim.siraNo.map { String(format: "%03d - ", $0) + baslik } ?? baslik
        var uzanti = plan.uzanti
        let ara: URL   // önce çalışma dizinine üretilir, sonra benzersiz adla kütüphaneye taşınır

        if plan.tur == .ham || (plan.tur == .ses && plan.uzanti == "mp3" && secim.kesit == nil) {
            guard let kaynak = videoDosyasi ?? sesDosyasi else { throw BirlestirmeHatasi.izYok }
            // HLS'den gelen özgün dosya MPEG-TS olabilir (yt-dlp uzantıyı mp4 bildirir).
            if plan.tur == .ham, let tutamac = try? FileHandle(forReadingFrom: kaynak) {
                if (try? tutamac.read(upToCount: 1))?.first == 0x47 { uzanti = "ts" }
                try? tutamac.close()
            }
            ara = kaynak
        } else {
            let etiket = MedyaEtiketi(baslik: baslik, sanatci: bilgi.yazar, aciklama: bilgi.description, tarih: Self.tarih(bilgi.uploadDate), kapak: kapak)
            if plan.uzanti == "mp3" { uzanti = "m4a" }   // kesitli mp3 → m4a
            ara = calisma.appending(path: "cikti.\(uzanti)")
            try await Birlestirici.birlestir(video: videoDosyasi, ses: sesDosyasi, cikis: ara, yalnizSes: plan.tur == .ses, etiket: etiket, kesit: secim.kesit)
        }
        let cikis = try Kutuphane.tasi(ara, baslik: dosyaAdi, uzanti: uzanti, klasor: klasor)
        return try await oge(plan, bilgi: bilgi, secim: secim, dosya: cikis, kapak: kapak, id: id)
    }

    private func oge(_ plan: IndirmePlani, bilgi: MedyaBilgisi, secim: IndirmeSecimi, dosya: URL, kapak: Data?, id: UUID) async throws -> KutuphaneOgesi {
        var oge = KutuphaneOgesi(baslik: bilgi.title ?? dosya.deletingPathExtension().lastPathComponent, yazar: bilgi.yazar,
                                 kaynak: bilgi.webpageURL ?? "", dosya: Kutuphane.goreli(dosya), tur: plan.tur,
                                 sure: secim.kesit.map { $0.upperBound - $0.lowerBound } ?? bilgi.duration,
                                 boyut: (try? dosya.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0,
                                 etiket: plan.etiket, bolumler: secim.kesit == nil ? bilgi.chapters : nil, liste: secim.liste)
        if let kapak {
            let ad = "\(oge.id.uuidString).jpg"
            try? kapak.write(to: Kutuphane.kapaklar.appending(path: ad))
            oge.kapak = ad
        }
        if let dil = secim.altyazi, !dil.isEmpty, plan.tur != .ses,
           let srt = await altyazi(bilgi, dil: dil, otomatik: secim.otomatikAltyazi, kaydir: secim.kesit?.lowerBound ?? 0) {
            let hedef = dosya.deletingPathExtension().appendingPathExtension("\(dil).srt")
            if (try? srt.write(to: hedef, atomically: true, encoding: .utf8)) != nil { oge.altyazilar[dil] = Kutuphane.goreli(hedef) }
        }
        return oge
    }

    /// İstenen dildeki altyazıyı (yoksa otomatik altyazıyı) indirip SRT'ye çevirir.
    private func altyazi(_ bilgi: MedyaBilgisi, dil: String, otomatik: Bool, kaydir: Double) async -> String? {
        func bul(_ tablo: [String: [AltyaziIzi]]?) -> AltyaziIzi? {
            guard let tablo else { return nil }
            let anahtar = tablo.keys.first { $0 == dil } ?? tablo.keys.sorted().first { $0.hasPrefix(dil + "-") || $0.hasPrefix(dil) }
            return anahtar.flatMap { tablo[$0]?.first { $0.ext == "vtt" } }
        }
        guard let iz = bul(bilgi.subtitles) ?? (otomatik ? bul(bilgi.automaticCaptions) : nil), let url = URL(string: iz.url),
              let (veri, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let metin = String(decoding: veri, as: UTF8.self)
        var satirlar = await Task.detached(priority: .utility) { Altyazi.vtt(metin) }.value
        if kaydir > 0 {
            satirlar = satirlar.compactMap { s in
                guard s.bitis > kaydir else { return nil }
                return AltyaziSatiri(baslangic: max(0, s.baslangic - kaydir), bitis: s.bitis - kaydir, metin: s.metin)
            }
        }
        return satirlar.isEmpty ? nil : Altyazi.srtMetni(satirlar)
    }

    /// AVFoundation biçimi uzantıdan anlar: uzantısız dosyayı "Açılamıyor" diye reddeder.
    nonisolated static func calismaDosyasi(_ calisma: URL, _ ad: String, _ bicim: Bicim) -> URL {
        var ext = (bicim.ext ?? "").lowercased()
        if ext.isEmpty || ext == "unknown_video" || ext.count > 5 { ext = bicim.videoVar ? "mp4" : "m4a" }
        if ext == "mp4" && !bicim.videoVar { ext = "m4a" }
        return calisma.appending(path: "\(ad).\(ext)")
    }

    static func tarih(_ yyyymmdd: String?) -> String? {
        guard let t = yyyymmdd, t.count == 8 else { return nil }
        return "\(t.prefix(4))-\(t.dropFirst(4).prefix(2))-\(t.suffix(2))"
    }
}
