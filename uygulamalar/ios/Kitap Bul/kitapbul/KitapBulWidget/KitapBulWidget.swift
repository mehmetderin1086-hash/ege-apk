import WidgetKit
import SwiftUI
import AppIntents

/// Ana ekran ve kilit ekranı için hızlı işlem widget'ı: dokununca uygulamada ilgili
/// ekran açılır (kitapbul:// bağlantıları). Geciken/bugün iade özeti App Group'taki küçük
/// WidgetSnapshot.json dosyasından okunur; kitap deposu paylaşılmaz.
struct HizliIslemGirdisi: TimelineEntry {
    let date: Date
    var ozet: WidgetSnapshot? = nil

    var bayat: Bool { ozet?.bayatMi(now: date) ?? false }
    var ozetMetni: String? {
        guard let ozet else { return nil }
        if bayat { return "Özet güncel değil" }
        let bugun = ozet.bugunGecerli(now: date) ? ", bugün iade \(ozet.bugunIade)" : ""
        return "Geciken \(ozet.geciken)" + bugun
    }
}

struct HizliIslemSaglayici: TimelineProvider {
    func placeholder(in context: Context) -> HizliIslemGirdisi { HizliIslemGirdisi(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (HizliIslemGirdisi) -> Void) {
        completion(HizliIslemGirdisi(date: .now, ozet: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HizliIslemGirdisi>) -> Void) {
        let now = Date.now
        let ozet = WidgetSnapshotStore.read()
        let calendar = Calendar.current
        let gunDonumu = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        var tarihler = [now, gunDonumu]
        if let ozet {
            let bayatlik = ozet.guncelleme.addingTimeInterval(WidgetSnapshot.bayatlikSuresi + 1)
            if bayatlik > now { tarihler.append(bayatlik) }
        }
        let girdiler = Set(tarihler).sorted().map { HizliIslemGirdisi(date: $0, ozet: ozet) }
        completion(Timeline(entries: girdiler, policy: .after(gunDonumu)))
    }
}

private struct Islem: Identifiable {
    let route: DeepLinkRoute
    let baslik: String
    let etiket: String
    let ikon: String
    let renk: Color
    var id: String { route.rawValue }
    var url: URL { route.url }
}

private let islemler: [Islem] = DeepLinkRoute.widgetRoutes.map { route in
    switch route {
    case .ses: Islem(route: route, baslik: "Sesle", etiket: "Sesle kitap ekle", ikon: "mic.fill", renk: .teal)
    case .kapak: Islem(route: route, baslik: "Kapak", etiket: "Kapaktan kitap ekle", ikon: "text.viewfinder", renk: .purple)
    case .asistan: Islem(route: route, baslik: "Asistan", etiket: "Asistanı aç", ikon: "waveform.and.mic", renk: .orange)
    default: Islem(route: route, baslik: "Barkod", etiket: "Barkodla kitap ekle", ikon: "barcode.viewfinder", renk: .indigo)
    }
}

struct KitapBulWidgetGorunumu: View {
    @Environment(\.widgetFamily) private var aile
    var entry: HizliIslemGirdisi

    var body: some View {
        switch aile {
        case .accessoryCircular:
            Image(systemName: "barcode.viewfinder")
                .font(.title2)
                .widgetURL(islemler[0].url)
                .accessibilityLabel("Kitap Bul: barkod okut")
                .accessibilityHint("Kitap Bul'u açar")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Kitap Bul", systemImage: "books.vertical.fill").font(.caption.weight(.bold))
                Text(entry.ozetMetni ?? "Barkodla kitap ekle").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLinkRoute.odunc.url)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Kitap Bul'u açar")
        case .accessoryInline:
            Text(entry.ozetMetni.map { "Kitap Bul: " + $0 } ?? "Kitap Bul")
                .widgetURL(DeepLinkRoute.odunc.url)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Label("Kitap Bul", systemImage: "books.vertical.fill")
                    .font(.caption.weight(.bold))
                Spacer()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 38, weight: .semibold))
                Text("Barkodla kitap ekle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(islemler[0].url)
            .accessibilityHint("Kitap Bul'u açar")
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Kitap Bul", systemImage: "books.vertical.fill")
                        .font(.caption.weight(.bold))
                    Spacer()
                    if let metin = entry.ozetMetni {
                        Text(metin)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.bayat ? .orange : .secondary)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(islemler) { islem in
                        Link(destination: islem.url) {
                            VStack(spacing: 4) {
                                Image(systemName: islem.ikon).font(.title2)
                                Text(islem.baslik).font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(islem.renk.gradient, in: .rect(cornerRadius: 12))
                        }
                        .accessibilityLabel(islem.etiket)
                        .accessibilityHint("Kitap Bul'u açar")
                    }
                }
            }
        }
    }
}

struct KitapBulWidget: Widget {
    let kind = WidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HizliIslemSaglayici()) { entry in
            KitapBulWidgetGorunumu(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Kitap Bul Hızlı İşlem")
        .description("Barkodla, sesle ya da kapaktan kitap ekleyin; asistanı açın.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Denetim Merkezi / kilit ekranı / Eylem düğmesi: tek dokunuşla barkod tarama.
struct KitapTaraKontrolu: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mehmetderin.kitapkatalogu.kitapTara") {
            ControlWidgetButton(action: OpenURLIntent(DeepLinkRoute.barkod.url)) {
                Label("Kitap Tara", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Kitap Tara")
        .description("Kitap Bul'da barkod tarayıcıyı açar.")
    }
}

#Preview(as: .systemMedium) {
    KitapBulWidget()
} timeline: {
    HizliIslemGirdisi(date: .now)
}
