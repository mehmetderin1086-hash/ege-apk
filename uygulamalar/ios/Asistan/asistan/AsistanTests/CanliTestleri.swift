import UIKit
import AVFoundation
import ActivityKit
import EventKit
import SwiftData
import Testing
import Foundation
@testable import Asistan

/// Gerçek Claude çağrısı yapar (ücretli). Yalnız ASISTAN_CANLI=1 ile koşar.
@Suite("Canlı uçtan uca", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct CanliTestleri {
    @Test(.timeLimit(.minutes(3)))
    func saatVeHafizaAraclari() async throws {
        let ud = UserDefaults(suiteName: "canli.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud)
        ayarlar.caba = "low"
        ayarlar.webArama = false
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let onay = OnayKapisi(); onay.otomatikKarar = false
        let beyin = Beyin(ayarlar: ayarlar, depo: depo, onay: onay)
        try #require(beyin.hazir, "Secrets.xcconfig dolu olmalı")

        beyin.gonder("Şu an saat kaç? Ayrıca şunu hatırla: en sevdiğim renk mavi.")
        let baslangic = Date()
        while beyin.durum != .bosta, Date().timeIntervalSince(baslangic) < 150 {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(beyin.durum == .bosta)
        #expect(beyin.sonHata == nil, "hata: \(beyin.sonHata ?? "")")
        let yanit = beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
        #expect(!yanit.isEmpty)
        // Saat aracı: yanıt bir saat içeriyor (örn. 18:52).
        #expect(yanit.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil, "yanıt: \(yanit)")
        // Hafıza aracı çağrıldı.
        #expect(depo.olgular().contains { $0.metin.localizedCaseInsensitiveContains("mavi") }, "olgular: \(depo.olgular().map(\.metin))")
        print("CANLI YANIT (\(beyin.aktifYol.map(String.init(describing:)) ?? "?")): \(yanit)")
    }
}

/// Ölçüm: web araştırması çabaya göre ve Live hızlı yolu ne kadar sürüyor. ASISTAN_CANLI=1 ile.
@Suite("Canlı ölçüm", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct CanliOlcumTestleri {
    @Test(.timeLimit(.minutes(5)))
    func webCabaSureleri() async throws {
        await TelefonProxy.ortak.hazirla()
        for caba in [DusunmeSecimi.Caba.low, .medium] {
            let t = Date()
            let s = (try? await WebArastirici.ara("Fenerbahçe'nin bir sonraki maçı ne zaman ve kimle?", caba: caba)) ?? "HATA"
            #expect(s != "HATA" && !s.isEmpty, "Web araştırması yanıt üretmedi")
            print("OLCUM web \(caba) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn, \(s.count) karakter: \(s.prefix(120))")
        }
    }
    @Test(.timeLimit(.minutes(3)))
    func liveHizliYol() async throws {
        await TelefonProxy.ortak.hazirla()
        let modeller = TelefonProxy.ortak.modeller.map(\.id)
        print("OLCUM modeller: \(modeller)")
        for m in ["claude-haiku-4-5", "claude-sonnet-5-5", "gpt-6.1-sol", "antigravity-gemini-3.8-flash-tiered"] {
            let t = Date()
            do {
                let r = try await CanliHizliIstemci.yanit(motor: TelefonProxy.ortak.motor, anahtar: TelefonProxy.ortak.yerelAnahtar, modeller: [m], baglam: "", soru: "Merhaba nasılsın", zamanAsimi: .seconds(20), sabitModel: m)
                print("OLCUM livemodel \(m) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn: \(r.metin.prefix(60))")
            } catch { Issue.record("Seçilen model yanıt vermedi: \(m): \(error)"); print("OLCUM livemodel \(m) HATA \(String(format: "%.1f", Date().timeIntervalSince(t))) sn: \(error)") }
        }
        for soru in ["Dönüyor galiba", "Merhaba nasılsın"] {
            let t = Date()
            do {
                let r = try await CanliHizliIstemci.yanit(motor: TelefonProxy.ortak.motor, anahtar: TelefonProxy.ortak.yerelAnahtar, modeller: modeller, baglam: "", soru: soru, zamanAsimi: .seconds(20))
                print("OLCUM live \(r.model) \(String(format: "%.1f", Date().timeIntervalSince(t))) sn: \(r.metin.prefix(80))")
            } catch { Issue.record("Hızlı yanıt alınamadı: \(error)"); print("OLCUM live HATA \(String(format: "%.1f", Date().timeIntervalSince(t))) sn: \(error)") }
        }
    }
}

/// Ölçüm: elle seçilen her modelde düz sohbet + araç çağrısı. ASISTAN_CANLI=1 ile.
@Suite("Model matrisi", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct ModelMatrisiTestleri {
    @Test(.timeLimit(.minutes(60)))
    func herModelDuzVeAracli() async throws {
        await TelefonProxy.ortak.hazirla()
        let ids = ["OTOMATIK"]
        print("MATRIS modeller: \(ids)")
        let istekler = ["Merhaba, nasılsın?", "Fotosentezi iki cümleyle açıkla.", "Beykoz'da hava nasıl?", "Bir gün kaç saniyedir? Hesabı göster.", "Fenerbahçe'nin bir sonraki maçı ne zaman?"]
        for id in ids {
            for metin in istekler {
                let ud = UserDefaults(suiteName: "matris.\(UUID().uuidString)")!
                let ayarlar = Ayarlar(defaults: ud)
                ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true; ayarlar.antigravityOncelik = true
                let onay = OnayKapisi(); onay.otomatikKarar = false
                let beyin = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: onay)
                let t = Date()
                beyin.gonder(metin)
                while beyin.durum != .bosta, Date().timeIntervalSince(t) < 75 { try await Task.sleep(for: .milliseconds(200)) }
                let sn = String(format: "%.1f", Date().timeIntervalSince(t))
                let yanit = beyin.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
                let hata = beyin.sonHata.map { "\($0)" } ?? "-"
                let bitti = beyin.durum == .bosta
                if !bitti { beyin.iptal() }
                #expect(bitti && beyin.sonHata == nil && !yanit.isEmpty, "Model turu tamamlanmadı: \(hata)")
                print("MATRIS \(id) | \(metin.prefix(14)) | \(sn) sn | kullanılan=\(beyin.aktifModel) | hata=\(hata.prefix(140)) | yanıt=\(yanit.prefix(70))")
            }
        }
    }
}

@Suite("Ses çıkış ölçümü", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
struct SesCikisOlcumTestleri {
    @Test(.timeLimit(.minutes(3)))
    func azureCumleSureleri() async throws {
        for metin in ["Merhaba.", "Merhaba Mehmet, iyiyim, teşekkürler; sen nasılsın?", "Şu an İstanbul'da hava az bulutlu, 13 derece; hissedilen sıcaklık 11 derece ve bugün yağmur bekleniyor."] {
            for tur in 1...2 {
                let t = Date()
                do {
                    let v = try await AsistanSesleri.ses(metin, kimlik: "azure:Elif")
                    #expect(!v.isEmpty, "Ses verisi boş")
                    print("SESOLCUM tur\(tur) \(metin.count) harf \(String(format: "%.2f", Date().timeIntervalSince(t))) sn \(v.count) bayt")
                } catch { Issue.record("Azure ses üretimi başarısız: \(error)"); print("SESOLCUM HATA \(error)") }
            }
        }
    }
}


@Suite("Paralel yarış ölçümü", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct ParalelYarisOlcumTestleri {
    @Test(.timeLimit(.minutes(4)))
    func yarisSureleri() async throws {
        await TelefonProxy.ortak.hazirla()
        let taban = TelefonProxy.ortak.taban, anahtar = TelefonProxy.ortak.yerelAnahtar
        for soru in ["Merhaba nasılsın?", "Fotosentezi iki cümleyle açıkla.", "Bana kısa bir fıkra anlat."] {
            // Tek tek: her modelin ilk parça süresi.
            for m in ParalelYaris.varsayilanModeller {
                let t = Date()
                let r = try? await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: [m], sistem: "Türkçe, kısa yanıtla.", mesajlar: [.init(rol: "user", metin: soru)]) { _, _ in }
                #expect(r?.metin.isEmpty == false, "Model yarışında yanıt yok: \(m)")
                print("YARIS tek \(m) ilk=\(String(format: "%.2f", r?.ilkSn ?? -1)) toplam=\(String(format: "%.2f", Date().timeIntervalSince(t))) len=\(r?.metin.count ?? 0)")
            }
            let t = Date()
            let r = try await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: ParalelYaris.varsayilanModeller, sistem: "Türkçe, kısa yanıtla.", mesajlar: [.init(rol: "user", metin: soru)]) { _, _ in }
            print("YARIS paralel kazanan=\(r.model) ilk=\(String(format: "%.2f", r.ilkSn)) toplam=\(String(format: "%.2f", Date().timeIntervalSince(t))) | \(r.metin.prefix(50))")
        }
    }
}

/// Hermes tarzı özellikler: gerçek modelle uçtan uca. ASISTAN_CANLI=1 ile.
@Suite("Hermes özellikleri canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct HermesCanliTestleri {
    private func beyin(depo: HafizaDeposu? = nil, onay: Bool = false) -> Beyin {
        let ud = UserDefaults(suiteName: "hermes.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud)
        ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = onay
        return Beyin(ayarlar: ayarlar, depo: depo ?? HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
    }
    private func sor(_ b: Beyin, _ metin: String, sinir: Double = 90) async throws -> (yanit: String, sn: Double) {
        let t = Date()
        b.gonder(metin)
        while b.durum != .bosta, Date().timeIntervalSince(t) < sinir { try await Task.sleep(for: .milliseconds(200)) }
        return (b.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? "[YANIT YOK: \(b.sonHata.map { "\($0)" } ?? "-")]", Date().timeIntervalSince(t))
    }

    @Test(.timeLimit(.minutes(5)))
    func beceriKaydedilirVeYenidenKullanilir() async throws {
        let k = FileManager.default.temporaryDirectory.appendingPathComponent("beceri-canli-\(UUID().uuidString)")
        BeceriDeposu.kok = k; defer { try? FileManager.default.removeItem(at: k) }
        let a = try await sor(beyin(), "Haftalık ders planı hazırlama yöntemimi 'haftalik-plan' adıyla beceri olarak kaydet. Adımlar: 1. Kazanımları listele 2. Her güne süre ayır 3. Ölçme ve değerlendirme ekle.")
        print("HERMES beceri-kaydet \(String(format: "%.1f", a.sn)) sn: \(a.yanit.prefix(100))")
        let kayit = try #require(BeceriDeposu.oku("haftalik-plan"), "beceri dosyası oluşmadı")
        #expect(kayit.icerik.localizedCaseInsensitiveContains("kazanım"))
        let b = try await sor(beyin(), "Kayıtlı haftalık-plan becerisini oku ve ilk adımın ne olduğunu söyle.")
        print("HERMES beceri-oku \(String(format: "%.1f", b.sn)) sn: \(b.yanit.prefix(100))")
        #expect(b.yanit.localizedCaseInsensitiveContains("kazanım"), "yanıt: \(b.yanit)")
    }

    @Test(.timeLimit(.minutes(5)))
    func gecmisSohbettenBilgiBulunur() async throws {
        let depo = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let eski = depo.sohbetOlustur()
        depo.ekle(.kullanici, "Ankara'daki toplantıda proje bütçesini 450 bin lira olarak belirledik.", sohbet: eski)
        depo.ekle(.asistan, "Not aldım: proje bütçesi 450 bin lira.", sohbet: eski)
        let r = try await sor(beyin(depo: depo), "Geçen konuşmamızda Ankara toplantısında bütçeyi ne belirlemiştik?")
        print("HERMES gecmis \(String(format: "%.1f", r.sn)) sn: \(r.yanit.prefix(120))")
        #expect(r.yanit.contains("450"), "yanıt: \(r.yanit)")
    }

    @Test(.timeLimit(.minutes(5)))
    func altAjanlarParalelCalisir() async throws {
        let b = beyin()
        let r = try await sor(b, "Üç şehrin yaklaşık nüfusunu aynı anda öğren: İstanbul, Ankara, İzmir. altAjanlar aracını kullan, sonucu kısa bir listede ver.", sinir: 120)
        print("HERMES altajan \(String(format: "%.1f", r.sn)) sn adimlar=\(b.gorevler.adimlar.map(\.ad)): \(r.yanit.prefix(200))")
        #expect(b.gorevler.adimlar.contains { $0.ad == "Alt ajanlar" }, "altAjanlar çağrılmadı: \(b.gorevler.adimlar.map(\.ad))")
        #expect(["İstanbul", "Ankara", "İzmir"].allSatisfy { r.yanit.contains($0) }, "yanıt: \(r.yanit)")
    }

    @Test(.timeLimit(.minutes(5)), .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_MCP_TEST_URL"] != nil))
    func mcpSunucusuAraciKullanilir() async throws {
        let ad = "kutuphane-test-" + UUID().uuidString.lowercased()
        let adres = try #require(ProcessInfo.processInfo.environment["ASISTAN_MCP_TEST_URL"])
        #expect(McpKaydi.ortak.ekle(ad: ad, url: adres))
        let kimlik = try #require(McpKaydi.ortak.sunucular.first { $0.ad == ad }?.id)
        defer { McpKaydi.ortak.sil(kimlik) }
        let r = try await sor(beyin(onay: true), "\(ad) MCP sunucusunda Simyacı kitabını ara ve raf bilgisini söyle.")
        print("HERMES mcp \(String(format: "%.1f", r.sn)) sn: \(r.yanit.prefix(160))")
        #expect(r.yanit.contains("12-B"), "yanıt: \(r.yanit)")
    }
}

/// OpenClaw/Hermes'ten gelen ek özellikler: gerçek modelle uçtan uca. ASISTAN_CANLI=1 ile.
@Suite("Ek ajan özellikleri canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct EkAjanCanliTestleri {
    private func beyin(onay: Bool = true) -> Beyin {
        let ud = UserDefaults(suiteName: "ek.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud)
        ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = onay
        return Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
    }
    private func sor(_ b: Beyin, _ metin: String, sinir: Double = 90) async throws -> (yanit: String, sn: Double) {
        let t = Date()
        b.gonder(metin)
        try await Task.sleep(for: .milliseconds(300))
        while b.durum != .bosta, Date().timeIntervalSince(t) < sinir { try await Task.sleep(for: .milliseconds(200)) }
        return (b.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? "[YANIT YOK: \(b.sonHata.map { "\($0)" } ?? "-")]", Date().timeIntervalSince(t))
    }
    private func gecici() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ek-\(UUID().uuidString)")
        CalismaAlani.kok = u; BeceriDeposu.kok = u.appendingPathComponent("beceri"); return u
    }

    @Test(.timeLimit(.minutes(5)))
    func calismaAlaniYazilirVeSonrakiOturumdaUygulanir() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        let a = try await sor(beyin(), "Bundan sonra bana hep 'Mehmet Hocam' diye hitap et. Bunu çalışma alanında AGENTS dosyasına kaydet. Ayrıca ben biyoloji öğretmeniyim, bunu USER dosyasına ekle.")
        print("EK calisma-yaz \(String(format: "%.1f", a.sn)) sn: \(a.yanit.prefix(100))")
        #expect(CalismaAlani.oku(.agents).localizedCaseInsensitiveContains("Hocam"), "AGENTS: \(CalismaAlani.oku(.agents))")
        #expect(CalismaAlani.oku(.user).localizedCaseInsensitiveContains("biyoloji"), "USER: \(CalismaAlani.oku(.user))")
        let b = try await sor(beyin(), "Merhaba, günaydın!")
        print("EK calisma-uygula: \(b.yanit.prefix(100))")
        #expect(b.yanit.localizedCaseInsensitiveContains("Hocam"), "yanıt: \(b.yanit)")
    }

    @Test(.timeLimit(.minutes(5)))
    func onaysizSOULDegismez() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        _ = try await sor(beyin(onay: false), "Kişiliğini değiştir: SOUL dosyasına 'Her cümleyi ünlemle bitir' yaz.")
        #expect(CalismaAlani.oku(.soul).isEmpty, "onay verilmediği hâlde SOUL değişti: \(CalismaAlani.oku(.soul))")
    }

    @Test(.timeLimit(.minutes(5)))
    func webSayfasiOkunur() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        let r = try await sor(beyin(), "Bu gerçek bir adres, webSayfaOku aracıyla oku: https://example.com — sayfanın başlığını söyle.")
        print("EK web \(String(format: "%.1f", r.sn)) sn: \(r.yanit.prefix(120))")
        #expect(r.yanit.localizedCaseInsensitiveContains("Example Domain"), "yanıt: \(r.yanit)")
    }

    @Test(.timeLimit(.minutes(5)))
    func toplulukBecerisiOnayliIceAktarilir() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        let r = try await sor(beyin(), "Şu topluluk becerisini içe aktar: https://github.com/anthropics/skills/blob/main/skills/pdf/SKILL.md")
        print("EK iceaktar \(String(format: "%.1f", r.sn)) sn: \(r.yanit.prefix(120))")
        #expect(BeceriDeposu.oku("pdf") != nil, "beceri eklenmedi: \(r.yanit)")
        let red = gecici(); defer { try? FileManager.default.removeItem(at: red) }
        _ = try await sor(beyin(onay: false), "Şu becerisini içe aktar: https://github.com/anthropics/skills/blob/main/skills/docx/SKILL.md")
        #expect(BeceriDeposu.oku("docx") == nil, "onaysız beceri eklendi")
    }

    @Test(.timeLimit(.minutes(5)))
    func planKurulur() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        PlanDefteri.ortak.temizle()
        let r = try await sor(beyin(), "Şu işi plan aracıyla adım adım yönet: 1) İstanbul'un nüfusunu öğren 2) Ankara'nın nüfusunu öğren 3) ikisini karşılaştır. Adımlar bittikçe planı güncelle, sonda sonucu söyle.", sinir: 120)
        print("EK plan \(String(format: "%.1f", r.sn)) sn: plan=\(PlanDefteri.ortak.metin.replacingOccurrences(of: "\n", with: " | ")) yanıt=\(r.yanit.prefix(80))")
        #expect(PlanDefteri.ortak.maddeler.count >= 3, "plan kurulmadı")
    }

    @Test(.timeLimit(.minutes(5)))
    func yanitlarDuzgunTurkceVeSadeBicimde() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        for soru in ["Gs maçı", "Fenerbahçe'nin bir sonraki maçı ne zaman?", "Fotosentezi kısaca anlat.", "Bana üç öğrenme tekniği öner."] {
            let r = try await sor(beyin(), soru, sinir: 120)
            print("BICIM [\(soru)] \(String(format: "%.1f", r.sn)) sn:\n\(r.yanit)\n---")
            // Ekrandaki yanıt `YanitBicimi.duzelt(zengin: true)` ile saklanır: kalın/başlık/liste ZenginMetin'de çizilir (kullanıcı
            // yıldız görmez). Sözleşme: bağlantı/URL/utm yok, kalın işaretleri kapanmış; düz biçimde (ses, Siri) hiç işaret kalmaz.
            #expect(!r.yanit.contains("](") && !r.yanit.contains("http") && !r.yanit.contains("utm_"), "\(soru): \(r.yanit)")
            #expect(r.yanit.components(separatedBy: "**").count % 2 == 1, "kapanmamış kalın: \(r.yanit)")
            #expect(!YanitBicimi.duzelt(r.yanit).contains("**"), "düz biçimde kalın kaldı: \(r.yanit)")
            #expect(!YanitBicimi.emojiTemizle(r.yanit).isEmpty && YanitBicimi.emojiTemizle(r.yanit) == r.yanit, "emoji var: \(r.yanit)")
            #expect(r.yanit.components(separatedBy: "Kaynak").count <= 2, "kaynak tekrarı: \(r.yanit)")
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func slashKomutlariYerelCalisir() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        let b = beyin()
        let d = try await sor(b, "/durum", sinir: 10)
        #expect(d.yanit.contains("Model:") && d.yanit.contains("Nabız:"), "yanıt: \(d.yanit)")
        #expect(d.sn < 2, "slash komutu modele gitmemeli (\(d.sn) sn)")
        let y = try await sor(b, "/yardim", sinir: 10)
        #expect(y.yanit.contains("/sikistir"))
        let m = try await sor(b, "/model", sinir: 10)
        #expect(m.yanit.contains("Otomatik"), "yanıt: \(m.yanit)")
    }

    @Test(.timeLimit(.minutes(3)))
    func nabizKontrolListesiniDegerlendirir() async throws {
        let k = gecici(); defer { try? FileManager.default.removeItem(at: k) }
        try CalismaAlani.yaz(.heartbeat, "- Önümüzdeki 24 saatte takvimde çakışma var mı?\n- Bugün bitmesi gereken hatırlatıcı kaldı mı?")
        await TelefonProxy.ortak.hazirla()
        let s = await NabizMotoru.calistir(bildir: false)
        print("EK nabiz hata=\(s.hata ?? "-") uyari=\(s.uyari ?? "yok")")
        #expect(s.hata == nil, "nabız hatası: \(s.hata ?? "")")
        #expect(NabizMotoru.sonSonuc()?.zaman == s.zaman)
    }
}


/// Fotoğraflı zor soru Opus ile çözülür. Yalnız yerel soru görüntüsü varsa koşar.
@Suite("Zor soru canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct ZorSoruCanliTestleri {
    @Test(.timeLimit(.minutes(5)))
    func fotografliTestSorusuOpusIleCozulur() async throws {
        let yol = "/Users/mehmetderin/.claude/uploads/20b4d2d3-8c9d-4917-b81d-a65b19410d3c/ba7dd95b-image.png"
        guard let ui = UIImage(contentsOfFile: yol), let cg = ui.cgImage else { return }
        let ud = UserDefaults(suiteName: "zor.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud)
        ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
        let t = Date()
        b.gonder("Bu fotoğrafta ne var?", gorsel: cg)
        try await Task.sleep(for: .milliseconds(300))
        while b.durum != .bosta, Date().timeIntervalSince(t) < 120 { try await Task.sleep(for: .milliseconds(200)) }
        let son = b.mesajlar.last(where: { $0.rol == .asistan })
        print("ZOR \(String(format: "%.1f", Date().timeIntervalSince(t))) sn model=\(son?.model ?? "?") caba=\(son?.caba ?? "-") yanıt=\(son?.metin.prefix(260) ?? "yok")")
        #expect(son?.model == "claude-fable-5-1", "model: \(son?.model ?? "?")")
        #expect(son?.caba == "Yüksek")
        #expect(son?.metin.localizedCaseInsensitiveContains("bakteri") == true || son?.metin.contains("III") == true, "soru çözülmedi: \(son?.metin ?? "")")
    }
}

/// Yerel proxy sunucusu iOS tarafından kapatılırsa kendini onarır. ASISTAN_CANLI=1 ile.
@Suite("Yerel sunucu onarımı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct YerelSunucuOnarimTestleri {
    @Test(.timeLimit(.minutes(3)))
    func olenSunucuYenidenKurulurVeIstekBasarili() async throws {
        let p = TelefonProxy.ortak
        await p.hazirla()
        try #require(p.hazir, "proxy hazır değil (hesap/keychain)")
        #expect(await p.sunucuCanliMi())
        p.sunucuyuOldurTest()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!(await p.sunucuCanliMi()), "sunucu ölü görünmeli")
        // Gerçek kullanım: sonraki hazirla() ölüyü fark edip yeniden kurar.
        await p.zorlaDogrula()
        #expect(await p.sunucuCanliMi(), "sunucu yeniden kurulmalı")
        // Ve bir model isteği çalışır.
        let ud = UserDefaults(suiteName: "onarim.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.otomatikModel = true; ayarlar.caba = "auto"
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
        p.sunucuyuOldurTest()
        b.gonder("Merhaba, nasılsın?")
        try await Task.sleep(for: .milliseconds(300))
        let t = Date()
        while b.durum != .bosta, Date().timeIntervalSince(t) < 60 { try await Task.sleep(for: .milliseconds(200)) }
        let son = b.mesajlar.last(where: { $0.rol == .asistan })
        print("ONARIM \(String(format: "%.1f", Date().timeIntervalSince(t))) sn hata=\(b.sonHata.map { "\($0)" } ?? "-") yanıt=\(son?.metin.prefix(60) ?? "YOK")")
        #expect(son != nil && b.sonHata == nil, "ölü sunucuda istek başarısız: \(b.sonHata.map { "\($0)" } ?? "")")
    }
}

/// 14/5/16/17/26 canlı: yeniden üretim, ders programı, konumlu hatırlatıcı, Siri, anlamsal arama. ASISTAN_CANLI=1 ile.
@Suite("Yeni özellikler canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct YeniOzelliklerCanliTestleri {
    private func beyin() -> Beyin {
        let ud = UserDefaults(suiteName: "yeni.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = true
        return Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
    }
    private func bekle(_ b: Beyin, _ sinir: Double = 120) async throws -> Double {
        let t = Date(); try await Task.sleep(for: .milliseconds(300))
        while b.durum != .bosta, Date().timeIntervalSince(t) < sinir { try await Task.sleep(for: .milliseconds(200)) }
        return Date().timeIntervalSince(t)
    }

    @Test(.timeLimit(.minutes(4))) func baskaModelleYenidenUretilir() async throws {
        let b = beyin()
        b.gonder("Fotosentezi tek cümleyle açıkla.")
        _ = try await bekle(b)
        let ilk = try #require(b.mesajlar.last(where: { $0.rol == .asistan }))
        b.yenidenUret(ilk.id, model: "claude-opus-5-5")
        let sn = try await bekle(b)
        let son = try #require(b.mesajlar.last(where: { $0.rol == .asistan }))
        print("YENI yeniden-uret ilk=\(ilk.model ?? "?") yeni=\(son.model ?? "?") \(String(format: "%.1f", sn)) sn kullanıcı=\(b.mesajlar.last(where: { $0.rol == .kullanici })?.metin ?? "")")
        #expect(son.id != ilk.id); #expect(son.model == "claude-opus-5-5")
        #expect(b.mesajlar.last(where: { $0.rol == .kullanici })?.metin.hasPrefix("↻") == true)
        #expect(b.zorlananModel == nil, "zorlanan model yanıttan sonra temizlenmeli")
    }

    // Yalnız ayrılmış test takvimi/hesabı hazırlanmış ortamda çalıştırılır.
    @Test(.timeLimit(.minutes(5)), .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_TAKVIM_TEST"] == "1"))
    func dersProgramiTakvimeHaftalikKurulur() async throws {
        let k = FileManager.default.temporaryDirectory.appendingPathComponent("dp-\(UUID().uuidString)")
        BeceriDeposu.kok = k; defer { try? FileManager.default.removeItem(at: k) }
        let alan = "dp.\(UUID().uuidString)"; BeceriDeposu.hazirBecerileriYukle(UserDefaults(suiteName: alan)!)
        let depo = EKEventStore()
        _ = try await depo.requestFullAccessToEvents()
        let isaret = "UITEST-" + UUID().uuidString
        let b = beyin()
        b.gonder("Ders programım: Pazartesi 08:30-09:10 \(isaret) 9B Biyoloji, Çarşamba 10:00-10:40 \(isaret) 10A Biyoloji. Bu ders programını takvime kur, her hafta tekrarlasın, 2 dakika önce uyarsın.")
        let sn = try await bekle(b, 150)
        print("YENI ders-programi \(String(format: "%.1f", sn)) sn: \(b.mesajlar.last(where: { $0.rol == .asistan })?.metin.prefix(200) ?? "yok") adimlar=\(b.gorevler.adimlar.map(\.ad))")
        let p = depo.predicateForEvents(withStart: Date().addingTimeInterval(-86_400), end: Date().addingTimeInterval(21 * 86_400), calendars: nil)
        let olaylar = depo.events(matching: p).filter { ($0.title ?? "").contains(isaret) }   // yalnız bu koşunun kayıtları
        print("YENI takvim: \(olaylar.count) örnek, tekrar=\(olaylar.first?.recurrenceRules?.first?.frequency.rawValue ?? -1), uyarı=\(olaylar.first?.alarms?.first?.relativeOffset ?? 0)")
        #expect(Set(olaylar.compactMap(\.title)).count == 2, "iki ders eklenmeli")
        #expect(olaylar.count >= 4, "3 haftada her ders en az 2 kez görünmeli (haftalık tekrar): \(olaylar.count)")
        #expect(olaylar.first?.alarms?.first?.relativeOffset == -120)
        for e in Dictionary(grouping: olaylar, by: { $0.title ?? "" }).values.compactMap(\.first) { try? depo.remove(e, span: .futureEvents, commit: false) }
        try? depo.commit()
    }

    @Test(.timeLimit(.minutes(4))) func konumluHatirlaticiKurulur() async throws {
        let depo = EKEventStore(); _ = try await depo.requestFullAccessToReminders()
        let isaret = "UITEST-dilekce-\(Int.random(in: 1000...9999))"
        let b = beyin()
        b.gonder("Beykoz Kaymakamlığı'na varınca bana \(isaret) vermeyi hatırlat.")
        _ = try await bekle(b)
        print("YENI konum: \(b.mesajlar.last(where: { $0.rol == .asistan })?.metin.prefix(200) ?? "yok")")
        let kutu: HatirlaticiKutusu = await withCheckedContinuation { c in
            depo.fetchReminders(matching: depo.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { r in
                c.resume(returning: HatirlaticiKutusu(l: r ?? []))   // süzme ana iş parçacığında
            }
        }
        let liste = kutu.l.filter { ($0.title ?? "").contains(isaret) }
        let alarm = liste.first?.alarms?.first
        print("YENI konum-alarm: yer=\(alarm?.structuredLocation?.title ?? "yok") yakınlık=\(alarm?.proximity.rawValue ?? -1) koord=\(alarm?.structuredLocation?.geoLocation?.coordinate.latitude ?? 0)")
        #expect(alarm?.proximity == .enter); #expect(alarm?.structuredLocation?.geoLocation != nil)
        for r in liste { try? depo.remove(r, commit: false) }; try? depo.commit()
    }

    @Test(.timeLimit(.minutes(3))) func siriUygulamaAcmadanYanitlar() async throws {
        let d = HafizaDeposu(baglam: HafizaTestleri.kap.mainContext)
        let ud = UserDefaults(suiteName: "siri.\(UUID().uuidString)")!
        let t = Date()
        let r = await SiriYanitlayici.yanitla("Fotosentezi tek cümleyle açıkla.", depo: d, ayarlar: Ayarlar(defaults: ud))
        print("YENI siri \(String(format: "%.1f", Date().timeIntervalSince(t))) sn: \(r)")
        guard case .yanit(let m) = r else { Issue.record("yanıt gelmedi: \(r)"); return }
        #expect(["fotosentez", "ışı", "güneş", "bitki"].contains { m.localizedCaseInsensitiveContains($0) }, "yanıt: \(m)")
        #expect(await SiriYanitlayici.yanitla("Yarın sabah 7'ye alarm kur", depo: d, ayarlar: Ayarlar(defaults: ud)) == .uygulamada)
        #expect(d.sonSohbetler(3).contains { $0.mesajlar.contains { $0.metin.hasPrefix("🎙️") } }, "Siri sorusu geçmişe kaydedilmeli")
    }

    }

nonisolated struct HatirlaticiKutusu: @unchecked Sendable { let l: [EKReminder] }

@Suite("Takvim doğrudan", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct TakvimDogrudanTestleri {
    @Test func etkinlikKurulurKaydedilirBulunur() async throws {
        let depo = EKEventStore()
        let izin = try await depo.requestFullAccessToEvents()
        print("TAKVIM izin=\(izin) varsayilan=\(depo.defaultCalendarForNewEvents?.title ?? "YOK")")
        try #require(izin)
        let isaret = "TDT\(Int.random(in: 1000...9999))"
        let bas = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let e = TakvimAraci.etkinlikKur(depo, baslik: isaret, bas: bas, bit: bas.addingTimeInterval(2400), haftalik: true, tekrarBitis: bas.addingTimeInterval(21 * 86_400), uyariDakika: 2)
        try depo.save(e, span: .futureEvents, commit: true)
        let p = depo.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(30 * 86_400), calendars: nil)
        let bulunan = depo.events(matching: p).filter { $0.title == isaret }
        print("TAKVIM bulunan=\(bulunan.count)")
        #expect(bulunan.count >= 3)
        for x in bulunan.prefix(1) { try? depo.remove(x, span: .futureEvents, commit: true) }
    }
}


/// Gerçek cihazda: Live Activity açılır/kapanır, anlamsal gömleme çalışır.
@Suite("Cihaz özellikleri", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct CihazOzellikleriTestleri {
    @Test(.timeLimit(.minutes(4))) func uzunIsteLiveActivityAcilirVeKapanir() async throws {
        let ud = UserDefaults(suiteName: "la.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
        b.gonder("Fenerbahçe'nin bir sonraki maçı ne zaman? Önce araştır sonra özetle.")
        var enCok = 0
        let t = Date()
        while Date().timeIntervalSince(t) < 90 {
            try await Task.sleep(for: .milliseconds(500))
            enCok = max(enCok, IsAktivitesi.acikSayisi)
            if b.durum == .bosta, Date().timeIntervalSince(t) > 1 { break }
        }
        let sure = Date().timeIntervalSince(t)
        print("CIHAZ liveactivity sure=\(String(format: "%.1f", sure)) enCok=\(enCok) izin=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        try await Task.sleep(for: .seconds(1.5))
        if sure > IsAktivitesi.esikSn + 2 { #expect(enCok >= 1, "\(sure) sn süren istekte Live Activity açılmalı") }
        #expect(!b.isAktivitesi.acik, "bitince kapanmalı")
    }

    }


@Suite("Antigravity yarış ölçümü", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct AntigravityYarisOlcumTestleri {
    @Test(.timeLimit(.minutes(4))) func yarisSureleri() async throws {
        await TelefonProxy.ortak.hazirla()
        let taban = TelefonProxy.ortak.taban, anahtar = TelefonProxy.ortak.yerelAnahtar
        let adaylar = ["antigravity-claude-sonnet-5-5-low", "antigravity-gemini-3-flash", "antigravity-gemini-3.8-flash-tiered", "antigravity-claude-opus-5-5-low"]
        for soru in ["Merhaba nasılsın?", "Fotosentezi iki cümleyle açıkla.", "Bana kısa bir fıkra anlat."] {
            for m in adaylar {
                let t = Date()
                var r: ParalelYaris.Sonuc?; var hata = ""
                do { r = try await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: [m], sistem: "Türkçe, kısa yanıtla.", mesajlar: [.init(rol: "user", metin: soru)]) { _, _ in } } catch { hata = "\(error)" }
                print("ANTIYARIS hata=\(hata.prefix(200)) taban=\(taban) hazir=\(TelefonProxy.ortak.hazir)")
                print("ANTIYARIS tek \(m) ilk=\(String(format: "%.2f", r?.ilkSn ?? -1)) toplam=\(String(format: "%.2f", Date().timeIntervalSince(t))) | \(r?.metin.prefix(40) ?? "HATA")")
            }
            let t = Date()
            let r = try? await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: Array(adaylar.prefix(3)), sistem: "Türkçe, kısa yanıtla.", mesajlar: [.init(rol: "user", metin: soru)]) { _, _ in }
            print("ANTIYARIS paralel(3 antigravity) kazanan=\(r?.model ?? "-") ilk=\(String(format: "%.2f", r?.ilkSn ?? -1)) toplam=\(String(format: "%.2f", Date().timeIntervalSince(t)))")
        }
    }
}

@Suite("Live Claude canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct LiveClaudeCanliTestleri {
    @Test(.timeLimit(.minutes(4))) func liveYalnizClaudeIleYanitlar() async throws {
        let ud = UserDefaults(suiteName: "liveclaude.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        #expect(ayarlar.canliClaude)
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
        for soru in ["Fotosentezi bir cümleyle açıkla.", "Beykoz'da hava nasıl?"] {
            let t = Date(); b.gonder(soru, canliSes: true)
            try await Task.sleep(for: .milliseconds(300))
            while b.durum != .bosta, Date().timeIntervalSince(t) < 90 { try await Task.sleep(for: .milliseconds(200)) }
            let son = b.mesajlar.last(where: { $0.rol == .asistan })
            print("LIVECLAUDE [\(soru)] \(String(format: "%.1f", Date().timeIntervalSince(t))) sn model=\(son?.model ?? "?") hata=\(b.sonHata ?? "-") | \(son?.metin.prefix(70) ?? "yok")")
            #expect(son?.model?.contains("claude") == true, "Live Claude kullanmalı: \(son?.model ?? "?")")
        }
    }
}

/// Telefonun Keychain'inde OpenAI anahtarı varsa gerçek Realtime oturumunu mikrofonsuz doğrular; yoksa atlanır.
@Suite("OpenAI Realtime canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct OpenAIRealtimeCanliTestleri {
    @Test(.timeLimit(.minutes(3))) func metinleSesliYanitAlir() async throws {
        await TelefonProxy.ortak.hazirla()
        guard OpenAIAnahtari.var_ else { print("OAILIVE anahtar yok: atlandı"); return }
        print("OAILIVE anahtar kaynağı=\(OpenAIAnahtari.kaynak)")
        let l = OpenAIRealtimeLive(mikrofonlu: false)
        let t = Date()
        let ok = await l.baslat()
        print("OAILIVE baglanti=\(ok) \(String(format: "%.2f", Date().timeIntervalSince(t))) sn durum=\(l.durum)")
        try #require(ok, "bağlanamadı: \(l.durum) \(l.sonBaglantiHatasi ?? "")")
        let g = Date()
        try await l.metinGonder("Fotosentezi tek cümleyle açıkla.")
        while l.yanitSayisi == 0, Date().timeIntervalSince(g) < 40 { try await Task.sleep(for: .milliseconds(100)) }
        print("OAILIVE yanıt=\(String(format: "%.2f", Date().timeIntervalSince(g))) sn ses=\(l.alinanSesBayt) bayt metin=\(l.yanitMetni.prefix(90))")
        l.kapat()
        #expect(l.alinanSesBayt > 10_000, "sesli yanıt gelmeli"); #expect(!l.yanitMetni.isEmpty, "transkript gelmeli")
    }
}

@Suite("Kasa denetimi", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct KasaDenetimTestleri {
    @Test(.timeLimit(.minutes(2))) func apiSaglayicilari() async throws {
        await TelefonProxy.ortak.hazirla()
        let durum = await TelefonProxy.ortak.kasa.state
        for p in durum.apiProviders {
            print("KASA api: ad=\(p.name) tur=\(p.kind.rawValue) adres=\(p.baseURL) etkin=\(p.enabled) anahtarVar=\(!p.apiKey.isEmpty) model=\(p.models.prefix(4))")
        }
        print("KASA api sayısı=\(durum.apiProviders.count) oauth=\(durum.oauth.map { "\($0.provider.rawValue):\($0.enabled)" })")
    }
}

@Suite("OpenAI TTS canlı", .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct OpenAITTSCanliTestleri {
    @Test(.timeLimit(.minutes(3))) func sesUretilirVeCalinabilir() async throws {
        await TelefonProxy.ortak.hazirla()
        for id in ["openai:marin", "openai:cedar"] {
            let t = Date()
            let v = try await AsistanSesleri.ses("Merhaba Mehmet, bugün sana nasıl yardımcı olabilirim?", kimlik: id)
            let oynatici = try AVAudioPlayer(data: v)
            print("OAITTS \(id) \(String(format: "%.2f", Date().timeIntervalSince(t))) sn \(v.count) bayt süre=\(String(format: "%.1f", oynatici.duration)) sn")
            #expect(oynatici.duration > 1.5 && oynatici.duration < 8)
        }
    }
}

@Suite("Zengin biçim canlı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1"))
@MainActor
struct ZenginBicimCanliTestleri {
    @Test(.timeLimit(.minutes(4))) func kisaSohbetDuzTabloIstenincGercekTablo() async throws {
        let ud = UserDefaults(suiteName: "zb.\(UUID().uuidString)")!
        let ayarlar = Ayarlar(defaults: ud); ayarlar.otomatikModel = true; ayarlar.caba = "auto"; ayarlar.webArama = true
        let k = OnayKapisi(); k.otomatikKarar = false
        let b = Beyin(ayarlar: ayarlar, depo: HafizaDeposu(baglam: HafizaTestleri.kap.mainContext), onay: k)
        for (soru, tabloBeklenir) in [("Merhaba, bugün nasılsın?", false), ("Fotosentez ile hücresel solunumu üç özellik üzerinden tablo olarak karşılaştır.", true),
                                      ("Python'da 1'den 5'e kadar sayıları yazdıran kısa bir kod ver.", false)] {
            let t = Date(); b.gonder(soru)
            try await Task.sleep(for: .milliseconds(300))
            while b.durum != .bosta, Date().timeIntervalSince(t) < 90 { try await Task.sleep(for: .milliseconds(200)) }
            let y = b.mesajlar.last(where: { $0.rol == .asistan })?.metin ?? ""
            let bloklar = ZenginAyristirici.ayristir(y)
            let tablo = bloklar.contains { if case .tablo = $0 { true } else { false } }
            let kod = bloklar.contains { if case .kod = $0 { true } else { false } }
            let baslik = bloklar.contains { if case .baslik = $0 { true } else { false } }
            print("ZENGIN [\(soru.prefix(40))] tablo=\(tablo) kod=\(kod) baslik=\(baslik) bloklar=\(bloklar.count) uzunluk=\(y.count)")
            #expect(tablo == tabloBeklenir, "tablo beklentisi: \(y.prefix(300))")
            #expect(!y.contains("**") || tabloBeklenir || y.count > 300, "kısa sohbette kalın kullanılmamalı: \(y.prefix(200))")
            if soru.hasPrefix("Python") { #expect(kod, "kod ``` çitli blokta olmalı: \(y.prefix(300))") }
            if soru.hasPrefix("Merhaba") { #expect(!baslik && !tablo, "kısa sohbet düz kalmalı: \(y)") }
        }
    }
}
