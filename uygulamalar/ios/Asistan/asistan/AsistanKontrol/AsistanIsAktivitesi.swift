import WidgetKit
import SwiftUI
import ActivityKit

/// Asistan uzun bir iş yürütürken kilit ekranı ve Dynamic Island'da ilerleme.
struct AsistanIsAktivitesi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AsistanIsNitelikleri.self) { c in
            let hal = Self.hal(c)
            HStack(spacing: 12) {
                Self.simge(c.state, hal).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(IsAktivitesiGorunum.baslik(c.state, hal)).font(.headline)
                    Text(IsAktivitesiGorunum.adimMetni(c.state, hal)).font(.subheadline).lineLimit(1)
                    Text(c.attributes.istek).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if c.state.toplam > 0 { ProgressView(value: Double(c.state.tamamlanan), total: Double(c.state.toplam)) }
                    // P2.14: bitince yanıtın kısa özeti (kilitliyken gizlenebilir).
                    if c.state.bitti, let ozet = c.state.ozet {
                        Text(ozet).font(.caption).lineLimit(2).privacySensitive()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Self.sure(c, hal)
                    if !c.state.bitti { Self.durdurDugmesi }
                }
            }
            .padding()
            .activityBackgroundTint(.teal.opacity(0.18))
            // P2.14: dokununca sonucun sohbeti açılır (Button(intent:) uzantı sürecinde çalışır; bağlantı uygulamayı açar).
            .widgetURL(IsAktivitesiGorunum.sohbetAdresi(c.state.sohbetID))
        } dynamicIsland: { c in
            let hal = Self.hal(c)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Self.simge(c.state, hal).font(.title2) }
                DynamicIslandExpandedRegion(.center) {
                    Text(IsAktivitesiGorunum.adimMetni(c.state, hal)).font(.headline).lineLimit(1)
                    if c.state.toplam > 0 { ProgressView(value: Double(c.state.tamamlanan), total: Double(c.state.toplam)) }
                }
                DynamicIslandExpandedRegion(.trailing) { Self.sure(c, hal) }
                DynamicIslandExpandedRegion(.bottom) {
                    if !c.state.bitti {
                        Self.durdurDugmesi
                    } else if let url = IsAktivitesiGorunum.sohbetAdresi(c.state.sohbetID) {
                        HStack {
                            if let ozet = c.state.ozet { Text(ozet).font(.caption).lineLimit(2).privacySensitive() }
                            Spacer()
                            Link(destination: url) { Label("Aç", systemImage: "arrow.up.forward.app") }.font(.caption.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                Self.simge(c.state, hal)
            } compactTrailing: {
                Self.sure(c, hal).font(.caption2)
            } minimal: {
                Self.simge(c.state, hal)
            }
        }
    }

    /// Ortak karar: bitmemiş iş için güncelleme gelmediyse (staleDate geçti) `c.isStale` → "Bağlantı koptu".
    static func hal(_ c: ActivityViewContext<AsistanIsNitelikleri>) -> IsAktivitesiGorunum.Hal {
        IsAktivitesiGorunum.hal(c.state, bayat: c.isStale)
    }

    static func renk(_ h: IsAktivitesiGorunum.Hal) -> Color {
        switch h {
        case .calisiyor: .teal
        case .hazir: .green
        case .durduruldu: .gray
        case .hata, .koptu: .orange
        }
    }

    /// P2.14: süren işi durdurur (LiveActivityIntent: uygulama sürecinde `IsKoprusu.durdur`).
    static var durdurDugmesi: some View {
        Button(intent: IsiDurdurIntent()) { Label("Durdur", systemImage: "stop.fill") }
            .font(.caption.weight(.semibold))
            .tint(.red)
    }

    /// P4.2: mikrofon açıkken (bas-konuş, arka plan Live) dalga simgesi canlı efektle döner.
    static func simge(_ s: AsistanIsNitelikleri.ContentState, _ h: IsAktivitesiGorunum.Hal) -> some View {
        Image(systemName: IsAktivitesiGorunum.simge(s, h)).foregroundStyle(renk(h))
            .symbolEffect(.variableColor.iterative, isActive: s.dinliyor && h == .calisiyor)
    }

    /// Bitmiş işte (durdurulmuş dahil) "X sn"; koptuysa sayaç yanıltır, "—"; çalışırken canlı sayaç.
    @ViewBuilder static func sure(_ c: ActivityViewContext<AsistanIsNitelikleri>, _ h: IsAktivitesiGorunum.Hal) -> some View {
        switch h {
        case .hazir, .durduruldu, .hata: Text("\(c.state.sureSn) sn").monospacedDigit()
        case .koptu: Text("—").monospacedDigit()
        case .calisiyor: Text(c.attributes.baslangic, style: .timer).monospacedDigit().frame(maxWidth: 52)
        }
    }
}
