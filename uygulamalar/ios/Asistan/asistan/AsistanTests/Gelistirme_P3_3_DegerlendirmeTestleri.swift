import Foundation
import Testing
@testable import Asistan

/// Test paketini bulmak için yerel işaret sınıfı (`Bundle(for:)`).
private final class DegerlendirmeIsareti {}

/// P3.3: değerlendirme seti her birim test turunda koşar (ağ, izin, model yok).
/// `AsistanTests/Veri/DegerlendirmeSeti.json`'daki her istek için `YolTahmini` (gonder sırasının saf taklidi) beklenen yolu,
/// çabayı ve hızlı yol uygunluğunu vermeli; örnek yanıtlı olanlarda "yaptım" bekçisi beklenen kararı vermeli.
@MainActor
struct DegerlendirmeTestleri {
    /// Set test paketinin kaynağıdır; paket kopyası bulunamazsa (kaynak aşaması eksikse) kaynak ağacındaki dosya okunur.
    static func seti() throws -> [DegerlendirmeOrnegi] {
        let paket = Bundle(for: DegerlendirmeIsareti.self).url(forResource: "DegerlendirmeSeti", withExtension: "json")
        let kaynak = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Veri/DegerlendirmeSeti.json")
        let url = try #require(paket ?? (FileManager.default.fileExists(atPath: kaynak.path) ? kaynak : nil), "DegerlendirmeSeti.json bulunamadı")
        return try DegerlendirmeDeposu.coz(Data(contentsOf: url))
    }

    @Test func setYuklenirVeYeterinceGenis() throws {
        let set = try Self.seti()
        #expect(set.count >= 30, "örnek sayısı: \(set.count)")
        for o in set {
            #expect(YolTahmini.yollar.contains(o.beklenenYol), "bilinmeyen yol '\(o.beklenenYol)': \(o.istek)")
            if let c = o.beklenenCaba { #expect(DusunmeSecimi.Caba(rawValue: c) != nil, "bilinmeyen çaba '\(c)': \(o.istek)") }
        }
        // Her yönlendirme aşaması en az bir örnekle temsil edilir.
        #expect(Set(set.map(\.beklenenYol)) == Set(YolTahmini.yollar), "eksik yollar: \(Set(YolTahmini.yollar).subtracting(set.map(\.beklenenYol)))")
    }

    @Test func herOrnekBeklenenYoldanGider() throws {
        for o in try Self.seti() {
            let r = YolTahmini.tahmin(o.istek)
            #expect(r.yol == o.beklenenYol, "yol: '\(o.istek)' → \(r.yol), beklenen \(o.beklenenYol)")
            if let c = o.beklenenCaba {
                #expect(r.caba.rawValue == c, "çaba: '\(o.istek)' → \(r.caba.rawValue), beklenen \(c)")
            }
            if let h = o.hizliUygun {
                #expect(r.hizliUygun == h, "hızlı yol: '\(o.istek)' → \(r.hizliUygun), beklenen \(h)")
            }
        }
    }

    @Test func ornekYanitlardaEylemBekcisi() throws {
        let ornekli = try Self.seti().filter { $0.ornekYanit != nil && $0.eylemIddiasiBeklenir != nil }
        #expect(ornekli.count >= 2)
        for o in ornekli {
            let yakalandi = EylemIddiasi.denetle(o.ornekYanit ?? "", basariliAraclar: []) != nil
            #expect(yakalandi == o.eylemIddiasiBeklenir, "eylem bekçisi: '\(o.istek)' / '\(o.ornekYanit ?? "")' → \(yakalandi)")
        }
    }

    // MARK: YolTahmini ayrıntıları

    @Test func yolTahminiSirasiGonderIleAyni() {
        // Kod kipinde sunucu görevleri kapalıysa zincire düşer.
        #expect(YolTahmini.tahmin("python ile fibonacci kodu yaz").yol == "sunucu")
        #expect(YolTahmini.tahmin("python ile fibonacci kodu yaz", sunucuGorevleri: false).yol == "zincir")
        // Web araması kapalıyken açık araştırma zincire düşer.
        #expect(YolTahmini.tahmin("Dolar kaç", webArama: false).yol == "zincir")
        // Ekli istek yerel/müzik kısa yollarına girmez.
        #expect(YolTahmini.tahmin("saat kaç", ekVar: true).yol != "yerel")
        #expect(YolTahmini.tahmin("Tarkan'ın Şımarık şarkısını çal", ekVar: true).yol != "muzik")
    }

    /// YolTahmini `Beyin.gonder` sırasının taklidi olduğundan, gerçek `gonder` ile aynı yolu verdiği ağsız yerel yollarda doğrulanır.
    /// Tam çözüm: yol kararı Beyin'den saf bir fonksiyona çıkarılıp YolTahmini onu çağırmalı (dış ihtiyaç, bkz. rapor).
    @Test(.timeLimit(.minutes(1)))
    func yolTahminiGercekGonderIleAyni() async throws {
        let alan = "yol-tahmini.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: alan))
        defer { d.removePersistentDomain(forName: alan) }
        let a = Ayarlar(defaults: d); a.otomatikHafiza = false; a.istemSuzgeci = false
        let kap = HafizaDeposu.kapOlustur(bellekte: true)
        for istek in ["saat kaç", "Görsel üret: mavi bir daire", "Sohbet arşivini aç"] {
            let b = Beyin(ayarlar: a, depo: HafizaDeposu(baglam: kap.mainContext), onay: OnayKapisi())
            // Ortak ağ izleyicisini başka bir test çevrimdışı bırakmış olabilir; gonder aynı adımda okuduğu için hemen önce aç.
            AgIzleyici.ortak.durumGuncelle(true)
            b.gonder(istek)
            let son = ContinuousClock.now + .seconds(45)
            while b.durum != .bosta, ContinuousClock.now < son { try await Task.sleep(for: .milliseconds(10)) }
            try #require(b.durum == .bosta, "gönderim bitmedi: \(istek)")
            let tahmin = YolTahmini.tahmin(istek)
            #expect(b.sonYonlendirme == tahmin.yol, "'\(istek)': gonder → \(b.sonYonlendirme), YolTahmini → \(tahmin.yol)")
        }
    }

    // MARK: Kalite defteri

    @Test func itirazMi() {
        for t in ["Hayır", "Hayır, yanlış anladın", "Yanlış anladın beni", "Olmadı bu", "Öyle değil", "Bu değil!", "yanlış"] {
            #expect(KaliteDefteri.itirazMi(t), "itiraz sayılmalı: \(t)")
        }
        for t in ["Hayırlı olsun", "Yanlışlık nedir", "Hayır teşekkürler", "olmadık işler", "Bu değilse ne", "mitoz nedir", ""] {
            #expect(!KaliteDefteri.itirazMi(t), "itiraz sayılmamalı: \(t)")
        }
    }

    @Test func kaliteDefteriMetinYazmazVeOzetler() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kalite-test-\(UUID().uuidString).json")
        defer { KaliteDefteri.yazimlariBekle(); try? FileManager.default.removeItem(at: url) }
        let d = KaliteDefteri(dosya: url)
        let iz = YanitIzi(yol: "yaris", kip: "sohbet", caba: "low", araclar: [])
        let mesaj = UUID()
        d.oyla(mesaj, begendi: true, model: "haiku", iz: iz)
        d.oyla(mesaj, begendi: true, model: "haiku", iz: iz)   // aynı beğeni ikinci kez sayılmaz
        d.oyla(UUID(), begendi: false, neden: "Yanlış bilgi", model: "haiku", iz: iz)
        d.kaydet(.itiraz, model: "gpt", iz: YanitIzi(yol: "zincir", kip: "sohbet", caba: nil, araclar: ["webAra"]))
        d.kaydet(.durdur, model: "gpt", iz: nil)
        d.kaydet(.yenidenUret, model: "gpt", iz: nil, zaman: Date().addingTimeInterval(-10 * 86_400))   // 7 günün dışında
        #expect(d.oylar[mesaj] == true)
        let ozet = d.ozet(gun: 7)
        let haiku = try #require(ozet.first { $0.model == "haiku" })
        #expect(haiku.begeni == 1 && haiku.begenmeme == 1)
        let gpt = try #require(ozet.first { $0.model == "gpt" })
        #expect(gpt.itiraz == 1 && gpt.durdur == 1 && gpt.yenidenUret == 0)
        #expect(KaliteDefteri.nedenSayilari(d.kayitlar).first?.neden == "Yanlış bilgi")
        // Kalıcı dosya geri yüklenir; içinde istek/yanıt metni alanı yoktur.
        KaliteDefteri.yazimlariBekle()
        let ikinci = KaliteDefteri(dosya: url)
        #expect(ikinci.kayitlar == d.kayitlar)
        let ham = try String(contentsOf: url, encoding: .utf8)
        #expect(!ham.contains("\"metin\"") && !ham.contains("\"istek\""))
        d.temizle()
        #expect(d.kayitlar.isEmpty && d.oylar.isEmpty)
    }

    @Test func kaliteDefteri500KayitlaSinirli() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kalite-sinir-\(UUID().uuidString).json")
        defer { KaliteDefteri.yazimlariBekle(); try? FileManager.default.removeItem(at: url) }
        let d = KaliteDefteri(dosya: url)
        for _ in 0..<(KaliteDefteri.enFazlaKayit + 20) { d.kaydet(.durdur, model: "m", iz: nil) }
        #expect(d.kayitlar.count == KaliteDefteri.enFazlaKayit)
    }

    // MARK: Değerlendirme deposu

    @Test func degerlendirmeDeposuGidisDonus() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("degerlendirme-test-\(UUID().uuidString).json")
        defer { DegerlendirmeDeposu.yazimlariBekle(); try? FileManager.default.removeItem(at: url) }
        let depo = DegerlendirmeDeposu(dosya: url)
        // ISO 8601 saniye hassasiyetindedir: gidiş-dönüş eşitliği için tam saniyelik tarih.
        let zaman = Date(timeIntervalSince1970: 1_790_000_000)
        let a = DegerlendirmeOrnegi(istek: "9B yoklama", beklenenYol: "zincir", hizliUygun: false, beklenenAraclar: ["sinif"], eklenme: zaman)
        let b = DegerlendirmeOrnegi(istek: "saat kaç", beklenenYol: "yerel", beklenenCaba: "low", ornekYanit: "Saat 10:00.",
                                    eylemIddiasiBeklenir: false, not: "yerel saat", eklenme: zaman)
        depo.ekle(a); depo.ekle(b)
        DegerlendirmeDeposu.yazimlariBekle()
        let geri = DegerlendirmeDeposu(dosya: url)
        #expect(geri.hepsi == [a, b])
        depo.sil(a.id)
        DegerlendirmeDeposu.yazimlariBekle()
        #expect(DegerlendirmeDeposu(dosya: url).hepsi == [b])
        // Dışa aktarılan kopya başlangıç setiyle aynı biçimde çözülür.
        let disari = depo.disaAktar()
        #expect(try DegerlendirmeDeposu.coz(Data(contentsOf: disari)) == [b])
    }

    @Test func elleYazilanOrnekteYalnizIstekVeYolZorunlu() throws {
        let ham = #"[{"istek": "merhaba", "beklenenYol": "yerel"}]"#
        let o = try #require(DegerlendirmeDeposu.coz(Data(ham.utf8)).first)
        #expect(o.istek == "merhaba" && o.beklenenYol == "yerel" && o.beklenenAraclar.isEmpty && o.beklenenCaba == nil && o.hizliUygun == nil)
    }

    @Test func yanitIziEsitlenebilir() {
        let a = YanitIzi(yol: "zincir", kip: "sohbet", caba: "medium", araclar: ["webAra"])
        var g = Beyin.Goruntu(rol: .asistan, metin: "x")
        #expect(g.iz == nil)
        g.iz = a
        #expect(g.iz == a)
    }
}
