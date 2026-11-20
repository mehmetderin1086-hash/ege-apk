import WidgetKit
import SwiftUI
import AlarmKit
import ActivityKit

/// Zamanlayıcı/alarm için kilit ekranı ve Dynamic Island görünümü (AlarmKit bunu zorunlu kılar).
struct AsistanAlarmAktivitesi: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AsistanAlarmMeta>.self) { context in
            HStack {
                Image(systemName: "timer").font(.title2)
                VStack(alignment: .leading) {
                    Text(context.attributes.metadata?.baslik ?? "Asistan").font(.headline)
                    Self.sure(context.state)
                }
                Spacer()
                Self.dugmeler(context.state)
            }
            .padding()
            .activityBackgroundTint(.orange.opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer").font(.title2) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.baslik ?? "Asistan").font(.headline)
                    Self.sure(context.state)
                }
                DynamicIslandExpandedRegion(.bottom) { Self.dugmeler(context.state) }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Self.sure(context.state).font(.caption2)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }

    @ViewBuilder
    static func sure(_ durum: AlarmPresentationState) -> some View {
        switch durum.mode {
        case .countdown(let c): Text(timerInterval: aralik(c.fireDate), countsDown: true).monospacedDigit()
        case .paused: Text("Duraklatıldı")
        case .alert: Text("Süre doldu")
        @unknown default: Text("")
        }
    }

    /// P2.14: geri sayımda (zamanlayıcı ya da "Ertele 10 dk" sonrası) Duraklat/Sürdür ve Durdur; çalarken sistem kendi düğmelerini gösterir.
    @ViewBuilder
    static func dugmeler(_ durum: AlarmPresentationState) -> some View {
        switch durum.mode {
        case .countdown: dugmeSatiri(durum.alarmID.uuidString, duraklatildi: false)
        case .paused: dugmeSatiri(durum.alarmID.uuidString, duraklatildi: true)
        default: EmptyView()
        }
    }

    static func dugmeSatiri(_ kimlik: String, duraklatildi: Bool) -> some View {
        HStack(spacing: 8) {
            Button(intent: AlarmDuraklatIntent(alarmKimligi: kimlik)) {
                Label(duraklatildi ? "Sürdür" : "Duraklat", systemImage: duraklatildi ? "play.fill" : "pause.fill")
            }
            Button(intent: AlarmDurdurIntent(alarmKimligi: kimlik)) { Label("Durdur", systemImage: "xmark") }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .tint(.orange)
    }

    /// Şimdiki zaman bir kez okunur: süre dolmuşken (fireDate geçmişte) `Date.now...fireDate` aralık tuzağıyla uzantıyı çökertir.
    static func aralik(_ bitis: Date) -> ClosedRange<Date> {
        let simdi = Date.now
        return simdi...max(simdi, bitis)
    }
}
