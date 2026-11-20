import CoreSpotlight
import KagitKit
import PDFKit
import SwiftUI

/// Spotlight + Kısayollar kurulumu. `KagitApp` yalnız `.sistemKurulumu(...)` çağırır.
enum SistemKurulumu {
    /// Kısayollar eylemlerinin uygulamayı yönlendirebilmesi için.
    static weak var yonlendirici: Yonlendirici?
    private static var kuruldu = false

    static func kur(kitaplik: Kitaplik) {
        guard !kuruldu else { return }
        kuruldu = true
        kitaplik.taramaSonrasi.append { ogeler in SpotlightDizini.paylasilan.guncelle(ogeler) }
        SpotlightDizini.paylasilan.guncelle(kitaplik.ogeler)
        KagitKisayollari.updateAppShortcutParameters()
    }

    /// Spotlight sonucuna dokunulunca belgeyi açar.
    static func spotlightAc(_ etkinlik: NSUserActivity, kitaplik: Kitaplik, yon: Yonlendirici) {
        guard let yol = etkinlik.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let oge = kitaplik.oge(yol: yol), oge.pdfMi else { return }
        yon.ac(oge)
    }
}

extension View {
    func sistemKurulumu(kitaplik: Kitaplik, yon: Yonlendirici) -> some View {
        task {
            SistemKurulumu.yonlendirici = yon
            SistemKurulumu.kur(kitaplik: kitaplik)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { SistemKurulumu.spotlightAc($0, kitaplik: kitaplik, yon: yon) }
    }
}

/// Kitaplıktaki PDF'leri (ad + ilk 2 sayfa metni) Spotlight'a dizinler; değişmeyenleri yeniden dizinlemez.
final class SpotlightDizini {
    static let paylasilan = SpotlightDizini()
    private let alan = "com.mehmetderin.kagit.belge"
    private let anahtar = "spotlight.imzalar"
    private var calisiyor = false
    private var bekleyen: [KitaplikOgesi]?

    func guncelle(_ ogeler: [KitaplikOgesi]) {
        guard !calisiyor else { bekleyen = ogeler; return }
        calisiyor = true
        let pdfler = ogeler.filter(\.pdfMi)
        let eski = UserDefaults.standard.dictionary(forKey: anahtar) as? [String: String] ?? [:]
        let alan = alan
        Task {
            let yeni = await Task.detached(priority: .utility) { Self.dizinle(pdfler, eski: eski, alan: alan) }.value
            UserDefaults.standard.set(yeni, forKey: anahtar)
            calisiyor = false
            if let b = bekleyen { bekleyen = nil; guncelle(b) }
        }
    }

    /// Yeni imza tablosunu döndürür.
    nonisolated private static func dizinle(_ pdfler: [KitaplikOgesi], eski: [String: String], alan: String) -> [String: String] {
        let indeks = CSSearchableIndex.default()
        var yeni: [String: String] = [:]
        var degisenler: [KitaplikOgesi] = []
        for o in pdfler {
            let im = "\(o.boyut)-\(Int(o.degistirilme.timeIntervalSince1970))"
            yeni[o.yol] = im
            if eski[o.yol] != im { degisenler.append(o) }
        }
        let silinen = Set(eski.keys).subtracting(yeni.keys)
        if !silinen.isEmpty { indeks.deleteSearchableItems(withIdentifiers: Array(silinen)) { _ in } }

        var grup: [CSSearchableItem] = []
        func bosalt() {
            guard !grup.isEmpty else { return }
            indeks.indexSearchableItems(grup) { _ in }
            grup = []
        }
        for o in degisenler {
            let nitelik = CSSearchableItemAttributeSet(contentType: .pdf)
            let ad = o.url.deletingPathExtension().lastPathComponent
            nitelik.title = ad
            nitelik.displayName = ad
            var metin = ""
            if !UserDefaults.standard.bool(forKey: "kilitEtkin"), let b = PDFDocument(url: o.url), !b.isLocked {
                for i in 0..<min(2, b.pageCount) { metin += (b.page(at: i)?.string ?? "") + "\n" }
            }
            metin = String(metin.prefix(6000))
            nitelik.textContent = metin
            nitelik.contentDescription = String(metin.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
            nitelik.contentModificationDate = o.degistirilme
            let oge = CSSearchableItem(uniqueIdentifier: o.yol, domainIdentifier: alan, attributeSet: nitelik)
            grup.append(oge)
            if grup.count >= 40 { bosalt() }
        }
        bosalt()
        return yeni
    }
}
