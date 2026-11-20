import Foundation
import Observation

nonisolated struct TuvalSurumu: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let onceki: UUID?
    let metin: String
    let tarih: Date
    let aciklama: String
}

nonisolated struct TuvalBelgesi: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var baslik: String
    let tur: String
    let projeID: UUID?
    let olusturma: Date
    var surumler: [TuvalSurumu]
    var guncel: TuvalSurumu { surumler[surumler.count - 1] }
}

nonisolated struct TuvalTaslagi: Codable, Sendable {
    let temel: UUID
    let metin: String
}

nonisolated enum TuvalHatasi: LocalizedError {
    case bulunamadi, eskiSurum, gecersizSecim, sinir, bozuk
    var errorDescription: String? {
        switch self {
        case .bulunamadi: "Belge bulunamadı."
        case .eskiSurum: "Belge başka bir işlemde değişti. Metnin korunuyor; güncel sürümü açıp karşılaştır."
        case .gecersizSecim: "Seçili bölüm değişmiş veya geçersiz. Metni yeniden seç."
        case .sinir: "Tuval sınırı aşıldı: belge 200.000 karakter, toplam alan 50 MB. Hiçbir belge silinmedi."
        case .bozuk: "Belge okunamadı. Asıl dosya değiştirilmedi."
        }
    }
}

/// Her belge ve sürümleri tek atomik dosyada tutulur; disk yazımı başarısızsa bellek de değişmez.
@MainActor @Observable
final class TuvalDeposu {
    static let ortak = TuvalDeposu()
    private(set) var belgeler: [TuvalBelgesi] = []
    private(set) var okumaHatasi: String?
    let dizin: URL
    private let kota = 50 * 1024 * 1024

    init(dizin: URL? = nil) {
        let destek = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let test = ProcessInfo.processInfo.environment["ASISTAN_TEST"] == "1"
        self.dizin = dizin ?? (test ? FileManager.default.temporaryDirectory.appending(path: "TuvalTest-\(ProcessInfo.processInfo.processIdentifier)") : destek.appending(path: "Tuval"))
        do {
            try FileManager.default.createDirectory(at: self.dizin, withIntermediateDirectories: true)
            for yol in try FileManager.default.contentsOfDirectory(at: self.dizin, includingPropertiesForKeys: nil) where yol.pathExtension == "json" {
                do {
                    let b = try JSONDecoder().decode(TuvalBelgesi.self, from: Data(contentsOf: yol))
                    guard !b.surumler.isEmpty, yol.deletingPathExtension().lastPathComponent == b.id.uuidString else { throw TuvalHatasi.bozuk }
                    belgeler.append(b)
                } catch { okumaHatasi = "Bazı Tuval belgeleri okunamadı; dosyaları korunuyor." }
            }
            sirala()
        } catch { okumaHatasi = error.localizedDescription }
    }

    func bul(_ id: UUID) -> TuvalBelgesi? { belgeler.first { $0.id == id } }

    func taslak(_ id: UUID) -> TuvalTaslagi? {
        guard let veri = try? Data(contentsOf: taslakYolu(id)) else { return nil }
        return try? JSONDecoder().decode(TuvalTaslagi.self, from: veri)
    }

    func taslakKaydet(_ id: UUID, temel: UUID, metin: String) throws {
        guard metin.count <= 200_000 else { throw TuvalHatasi.sinir }
        guard bul(id) != nil else { throw TuvalHatasi.bulunamadi }
        let yol = taslakYolu(id)
        try FileManager.default.createDirectory(at: yol.deletingLastPathComponent(), withIntermediateDirectories: true)
        let veri = try JSONEncoder().encode(TuvalTaslagi(temel: temel, metin: metin))
        guard try toplamBoyut(haric: yol) + veri.count <= kota else { throw TuvalHatasi.sinir }
        try veri.write(to: yol, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func taslakYolu(_ id: UUID) -> URL { dizin.appending(path: "Taslaklar").appending(path: id.uuidString + ".json") }

    @discardableResult
    func olustur(baslik: String, metin: String, tur: String = "markdown", projeID: UUID? = nil) throws -> TuvalBelgesi {
        guard metin.count <= 200_000 else { throw TuvalHatasi.sinir }
        let ad = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = TuvalBelgesi(id: UUID(), baslik: String((ad.isEmpty ? "Yeni belge" : ad).prefix(160)), tur: tur,
                            projeID: projeID, olusturma: .now,
                            surumler: [TuvalSurumu(id: UUID(), onceki: nil, metin: metin, tarih: .now, aciklama: "İlk sürüm")])
        try yaz(b); belgeler.insert(b, at: 0); return b
    }

    @discardableResult
    func kaydet(_ id: UUID, temel: UUID, metin: String, aciklama: String = "Düzenleme") throws -> TuvalBelgesi {
        guard var b = bul(id) else { throw TuvalHatasi.bulunamadi }
        guard b.guncel.id == temel else { throw TuvalHatasi.eskiSurum }
        guard metin.count <= 200_000 else { throw TuvalHatasi.sinir }
        if b.guncel.metin == metin { eslesenTaslagiSil(id, temel: temel, metin: metin); return b }
        b.surumler.append(TuvalSurumu(id: UUID(), onceki: temel, metin: metin, tarih: .now, aciklama: String(aciklama.prefix(160))))
        try yaz(b)
        eslesenTaslagiSil(id, temel: temel, metin: metin)
        belgeler[belgeler.firstIndex { $0.id == id }!] = b
        sirala(); return b
    }

    /// UTF-16 konumları UITextView ile aynıdır; bölünmüş emoji ve eski seçim reddedilir.
    func secimiDegistir(_ id: UUID, temel: UUID, aralik: NSRange, beklenen: String, yeni: String) throws -> TuvalBelgesi {
        guard let b = bul(id) else { throw TuvalHatasi.bulunamadi }
        guard b.guncel.id == temel else { throw TuvalHatasi.eskiSurum }
        guard let aralik = Range(aralik, in: b.guncel.metin), String(b.guncel.metin[aralik]) == beklenen else { throw TuvalHatasi.gecersizSecim }
        var m = b.guncel.metin; m.replaceSubrange(aralik, with: yeni)
        return try kaydet(id, temel: temel, metin: m, aciklama: "Seçili bölüm düzenlendi")
    }

    func geriDon(_ id: UUID, surum: UUID, temel: UUID) throws -> TuvalBelgesi {
        guard let b = bul(id), let s = b.surumler.first(where: { $0.id == surum }) else { throw TuvalHatasi.bulunamadi }
        return try kaydet(id, temel: temel, metin: s.metin, aciklama: "Önceki sürüm geri getirildi")
    }

    func disaAktar(_ id: UUID) throws -> URL {
        guard let b = bul(id) else { throw TuvalHatasi.bulunamadi }
        let klasor = FileManager.default.temporaryDirectory.appending(path: "TuvalPaylasim")
        try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
        let yol = klasor.appending(path: "\(b.id.uuidString).\(b.tur == "html" ? "html" : "md")")
        try Data(b.guncel.metin.utf8).write(to: yol, options: .atomic)
        return yol
    }

    private func sirala() { belgeler.sort { $0.guncel.tarih > $1.guncel.tarih } }
    private func eslesenTaslagiSil(_ id: UUID, temel: UUID, metin: String) {
        guard let t = taslak(id), t.temel == temel, t.metin == metin else { return }
        try? FileManager.default.removeItem(at: taslakYolu(id))
    }
    private func yaz(_ b: TuvalBelgesi) throws {
        let veri = try JSONEncoder().encode(b), yol = dizin.appending(path: b.id.uuidString + ".json")
        let toplam = try toplamBoyut(haric: yol)
        guard toplam + veri.count <= kota else { throw TuvalHatasi.sinir }
        try veri.write(to: yol, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func toplamBoyut(haric: URL) throws -> Int {
        guard let e = FileManager.default.enumerator(at: dizin, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { throw TuvalHatasi.bozuk }
        var toplam = 0
        for case let yol as URL in e where yol != haric {
            let deger = try yol.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if deger.isRegularFile == true { toplam += deger.fileSize ?? 0 }
        }
        return toplam
    }
}
