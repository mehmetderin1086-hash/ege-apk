import Foundation
import CryptoKit
import Darwin

/// İşçi hiçbir global defter, UserDefaults, ModelContext veya yol override'ı
/// okumaz. Doğrulanmış özel yedek dosyaları ve değişmez yol değerleri alır.
nonisolated enum ArchiveSwitchLeaseWorker {
    struct FileSeal: Equatable, Sendable {
        let path: String
        let size: UInt64
        let modified: Date
        let inode: UInt64
        let device: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        static func capture(_ url: URL) throws -> FileSeal {
            // lstat bir tek disk metadata snapshot'ı verir; symlink takip etmez.
            // ctime kullanıcı tarafından eski mtime gibi geri ayarlanamaz. Aynı
            // inode/boyut ve geri yüklenmiş mtime ile yerinde değişiklik de yakalanır.
            var information = stat()
            let result = url.path.withCString { Darwin.lstat($0, &information) }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            guard UInt32(information.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG), information.st_size >= 0 else {
                throw Failure(message: "Geçiş yedeği normal özel dosya değil; işlem başlamadı.")
            }
            let mtime = information.st_mtimespec, ctime = information.st_ctimespec
            return FileSeal(path: url.standardizedFileURL.resolvingSymlinksInPath().path,
                size: UInt64(information.st_size),
                modified: Date(timeIntervalSince1970: Double(mtime.tv_sec) + Double(mtime.tv_nsec) / 1_000_000_000),
                inode: UInt64(information.st_ino), device: UInt64(UInt32(bitPattern: information.st_dev)),
                modifiedSeconds: Int64(mtime.tv_sec), modifiedNanoseconds: Int64(mtime.tv_nsec),
                changedSeconds: Int64(ctime.tv_sec), changedNanoseconds: Int64(ctime.tv_nsec))
        }

        func validateCurrent() throws {
            let url = URL(fileURLWithPath: path)
            guard try Self.capture(url) == self else {
                throw Failure(message: "Doğrulanan geçiş yedeğinin dosya kimliği, boyutu, değiştirilme veya metadata değişim zamanı değişmiş; yeni prova gerekli.")
            }
        }
    }

    struct Proof: Sendable {
        let directory: URL
        let backupRoot: URL
        let beforeFingerprint: String
        let hashes: [String: String]
        let seals: [String: FileSeal]

        /// Ana aktörde büyük dosya okumaz/ZIP çözmez. Sealed private dosyaların
        /// yol, dosya kimliği, boyut ve zamanının işçi sonucuyla aynı kaldığını denetler.
        func validateCurrent(backupRoot expectedRoot: URL) throws {
            guard expectedRoot.standardizedFileURL.resolvingSymlinksInPath() == backupRoot,
                  directory.standardizedFileURL.resolvingSymlinksInPath() == directory,
                  directory.path.hasPrefix(backupRoot.path + "/"),
                  Set(hashes.keys) == Set(seals.keys) else {
                throw Failure(message: "Doğrulanmış geçiş yedeğinin yol veya tam dosya kapsamı değişmiş.")
            }
            for (name, seal) in seals {
                guard directory.appendingPathComponent(name).standardizedFileURL.path == seal.path else {
                    throw Failure(message: "Doğrulanmış yedek dosyası özel dizinden çıkıyor.")
                }
                try seal.validateCurrent()
            }
        }
    }

    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Her dosyanın SHA256'sı, index tamlığı, güvenli ayar JSON'u ve önceki tam
    /// arşivin bütün ilişkileri+fingerprint işçi üzerinde denetlenir.
    static func verify(directory rawDirectory: URL, backupRoot rawRoot: URL,
                       beforeFingerprint: String, expectedHashes: [String: String]? = nil) throws -> Proof {
        let root = rawRoot.standardizedFileURL.resolvingSymlinksInPath()
        let directory = rawDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/"),
              (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw Failure(message: "Geçiş yedeği özel katalog yedek dizininde değil.")
        }
        func read(_ name: String) throws -> (Data, FileSeal) {
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
                throw Failure(message: "Ham geçiş yedeğinin dosya adı geçersiz.")
            }
            let url = directory.appendingPathComponent(name)
            guard url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == directory else {
                throw Failure(message: "Ham geçiş yedeği özel dizinin dışına çıkıyor.")
            }
            let seal = try FileSeal.capture(url)
            let data = try Data(contentsOf: url)
            guard try FileSeal.capture(url) == seal else { throw Failure(message: "Ham geçiş yedeği okuma sırasında değişmiş.") }
            return (data, seal)
        }
        let indexRead = try read("dosya-dizini.json")
        let index = try JSONDecoder().decode([String: String].self, from: indexRead.0)
        let required = Set(index.keys).union(["dosya-dizini.json", "onceki-ayarlar.json", "Islem-Oncesi-Tam-Arsiv.zip"])
        if let expectedHashes, Set(expectedHashes.keys) != required {
            throw Failure(message: "Bekleyen geçiş günlüğünün tam ham yedek kapsamı eksik.")
        }
        var hashes: [String: String] = [:], seals: [String: FileSeal] = [:]
        var archive = Data(), preferences = Data()
        for name in required.sorted() {
            let item: (Data, FileSeal)
            if name == "dosya-dizini.json" { item = indexRead } else { item = try read(name) }
            let hash = digest(item.0)
            if let expectedHashes, expectedHashes[name] != hash {
                throw Failure(message: "Bekleyen geçişin ham yedeği değişmiş; katalog etkinleştirilmedi.")
            }
            hashes[name] = hash; seals[name] = item.1
            if name == "Islem-Oncesi-Tam-Arsiv.zip" { archive = item.0 }
            if name == "onceki-ayarlar.json" { preferences = item.0 }
        }
        _ = try JSONDecoder().decode([String: Data].self, from: preferences)
        let contents = try FullArchive.readValidated(data: archive)
        guard try ArchiveImportCoordinator.fingerprint(contents) == beforeFingerprint else {
            throw Failure(message: "Önceki tam arşivin ilişki ve kapsam doğrulaması başarısız.")
        }
        let proof = Proof(directory: directory, backupRoot: root, beforeFingerprint: beforeFingerprint, hashes: hashes, seals: seals)
        try proof.validateCurrent(backupRoot: rawRoot)
        return proof
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
