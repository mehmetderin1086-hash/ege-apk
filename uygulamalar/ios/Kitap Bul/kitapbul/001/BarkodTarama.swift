import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
import VisionKit
#endif

// MARK: - Okutma geri bildirimi (Ekle → Sayım sözleşmesi)

/// Sürekli tarayıcıda her okutmanın sonucu. `LiveISBNScannerView(onScanResult:)` bu değeri alır ve
/// titreşimi buna göre verir: başarıda hafif, uyarıda çift, hatada sert titreşim; `none` sessizdir.
nonisolated enum ScanFeedback: Equatable, Sendable {
    case success, warning, error, none
}

// MARK: - Tarama kipi

/// Barkod tarayıcının tek kipi. Eskiden birbirini dışlayan beş ayrı Bool bayrağıydı; aynı anda ikisi
/// açık kalabiliyordu.
enum TaramaKipi {
    case tekli
    /// Kitaplar künyeleriyle kuyruğa alınır; `BulkAssignment` konum/kategori atamasıdır.
    case seri(BulkAssignment, otoKayit: Bool)
    /// Ağsız hızlı kayıt: konum, dolap ve raf ContentView'daki canlı durumdadır (Raf + ile ilerler).
    case depo
    case rafAtama
    case arama

    var seri: Bool { if case .seri = self { true } else { false } }
    var depo: Bool { if case .depo = self { true } else { false } }
    var rafAtama: Bool { if case .rafAtama = self { true } else { false } }
    var arama: Bool { if case .arama = self { true } else { false } }
    /// Tarayıcı bir okutmadan sonra açık kalıyor mu?
    var surekli: Bool { seri || depo || rafAtama }
    /// Alttaki canlı bilgi paneli (günlük, sayaç, Geri Al) görünür mü?
    var panelGerekli: Bool { surekli }
}

// MARK: - Kamera izni

/// Tarayıcıyı açmadan önce kamera izninin durumu. `DataScannerViewController.isAvailable` izin
/// reddedilince de `false` döner; eskiden bu "cihaz desteklemiyor" diye gösteriliyordu.
enum KameraIzni {
    enum Sonuc: Equatable {
        case izinli
        /// Kullanıcı reddetti ya da kısıtlı: Ayarlar'a yönlendirilir.
        case reddedildi
        /// Cihazda ya da simülatörde canlı tarayıcı yok.
        case desteklenmiyor
    }

    /// Saf karar: durum ve cihaz yeteneğinden sonuç. `izinIste` yalnız belirsiz durumda çağrılır.
    static func karar(durum: AVAuthorizationStatus, destekleniyor: Bool, kullanilabilir: Bool,
                      izinIste: () async -> Bool) async -> Sonuc {
        guard destekleniyor else { return .desteklenmiyor }
        switch durum {
        case .denied, .restricted:
            return .reddedildi
        case .notDetermined:
            guard await izinIste() else { return .reddedildi }
        default:
            break
        }
        return kullanilabilir ? .izinli : .desteklenmiyor
    }

#if os(iOS)
    static func iste() async -> Sonuc {
        let ilkDurum = AVCaptureDevice.authorizationStatus(for: .video)
        let destekleniyor = DataScannerViewController.isSupported
        let sonuc = await karar(durum: ilkDurum, destekleniyor: destekleniyor, kullanilabilir: true,
                                izinIste: { await AVCaptureDevice.requestAccess(for: .video) })
        guard sonuc == .izinli else { return sonuc }
        // İzin yeni verildiyse kullanılabilirlik ancak şimdi doğru okunur.
        return DataScannerViewController.isAvailable ? .izinli : .desteklenmiyor
    }

    static func ayarlariAc() {
        guard let adres = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(adres)
    }
#endif
}

/// "Kamera izni kapalı" uyarısı ve Ayarlar'a götüren düğme. Ayrı modifier: ContentView gövdesindeki
/// uzun zincire ağır bir `alert` eklemek tür denetimini yavaşlatır.
struct KameraIzniUyarisi: ViewModifier {
    @Binding var goster: Bool

    func body(content: Content) -> some View {
        content.alert("Kamera izni kapalı", isPresented: $goster) {
#if os(iOS)
            Button("Ayarlar'ı Aç") { KameraIzni.ayarlariAc() }
#endif
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Barkod okutmak için Ayarlar'dan Kitap Bul'a kamera izni verin.")
        }
    }
}

// MARK: - Denetleyici

/// Tarayıcı oturumunun geçici durumu: kip, sayaç, günlük, kalıcı ISBN kuyruğu ve art arda okutma
/// bastırıcısı. Görünümden ayrıldığı için kamera olmadan sınanır.
@Observable
final class BarkodTaramaDenetleyicisi {
    var kip: TaramaKipi = .tekli
    var okunan = 0
    var gunluk: [String] = []
    /// Tarayıcı kapanmadan okunması gereken hata (ör. kamera başlatılamadı).
    var hata: String?
    /// ISBN başına bu oturumda eklenen nüsha; günlükte kümülatif adet olarak görünür.
    var oturumAdetleri: [String: Int] = [:]
    @ObservationIgnored var tekrar = TekrarBastirici()

    /// İşlenmeyi bekleyen ISBN'ler (sıralı).
    private(set) var kuyruk: [String] = []
    /// Künyesi şu an alınan ISBN. Bitene dek kalıcı listede kalır; uygulama kapanırsa kaybolmaz.
    private(set) var islenen: String?

    static let gunlukSatiri = 4

    func gunlugeEkle(_ satir: String) {
        gunluk.append(satir)
        if gunluk.count > Self.gunlukSatiri { gunluk.removeFirst(gunluk.count - Self.gunlukSatiri) }
    }

    func isbnEkle(_ isbn: String) { kuyruk.append(isbn) }

    /// Sıradaki ISBN'i işleme alır; `islemBitti()` çağrılana dek kalıcı listede durur.
    func siradakiniAl() -> String? {
        guard !kuyruk.isEmpty else { return nil }
        let isbn = kuyruk.removeFirst()
        islenen = isbn
        return isbn
    }

    func islemBitti() { islenen = nil }

    /// Kayıt penceresi kapandığı için yarım kalan ISBN, sıranın başına geri döner.
    func islenenigeriVer() {
        guard let isbn = islenen else { return }
        kuyruk.insert(isbn, at: 0)
        islenen = nil
    }

    /// Diske yazılacak liste: işlenen ISBN başta, ardından bekleyenler. Boşsa `nil` (JSON'da alan yok).
    var bekleyenISBNler: [String]? {
        let liste = (islenen.map { [$0] } ?? []) + kuyruk
        return liste.isEmpty ? nil : liste
    }

    var bekleyenSayisi: Int { kuyruk.count + (islenen == nil ? 0 : 1) }

    /// Açılışta yarım kalan oturumdan kuyruğu devralır.
    func devral(bekleyen: [String]) {
        kuyruk = bekleyen
        islenen = nil
    }

    func sifirla() {
        okunan = 0
        gunluk = []
        hata = nil
        oturumAdetleri = [:]
        tekrar = TekrarBastirici()
    }

    /// Günlük satırı için kümülatif adet: "adet +1 (bu oturumda 3 nüsha)".
    func nushaEklendi(isbn: String, adet: Int) -> Int {
        let toplam = oturumAdetleri[isbn, default: 0] + adet
        oturumAdetleri[isbn] = toplam
        return toplam
    }
}

// MARK: - Alt bilgi paneli

/// Depo, seri ve raf atama taramasında kameranın altındaki canlı panel. Büyük yazı boyutunda düğmeler
/// alt alta iner, günlük satırları iki satıra kadar uzar ve VoiceOver paneli tek kap olarak okur.
struct TaramaPaneli: View {
    var gunluk: [String]
    var durumMetni: String
    var rafArtirGoster: Bool
    var geriAlGoster: Bool
    var sonKitabaArtiGoster: Bool
    var onRafArtir: () -> Void
    var onGeriAl: () -> Void
    var onSonKitabaArti: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            if !gunluk.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(gunluk.enumerated()), id: \.offset) { _, satir in
                        Text(satir)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Son okutmalar")
                .accessibilityValue(gunluk.joined(separator: ". "))
                .accessibilityIdentifier("scanner.log")
            }

            let duzen = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 12))
            duzen {
                Text(durumMetni)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scanner.status")

                if rafArtirGoster {
                    Button(action: onRafArtir) {
                        Label("Raf +", systemImage: "plus.rectangle.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("scanner.shelfNext")
                }
                if sonKitabaArtiGoster {
                    Button { onSonKitabaArti(1) } label: {
                        Label("Son kitaba +1", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .contextMenu {
                        Button("Son kitaba +2") { onSonKitabaArti(2) }
                        Button("Son kitaba +5") { onSonKitabaArti(5) }
                        Button("Son kitaba +10") { onSonKitabaArti(10) }
                    }
                    .accessibilityHint("Uzun basarak birden çok nüsha ekleyebilirsiniz")
                    .accessibilityIdentifier("scanner.plusOne")
                }
                if geriAlGoster {
                    Button(action: onGeriAl) {
                        Label("Geri Al", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("scanner.undo")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 20 : 28))
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.panel")
    }
}

/// Kamera hatası şeridi: tarayıcı kapanmaz, hata kapağın içinde okunur.
struct TaramaHataSeridi: View {
    let mesaj: String

    var body: some View {
        Label(mesaj, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scanner.error")
    }
}
