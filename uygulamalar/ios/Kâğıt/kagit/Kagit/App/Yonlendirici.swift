import KagitKit
import SwiftUI

/// Uygulama geneli gezinme durumu: seçili sekme, açık belge, açık araç.
@Observable
final class Yonlendirici {
    enum Sekme: Hashable { case anaSayfa, dosyalar, araclar, ogretmen, ayarlar }

    var sekme: Sekme = .anaSayfa
    /// Tam ekran açılan belge (düzenleyici).
    var acikBelge: KitaplikOgesi?
    /// Açılış kipi (ör. "imzala" kısayolundan gelince doğrudan imza kipi).
    var acilisKipi: BelgeKipi = .oku
    /// Sayfa olarak açılan araç ve hazır girdileri.
    var acikArac: AracIstegi?
    /// Tarayıcı ekranı.
    var taramaAcik = false
    /// Genel hata/bilgi iletisi.
    var ileti: Ileti?

    struct AracIstegi: Identifiable {
        let id = UUID()
        let arac: Arac
        var girdiler: [URL]
    }

    func ac(_ oge: KitaplikOgesi, kip: BelgeKipi = .oku) {
        acilisKipi = kip
        acikBelge = oge
    }

    func aracAc(_ arac: Arac, girdiler: [URL] = []) {
        acikArac = AracIstegi(arac: arac, girdiler: girdiler)
    }

    func aracAc(id: String, girdiler: [URL] = []) {
        if let a = AracKatalogu.bul(id) { aracAc(a, girdiler: girdiler) }
    }

    /// Dosyalar/Paylaş ile gelen dosyayı kitaplığa alıp açar.
    func disaridanAc(_ url: URL, kitaplik: Kitaplik) async {
        guard url.isFileURL else { return }
        do {
            let alinan = try await kitaplik.iceAktar([url])
            if let ilk = alinan.first, ilk.pdfMi { ac(ilk) } else { sekme = .dosyalar }
        } catch {
            ileti = Ileti(error)
        }
    }
}

/// Kullanıcıya gösterilecek kısa ileti.
struct Ileti: Identifiable, Equatable {
    let id = UUID()
    let baslik: String
    let metin: String
    var hata: Bool = true

    init(baslik: String = "Hata", metin: String, hata: Bool = true) {
        self.baslik = baslik
        self.metin = metin
        self.hata = hata
    }

    init(_ hata: Error) {
        baslik = "Hata"
        metin = (hata as? LocalizedError)?.errorDescription ?? hata.localizedDescription
        self.hata = true
    }
}

extension View {
    /// `Ileti` bağlamasını uyarı olarak gösterir.
    func iletiGoster(_ ileti: Binding<Ileti?>) -> some View {
        alert(ileti.wrappedValue?.baslik ?? "", isPresented: Binding(
            get: { ileti.wrappedValue != nil }, set: { if !$0 { ileti.wrappedValue = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(ileti.wrappedValue?.metin ?? "")
        }
    }
}
