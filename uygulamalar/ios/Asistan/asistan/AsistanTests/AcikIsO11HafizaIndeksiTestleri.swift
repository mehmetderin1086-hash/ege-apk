import Testing
import Foundation
import SQLite3
@testable import Asistan

/// O11: hafıza indeksi tam metin (4000 → 32.000 karakter), eşleşme özeti ve bir kez yeniden indeksleme.
@Suite("O11 hafıza indeksi tam metin") @MainActor
struct AcikIsO11HafizaIndeksiTestleri {
    /// `adet` karakterlik sözcük dolgusu ("lorem " tekrarı).
    private func dolgu(_ adet: Int) -> String { String(String(repeating: "lorem ", count: adet / 6 + 1).prefix(adet)) }

    @Test func dortBinKarakterdenSonrakiTerimBulunur() {
        let ix = HafizaIndeksi(bellekte: true)
        let metin = dolgu(5000) + " zeytinyagiprotein deneyini tartıştık " + dolgu(200)
        ix.ekle(tur: .mesaj, kimlik: "uzun", sohbet: "A", metin: metin)
        ix.ekle(tur: .mesaj, kimlik: "kisa", sohbet: "B", metin: "Bugün hava güzel")
        let r = ix.ara("zeytinyagiprotein", tur: .mesaj)
        #expect(r.map(\.kimlik) == ["uzun"], "5000. karakterden sonraki terim aranabilir (eskiden 4000'de kesiliyordu)")
        guard let ilk = r.first else { return }
        #expect(!ilk.metin.contains("zeytinyagiprotein"), "asil sütunu ilk 1500 karakterle sınırlı kalır")
        #expect(ilk.metin.count <= 1500)
        #expect(ilk.eslesme.contains("zeytinyagiprotein"), "eşleşme özeti terimi taşır: \(ilk.eslesme)")
        let t = HafizaIndeksi.terimler("zeytinyagiprotein")
        #expect(HafizaDeposu.parcaUygun(ilk, terimler: t), "geri çağırma süzgeci eşleşme özetiyle parçayı tutar")
        let p = HafizaDeposu.baglamParcasi(ilk, terimler: t)
        #expect(!p.eslesme.isEmpty, "terim önizlemede yoksa özet kalır")
        let baglam = HafizaDeposu.geriCagirmaMetni(HafizaDeposu.GeriCagirma(olgular: [], parcalar: [p]))
        #expect(baglam.contains("zeytinyagiprotein"), "model bağlamı eşleşen bölümü görür")
        #expect(baglam.contains("Geçmiş sohbetlerden"))
    }

    @Test func onizlemedeGorunenTerimdeOzetDusulur() {
        let ix = HafizaIndeksi(bellekte: true)
        ix.ekle(tur: .mesaj, kimlik: "1", sohbet: "A", metin: "Mitokondri zarı hakkında konuştuk. " + dolgu(3000))
        let r = ix.ara("mitokondri", tur: .mesaj)
        #expect(r.map(\.kimlik) == ["1"])
        guard let ilk = r.first else { return }
        let t = HafizaIndeksi.terimler("mitokondri")
        #expect(HafizaDeposu.parcaUygun(ilk, terimler: t))
        let p = HafizaDeposu.baglamParcasi(ilk, terimler: t)
        #expect(p.eslesme.isEmpty, "terim önizlemede görünüyorsa özet yinelenmez")
        let baglam = HafizaDeposu.geriCagirmaMetni(HafizaDeposu.GeriCagirma(olgular: [], parcalar: [p]))
        #expect(!baglam.contains(" … "), "özet eklenmez")
        #expect(baglam.contains("Mitokondri zarı"))
    }

    @Test func ilgisizParcaSuzgectenGecmez() {
        let ix = HafizaIndeksi(bellekte: true)
        ix.ekle(tur: .mesaj, kimlik: "1", sohbet: "A", metin: dolgu(4000) + " fotosentez " + dolgu(100))
        guard let ilk = ix.ara("fotosentez", tur: .mesaj).first else { Issue.record("sonuç bekleniyordu"); return }
        // İki terimli sorguda iki terim de geçmeli; yalnız biri geçiyorsa elenir.
        #expect(!HafizaDeposu.parcaUygun(ilk, terimler: HafizaIndeksi.terimler("fotosentez kloroplast")))
        #expect(HafizaDeposu.parcaUygun(ilk, terimler: HafizaIndeksi.terimler("fotosentez")))
    }

    @Test func ustSinirdanSonrakiTerimBulunmaz() {
        let ix = HafizaIndeksi(bellekte: true)
        let metin = dolgu(33_000) + " karadutzeytin " + dolgu(40_000 - 33_015)
        #expect(metin.count >= 40_000)
        ix.ekle(tur: .mesaj, kimlik: "dev", sohbet: "A", metin: metin)
        #expect(ix.say(tur: .mesaj) == 1)
        #expect(ix.ara("karadutzeytin", tur: .mesaj).isEmpty, "\(HafizaIndeksi.enFazlaIndeksMetni) karakterden sonrası indekslenmez")
        #expect(ix.ara("lorem", tur: .mesaj).map(\.kimlik) == ["dev"])
    }

    @Test func bellekIciIndeksSurumuYazilir() {
        let ix = HafizaIndeksi(bellekte: true)
        #expect(ix.hazir)
        #expect(ix.surum == HafizaIndeksi.indeksSurumu)
        #expect(HafizaIndeksi.indeksSurumu == 2)
    }

    @Test func eskiSurumluIndeksBirKezBosaltilir() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("o11-\(UUID().uuidString).sqlite")
        defer { for ek in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + ek) } }

        do {
            let ix = HafizaIndeksi(dosya: url)
            #expect(ix.hazir)
            ix.ekle(tur: .mesaj, kimlik: "eski", sohbet: "A", metin: "Eski kurala göre indekslenmiş mesaj")
            #expect(ix.say() == 1)
            #expect(ix.surum == 2)
        }

        // Dosyayı eski sürüme geri çek (4000 karakter kuralıyla yazılmış indeks gibi).
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version = 1;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        do {
            let ix = HafizaIndeksi(dosya: url)
            #expect(ix.say() == 0, "eski sürümlü indeks bir kez boşaltılır (senkron yeniden doldurur)")
            #expect(ix.surum == 2)
            ix.ekle(tur: .mesaj, kimlik: "yeni", sohbet: "A", metin: "Yeni kurala göre indekslenen mesaj")
            #expect(ix.say() == 1)
        }

        do {
            let ix = HafizaIndeksi(dosya: url)
            #expect(ix.say() == 1, "güncel sürümde yeniden açılış kaydı silmez")
            #expect(ix.ara("indekslenen", tur: .mesaj).map(\.kimlik) == ["yeni"])
            #expect(ix.surum == 2)
        }
    }
}
