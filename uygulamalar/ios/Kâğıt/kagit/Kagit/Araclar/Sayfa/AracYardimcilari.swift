import KagitKit
import Photos
import SwiftUI

/// Ağır işi arka plan iş parçacığında çalıştırır; üst görev iptal edilince iş de iptal edilir.
nonisolated func arkaPlanda<T: Sendable>(_ yap: @escaping @Sendable () throws -> T) async throws -> T {
    let gorev = Task.detached(priority: .userInitiated) { try yap() }
    return try await withTaskCancellationHandler { try await gorev.value } onCancel: { gorev.cancel() }
}

/// Toplu işlem: aynı işlemi her girdi dosyasına uygular, çıktıları birleştirir.
nonisolated func herDosyayaUygula(_ girdiler: [URL], _ ilerleme: @escaping Ilerleme,
                                  _ islem: @escaping @Sendable (URL) throws -> [URL]) async throws -> [URL] {
    try await arkaPlanda {
        var sonuc: [URL] = []
        for (i, u) in girdiler.enumerated() {
            try iptalDenetle()
            sonuc += try islem(u)
            ilerleme(Double(i + 1) / Double(girdiler.count))
        }
        return sonuc
    }
}

extension AracKatalogu {
    /// Katalogdaki aracı kimliğiyle getirir (ekranlar kendi aracını buradan alır).
    static func arac(_ id: String) -> Arac {
        guard let a = bul(id) else { fatalError("Araç kataloğunda yok: \(id)") }
        return a
    }
}

/// VPS'e dosya gönderen araçların ekranında gösterilen not.
struct SunucuNotu: View {
    private let ayarlar = Ayarlar.paylasilan

    var body: some View {
        Label(ayarlar.sunucuEtkin
              ? "Bu işlem için dosya kendi sunucuna gönderilecek; dönüşüm bitince sunucudan silinir."
              : "Sunucu kapalı. Bu dönüşüm için Ayarlar > Sunucu bölümünden açın.",
              systemImage: ayarlar.sunucuEtkin ? "icloud.and.arrow.up" : "icloud.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// PDF Studio istemcisi: adres ve anahtar ayarlardan.
@MainActor func pdfStudioIstemcisi() -> PDFStudioIstemcisi {
    PDFStudioIstemcisi(taban: Sunucu.pdfStudio, anahtar: Gizli.vekilAnahtari)
}

/// Sunucu kapalıyken sunucu gerektiren işlemde verilen hata.
func sunucuKapaliHatasi(_ ne: String) -> KagitHata {
    .desteklenmiyor("\(ne) için sunucu gerekli. Ayarlar > Sunucu bölümünden açın.")
}

extension Color {
    /// SwiftUI rengini KagitKit RGBA'sına çevirir.
    var kagitRGBA: RGBA {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(Double(r), Double(g), Double(b), Double(a))
    }
}

/// PDF sayfalarından çıkan görselleri Fotoğraflar'a kaydeder.
enum FotoKaydet {
    static func kaydet(_ urller: [URL]) async throws {
        let durum = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard durum == .authorized || durum == .limited else {
            throw KagitHata.genel("Fotoğraflar'a kaydetme izni verilmedi. Ayarlar'dan izin verin.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            for u in urller { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: u) }
        }
    }
}

/// Yalnız aralık seçeneği olan, tek dosyadan tek çıktı üreten araçlar için ortak ekran.
struct KisaDonusumEkrani: View {
    let aracId: String
    let baglam: AracBaglami
    var aralikVar = true
    var not: String?
    let islem: @Sendable (URL, String) throws -> [URL]
    @State private var aralik = ""

    var body: some View {
        let a = aralik
        AracSablonu(arac: AracKatalogu.arac(aracId), girdiler: baglam.girdiler, secenekler: {
            if aralikVar || not != nil {
                Section {
                    if aralikVar { SayfaAraligiAlani(metin: $aralik) }
                } footer: {
                    if let not { Text(not) }
                }
            }
        }, calistir: { girdiler, ilerleme in
            try await herDosyayaUygula(girdiler, ilerleme) { try islem($0, a) }
        })
    }
}
