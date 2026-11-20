import Testing
import Foundation
@testable import _01

@MainActor @Suite(.serialized)
struct AltyapiGelistirmeTests {
    // MARK: TestSandbox ve StoreLocations

    @Test func sandboxGeciciDizinVeSuiteKurarVeGeriAlir() throws {
        let onceki = StoreLocations.current
        let oncekiOgrenci = StudentStore.directoryOverride
        var kok: URL?
        var suite = ""
        try TestSandbox.runSync { sandbox in
            kok = sandbox.root; suite = sandbox.suiteName
            #expect(FileManager.default.fileExists(atPath: sandbox.root.path))
            #expect(StoreLocations.current.supportingDirectory == sandbox.root)
            #expect(StoreLocations.current.defaultsSuite == sandbox.suiteName)
            sandbox.defaults.set("deneme", forKey: "anahtar")
            #expect(StoreLocations.current.defaults.string(forKey: "anahtar") == "deneme")
            #expect(UserDefaults.standard.string(forKey: "anahtar") == nil)
        }
        #expect(StoreLocations.current == onceki)
        #expect(StudentStore.directoryOverride == oncekiOgrenci)
        let silinen = try #require(kok)
        #expect(!FileManager.default.fileExists(atPath: silinen.path))
        #expect(UserDefaults(suiteName: suite)?.string(forKey: "anahtar") == nil)
    }

    @Test func sandboxHataFirlatsaDaGeriAlir() {
        let onceki = StoreLocations.current
        struct Hata: Error {}
        #expect(throws: Hata.self) {
            try TestSandbox.runSync { _ in throw Hata() }
        }
        #expect(StoreLocations.current == onceki)
    }

    @Test func icIceSandboxEskiDegeriKorur() throws {
        try TestSandbox.runSync { dis in
            try TestSandbox.runSync { ic in
                #expect(ic.root != dis.root)
                #expect(StoreLocations.current.supportingDirectory == ic.root)
            }
            #expect(StoreLocations.current.supportingDirectory == dis.root)
            #expect(StudentStore.directoryOverride == dis.root)
            #expect(FileManager.default.fileExists(atPath: dis.root.path))
        }
    }

    @Test func storeLocationsOverrideTumTuremisYollariDegistirir() throws {
        let canli = StoreLocations.live
        #expect(canli.archivesDirectory.lastPathComponent == "Arsivler")
        try TestSandbox.runSync { sandbox in
            let kok = sandbox.root.path
            let yollar: [URL?] = [
                StudentStore.storageURL, GraduatedStudentStore.storageURL, StudentImportStore.storageURL,
                GradeLoanRuleStore.storageURL, FieldMaintenanceStore.storageURL, ArchiveSettings.supportingDirectory,
                TrashStore.directory, AutoArchive.directory
            ]
            for yol in yollar {
                let path = try #require(yol).path
                #expect(path.hasPrefix(kok), "Sandbox dışında yol: \(path)")
            }
            #expect(AutoArchive.directory == StoreLocations.current.archivesDirectory)
        }
    }

    // MARK: DeepLinkRoute

    @Test func derinBaglantiRotalariBenzersizVeBiciminde() {
        let adresler = DeepLinkRoute.allCases.map(\.url.absoluteString)
        #expect(Set(adresler).count == DeepLinkRoute.allCases.count)
        #expect(adresler.allSatisfy { $0.hasPrefix("kitapbul://") })
        #expect(DeepLinkRoute.barkod.url.absoluteString == "kitapbul://ekle/barkod")
        #expect(DeepLinkRoute.asistan.url.absoluteString == "kitapbul://asistan")
        #expect(DeepLinkRoute.odunc.url.absoluteString == "kitapbul://odunc")
        #expect(Set(DeepLinkRoute.widgetRoutes).isSubset(of: Set(DeepLinkRoute.allCases)))
        #expect(DeepLinkRoute.widgetRoutes == [.barkod, .ses, .kapak, .asistan])
    }

    @Test func widgetRotalariQRVeKuyrukIleEslesir() {
        for route in DeepLinkRoute.widgetRoutes {
            #expect(KitapQR.hedef(from: route.url) != nil, "\(route.rawValue) QR'da çözülmüyor")
            let kuyruk = LibraryLaunchLinkQueue()
            kuyruk.enqueue(route.url)
            #expect(kuyruk.pendingURL == route.url)
        }
        #expect(KitapQR.hedef(from: DeepLinkRoute.ses.url) == .ekle("ses"))
        #expect(KitapQR.hedef(from: DeepLinkRoute.asistan.url) == .asistan)
    }

    // MARK: WidgetSnapshot

    @Test func widgetOzetiKodlanipCozulur() throws {
        let an = Date(timeIntervalSince1970: 1_800_000_000)
        let ozet = WidgetSnapshot(geciken: 3, bugunIade: 2, sonArsiv: an.addingTimeInterval(-3600), guncelleme: an)
        #expect(try WidgetSnapshot.decode(ozet.encoded()) == ozet)
        let arsivsiz = WidgetSnapshot(geciken: 0, bugunIade: 0, sonArsiv: nil, guncelleme: an)
        #expect(try WidgetSnapshot.decode(arsivsiz.encoded()) == arsivsiz)
    }

    @Test func widgetOzetiYirmiDortSaatSonraBayatlar() {
        let an = Date(timeIntervalSince1970: 1_800_000_000)
        let ozet = WidgetSnapshot(geciken: 1, bugunIade: 1, sonArsiv: nil, guncelleme: an)
        #expect(!ozet.bayatMi(now: an.addingTimeInterval(86_400)))
        #expect(ozet.bayatMi(now: an.addingTimeInterval(86_401)))
        var takvim = Calendar(identifier: .gregorian); takvim.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(ozet.bugunGecerli(now: an.addingTimeInterval(60), calendar: takvim))
        #expect(!ozet.bugunGecerli(now: an.addingTimeInterval(2 * 86_400), calendar: takvim))
    }

    @Test func widgetOzetiDosyayaYazilirVeOkunur() throws {
        try TestSandbox.runSync { sandbox in
            let yol = sandbox.root.appendingPathComponent(WidgetSnapshotStore.fileName)
            #expect(WidgetSnapshotStore.read(from: yol) == nil)
            let an = Date(timeIntervalSince1970: 1_800_000_000)
            #expect(WidgetSnapshotStore.publish(geciken: -4, bugunIade: 5, sonArsiv: nil, now: an, to: yol, reload: false))
            let okunan = try #require(WidgetSnapshotStore.read(from: yol))
            #expect(okunan.geciken == 0 && okunan.bugunIade == 5 && okunan.guncelleme == an)
            try Data("bozuk".utf8).write(to: yol)
            #expect(WidgetSnapshotStore.read(from: yol) == nil)
        }
    }

    // MARK: TestEnvironment

    @Test func testOrtamiBayraklariBeklenenDegerde() {
        #expect(TestEnvironment.isXCTestHost)
        #expect(TestEnvironment.suppressesLaunchSideEffects)
#if !DEBUG
        #expect(!TestEnvironment.isUITesting && !TestEnvironment.isReadOnlyUITesting && !TestEnvironment.isXCTestHost)
#endif
    }

    // MARK: Yan dosya eşlemesi

    /// Arşive giren her yan dosya adının sahibi bir depo olmalı; yeni ad eklenince bu tablo da güncellenir.
    @Test func destekDosyalariniHerBiriniBirDepoKullanir() {
        let sahipler: [String: String] = [
            "KademeKurallari.json": "GradeLoanRuleStore",
            "KayitliGorunumler.json": "CatalogTools kayıtlı görünümler",
            "SayimOturumu.json": "InventorySessionStore",
            "OCRDuzeltmeleri.json": "CorrectionMemory",
            "BekleyenKuyruk.json": "BatchAdd bekleyen kuyruk",
            "Mezunlar.json": "GraduatedStudentStore",
            "OgrenciAktarimGunlugu.json": "StudentImportStore",
            "field_maintenance_journal.json": "FieldMaintenanceStore",
            "SayimBeklenti.json": "Sayım beklenti",
            "SayimOkutmalar.jsonl": "Sayım okutma günlüğü",
            "sayim_islem_fisleri.json": "Sayım işlem fişleri",
            "AyriTutCiftleri.json": "Ayrı tut çiftleri",
            "AIDegisiklikGunlugu.jsonl": "AIDegisiklikGunlugu"
        ]
        let sahipsiz = ArchiveSettings.supportingFileNames.filter { sahipler[$0] == nil }
        #expect(sahipsiz.isEmpty, "Sahibi tanımsız yan dosya: \(sahipsiz.sorted())")
        #expect(StudentImportStore.fileName == "OgrenciAktarimGunlugu.json")
        #expect(FieldMaintenanceStore.fileName == "field_maintenance_journal.json")
    }
}
