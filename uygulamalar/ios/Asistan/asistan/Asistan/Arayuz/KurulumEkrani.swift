import SwiftUI
import Observation
@preconcurrency import WidgetKit

// P2.4: Ayarlar'ın tepesindeki "Kurulum durumu": bağlantı, zorunlu izinler, bulut sesi, Kontrol Merkezi ve Siri.
// Hesap saftır (`KurulumHesabi`, birim testli); okuma `KurulumDurumu.yenile()`'de.

nonisolated struct KurulumAdimi: Identifiable, Equatable, Sendable {
    enum Durum: Equatable, Sendable { case tamam, eksik, bilinmiyor }
    let id: String
    let baslik: String
    let ayrinti: String
    let durum: Durum
}

nonisolated enum KurulumHesabi {
    /// Kurulumun beş adımı. `kontrolEklendi` nil: iOS Kontrol Merkezi listesini veremedi.
    /// `tetikKullanildi`: asistan://dinle bir kez açıldı (Kontrol Merkezi, Siri ya da Eylem düğmesi).
    static func adimlar(proxyHazir: Bool, hesapSayisi: Int, izinler: [IzinTuru: IzinDurumu], bulutSesHatasi: Bool,
                        sesKimligi: String, kontrolEklendi: Bool?, tetikKullanildi: Bool, siriKullanildi: Bool) -> [KurulumAdimi] {
        var sonuc: [KurulumAdimi] = []

        // Bağlantı
        if proxyHazir && hesapSayisi > 0 {
            sonuc.append(.init(id: "baglanti", baslik: "Bağlantı", ayrinti: "CLI Proxy'de \(hesapSayisi) hesap bağlı.", durum: .tamam))
        } else {
            let neden = proxyHazir ? "CLI Proxy'de bağlı hesap yok." : "CLI Proxy hesaplarına bağlanılamadı."
            sonuc.append(.init(id: "baglanti", baslik: "Bağlantı", ayrinti: neden + " Bağlantıyı sına.", durum: .eksik))
        }

        // İzinler: yalnız mikrofon ve konuşma tanıma zorunlu; öbürleri gerektiğinde sorulur, eksik sayılmaz.
        let zorunlu: [IzinTuru] = [.mikrofon, .konusma]
        let eksikZorunlu = zorunlu.filter { izinler[$0] != .verildi }
        let kapaliDiger = IzinTuru.allCases.filter { !zorunlu.contains($0) && (izinler[$0] == .reddedildi || izinler[$0] == .kisitli) }
        if eksikZorunlu.isEmpty {
            let not = kapaliDiger.isEmpty ? "Mikrofon ve konuşma tanıma açık."
                : "Mikrofon ve konuşma tanıma açık. Kapalı: " + kapaliDiger.map(\.ad).joined(separator: ", ") + "."
            sonuc.append(.init(id: "izinler", baslik: "İzinler", ayrinti: not, durum: .tamam))
        } else {
            let adlar = eksikZorunlu.map(\.ad).joined(separator: " ve ")
            sonuc.append(.init(id: "izinler", baslik: "İzinler", ayrinti: "\(adlar) izni gerekli.", durum: .eksik))
        }

        // Ses: iPhone sesi çevrimdışı çalışır; bulut sesi (Azure Elif, OpenAI) vekile ulaşabilmeli.
        let bulutSesi = !sesKimligi.hasPrefix("apple")
        if bulutSesi && bulutSesHatasi {
            sonuc.append(.init(id: "ses", baslik: "Ses", ayrinti: "Bulut sesine ulaşılamıyor; yanıtlar iPhone sesiyle okunabilir.", durum: .eksik))
        } else {
            sonuc.append(.init(id: "ses", baslik: "Ses", ayrinti: bulutSesi ? "Bulut sesi hazır." : "iPhone sesi (çevrimdışı).", durum: .tamam))
        }

        // Kontrol Merkezi
        switch kontrolEklendi {
        case true?:
            sonuc.append(.init(id: "kontrol", baslik: "Kontrol Merkezi", ayrinti: "Asistan kontrolü ekli.", durum: .tamam))
        case false?:
            sonuc.append(.init(id: "kontrol", baslik: "Kontrol Merkezi", ayrinti: "\"Asistan'ı başlat\" kontrolü ekli değil.", durum: .eksik))
        case nil:
            if tetikKullanildi {
                sonuc.append(.init(id: "kontrol", baslik: "Kontrol Merkezi", ayrinti: "Hızlı başlatma daha önce kullanıldı.", durum: .tamam))
            } else {
                sonuc.append(.init(id: "kontrol", baslik: "Kontrol Merkezi", ayrinti: "iOS bu bilgiyi vermedi.", durum: .bilinmiyor))
            }
        }

        // Siri: iOS cümlenin kurulu olup olmadığını söylemez; yalnız bir kez kullanıldıysa bilinir.
        if siriKullanildi {
            sonuc.append(.init(id: "siri", baslik: "Siri", ayrinti: "Siri ile soru sorulmuş.", durum: .tamam))
        } else {
            sonuc.append(.init(id: "siri", baslik: "Siri", ayrinti: "‘Hey Siri, Asistan ile konuş’ de.", durum: .bilinmiyor))
        }
        return sonuc
    }

    static func eksikSayisi(_ adimlar: [KurulumAdimi]) -> Int { adimlar.filter { $0.durum == .eksik }.count }
}

@MainActor @Observable final class KurulumDurumu {
    static let ortak = KurulumDurumu()
    nonisolated static let siriAnahtari = "kurulum.siriKullanildiV1"
    nonisolated static let tetikAnahtari = "kurulum.tetikKullanildiV1"
    nonisolated static let kontrolTurleri: Set<String> = ["com.mehmetderin.asistan.kontrol", "com.mehmetderin.asistan.canli-kontrol"]

    private(set) var adimlar: [KurulumAdimi] = []
    private(set) var yenileniyor = false
    var eksik: Int { KurulumHesabi.eksikSayisi(adimlar) }

    func yenile() async {
        // Çekmece ve Ayarlar aynı anda isteyebilir: süren yenileme varken ikincisi koşmaz.
        guard !yenileniyor else { return }
        yenileniyor = true
        defer { yenileniyor = false }
        let izinler = await IzinDenetcisi.hepsi()
        let kontrol = await Self.kontrolEkliMi()
        let d = UserDefaults.standard
        let sesKimligi = d.string(forKey: "ayar.sesKimligi") ?? "azure:Elif"
        adimlar = KurulumHesabi.adimlar(
            proxyHazir: TelefonProxy.ortak.hazir, hesapSayisi: TelefonProxy.ortak.hesapSayisi, izinler: izinler,
            bulutSesHatasi: AsistanSesleri.ortak.hata != nil || Gizli.vekilToken == nil, sesKimligi: sesKimligi,
            kontrolEklendi: kontrol, tetikKullanildi: d.bool(forKey: Self.tetikAnahtari), siriKullanildi: d.bool(forKey: Self.siriAnahtari))
    }

    /// Kontrol Merkezi'ne Asistan kontrollerinden biri eklendi mi; iOS listeyi veremezse nil.
    nonisolated static func kontrolEkliMi() async -> Bool? {
        do {
            let kontroller = try await ControlCenter.shared.currentControls()
            return kontroller.contains { kontrolTurleri.contains($0.kind) }
        } catch {
            return nil
        }
    }
}

// MARK: - Görünüm

private extension KurulumAdimi.Durum {
    var renk: Color {
        switch self {
        case .tamam: .green
        case .eksik: .orange
        case .bilinmiyor: .gray
        }
    }
    var simge: String {
        switch self {
        case .tamam: "checkmark.circle.fill"
        case .eksik: "exclamationmark.circle.fill"
        case .bilinmiyor: "questionmark.circle"
        }
    }
    var ad: String {
        switch self {
        case .tamam: "tamam"
        case .eksik: "eksik"
        case .bilinmiyor: "bilinmiyor"
        }
    }
}

/// Ayarlar kökündeki satır: eksik yoksa yeşil tik, varsa turuncu "N eksik" hapı.
struct KurulumSatiri: View {
    private let kurulum = KurulumDurumu.ortak

    var body: some View {
        HStack {
            Label("Kurulum durumu", systemImage: "checklist")
            Spacer(minLength: 4)
            if kurulum.adimlar.isEmpty {
                ProgressView()
            } else if kurulum.eksik > 0 {
                Text("\(kurulum.eksik) eksik").font(.caption.bold()).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(kurulum.adimlar.isEmpty ? "denetleniyor" : kurulum.eksik > 0 ? "\(kurulum.eksik) adım eksik" : "tamam")
    }
}

struct KurulumEkrani: View {
    private let kurulum = KurulumDurumu.ortak
    @Environment(\.scenePhase) private var sahne

    var body: some View {
        List {
            if kurulum.adimlar.isEmpty {
                Section { HStack { ProgressView(); Text("Denetleniyor…") } }
            }
            ForEach(kurulum.adimlar) { adim in
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: adim.durum.simge).foregroundStyle(adim.durum.renk).font(.title3).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(adim.baslik).font(.body.weight(.semibold))
                            Text(adim.ayrinti).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(adim.durum.ad)
                    .accessibilityIdentifier("kurulum-adim-\(adim.id)")
                    eylem(adim)
                }
            }
            Section {
                Button(kurulum.yenileniyor ? "Denetleniyor…" : "Yeniden denetle") { Task { await kurulum.yenile() } }
                    .disabled(kurulum.yenileniyor)
                    .accessibilityIdentifier("kurulum-yenile")
            }
        }
        .navigationTitle("Kurulum durumu")
        .task { await kurulum.yenile() }
        .onChange(of: sahne) { _, yeni in
            // Sistem Ayarları'ndan izin verip dönünce durum tazelenir.
            if yeni == .active { Task { await kurulum.yenile() } }
        }
    }

    @ViewBuilder
    private func eylem(_ adim: KurulumAdimi) -> some View {
        switch adim.id {
        case "baglanti":
            if adim.durum != .tamam {
                Button(TelefonProxy.ortak.sinaniyor ? "Sınanıyor…" : "Bağlantıyı sına") {
                    Task { await TelefonProxy.ortak.sina(); await kurulum.yenile() }
                }.disabled(TelefonProxy.ortak.sinaniyor)
                if let sonuc = TelefonProxy.ortak.sonSinama { Text(sonuc).font(.footnote) }
            }
        case "izinler":
            NavigationLink("İzinleri aç") { IzinlerEkrani() }
        case "ses":
            NavigationLink("Ses ayarları") { SesVeLiveAyarlari() }
        case "kontrol":
            if adim.durum != .tamam {
                Text("Kontrol Merkezi'ni aç, sol üstteki + ile 'Kontrol ekle'ye dokun ve \"Asistan'ı başlat\" kontrolünü seç.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case "siri":
            if adim.durum != .tamam {
                Text("Siri'ye \"Asistan ile konuş\" ya da \"Asistan'a sor\" demen yeterli; ilk kullanımdan sonra burada tamam görünür.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }
}
