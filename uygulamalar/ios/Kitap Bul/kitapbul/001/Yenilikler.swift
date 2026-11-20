import SwiftUI

/// Güncellemeden sonra bir kez gösterilen "Yenilikler" sayfası; Ayarlar > Yardım'dan yeniden açılabilir.
enum Yenilikler {
    static let anahtar = "lastSeenWhatsNewVersion"

    static var surum: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Yeni kurulumda gösterilmez (tanıtım zaten açılır); güncellemede bir kez gösterilir.
    static func gosterilmeli(sonGorulen: String?, surum: String, tanitimGoruldu: Bool) -> Bool {
        guard tanitimGoruldu else { return false }
        return sonGorulen != surum
    }

    struct Madde: Identifiable {
        let id = UUID()
        let ikon: String
        let renk: Color
        let baslik: String
        let detay: String
    }

    /// Sürüme göre yenilik listeleri, eskiden yeniye. Listede olmayan sürüm en son girdiyi gösterir.
    private static let surumMaddeleri: [(surum: String, maddeler: [Madde])] = [
        ("1.0", [
            Madde(ikon: "paintpalette.fill", renk: KitapTema.foto, baslik: "Anında tema",
                  detay: "Ana renk seçince ekran yeniden kurulmadan değişir; Ayarlar açık kalır ve önizleme kartı sonucu gösterir."),
            Madde(ikon: "lock.open.rotation", renk: KitapTema.vurgu, baslik: "Kısa süreli yönetici oturumu",
                  detay: "Başka uygulamaya kısa süre geçince Face ID yeniden sorulmaz; süreyi Ayarlar > Güvenlik’ten seçersiniz."),
            Madde(ikon: "slider.horizontal.3", renk: KitapTema.dosya, baslik: "Sadeleşen Ayarlar ve Yönetim",
                  detay: "Ayarlar altı görev bölümüne indi, sık kullanılanlar üstte. Yönetim son açtığınız araçları ve bekleyen işleri gösterir."),
            Madde(ikon: "externaldrive.badge.checkmark", renk: KitapTema.basari, baslik: "Veri güvenliği",
                  detay: "Günlük tam arşiv, 30 günlük çöp kutusu, açılışta bütünlük denetimi ve tanılama ekranı."),
            Madde(ikon: "checklist", renk: KitapTema.ana, baslik: "Kitaplar sekmesi",
                  detay: "Çoklu seçim, kayıtlı filtreler, A–Z dizini, seri eksikleri, nüshalar, benzer kitaplar ve iPad bölünmüş görünüm."),
            Madde(ikon: "barcode.viewfinder", renk: KitapTema.foto, baslik: "Daha akıllı tarama",
                  detay: "Barkodla birlikte arka kapak, canlı kapak tarama, eğik kapak düzeltme, videodan raf tarama, ISBN onarma önerileri."),
            Madde(ikon: "waveform.and.mic", renk: KitapTema.toplu, baslik: "Asistan ve Siri",
                  detay: "Toplu dikte, düzenleme komutları, grafikli yanıtlar, sohbet geçmişi, bas-konuş, 6 dil ve Siri kısayolları."),
            Madde(ikon: "person.2.badge.gearshape", renk: KitapTema.amazon, baslik: "Ödünç ve öğrenci",
                  detay: "Kart + barkodla hızlı ödünç, rezervasyon, süre uzatma, kayıp tutanağı, okuma puanı, sınıf panosu, sınıf atlatma."),
            Madde(ikon: "doc.richtext", renk: KitapTema.dosya, baslik: "Rapor ve baskı",
                  detay: "Dönem raporu, grafikler, okunmayanlar, sütun seçmeli CSV, QR kitap kartları ve renk bantlı sırt etiketleri."),
            Madde(ikon: "sparkles", renk: KitapTema.vurgu, baslik: "Yeni yapay zekâ araçları",
                  detay: "Kitap soruları, kişisel okuma listeleri, koleksiyon analizi, bağış değerlendirme, kategori tutarlılığı, aylık sınır."),
            Madde(ikon: "paintpalette", renk: KitapTema.foto, baslik: "Kişiselleştirme",
                  detay: "Ana renk seçimi, yüzen ekle düğmesi ve Face ID ile görevli/yönetici rolleri."),
        ])
    ]

    /// Verilen sürümün yenilikleri; bilinmeyen sürümde en son girdi.
    static func maddeler(surum: String) -> [Madde] {
        (surumMaddeleri.first { $0.surum == surum } ?? surumMaddeleri.last)?.maddeler ?? []
    }

    static var maddeler: [Madde] { maddeler(surum: surum) }
}

/// Açılışta ne gösterileceği: güncellemede Yenilikler, yeni kurulumda tanıtım. Saf karar;
/// `MainTabView` yalnız sonucu uygular (Yenilikler tanıtımdan önce gelir).
enum AcilisPlani: Equatable {
    case yenilikler, tanitim, hic

    static func yap(onboardingShown: Bool, sonGorulen: String, surum: String) -> AcilisPlani {
        if Yenilikler.gosterilmeli(sonGorulen: sonGorulen, surum: surum, tanitimGoruldu: onboardingShown) { return .yenilikler }
        return onboardingShown ? .hic : .tanitim
    }
}

struct YeniliklerSayfasi: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Yenilikler.maddeler) { madde in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: madde.ikon)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(madde.renk.gradient, in: .rect(cornerRadius: 10))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(madde.baslik).font(.headline)
                                Text(madde.detay).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Sürüm \(Yenilikler.surum)")
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Yenilikler")
            // Büyük, yüksek kontrastlı düğme (araç çubuğu düğmesi kontrast denetiminden geçmiyordu)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    // Ayarlar > Yardım'dan da açılır; "Başla" orada yanıltıcıydı
                    Text("Tamam").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kitapDolu(KitapTema.ana))
                .padding()
                .background(.bar)
            }
        }
    }
}
