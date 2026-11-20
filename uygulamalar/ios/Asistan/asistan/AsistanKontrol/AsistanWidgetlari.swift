import WidgetKit
import SwiftUI

// P3.11: ana ekran ve kilit ekranı widget'ları. Veri ana uygulamanın App Group'a yazdığı anlıktan gelir
// (`DersGunu.oku`, Asistan/Beyin/DersGunu.swift uzantıya da derlenir); widget takvimi kendisi okumaz.

// MARK: Zaman çizelgesi

nonisolated struct AnlikGiris: TimelineEntry, Sendable {
    let date: Date
    let anlik: WidgetAnlik?
}

/// Anlıktaki ders başlangıç/bitişlerinde (ve gece yarısında) bir girdi üretir; çizelge son noktada ya da 1 saat sonra yenilenir.
nonisolated struct AnlikSaglayici: TimelineProvider {
    func placeholder(in context: Context) -> AnlikGiris {
        AnlikGiris(date: .now, anlik: WidgetOrnek.anlik(.now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AnlikGiris) -> Void) {
        let simdi = Date()
        let a = DersGunu.oku() ?? (context.isPreview ? WidgetOrnek.anlik(simdi) : nil)
        completion(AnlikGiris(date: simdi, anlik: a))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AnlikGiris>) -> Void) {
        let simdi = Date()
        let a = DersGunu.oku()
        let noktalar = DersGunu.zamanNoktalari(a?.olaylar ?? [], simdi: simdi)
        let girisler = noktalar.map { AnlikGiris(date: $0, anlik: a) }
        let sonraki = noktalar.count > 1 ? noktalar[noktalar.count - 1] : simdi.addingTimeInterval(3_600)
        completion(Timeline(entries: girisler, policy: .after(sonraki)))
    }
}

/// Veriye bakmayan widget'lar (Konuş, Hızlı sor) için tek girdili çizelge.
nonisolated struct SabitSaglayici: TimelineProvider {
    func placeholder(in context: Context) -> AnlikGiris { AnlikGiris(date: .now, anlik: nil) }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (AnlikGiris) -> Void) {
        completion(AnlikGiris(date: .now, anlik: nil))
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AnlikGiris>) -> Void) {
        completion(Timeline(entries: [AnlikGiris(date: .now, anlik: nil)], policy: .never))
    }
}

/// Galeri ve yer tutucu için örnek gün (gerçek veri değildir).
nonisolated enum WidgetOrnek {
    static func anlik(_ simdi: Date) -> WidgetAnlik {
        let o: [WidgetAnlik.Olay] = [
            .init(baslik: "Biyoloji 10-A", baslangic: simdi.addingTimeInterval(-600), bitis: simdi.addingTimeInterval(1_800), yer: "B-12"),
            .init(baslik: "Biyoloji 11-C", baslangic: simdi.addingTimeInterval(2_400), bitis: simdi.addingTimeInterval(4_800), yer: "Lab"),
            .init(baslik: "Zümre toplantısı", baslangic: simdi.addingTimeInterval(9_000), bitis: simdi.addingTimeInterval(12_600), yer: nil),
        ]
        return WidgetAnlik(olaylar: o, takvimIzni: true, sonYanit: "Bugün üç dersin var; ilk ders 10-A.", sonSohbetID: nil,
                           sonYanitZamani: simdi, guncelleme: simdi)
    }
}

enum WidgetRenk {
    /// Uygulamanın varsayılan vurgusu (D97757).
    static let ana = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
}

enum WidgetAdres {
    static let dinle = URL(string: "asistan://dinle")!
}

// MARK: Konuş (kilit ekranı, yuvarlak)

struct KonusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.mehmetderin.asistan.konus", provider: SabitSaglayici()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform").font(.title2.weight(.semibold)).widgetAccentable()
            }
            .accessibilityLabel("Asistan'la konuş")
            .widgetURL(WidgetAdres.dinle)
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Konuş")
        .description("Asistan'ı açar ve dinlemeye başlar.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: Bugün (ana ekran)

struct BugunWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.mehmetderin.asistan.bugun", provider: AnlikSaglayici()) { giris in
            BugunGorunum(giris: giris)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bugün")
        .description("Bugünün kalan dersleri ve Asistan'ın son yanıtı.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BugunGorunum: View {
    let giris: AnlikGiris
    @Environment(\.widgetFamily) private var aile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Bugün", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(WidgetRenk.ana)
            icerik
            Spacer(minLength: 0)
            if aile == .systemMedium, let yanit = giris.anlik?.sonYanit {
                Divider()
                Link(destination: IsAktivitesiGorunum.sohbetAdresi(giris.anlik?.sonSohbetID) ?? WidgetAdres.dinle) {
                    Text(yanit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .privacySensitive()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var icerik: some View {
        if let a = giris.anlik, a.takvimIzni {
            let kalan = DersGunu.bugun(a.olaylar, simdi: giris.date)
            if kalan.isEmpty {
                Text("Bugün kalan ders yok").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(kalan.prefix(aile == .systemSmall ? 3 : 2).enumerated()), id: \.offset) { _, o in
                    satir(o)
                }
                if kalan.count > (aile == .systemSmall ? 3 : 2) {
                    Text("+\(kalan.count - (aile == .systemSmall ? 3 : 2)) etkinlik daha").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Text(giris.anlik == nil ? "Dersleri görmek için Asistan'ı bir kez aç" : "Takvim izni için Asistan'ı aç")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func satir(_ o: WidgetAnlik.Olay) -> some View {
        let suruyor = o.baslangic <= giris.date && o.bitis > giris.date
        return HStack(spacing: 4) {
            Text(DersGunu.saat(o.baslangic)).monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(suruyor ? WidgetRenk.ana : .primary)
            Text(o.baslik).lineLimit(1)
            if let yer = o.yer, aile != .systemSmall {
                Text("· \(yer)").foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.caption)
    }
}

// MARK: Hızlı sor (ana ekran)

struct HizliSorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.mehmetderin.asistan.hizli-sor", provider: SabitSaglayici()) { _ in
            HizliSorGorunum()
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [WidgetRenk.ana, WidgetRenk.ana.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Hızlı sor")
        .description("Hazır sorulardan birine dokun, Asistan hemen yanıtlasın.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HizliSorGorunum: View {
    @Environment(\.widgetFamily) private var aile

    var body: some View {
        if aile == .systemSmall {
            // Küçük widget tek dokunma hedefidir (Link çalışmaz): yalnız ilk istem, widgetURL ile.
            let ilk = DersGunu.hizliIstemler[0]
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: ilk.simge).font(.title2)
                Spacer(minLength: 0)
                Text(ilk.baslik).font(.headline)
                Text("Asistan'a sor").font(.caption).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(DersGunu.hizliAdres(ilk.no))
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(DersGunu.hizliIstemler) { i in
                    Link(destination: DersGunu.hizliAdres(i.no) ?? WidgetAdres.dinle) {
                        HStack(spacing: 6) {
                            Image(systemName: i.simge)
                            Text(i.baslik).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }
}
