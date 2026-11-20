import Foundation
import Testing
@testable import Asistan

/// O8: paylaşım uzantısında Vazgeç/kapatma, geçici klasöre kopyalanan dosyaları siler; kök dışına dokunmaz.
/// Kök enjekte edilir (gerçek tmp köküne ya da kapsayıcı köküne yazmaya bağlı kalmaz).
@Suite("Paylaşım Vazgeç temizliği (O8)") struct AcikIsO8PaylasimTemizlikTestleri {
    private let fm = FileManager.default

    private func klasor(_ ad: String) throws -> URL {
        let u = fm.temporaryDirectory.appending(path: ad, directoryHint: .isDirectory)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func dosya(_ klasor: URL, _ ad: String) throws -> URL {
        let u = klasor.appending(path: ad)
        try Data("o8".utf8).write(to: u)
        return u
    }

    @Test func kokAltindakiIkiDosyaSilinir() throws {
        let kok = try klasor("o8-\(UUID())")
        defer { try? fm.removeItem(at: kok) }
        let a = try dosya(kok, "\(UUID())-a.pdf"), b = try dosya(kok, "\(UUID())-b.jpg")
        #expect(PaylasimKutusu.geciciDosyalariSil([a, b], kok: kok) == 2)
        #expect(!fm.fileExists(atPath: a.path))
        #expect(!fm.fileExists(atPath: b.path))
    }

    @Test func kokDisindakiDosyaSilinmez() throws {
        let kok = try klasor("o8-\(UUID())")
        let dis = try klasor("o8-dis-\(UUID())")
        defer { try? fm.removeItem(at: kok); try? fm.removeItem(at: dis) }
        let d = try dosya(dis, "kutu.pdf")
        #expect(PaylasimKutusu.geciciDosyalariSil([d], kok: kok) == 0)
        #expect(fm.fileExists(atPath: d.path))
        // ".." ile kökten dışarı çıkan yol da standartlaştırılır ve korunur.
        let kacak = kok.appending(path: "..").appending(path: dis.lastPathComponent).appending(path: "kutu.pdf")
        #expect(PaylasimKutusu.geciciDosyalariSil([kacak], kok: kok) == 0)
        #expect(fm.fileExists(atPath: d.path))
        // Kökün kendisi silinmez.
        #expect(PaylasimKutusu.geciciDosyalariSil([kok], kok: kok) == 0)
        #expect(fm.fileExists(atPath: kok.path))
    }

    @Test func olmayanDosyaHataAtmaz() throws {
        let kok = try klasor("o8-\(UUID())")
        defer { try? fm.removeItem(at: kok) }
        let yok = kok.appending(path: "yok-\(UUID()).pdf")
        #expect(PaylasimKutusu.geciciDosyalariSil([yok], kok: kok) == 0)
        // Karışık listede yalnız var olan sayılır.
        let var1 = try dosya(kok, "var.pdf")
        #expect(PaylasimKutusu.geciciDosyalariSil([yok, var1], kok: kok) == 1)
        #expect(PaylasimKutusu.geciciDosyalariSil([], kok: kok) == 0)
    }

    @Test func onekKardesKlasoruKorunur() throws {
        let kok = try klasor("o8-\(UUID())")
        let kardes = URL(fileURLWithPath: kok.path + "-x", isDirectory: true)
        try fm.createDirectory(at: kardes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: kok); try? fm.removeItem(at: kardes) }
        let kd = try dosya(kardes, "kardes.pdf")
        #expect(PaylasimKutusu.geciciDosyalariSil([kd], kok: kok) == 0)
        #expect(fm.fileExists(atPath: kd.path))
    }

    @Test func varsayilanKokGeciciKlasordur() throws {
        // Uzantının ParcaYukleyici.kopyala'sı gibi doğrudan geçici klasöre yazılmış kopya varsayılan kökle silinir.
        let u = fm.temporaryDirectory.appending(path: "\(UUID())-o8.pdf")
        try Data("o8".utf8).write(to: u)
        defer { try? fm.removeItem(at: u) }
        #expect(PaylasimKutusu.geciciDosyalariSil([u]) == 1)
        #expect(!fm.fileExists(atPath: u.path))
    }

    @Test func dosyaOlmayanURLGecilir() {
        let web = URL(string: "https://ornek.com/a.pdf")!
        #expect(PaylasimKutusu.geciciDosyalariSil([web]) == 0)
    }
}
