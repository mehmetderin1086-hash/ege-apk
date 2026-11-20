import Foundation
import Testing
@testable import Asistan

// Bu dosyadaki ağa çıkan takımlar yalnız ASISTAN_CANLI=1 ile koşar (CanliTestleri.swift ile aynı kapı);
// varsayılan birim test koşusu ağa, YouTube'a ve Python motoruna bağlı kalmasın. Ağsız yardımcılar en alttaki takımda.

/// Gerçek ağla uçtan uca (kazıma + indirme). Ağ yoksa sonuç anlamsızdır.
@Suite("Canlı kazıma ve indirme", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct AgCanliTestleri {
    @Test func gercekSayfadanTabloKazinir() async throws {
        EkDefteri.ortak.temizle()
        let a = VeriKaziAraci.Arguments(islem: "tablo", adres: "https://en.wikipedia.org/wiki/List_of_countries_and_dependencies_by_population", ayrinti: "", sayfa: 1, tarayici: false)
        let sonuc = try await VeriKaziAraci().call(arguments: a)
        print("KAZIMA:", sonuc.prefix(300))
        #expect(sonuc.contains("satır ×"), "tablo çıkarılmalı")
        let ekler = EkDefteri.ortak.al()
        guard case .tablo(_, let s, let r, _, let d)? = ekler.first?.tur else { Issue.record("tablo kartı yok"); return }
        #expect(s.count >= 3 && r.count >= 100)
        #expect(d.map { FileManager.default.fileExists(atPath: $0.path) } == true, "Excel kaydedildi")
    }
    @Test func gercekDosyaIndirilirVeOkunur() async throws {
        EkDefteri.ortak.temizle()
        let ekle = IndirmeAraci.Arguments(islem: "ekle", deger: "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf", tur: "file")
        let s1 = try await IndirmeAraci().call(arguments: ekle)
        print("INDIR:", s1)
        guard let r = s1.range(of: #"Kimlik: ([0-9A-F-]{36})"#, options: .regularExpression) else { Issue.record("kimlik yok: \(s1)"); return }
        let id = String(s1[r].dropFirst(8))
        if case .indirme? = EkDefteri.ortak.bekleyen.first?.tur {} else { Issue.record("indirme kartı eklenmedi") }
        let s2: String
        do { s2 = try await IndirmeAraci().call(arguments: .init(islem: "bekle", deger: id, tur: "file")) }
        catch { if let u = UUID(uuidString: id) { await AdlaIndirmeCanliTestleri.temizle(u) }; throw error }
        print("BEKLE:", s2.prefix(300))
        #expect(s2.hasPrefix("İndirildi"), "indirme tamamlanmalı")
        #expect(s2.lowercased().contains("dummy"), "PDF metni okunmalı")
        // Test kaydı ve dosyası Documents/Indirmeler'de birikmesin.
        if let u = UUID(uuidString: id) { await AdlaIndirmeCanliTestleri.temizle(u) }
    }
}

@Suite("Canlı müzik arama", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct MuzikAramaTestleri {
    @Test func appleMusicAramasiOnizlemeKartiVerir() async throws {
        EkDefteri.ortak.temizle()
        let s = try await MuzikAraci().call(arguments: .init(islem: "ara", sorgu: "Dua Lipa Levitating"))
        print("MUZIK:", s.prefix(200))
        #expect(s.contains("Dua Lipa"))
        let ekler = EkDefteri.ortak.al()
        #expect(ekler.contains { if case .medya(let m) = $0.tur { m.contains { $0.tur == .ses } } else { false } }, "30 sn önizleme kartı")
        #expect(ekler.contains { if case .kaynaklar(let k) = $0.tur { k.contains { $0.contains("music.apple.com") } } else { false } }, "Apple Music bağlantısı")
    }
}

@Suite("Canlı İETT", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct IettKonumCanliTestleri {
}

@Suite("İndirme araması süre sınırı", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct IndirmeBulSureTestleri {
    @Test func gercekBulIslemiSinirIcindeBiter() async throws {
        let bas = Date()
        let s = try await IndirmeAraci().call(arguments: .init(islem: "bul", deger: "Dua Lipa resim", tur: "png"))
        print("BUL:", Date().timeIntervalSince(bas), s.prefix(160))
        #expect(Date().timeIntervalSince(bas) < 75, "bul işlemi donmamalı")
    }
}

/// Gömülü Kepçe motoru: gerçek YouTube videosu çözülür, indirilir, birleştirilir.
@Suite("Canlı motorlu indirme", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct MotorluIndirmeCanliTestleri {
    @Test func youtubeSesiIndirilir() async throws {
        let k = IndirmeYoneticisi.ortak
        let id = try k.motorluEkle("https://www.youtube.com/watch?v=jNQXAC9IVRw", tur: "audio")   // "Me at the zoo", 19 sn
        // Kimlik alındıktan sonra temizliğe kadar fırlatan satır yok: başarısız/süren kayıt ve MotorIsleri klasörü birikmesin.
        do {
            for _ in 0..<120 {
                if let kayit = k.kayitlar.first(where: { $0.id == id }), !kayit.etkin { break }
                try await Task.sleep(for: .seconds(1))
            }
        } catch { await AdlaIndirmeCanliTestleri.temizle(id); throw error }
        if let kayit = k.kayitlar.first(where: { $0.id == id }) {
            print("MOTOR:", kayit.durum, kayit.ad, kayit.dosya ?? "-", kayit.hata ?? "-")
            #expect(kayit.durum == "done", "hata: \(kayit.hata ?? "-")")
            if let dosya = k.dosyaURL(kayit) {
                #expect((try? dosya.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 50_000)
            } else { Issue.record("indirilen dosya yok: \(kayit.hata ?? kayit.durum)") }
        } else { Issue.record("indirme kaydı bulunamadı") }
        await AdlaIndirmeCanliTestleri.temizle(id)
    }
}

@Suite("Canlı yedek arama", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct YedekAramaCanliTestleri {
    @Test func duckduckgoSonucVerir() async throws {
        let s = try await YedekArama.ara("Trabzonspor canlı skor", sayfa: 1)
        print("YEDEK:", s.prefix(400))
        #expect(s.contains("Arama sonuçları:") && s.contains("Kaynaklar:"))
        #expect(EkDefteri.kaynaklar(s).count >= 2)
    }
}

@Suite("Canlı motor teşhis", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct MotorTeshisTestleri {
    /// İki YouTube videosu çözülmeli, biçim listesi dolu gelmeli ve 1080p'ye kadar bir video planı kurulabilmeli.
    @Test func houdiniCozumu() async throws {
        for adres in ["https://www.youtube.com/watch?v=suAR1PYFNYA", "https://www.youtube.com/watch?v=WEDoZm14cJs"] {
            let b = try await PythonMotoru.shared.coz(adres)
            let k = BicimSecici.kaliteler(b)
            let plan = BicimSecici.plan(b, tur: .video, enFazla: 1080)
            print("TESHIS", adres, b.title ?? "-", "biçim:", b.formats?.count ?? 0, "kalite:", k.map(\.etiket), "ses:", BicimSecici.sesler(b).count, "plan:", plan?.etiket ?? "nil")
            #expect(b.formats?.isEmpty == false, "biçim listesi boş: \(adres)")
            #expect(plan != nil, "video planı kurulamadı: \(adres)")
        }
    }
}

@Suite("Canlı adla indirme", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ASISTAN_CANLI"] == "1")) @MainActor
struct AdlaIndirmeCanliTestleri {
    @Test func adVerinceYoutubedeAranirVeInmeyeBaslar() async throws {
        EkDefteri.ortak.temizle()
        let s = try await IndirmeAraci().call(arguments: .init(islem: "ekle", deger: "Me at the zoo jawed karim", tur: "audio"))
        print("ADLA:", s.prefix(200))
        #expect(s.contains("Kimlik:"), "\(s)")
        // Başlatılan indirme kalıcı kuyrukta birikmesin: iptal et, kaydı ve dosyayı sil.
        if let r = s.range(of: #"Kimlik: ([0-9A-F-]{36})"#, options: .regularExpression), let id = UUID(uuidString: String(s[r].dropFirst(8))) {
            await Self.temizle(id)
        } else { Issue.record("kimlik ayıklanamadı: \(s.prefix(200))") }
    }

    /// Test indirmesini durdurur, kaydını ve dosyasını kaldırır. `sil` etkin kaydı silmediği için kayıt iptalden SONRA yeniden okunur.
    static func temizle(_ id: UUID) async {
        let k = IndirmeYoneticisi.ortak
        await k.iptal(id)
        if let kayit = k.kayitlar.first(where: { $0.id == id }) { k.sil(kayit) }
    }
}

/// Ağsız indirme/kazıma yardımcıları: kapısız, her birim test koşusunda çalışır.
@Suite("Ağsız indirme ve kazıma yardımcıları") @MainActor
struct AgsizYardimciTestleri {
    @Test func baglantiMedyaTuruTaninir() {
        #expect(Kaziyici.medyaTuru(URL(string: "https://www.youtube.com/watch?v=TUVcZfQe-Kw")!)?.tur == .youtube)
        #expect(Kaziyici.medyaTuru(URL(string: "https://a.com/x.mp3")!)?.tur == .ses)
        #expect(Kaziyici.medyaTuru(URL(string: "https://a.com/kitap.epub")!)?.tur == .belge)
        #expect(Kaziyici.medyaTuru(URL(string: "https://a.com/sayfa")!) == nil)
    }
    @Test func sureSinirliBitmeyeniKeser() async {
        let bas = Date()
        let r: Int? = await sureSinirli(0.3) { try? await Task.sleep(for: .seconds(5)); return 1 }
        #expect(r == nil && Date().timeIntervalSince(bas) < 1.5)
        let hizli: Int? = await sureSinirli(2) { 7 }
        #expect(hizli == 7)
    }
}
