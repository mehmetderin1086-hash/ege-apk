import Testing
import Foundation
import SwiftData
@testable import _01

/// Paket 5 (Veri-Arşiv) testleri. Hepsi geçici klasör kullanır; gerçek disk kapasitesi, gerçek Belgeler
/// klasörü ve gerçek depo işaretçisi okunmaz. Küresel ayarlar `defer` ile geri alınır.
@MainActor
@Suite(.serialized)
struct VeriGelistirmeTests {
    // MARK: Yardımcılar

    private func geciciKlasor(_ ad: String = "vgel") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(ad)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func katalog(_ adet: Int) throws -> ModelContext {
        let context = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        for i in 0..<adet { context.insert(CatalogBook(book: Book(title: "Kitap \(i)", author: "Yazar"))) }
        try context.save()
        return context
    }

    private func arsivDurumunuSifirla() {
        for key in ["autoArchiveLastDate", "autoArchiveLastAttempt", "autoArchiveLastFailure"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func eskit(_ url: URL, saniye: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-saniye)], ofItemAtPath: url.path)
    }

    private func yaz(_ url: URL, _ bayt: Int = 4) throws {
        try Data(repeating: 7, count: bayt).write(to: url)
    }

    private func journalYolu(_ root: URL) -> ArchiveSwitchJournal.Paths {
        .init(journalURL: root.appendingPathComponent("journal.json"),
              backupRoot: root.appendingPathComponent("backups", isDirectory: true),
              recoveredRoot: root.appendingPathComponent("stores", isDirectory: true))
    }

    private func gecicileriListele(_ klasor: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: klasor.path)) ?? []).filter { $0.hasPrefix("yaziliyor-") }
    }

    // MARK: Süpürücü

    @Test func supurucuEskiYarimDosyalariSilerTazeVeArsivleriKorur() throws {
        let kok = try geciciKlasor()
        let arsiv = kok.appendingPathComponent("Arsivler", isDirectory: true)
        let gunluk = kok.appendingPathComponent("journal", isDirectory: true)
        try FileManager.default.createDirectory(at: arsiv, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gunluk, withIntermediateDirectories: true)
        let eskiPaths = ArchiveSwitchJournal.pathsOverride
        ArchiveSwitchJournal.pathsOverride = .init(journalURL: gunluk.appendingPathComponent("j.json"),
            backupRoot: kok.appendingPathComponent("b"), recoveredRoot: kok.appendingPathComponent("s"))
        AutoArchive.directoryOverride = arsiv
        defer {
            AutoArchive.directoryOverride = nil; ArchiveSwitchJournal.pathsOverride = eskiPaths
            try? FileManager.default.removeItem(at: kok)
        }
        let eski = arsiv.appendingPathComponent("yaziliyor-ESKI.tmp"), taze = arsiv.appendingPathComponent("yaziliyor-TAZE.tmp")
        let zip = arsiv.appendingPathComponent("KitapArsivi-2026-01-01.zip")
        let eskiGunluk = gunluk.appendingPathComponent(".switch-journal-ESKI.tmp")
        for url in [eski, taze, zip, eskiGunluk] { try yaz(url) }
        for url in [eski, zip, eskiGunluk] { try eskit(url, saniye: 1_200) }

        let sayim = AutoArchive.staleTemporaryCount(olderThan: 600)
        #expect(sayim.count == 2 && sayim.bytes == 8)
        let silinen = AutoArchive.sweepStaleTemporaries(olderThan: 600)
        #expect(Set(silinen.map(\.lastPathComponent)) == ["yaziliyor-ESKI.tmp", ".switch-journal-ESKI.tmp"])
        #expect(!FileManager.default.fileExists(atPath: eski.path))
        #expect(!FileManager.default.fileExists(atPath: eskiGunluk.path))
        #expect(FileManager.default.fileExists(atPath: taze.path), "10 dakikadan taze yazım korunur")
        #expect(FileManager.default.fileExists(atPath: zip.path), "Tamamlanmış arşiv süpürülmez")
    }

    @Test func supurucuYazimSurerkenHicbirSeyeDokunmaz() throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        let eskiPaths = ArchiveSwitchJournal.pathsOverride
        ArchiveSwitchJournal.pathsOverride = journalYolu(kok.appendingPathComponent("j"))
        defer {
            AutoArchive.activeTemporaries = []; AutoArchive.directoryOverride = nil
            ArchiveSwitchJournal.pathsOverride = eskiPaths; try? FileManager.default.removeItem(at: kok)
        }
        let canli = kok.appendingPathComponent("yaziliyor-CANLI.tmp")
        try yaz(canli); try eskit(canli, saniye: 5_000)
        AutoArchive.activeTemporaries = [canli.standardizedFileURL]
        #expect(AutoArchive.isWriting)
        #expect(AutoArchive.sweepStaleTemporaries(olderThan: 600).isEmpty)
        #expect(AutoArchive.staleTemporaryCount(olderThan: 600).count == 0)
        #expect(FileManager.default.fileExists(atPath: canli.path), "Canlı yazımın dosyası silinmemeli")
        // Yazım bitince aynı dosya artık yarım sayılır.
        AutoArchive.activeTemporaries = []
        #expect(AutoArchive.sweepStaleTemporaries(olderThan: 600).count == 1)
    }

    // MARK: run(): sonuçlar

    @Test func calisanArsivVarkenRunAtlandiDoner() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        defer { AutoArchive.activeTemporaries = []; AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        AutoArchive.activeTemporaries = [kok.appendingPathComponent("yaziliyor-X.tmp").standardizedFileURL]
        let outcome = await AutoArchive.run(context: try katalog(3))
        #expect(outcome == .atlandiCalisiyor)
        #expect(AutoArchive.existingArchives().isEmpty)
    }

    @Test func runYazildiVeLastDateKeyYazilir() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        defer { AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let simdi = Date(timeIntervalSince1970: 1_810_000_000)
        let outcome = await AutoArchive.run(context: try katalog(5), now: simdi)
        #expect(outcome == .yazildi)
        #expect(AutoArchive.lastArchiveDate == simdi)
        #expect(AutoArchive.lastFailure == nil)
        #expect(AutoArchive.existingArchives().count == 1)
        #expect(gecicileriListele(kok).isEmpty)
    }

    @Test func yayimdanSonraGelenIptalArsivSayilirVeTarihYazilir() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        var kancalar = AutoArchive.StreamingHooks()
        kancalar.onPublished = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        AutoArchive.testHooks = kancalar
        defer { AutoArchive.testHooks = nil; AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let context = try katalog(4)
        let simdi = Date(timeIntervalSince1970: 1_810_100_000)
        let outcome = await Task { @MainActor in await AutoArchive.run(context: context, now: simdi) }.value
        #expect(outcome == .yazildi, "Dosya diskte tamsa iptal onu yok saymaz")
        #expect(AutoArchive.lastArchiveDate == simdi)
        #expect(AutoArchive.existingArchives().count == 1)
    }

    @Test func iptalGeciciDosyayiSilerHedefeDokunmazOutcomeIptal() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        let simdi = Date(timeIntervalSince1970: 1_810_200_000)
        let hedef = kok.appendingPathComponent(AutoArchive.fileName(for: simdi))
        let onceki = Data("dünkü tam arşiv".utf8)
        try onceki.write(to: hedef)
        var kancalar = AutoArchive.StreamingHooks()
        kancalar.afterPageWritten = { _ in withUnsafeCurrentTask { $0?.cancel() } }
        AutoArchive.testHooks = kancalar
        defer { AutoArchive.testHooks = nil; AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let context = try katalog(250)
        let outcome = await Task { @MainActor in await AutoArchive.run(context: context, now: simdi) }.value
        #expect(outcome == .iptal)
        #expect(gecicileriListele(kok).isEmpty, "Yarım yazılan geçici dosya silinmeli")
        #expect(try Data(contentsOf: hedef) == onceki, "Önceki hedef dosya aynen kalmalı")
        #expect(AutoArchive.lastArchiveDate == nil)
    }

    @Test func yazmaHatasiENOSPCGeciciDosyayiSilerVeHatayiKaydeder() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        var kancalar = AutoArchive.StreamingHooks()
        kancalar.afterPageWritten = { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        AutoArchive.testHooks = kancalar
        defer { AutoArchive.testHooks = nil; AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let outcome = await AutoArchive.run(context: try katalog(250))
        guard case .basarisiz = outcome else { Issue.record("ENOSPC başarısız dönmeli: \(outcome)"); return }
        #expect(gecicileriListele(kok).isEmpty)
        #expect(AutoArchive.existingArchives().isEmpty)
        #expect(AutoArchive.lastFailure != nil)
        #expect(AutoArchive.lastArchiveDate == nil)
    }

    @Test func oncekiCalismadanKalanYarimDosyaRunBasindaTemizlenirVeHataYazilir() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        let eskiPaths = ArchiveSwitchJournal.pathsOverride
        ArchiveSwitchJournal.pathsOverride = journalYolu(kok.appendingPathComponent("j"))
        defer { AutoArchive.directoryOverride = nil; ArchiveSwitchJournal.pathsOverride = eskiPaths; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let artik = kok.appendingPathComponent("yaziliyor-ARTIK.tmp")
        try yaz(artik, 64); try eskit(artik, saniye: 3_600)
        var kancalar = AutoArchive.StreamingHooks()
        kancalar.afterPageWritten = { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
        AutoArchive.testHooks = kancalar
        defer { AutoArchive.testHooks = nil }
        _ = await AutoArchive.run(context: try katalog(250))
        #expect(!FileManager.default.fileExists(atPath: artik.path))
        // Yeni yazım da hata verdiği için son hata görünür kalır.
        #expect(AutoArchive.lastFailure != nil)
    }

    // MARK: Disk bütçesi

    @Test func diskButcesiFormulu() {
        #expect(AutoArchive.requiredCapacity(lastArchiveBytes: 0) == 300 * 1_048_576)
        #expect(AutoArchive.requiredCapacity(lastArchiveBytes: 10 * 1_048_576) == 330 * 1_048_576)
    }

    @Test func yetersizDiskKapasitesiRunuBasarisizYapar() async throws {
        let kok = try geciciKlasor()
        AutoArchive.directoryOverride = kok
        arsivDurumunuSifirla()
        defer { AutoArchive.availableCapacityProvider = nil; AutoArchive.directoryOverride = nil; arsivDurumunuSifirla(); try? FileManager.default.removeItem(at: kok) }
        let context = try katalog(3)
        AutoArchive.availableCapacityProvider = { _ in 10 * 1_048_576 }
        let outcome = await AutoArchive.run(context: context)
        guard case .basarisiz(let neden) = outcome else { Issue.record("Yetersiz disk başarısız dönmeli: \(outcome)"); return }
        #expect(neden.contains("Disk alanı yetersiz"))
        #expect(AutoArchive.lastFailure?.contains("Disk alanı yetersiz") == true)
        #expect(AutoArchive.existingArchives().isEmpty)
        // Yeterli kapasitede aynı katalog yazılır.
        AutoArchive.availableCapacityProvider = { _ in Int64.max / 4 }
        #expect(await AutoArchive.run(context: context) == .yazildi)
        #expect(AutoArchive.lastFailure == nil)
    }

    @Test func otomatikSaklamaVarsayilanKapaliVeEnYeniyiAslaSilmez() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let takvim = Calendar(identifier: .gregorian)
        let baslangic = takvim.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 1, day: 1))!
        for gun in 0..<40 {
            let tarih = takvim.date(byAdding: .day, value: gun, to: baslangic)!
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            try yaz(kok.appendingPathComponent("KitapArsivi-\(formatter.string(from: tarih)).zip"))
        }
        let enYeni = try #require(try ArchiveRetention.files(in: kok).first)
        let tumunu = try ArchiveRetention.applyAutomatically(in: kok, policy: .all)
        #expect(tumunu.isEmpty, "'Tümünü koru' hiçbir şey silmez")
        let silinen = try ArchiveRetention.applyAutomatically(in: kok, policy: .short)
        #expect(!silinen.isEmpty)
        #expect(!silinen.contains(enYeni.url))
        #expect(FileManager.default.fileExists(atPath: enYeni.url.path))
        let kalan = try ArchiveRetention.files(in: kok)
        #expect(kalan.count == 40 - silinen.count)
        #expect(kalan.count >= 7)
    }

    // MARK: Teknik yedek

    @Test func teknikYedekExternalDataVeKapsamBilgisiniIcerir() async throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let depo = kok.appendingPathComponent("kurtarma.store")
        try Data(repeating: 1, count: 30).write(to: depo)
        try Data(repeating: 2, count: 10).write(to: URL(fileURLWithPath: depo.path + "-wal"))
        let harici = kok.appendingPathComponent(".kurtarma_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: harici, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 500).write(to: harici.appendingPathComponent("abc"))
        try Data(repeating: 4, count: 20).write(to: harici.appendingPathComponent("def"))

        let sonuc = try await ArchiveFileBackgroundWork.technicalBackup(store: depo)
        let girisler = ZIPReader.entries(in: sonuc.data)
        let adlar = Set(girisler.map(\.name))
        #expect(adlar.isSuperset(of: ["depo/kurtarma.store", "depo/kurtarma.store-wal", "depo/_SUPPORT/_EXTERNAL_DATA/abc",
                                      "depo/_SUPPORT/_EXTERNAL_DATA/def", "BILGI.txt"]))
        #expect(sonuc.fileCount == 4)
        #expect(girisler.first { $0.name == "depo/_SUPPORT/_EXTERNAL_DATA/abc" }?.data == Data(repeating: 3, count: 500))
        let bilgi = String(decoding: try #require(girisler.first { $0.name == "BILGI.txt" }).data, as: UTF8.self)
        #expect(bilgi.contains("Depo dosyaları: 2"))
        #expect(bilgi.contains("Harici veri (_SUPPORT) dosyaları: 2"))
        #expect(bilgi.contains("depo + harici veri"))
        #expect(bilgi.contains("Toplam: 4 dosya, 560 bayt"))
    }

    @Test func teknikYedekHaricisizDepodaKapsamiDogruSoyler() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let depo = kok.appendingPathComponent("x.store")
        try Data(repeating: 1, count: 8).write(to: depo)
        let sonuc = try ArchiveFileBackgroundWork.buildTechnicalBackup(store: depo)
        let bilgi = String(decoding: try #require(ZIPReader.entries(in: sonuc.data).first { $0.name == "BILGI.txt" }).data, as: UTF8.self)
        #expect(bilgi.contains("yalnız depo"))
        #expect(throws: FullArchive.ValidationError.self) {
            try ArchiveFileBackgroundWork.buildTechnicalBackup(store: kok.appendingPathComponent("yok.store"))
        }
    }

    // MARK: Tek güvenli kap açıcı

    @Test func bekleyenGunlukSiriVeKapAcicidaKatalogAcmaz() throws {
        let kok = try geciciKlasor()
        let eskiPaths = ArchiveSwitchJournal.pathsOverride, eskiShared = KitapVeritabani.shared
        let paths = journalYolu(kok)
        ArchiveSwitchJournal.pathsOverride = paths
        KitapVeritabani.shared = nil
        defer { ArchiveSwitchJournal.pathsOverride = eskiPaths; KitapVeritabani.shared = eskiShared; try? FileManager.default.removeItem(at: kok) }
        #expect(!ArchiveSwitchJournal.hasMarker())
        try Data("{ bozuk".utf8).write(to: paths.journalURL)
        #expect(ArchiveSwitchJournal.hasMarker())
        #expect(throws: IntentVeri.GuvenliAcilisBekliyor.self) { try IntentVeri.context() }
        #expect(throws: (any Error).self) { try StoreRecovery.openVerifiedContainer(sync: false) }
        #expect(throws: (any Error).self) { try StoreRecovery.openVerifiedContainer(sync: true) }
        #expect(KitapVeritabani.shared == nil, "Hiçbir kap yayımlanmamalı")
    }

    @Test func acikKapVarsaIntentAyniKabiKullanir() throws {
        let eskiShared = KitapVeritabani.shared
        let kap = try KitapVeritabani.makeContainer(inMemory: true)
        KitapVeritabani.shared = kap
        defer { KitapVeritabani.shared = eskiShared }
        #expect(try IntentVeri.context().container === kap)
    }

    // MARK: Kişisel veri taşıma

    private func tercihler() -> (UserDefaults, String) {
        let ad = "vgel-reloc-\(UUID().uuidString)"
        return (UserDefaults(suiteName: ad)!, ad)
    }

    @Test func tasimaKopyalarDogrularBayrakYazarEskiyiSiler() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eski = kok.appendingPathComponent("Documents", isDirectory: true), yeni = kok.appendingPathComponent("Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        let (tercih, ad) = tercihler(); defer { tercih.removePersistentDomain(forName: ad) }
        let ogrenciler = Data("[{\"ad\":\"Ayşe\"}]".utf8), oturum = Data("{\"s\":1}".utf8)
        try ogrenciler.write(to: eski.appendingPathComponent("Ogrenciler.json"))
        try oturum.write(to: eski.appendingPathComponent("SayimOturumu.json"))
        try Data("kullanıcı dosyası".utf8).write(to: eski.appendingPathComponent("KitapKatalogu-Yedek.json"))

        let sonuc = MetadataRelocation.run(legacy: eski, target: yeni, legacyAuthoritative: true, defaults: tercih, flagKey: "k")
        #expect(sonuc == .tamamlandi(tasinan: 2))
        #expect(!FileManager.default.fileExists(atPath: eski.appendingPathComponent("SayimOturumu.json").path), "Sayım oturumu eski yerde kalıp hortlamamalı")
        #expect(tercih.bool(forKey: "k"))
        #expect(try Data(contentsOf: yeni.appendingPathComponent("Ogrenciler.json")) == ogrenciler)
        #expect(!FileManager.default.fileExists(atPath: eski.appendingPathComponent("Ogrenciler.json").path), "Eski kopya doğrulamadan sonra silinir")
        #expect(FileManager.default.fileExists(atPath: eski.appendingPathComponent("KitapKatalogu-Yedek.json").path), "Taşıma listesinde olmayan dosyaya dokunulmaz")
        #expect(!FileManager.default.fileExists(atPath: yeni.appendingPathComponent("KitapKatalogu-Yedek.json").path))
    }

    @Test func yarimGoctenSonrakiTekrarGuvenliVeEskiKopyaYetkilidir() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eski = kok.appendingPathComponent("D", isDirectory: true), yeni = kok.appendingPathComponent("M", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: yeni, withIntermediateDirectories: true)
        let (tercih, ad) = tercihler(); defer { tercih.removePersistentDomain(forName: ad) }
        // Önceki yarım çalışma: Uyeler.json kopyalanmış (eski yerinde duruyor), Ogrenciler.json hedefte bayat.
        try Data("uyeler".utf8).write(to: eski.appendingPathComponent("Uyeler.json"))
        try Data("uyeler".utf8).write(to: yeni.appendingPathComponent("Uyeler.json"))
        try Data("YENİ öğrenciler".utf8).write(to: eski.appendingPathComponent("Ogrenciler.json"))
        try Data("bayat".utf8).write(to: yeni.appendingPathComponent("Ogrenciler.json"))
        try eskit(yeni.appendingPathComponent("Ogrenciler.json"), saniye: 3_600)
        try Data("geçmiş".utf8).write(to: eski.appendingPathComponent("OduncGecmisi.json"))

        let birinci = MetadataRelocation.run(legacy: eski, target: yeni, legacyAuthoritative: true, defaults: tercih, flagKey: "k")
        #expect(birinci == .tamamlandi(tasinan: 2), "Yalnız değişen/eksik dosyalar yeniden yazılır")
        #expect(try String(contentsOf: yeni.appendingPathComponent("Ogrenciler.json"), encoding: .utf8) == "YENİ öğrenciler")
        #expect(try String(contentsOf: yeni.appendingPathComponent("OduncGecmisi.json"), encoding: .utf8) == "geçmiş")
        // Tekrar çalıştırmak hiçbir şeyi bozmaz.
        let ikinci = MetadataRelocation.run(legacy: eski, target: yeni, legacyAuthoritative: false, defaults: tercih, flagKey: "k")
        #expect(ikinci == .tamamlandi(tasinan: 0))
        #expect(try String(contentsOf: yeni.appendingPathComponent("Uyeler.json"), encoding: .utf8) == "uyeler")
    }

    @Test func bayrakSonrasiHedefYetkiliOlurFarkliEskiKopyaSilinmez() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eski = kok.appendingPathComponent("D", isDirectory: true), yeni = kok.appendingPathComponent("M", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: yeni, withIntermediateDirectories: true)
        let (tercih, ad) = tercihler(); defer { tercih.removePersistentDomain(forName: ad) }
        tercih.set(true, forKey: "k")
        try Data("güncel".utf8).write(to: yeni.appendingPathComponent("Uyeler.json"))
        try Data("bayat eski".utf8).write(to: eski.appendingPathComponent("Uyeler.json"))
        try Data("silinmeli".utf8).write(to: yeni.appendingPathComponent("Mezunlar.json"))
        try Data("silinmeli".utf8).write(to: eski.appendingPathComponent("Mezunlar.json"))
        try Data("dosyalardan geri geldi".utf8).write(to: eski.appendingPathComponent("OduncGecmisi.json"))

        let sonuc = MetadataRelocation.run(legacy: eski, target: yeni, legacyAuthoritative: false, defaults: tercih, flagKey: "k")
        #expect(sonuc == .tamamlandi(tasinan: 1))
        #expect(try String(contentsOf: yeni.appendingPathComponent("Uyeler.json"), encoding: .utf8) == "güncel", "Hedef bayattan ezilmez")
        #expect(FileManager.default.fileExists(atPath: eski.appendingPathComponent("Uyeler.json").path), "Farklı eski kopya bilgi kaybı olmasın diye kalır")
        #expect(!FileManager.default.fileExists(atPath: eski.appendingPathComponent("Mezunlar.json").path), "Aynı eski kopya temizlenir")
        #expect(try String(contentsOf: yeni.appendingPathComponent("OduncGecmisi.json"), encoding: .utf8) == "dosyalardan geri geldi", "Eksik hedef eski kopyadan tamamlanır")
    }

    @Test func hedefDahaYeniyseBayraksizTasimaOnuEzmez() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eski = kok.appendingPathComponent("D", isDirectory: true), yeni = kok.appendingPathComponent("M", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: yeni, withIntermediateDirectories: true)
        let (tercih, ad) = tercihler(); defer { tercih.removePersistentDomain(forName: ad) }
        try Data("eski".utf8).write(to: eski.appendingPathComponent("Uyeler.json"))
        try eskit(eski.appendingPathComponent("Uyeler.json"), saniye: 3_600)
        try Data("yeni".utf8).write(to: yeni.appendingPathComponent("Uyeler.json"))
        _ = MetadataRelocation.run(legacy: eski, target: yeni, legacyAuthoritative: true, defaults: tercih, flagKey: "k")
        #expect(try String(contentsOf: yeni.appendingPathComponent("Uyeler.json"), encoding: .utf8) == "yeni")
    }

    @Test func tasimaBasarisizsaBayrakYazilmazVeDosyalarYerindeKalir() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eski = kok.appendingPathComponent("D", isDirectory: true)
        try FileManager.default.createDirectory(at: eski, withIntermediateDirectories: true)
        try Data("öğrenciler".utf8).write(to: eski.appendingPathComponent("Ogrenciler.json"))
        // Hedef klasör yerine düz dosya: oluşturma başarısız olur.
        let engel = kok.appendingPathComponent("Metadata")
        try Data("engel".utf8).write(to: engel)
        let (tercih, ad) = tercihler(); defer { tercih.removePersistentDomain(forName: ad) }
        let sonuc = MetadataRelocation.run(legacy: eski, target: engel, legacyAuthoritative: true, defaults: tercih, flagKey: "k")
        guard case .basarisiz = sonuc else { Issue.record("Başarısız dönmeli: \(sonuc)"); return }
        #expect(!tercih.bool(forKey: "k"), "Bayrak yalnız tüm dosyalar doğrulandıktan sonra yazılır")
        #expect(try String(contentsOf: eski.appendingPathComponent("Ogrenciler.json"), encoding: .utf8) == "öğrenciler")
    }

    @Test func okuyucularTasimadanOnceEskiSonraYeniKlasoruKullanir() throws {
        guard !MetadataRelocation.isIsolated else { return }
        let kok = try geciciKlasor()
        let (tercih, ad) = tercihler()
        let eski = kok.appendingPathComponent("D", isDirectory: true), yeni = kok.appendingPathComponent("M", isDirectory: true)
        MetadataRelocation.legacyDirectoryOverride = eski; MetadataRelocation.targetDirectoryOverride = yeni
        MetadataRelocation.defaultsOverride = tercih
        defer {
            MetadataRelocation.legacyDirectoryOverride = nil; MetadataRelocation.targetDirectoryOverride = nil
            MetadataRelocation.defaultsOverride = nil; tercih.removePersistentDomain(forName: ad)
            try? FileManager.default.removeItem(at: kok)
        }
        #expect(MetadataRelocation.metadataDirectory == eski)
        #expect(MetadataRelocation.url(forFile: "Ogrenciler.json") == eski.appendingPathComponent("Ogrenciler.json"))
        tercih.set(true, forKey: MetadataRelocation.completedKey)
        #expect(MetadataRelocation.metadataDirectory == yeni)
        #expect(MetadataRelocation.url(forFile: "Ogrenciler.json") == yeni.appendingPathComponent("Ogrenciler.json"))
        // Taşınmayan dosyalar (örn. OCR düzeltmeleri) Belgeler'de kalır.
        #expect(MetadataRelocation.url(forFile: "OCRDuzeltmeleri.json") == eski.appendingPathComponent("OCRDuzeltmeleri.json"))
        #expect(ArchiveSettings.supportingFileNames.isSuperset(of: ["SayimBeklenti.json", "SayimOkutmalar.jsonl"]))
    }

    @Test func yalitilmisKlasorKullanilirkenGercekDosyalaraDokunulmaz() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let eskiOverride = StudentStore.directoryOverride
        StudentStore.directoryOverride = kok
        defer { StudentStore.directoryOverride = eskiOverride }
        guard case .atlandi = MetadataRelocation.migrateIfNeeded() else { Issue.record("Yalıtılmış klasörde taşıma atlanmalı"); return }
    }

    // MARK: Çöp kutusu makbuzları

    @Test func copGirdisiMakbuzlariGidipGelirVeEskiJSONOkunur() throws {
        let kitap = Book(title: "Makbuzlu", author: "Y")
        let makbuz = ArchivedScanReceipt(id: UUID(), operationID: UUID(), bookID: kitap.id, addedCopies: 2, inserted: true,
                                         createdAt: Date(timeIntervalSince1970: 1_700_000_000), beforeBookData: nil, afterBookData: Data([1]))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let giris = TrashEntry(book: kitap, deletedAt: .now, reason: "Silindi", receipts: [makbuz])
        let geri = try decoder.decode(TrashEntry.self, from: encoder.encode(giris))
        #expect(geri.receipts.count == 1 && geri.receipts.first?.operationID == makbuz.operationID)
        #expect(geri.receipts.first?.afterBookData == Data([1]))

        // Eski çöp dosyası: 'receipts' anahtarı yok.
        var nesne = try #require(JSONSerialization.jsonObject(with: encoder.encode(giris)) as? [String: Any])
        nesne.removeValue(forKey: "receipts")
        let eski = try decoder.decode(TrashEntry.self, from: JSONSerialization.data(withJSONObject: nesne))
        #expect(eski.receipts.isEmpty && eski.book.title == "Makbuzlu")
        // Varsayılanlı başlatıcı eski çağrı yerlerini bozmaz.
        #expect(TrashEntry(book: kitap, deletedAt: .now, reason: "x").receipts.isEmpty)
    }

    @Test func dogrulanmisCopeTasimaMakbuzlariKorurGeriAlmaGeriGetirir() throws {
        let kok = try geciciKlasor()
        let eskiTrash = TrashStore.directoryOverride, eskiGecmis = LoanHistoryStore.directoryOverride
        TrashStore.directoryOverride = kok.appendingPathComponent("cop", isDirectory: true)
        LoanHistoryStore.directoryOverride = kok; LoanHistoryStore.invalidateCache()
        defer {
            TrashStore.directoryOverride = eskiTrash; LoanHistoryStore.directoryOverride = eskiGecmis
            LoanHistoryStore.invalidateCache(); try? FileManager.default.removeItem(at: kok)
        }
        let context = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let kitap = CatalogBook(book: Book(title: "Silinecek", author: "Y"))
        context.insert(kitap)
        let makbuz = ScanWriteReceipt(operationID: UUID(), bookID: kitap.id, addedCopies: 1, inserted: true)
        makbuz.afterBookData = Data([5, 6])
        context.insert(makbuz)
        try context.save()

        try TrashStore.moveVerified([kitap], context: context)
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ScanWriteReceipt>()) == 0)
        let giris = try #require(TrashStore.entries().first)
        #expect(giris.receipts.count == 1)

        #expect(TrashStore.restore(giris, context: context))
        #expect(try context.fetchCount(FetchDescriptor<CatalogBook>()) == 1)
        let geri = try #require(try context.fetch(FetchDescriptor<ScanWriteReceipt>()).first)
        #expect(geri.operationID == makbuz.operationID && geri.afterBookData == Data([5, 6]))
        #expect(geri.bookID == kitap.id)
    }

    // MARK: Çözümleme ve doğrulama

    @Test(.tags(.performans), .timeLimit(.minutes(1))) func ucBinGirisliManifestDogrusalZamandaDogrulanir() throws {
        let kitaplar = (0..<3_000).map { Book(title: "K\($0)", author: "Y", coverData: Data([UInt8($0 % 250)])) }
        let arsiv = try FullArchive.buildVerified(ArchiveContents(books: kitaplar))
        let saat = ContinuousClock()
        var icerik: ArchiveContents?
        let sure = try saat.measure { icerik = try FullArchive.readValidated(data: arsiv) }
        #expect(icerik?.books.count == 3_000)
        #expect(icerik?.books.allSatisfy { $0.coverData != nil } == true)
        #expect(sure < .seconds(PerformansTabani.sinir(5)), "Doğrusal arama 3.000 girişte milyonlarca karşılaştırmaya çıkıyordu: \(sure)")
    }

    @Test func tekEntryDictionaryEskiOkumayaEsitSonucVerir() throws {
        let kitap = Book(title: "A", author: "B", coverData: Data([1, 2]), backCoverData: Data([3]))
        let arsiv = try FullArchive.buildVerified(ArchiveContents(books: [kitap]))
        let a = try FullArchive.readValidated(data: arsiv)
        let b = FullArchive.restoreContents(data: arsiv)
        #expect(a.books.map(\.id) == b.books.map(\.id))
        #expect(a.books.first?.coverData == Data([1, 2]) && a.books.first?.backCoverData == Data([3]))
        // Aynı adlı iki giriş hâlâ reddedilir.
        var zip = ZIPWriter()
        zip.add(name: "katalog.json", data: Data("[]".utf8)); zip.add(name: "katalog.json", data: Data("[]".utf8))
        #expect(throws: (any Error).self) { try FullArchive.readValidated(data: zip.finalize()) }
    }

    @Test func parcaliSHAKarsilastirmasiEsitVeFarkliDosya() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let kitaplar = (0..<20).map { Book(title: "K\($0)", author: "Y", coverData: Data(repeating: UInt8($0), count: 4_096)) }
        let veri = try FullArchive.buildVerified(ArchiveContents(books: kitaplar))
        let beklenen = kok.appendingPathComponent("beklenen.zip"), hedef = kok.appendingPathComponent("hedef.zip")
        try veri.write(to: beklenen); try veri.write(to: hedef)
        let makbuz = try BackupExportVerifier.verify(url: hedef, expectedURL: beklenen, now: Date(timeIntervalSince1970: 5))
        #expect(makbuz.books == 20 && makbuz.bytes == veri.count)
        #expect(makbuz.sha256 == (try BackupExportVerifier.chunkedDigest(of: beklenen)).sha256)
        // Eski sürümle aynı sonuç.
        #expect(try BackupExportVerifier.verify(url: hedef, expectedData: veri, now: Date(timeIntervalSince1970: 5)) == makbuz)

        var bozuk = veri; bozuk[bozuk.count / 2] ^= 0xFF
        try bozuk.write(to: hedef)
        #expect(throws: FullArchive.ValidationError.self) { try BackupExportVerifier.verify(url: hedef, expectedURL: beklenen) }
        try veri.prefix(veri.count - 10).write(to: hedef)
        #expect(throws: FullArchive.ValidationError.self) { try BackupExportVerifier.verify(url: hedef, expectedURL: beklenen) }
    }

    // MARK: Eski JSON yedek

    @Test func eskiJSONYedekTamArsivKapilarindanGecer() async throws {
        let kok = try geciciKlasor()
        let geri = StoreLocations.install(.isolated(root: kok))
        defer { geri(); try? FileManager.default.removeItem(at: kok) }
        let context = ModelContext(try KitapVeritabani.makeContainer(inMemory: true))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let yedek = try encoder.encode([Book(title: "Yedekten", author: "Yazar")])

        let hazirlik = try await ArchiveImportCoordinator.prepareAsync(jsonBackup: yedek, context: context)
        #expect(hazirlik.incoming.books.map(\.title) == ["Yedekten"])
        #expect(hazirlik.expected.books.count == 1)
        #expect(hazirlik.before.books.isEmpty)

        do { _ = try await ArchiveImportCoordinator.prepareAsync(jsonBackup: Data("[]".utf8), context: context); Issue.record("Boş yedek reddedilmeli") }
        catch is FullArchive.ValidationError {}
        do { _ = try await ArchiveImportCoordinator.prepareAsync(jsonBackup: Data("bozuk".utf8), context: context); Issue.record("Bozuk yedek reddedilmeli") }
        catch is FullArchive.ValidationError {}
    }

    // MARK: Geçiş yedekleri listesi ve etkin olmayan depolar

    private func gecisYedegi(_ kok: URL) throws -> URL {
        let kitap = Book(title: "Önceki", author: "Y", quantity: 1)
        let icerik = ArchiveContents(books: [kitap])
        let klasor = kok.appendingPathComponent("switch-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        try FullArchive.buildVerified(icerik).write(to: klasor.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip"), options: .atomic)
        let satirlar = ArchiveImportCoordinator.scope(before: icerik, incoming: ArchiveContents(), after: ArchiveContents())
            .map { "\($0.title): önce \($0.before), seçilen arşiv \($0.incoming), yeni katalog \($0.after)" }
        try Data((["Ayrı katalog açma: dogrulandi", "Önceki DB silinmez."] + satirlar).joined(separator: "\n").utf8)
            .write(to: klasor.appendingPathComponent("Katalog-Gecisi-Kapsam.txt"), options: .atomic)
        return klasor
    }

    @Test func gecisYedegiListesiOzetiOnbellekler() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let klasor = try gecisYedegi(kok)
        let birinci = try ArchiveSwitchBackupStore.listing(root: kok)
        #expect(birinci.entries.count == 1 && birinci.failures.isEmpty && birinci.entries.first?.books == 1)
        let ozet = klasor.appendingPathComponent(ArchiveSwitchBackupStore.Summary.fileName)
        #expect(FileManager.default.fileExists(atPath: ozet.path))

        // Önbelleğin gerçekten kullanıldığını kanıtla: mührü koruyup bir sayıyı değiştir.
        var kayit = try #require(ArchiveSwitchBackupStore.Summary.load(in: klasor))
        kayit = ArchiveSwitchBackupStore.Summary(seal: kayit.seal, scope: kayit.scope, books: 999, copies: kayit.copies,
                                                 loans: kayit.loans, students: kayit.students, members: kayit.members, events: kayit.events)
        kayit.save(in: klasor)
        #expect(try ArchiveSwitchBackupStore.listing(root: kok).entries.first?.books == 999)

        // ZIP değişirse mühür tutmaz ve özet yeniden doğrulanır.
        let zip = klasor.appendingPathComponent("Islem-Oncesi-Tam-Arsiv.zip")
        try FullArchive.buildVerified(ArchiveContents(books: [Book(title: "Önceki", author: "Y"), Book(title: "İki", author: "Y")])).write(to: zip, options: .atomic)
        let sonra = try ArchiveSwitchBackupStore.listing(root: kok)
        #expect(sonra.entries.isEmpty && sonra.failures.count == 1, "Rapor ZIP'le uyuşmadığı için güvenilmez")
    }

    @Test func etkinOlmayanDepolarListelenirVeYalnizKapsananSilinir() throws {
        let kok = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: kok) }
        let etkin = kok.appendingPathComponent("etkin.store"), eski = kok.appendingPathComponent("eski.store")
        try Data(repeating: 1, count: 100).write(to: etkin)
        try Data(repeating: 2, count: 50).write(to: eski)
        try Data(repeating: 3, count: 10).write(to: URL(fileURLWithPath: eski.path + "-wal"))
        let harici = kok.appendingPathComponent(".eski_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: harici, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 40).write(to: harici.appendingPathComponent("blob"))
        try Data(repeating: 5, count: 5).write(to: kok.appendingPathComponent("not.txt"))
        for url in [eski, URL(fileURLWithPath: eski.path + "-wal"), harici.appendingPathComponent("blob")] { try eskit(url, saniye: 7_200) }

        let liste = try InactiveStoreCatalog.list(root: kok, activePath: etkin.path)
        #expect(liste.map(\.url.lastPathComponent) == ["eski.store"])
        let madde = try #require(liste.first)
        #expect(madde.bytes == 100)
        #expect(!InactiveStoreCatalog.isCovered(madde, verifiedBackupDates: []), "Doğrulanmış yedek yoksa silinemez")
        #expect(!InactiveStoreCatalog.isCovered(madde, verifiedBackupDates: [Date().addingTimeInterval(-86_400)]), "Yedek depodan önceyse kapsamaz")
        #expect(InactiveStoreCatalog.isCovered(madde, verifiedBackupDates: [Date()]))

        #expect(throws: FullArchive.ValidationError.self) { try InactiveStoreCatalog.delete(.init(url: etkin, bytes: 1, modified: .now), root: kok, activePath: etkin.path) }
        let dis = try geciciKlasor()
        defer { try? FileManager.default.removeItem(at: dis) }
        let yabanci = dis.appendingPathComponent("baska.store"); try yaz(yabanci)
        #expect(throws: FullArchive.ValidationError.self) { try InactiveStoreCatalog.delete(.init(url: yabanci, bytes: 1, modified: .now), root: kok, activePath: nil) }
        #expect(FileManager.default.fileExists(atPath: yabanci.path))

        try InactiveStoreCatalog.delete(madde, root: kok, activePath: etkin.path)
        #expect(!FileManager.default.fileExists(atPath: eski.path))
        #expect(!FileManager.default.fileExists(atPath: eski.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: kok.appendingPathComponent(".eski_SUPPORT").path))
        #expect(FileManager.default.fileExists(atPath: etkin.path))
        #expect(FileManager.default.fileExists(atPath: kok.appendingPathComponent("not.txt").path))
    }
}
