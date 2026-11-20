import Foundation
import ZIPFoundation

/// Uygulama içi "Tanı paketi": maskeli tani.log/tani.1.log + ozet.txt tek .zip dosyasında (`/tani`, Sağlık → Tanı paketi).
/// Hiçbir anahtar ve sohbet içeriği eklenmez; günlük satırları pakete girerken yeniden maskelenir (eski satırlar için)
/// ve ayrıntılı tanıda yazılan ham istem metni "‹N karakter›" olur.
nonisolated enum TaniPaketi {
    static let onek = "Asistan-tani-"

    enum Hata: LocalizedError {
        case klasorYok
        var errorDescription: String? { "Belgeler klasörüne erişilemedi." }
    }

    /// Paketi ana aktör dışında hazırlar. `ozet` ana aktörde `ozetMetni()` ile kurulur.
    /// Aynı hedef klasördeki eski 'Asistan-tani-*.zip' dosyaları silinir.
    static func olustur(klasor: URL? = nil, hedefKlasor: URL = FileManager.default.temporaryDirectory,
                        ozet: String, zaman: Date = .now) async throws -> URL {
        guard let kaynak = klasor ?? TaniGunlugu.varsayilanKlasor else { throw Hata.klasorYok }
        return try await Task.detached(priority: .utility) {
            try paketle(klasor: kaynak, hedefKlasor: hedefKlasor, ozet: ozet, zaman: zaman)
        }.value
    }

    /// Eşzamanlı çekirdek (ana aktörde çağrılmaz).
    static func paketle(klasor: URL, hedefKlasor: URL, ozet: String, zaman: Date) throws -> URL {
        TaniGunlugu.bosalt()
        let fm = FileManager.default
        try fm.createDirectory(at: hedefKlasor, withIntermediateDirectories: true)
        for u in (try? fm.contentsOfDirectory(at: hedefKlasor, includingPropertiesForKeys: nil)) ?? []
        where u.lastPathComponent.hasPrefix(onek) && u.pathExtension.lowercased() == "zip" {
            try? fm.removeItem(at: u)
        }
        let hedef = hedefKlasor.appendingPathComponent(onek + dosyaZamani(zaman) + ".zip")
        let arsiv = try ZIPFoundation.Archive(url: hedef, accessMode: .create)
        do {
            for ad in [TaniGunlugu.eskiDosyaAdi, TaniGunlugu.dosyaAdi] {
                guard let ham = try? Data(contentsOf: klasor.appendingPathComponent(ad)) else { continue }
                let maskeli = String(decoding: ham, as: UTF8.self)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { istekMetniniGizle(TaniGunlugu.maskele(String($0))) }
                    .joined(separator: "\n")
                try ekle(arsiv, ad: ad, veri: Data(maskeli.utf8), zaman: zaman)
            }
            let metin = cihazOzeti(zaman: zaman) + "\n\n" + TaniGunlugu.maskele(ozet) + "\n"
            try ekle(arsiv, ad: "ozet.txt", veri: Data(metin.utf8), zaman: zaman)
        } catch {
            try? fm.removeItem(at: hedef)   // yarım .zip kalmasın
            throw error
        }
        return hedef
    }

    /// Ayrıntılı tanı açıkken "İSTEK … metin: <ham istem>" satırı yazılır; paylaşılan pakete ham istem girmez,
    /// kuyruk "‹N karakter›" olur (günlüğün kendisi cihazda kalır).
    static func istekMetniniGizle(_ satir: String) -> String {
        guard satir.contains(" İSTEK "), let r = satir.range(of: " metin: ") else { return satir }
        let n = satir[r.upperBound...].count
        return String(satir[..<r.upperBound]) + "‹\(n) karakter›"
    }

    private static func ekle(_ arsiv: ZIPFoundation.Archive, ad: String, veri: Data, zaman: Date) throws {
        try arsiv.addEntry(with: ad, type: .file, uncompressedSize: Int64(veri.count), modificationDate: zaman,
                           compressionMethod: .deflate) { konum, boyut in
            let bas = Int(konum)
            return veri.subdata(in: bas..<min(veri.count, bas + boyut))
        }
    }

    static func dosyaZamani(_ zaman: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: zaman)
    }

    /// Sürüm, iOS, makine kimliği, boş disk ve ayrıntılı tanı durumu (ana aktör gerekmez).
    static func cihazOzeti(zaman: Date = .now) -> String {
        let bilgi = Bundle.main.infoDictionary ?? [:]
        let kisa = bilgi["CFBundleShortVersionString"] as? String ?? "?"
        let derleme = bilgi["CFBundleVersion"] as? String ?? "?"
        let bos = (try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage)
            .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "bilinmiyor"
        let ayrinti = TaniGunlugu.ayrintiliBitis.flatMap { $0 > .now ? "açık (bitiş \($0.ISO8601Format()))" : nil } ?? "kapalı"
        return """
        Asistan tanı paketi · \(zaman.ISO8601Format())
        Sürüm: \(kisa) (\(derleme)) · \(SurumBilgisi.simdiki.uzun)
        iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Cihaz: \(makine())
        Boş disk: \(bos)
        Ayrıntılı tanı: \(ayrinti)
        """
    }

    static func makine() -> String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { b in String(decoding: b.prefix(while: { $0 != 0 }), as: UTF8.self) }
    }

    /// Ana aktörde kurulan özet: bağlantı durumu, model sayısı, sağlık ölçüm özetleri ve son 50 izleme kaydı.
    /// Anahtar ve sohbet içeriği girmez.
    @MainActor static func ozetMetni() -> String {
        var s: [String] = []
        let proxy = TelefonProxy.ortak
        s.append("Bağlantı: \(proxy.durum)")
        s.append("Model sayısı: \(proxy.modeller.count) (sohbet: \(proxy.modeller.filter(\.sohbet).count))")
        let merkez = SaglikMerkezi.ortak
        let turler = Set(merkez.olcumler.map(\.tur)).sorted()
        s.append("")
        s.append("Hız ölçümleri (son \(SaglikMerkezi.sinir) işlem):")
        if turler.isEmpty { s.append("• henüz ölçüm yok") }
        for tur in turler {
            guard let o = merkez.ozet(tur) else { continue }
            s.append("• \(tur): \(o.adet) örnek · ort \(Int(o.ortalamaMs)) ms · p95 \(Int(o.p95Ms)) ms · %\(Int(o.basariOrani * 100)) başarılı")
        }
        let izleme = IzlemeDefteri.ortak.hepsi().prefix(50)
        s.append("")
        s.append("İzleme kayıtları (son \(izleme.count)):")
        if izleme.isEmpty { s.append("• kayıt yok") }
        for k in izleme { s.append("• \(k.zaman.ISO8601Format()) \(k.tur.rawValue): \(k.ozet)") }
        return s.joined(separator: "\n")
    }
}
