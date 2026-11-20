import Foundation

/// Kişisel veri JSON'ları (öğrenci, üye, ödünç geçmişi, mezun, destek dosyaları) eskiden Belgeler
/// klasöründeydi. `UIFileSharingEnabled` açık olduğundan o klasör Dosyalar uygulamasında görünür:
/// okul öğrenci listesi ve ödünç geçmişi telefonu kullanan herkesin önüne açık kalıyordu.
/// Bu türden dosyalar `Application Support/Metadata/` altına taşınır; Arşivler ve elle alınan yedek
/// ZIP'leri kasıtlı olarak Belgeler'de kalır (kullanıcı onları Dosyalar'dan kopyalar).
///
/// Taşıma tek seferliktir ve geri alınamaz; bu yüzden sıra şudur: kopyala, bayt eşitliğini doğrula,
/// bayrağı yaz, ancak sonra eski kopyayı sil. Yarıda kalırsa bir sonraki açılış kaldığı yerden sürer.
@MainActor
enum MetadataRelocation {
    static let completedKey = "metadataRelocationCompletedV1"
    nonisolated static let directoryName = "Metadata"

    /// Taşınan dosyalar. Sahibi bu yolu `metadataDirectory` üzerinden türeten depolardır;
    /// Dolaşım (öğrenci/üye/geçmiş/mezun/kademe), Alan Bakım (supportingDirectory) ve Sayım.
    nonisolated static let relocatedFileNames: [String] = [
        "Ogrenciler.json", "Uyeler.json", "OduncGecmisi.json", "Mezunlar.json", "KademeKurallari.json",
        "OgrenciAktarimGunlugu.json", "field_maintenance_journal.json",
        "SayimOturumu.json", "SayimBeklenti.json", "SayimOkutmalar.jsonl", "sayim_islem_fisleri.json"
    ]
    /// Eski kopyası silinmeyecek dosyalar. Boş: eski kopya kalırsa silinen dosya sonraki açılışta hortlar.
    nonisolated static let copyOnlyFileNames: Set<String> = []

    /// Testler çekirdeği (`run`) yalıtılmış klasörlerle doğrudan çağırır; bu alanlar yalnız
    /// `migrateIfNeeded()` ve adres türetme için eski/yeni klasörü değiştirir.
    static var legacyDirectoryOverride: URL?
    static var targetDirectoryOverride: URL?
    static var defaultsOverride: UserDefaults?
    /// Taşıma öncesi okuyucuların yeni yolu kullandığı denenirken geçici olarak ayarlanır.
    private static var probeDirectory: URL?

    static var defaults: UserDefaults { defaultsOverride ?? StoreLocations.current.defaults }

    /// Testler ve arayüz fikstürleri `StoreLocations.current` ile yalıtılmış klasör verdiyse
    /// gerçek kişisel veri dosyalarına hiç dokunulmaz.
    /// Yalnız `StoreLocations.current` içindeki saklı alanlara bakar (`live` değerinden türemez), böylece
    /// `live` bir gün bu türden türetilirse bile döngü oluşmaz.
    static var isIsolated: Bool {
        let current = StoreLocations.current
        return current.defaultsSuite != nil
            || current.metadataDirectory.standardizedFileURL != URL.documentsDirectory.standardizedFileURL
    }

    static var legacyDirectory: URL {
        legacyDirectoryOverride ?? URL.documentsDirectory
    }

    static var targetDirectory: URL {
        targetDirectoryOverride ?? URL.applicationSupportDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static var isMigrated: Bool { defaults.bool(forKey: completedKey) }

    /// Kişisel veri dosyalarının güncel klasörü. Taşıma tamamlanana (ve bayrak yazılana) kadar eski
    /// Belgeler klasörünü döndürür; böylece taşıma başarısız ya da atlanmış olsa da okuyucular
    /// dosyalarını bulmaya devam eder. Okuyucular her çağrıda yeniden türetmelidir (önbelleğe almamalı).
    static var metadataDirectory: URL {
        if let probeDirectory { return probeDirectory }
        if isIsolated { return StoreLocations.current.metadataDirectory }
        return isMigrated ? targetDirectory : legacyDirectory
    }

    /// Verilen dosya adının güncel adresi. Taşınmayan dosyalar Belgeler'de kalır.
    static func url(forFile name: String) -> URL {
        if isIsolated { return StoreLocations.current.supportingDirectory.appendingPathComponent(name) }
        if isMigrated, relocatedFileNames.contains(name) { return targetDirectory.appendingPathComponent(name) }
        return legacyDirectory.appendingPathComponent(name)
    }

    enum Outcome: Equatable {
        case atlandi(String)
        case tamamlandi(tasinan: Int)
        case basarisiz(String)
    }

    /// Açılışta, geçiş günlüğü kurtarması BİTTİKTEN sonra ve herhangi bir depo okunmadan önce çağrılır.
    /// Tekrar çağrılması güvenlidir ve ucuzdur.
    @discardableResult
    static func migrateIfNeeded() -> Outcome {
        // Testler/arayüz sahte verisi kendi klasörünü verdiyse gerçek dosyalara dokunma.
        guard !isIsolated, StudentStore.directoryOverride == nil, MemberStore.directoryOverride == nil,
              LoanHistoryStore.directoryOverride == nil, ArchiveSettings.directoryOverride == nil,
              GradeLoanRuleStore.directoryOverride == nil else {
            return .atlandi("Yalıtılmış klasör kullanılıyor.")
        }
        if isMigrated {
            // Önceki açılışta silinemeyen eski kopyalar ve Dosyalar'dan geri yüklenen eksikler.
            return run(legacy: legacyDirectory, target: targetDirectory, legacyAuthoritative: false)
        }
        guard consumersUseTargetDirectory() else {
            AppLog.write("Kişisel veri taşıma atlandı: depolar henüz yeni klasörü kullanmıyor")
            return .atlandi("Okuyucular yeni klasörü kullanmıyor.")
        }
        let outcome = run(legacy: legacyDirectory, target: targetDirectory, legacyAuthoritative: true)
        switch outcome {
        case .tamamlandi(let count):
            // Yol değişti: eski konumdan okunmuş önbellekler atılır.
            StudentStore.invalidateCaches(); MemberStore.invalidateCaches(); LoanHistoryStore.invalidate()
            AppLog.write("Kişisel veri dosyaları Application Support'a taşındı: \(count)")
        case .basarisiz: AppLog.write("Kişisel veri taşıma tamamlanamadı; dosyalar yerinde ve korunuyor")
        case .atlandi: break
        }
        return outcome
    }

    /// Okuyucular yeni klasörü gerçekten kullanmıyorsa taşımak dosyaları onlardan saklar. Bu yüzden
    /// önce her okuyucunun adresi, hedef klasör varsayılarak sorulur.
    private static func consumersUseTargetDirectory() -> Bool {
        let target = targetDirectory
        probeDirectory = target
        defer { probeDirectory = nil }
        let expected = target.standardizedFileURL.resolvingSymlinksInPath().path
        let readers: [URL?] = [StudentStore.storageURL, MemberStore.storageURL, LoanHistoryStore.storageURL,
                               GraduatedStudentStore.storageURL, GradeLoanRuleStore.storageURL, FieldMaintenanceStore.storageURL,
                               InventoryActionStore.storageURL]
        return readers.allSatisfy {
            $0?.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == expected
        }
    }

    /// Çekirdek (testler doğrudan çağırır): kopyala → doğrula → bayrak → eski kopyayı sil.
    /// - Parameter legacyAuthoritative: taşıma sürerken okuyucular eski klasörü kullandığından eski
    ///   kopya doğrudur ve hedefteki farklı dosyanın üzerine yazar. Bayrak yazıldıktan sonra hedef doğrudur.
    static func run(legacy: URL, target: URL, legacyAuthoritative: Bool,
                    names: [String] = relocatedFileNames, copyOnly: Set<String> = copyOnlyFileNames,
                    defaults store: UserDefaults? = nil, flagKey: String? = nil) -> Outcome {
        let defaults = store ?? Self.defaults, flagKey = flagKey ?? completedKey
        let fileManager = FileManager.default
        var copied = 0
        // Taşınacak dosya olmasa da hedef klasör var olmalı: arşiv geri yükleme ve okuyucular oraya yazar.
        if defaults.bool(forKey: flagKey) {
            try? fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        }
        var legacyCopies: [(legacy: URL, target: URL, name: String)] = []
        do {
            for name in names {
                let source = legacy.appendingPathComponent(name), destination = target.appendingPathComponent(name)
                guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                }
                let data = try Data(contentsOf: source)
                let existing = fileManager.fileExists(atPath: destination.path) ? try? Data(contentsOf: destination) : nil
                if existing != data {
                    if existing != nil, !legacyAuthoritative { continue }
                    // Bayrak kaybolduysa hedef daha yeniyse eski kopya onu ezmez.
                    if existing != nil, let t = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       let l = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, t > l { continue }
                    try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    copied += 1
                }
                guard try Data(contentsOf: destination) == data else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                legacyCopies.append((source, destination, name))
            }
        } catch {
            return .basarisiz(error.localizedDescription)
        }
        // Bütün dosyalar doğrulandı: bayrak ancak şimdi yazılır.
        if !defaults.bool(forKey: flagKey) {
            do { try fileManager.createDirectory(at: target, withIntermediateDirectories: true) }
            catch { return .basarisiz(error.localizedDescription) }
            defaults.set(true, forKey: flagKey)
            defaults.synchronize()
            guard defaults.bool(forKey: flagKey) else { return .basarisiz("Taşıma bayrağı yazılamadı.") }
        }
        // Eski kopya yalnız hedefle bayt bayt aynıysa silinir.
        for item in legacyCopies where !copyOnly.contains(item.name) {
            guard let old = try? Data(contentsOf: item.legacy), let new = try? Data(contentsOf: item.target), old == new else { continue }
            try? fileManager.removeItem(at: item.legacy)
        }
        return .tamamlandi(tasinan: copied)
    }
}
