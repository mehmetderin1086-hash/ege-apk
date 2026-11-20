import SwiftUI

/// Ana ekranın büyük kota kartı: renk değiştiren halka, kalan istek, son saatin dilim grafiği, aktif hat/yenileme aralığı, açılış zamanı.
struct QuotaCard: View {
    @Environment(AppModel.self) private var model
    private var snapshot: QuotaSnapshot? { model.quota }

    private func color(_ s: QuotaSnapshot) -> Color {
        if s.blockedUntil != nil || s.remaining == 0 { return .red }
        return s.ratio < 0.5 ? .green : s.ratio < 0.8 ? .orange : .red
    }
    /// Açık zeminde okunur koyu tonlar (halka/grafik canlı rengi kullanır, yazılar bunu).
    private func ink(_ s: QuotaSnapshot) -> Color {
        if s.blockedUntil != nil || s.remaining == 0 || s.ratio >= 0.8 { return Color(red: 0.78, green: 0.10, blue: 0.10) }
        return s.ratio < 0.5 ? Color(red: 0.03, green: 0.45, blue: 0.16) : Color(red: 0.75, green: 0.36, blue: 0.0)
    }
    private func status(_ s: QuotaSnapshot) -> (text: String, icon: String) {
        if s.blockedUntil != nil { return ("Servis kısıtladı · \(minutes(s.waitSeconds)) sonra açılır", "lock.fill") }
        if s.remaining == 0 { return ("Kota doldu · \(minutes(s.waitSeconds)) sonra açılır", "hourglass") }
        if s.ratio >= 0.8 { return ("Kota azaldı, yenilemeler seyrekleşir", "exclamationmark.triangle.fill") }
        if s.ratio >= 0.5 { return ("Kullanım yarıyı geçti", "gauge.with.dots.needle.67percent") }
        return ("Kota rahat", "checkmark.seal.fill")
    }
    private func minutes(_ seconds: TimeInterval) -> String { seconds >= 3600 ? "\(Int(seconds / 3600)) sa \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)) dk" : "\(max(1, Int((seconds / 60).rounded(.up)))) dk" }

    var body: some View {
        if let s = snapshot {
            TimelineView(.periodic(from: .now, by: 1)) { context in card(s, now: context.date) }
        }
    }

    /// Kota açılışına kalan süre: servis kilidi ya da dolu kota için canlı geri sayım.
    private func remainingWait(_ s: QuotaSnapshot, now: Date) -> TimeInterval? {
        if let blocked = s.blockedUntil { return max(0, blocked.timeIntervalSince(now)) }
        if s.remaining == 0, let next = s.nextFree { return max(0, next.timeIntervalSince(now)) }
        return nil
    }
    private func clockText(_ seconds: TimeInterval) -> String {
        let t = Int(max(0, seconds)); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }

    private func card(_ s: QuotaSnapshot, now: Date) -> some View {
        let tint = color(s), ink = ink(s), state = status(s)
        let lines = model.activeLines.count, interval = FleetBudget.refreshInterval(activeLines: lines)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Canlı konum kotası").font(.title3.weight(.heavy))
                Spacer(minLength: 8)
                // Canlı saat
                Text(now, format: .dateTime.hour().minute().second().locale(Locale(identifier: "tr_TR"))).font(.system(.title3, design: .monospaced).weight(.heavy)).foregroundStyle(ink)
            }
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(tint.opacity(0.22), lineWidth: 16)
                    Circle().trim(from: 0, to: max(0.02, s.ratio)).stroke(AngularGradient(colors: [tint.opacity(0.6), tint], center: .center), style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: -4) {
                        Text("\(s.remaining)").font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(ink).contentTransition(.numericText(value: Double(s.remaining)))
                        Text("kalan").font(.subheadline.weight(.bold)).foregroundStyle(.primary.opacity(0.7))
                    }
                }
                .frame(width: 134, height: 134).animation(.spring(duration: 0.8), value: s.ratio)
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.text, systemImage: state.icon).font(.headline.weight(.bold)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    Text("\(s.used) / \(s.limit) istek").font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Text("son 1 saatte kullanılan").font(.footnote.weight(.medium)).foregroundStyle(.primary.opacity(0.7))
                    if let wait = remainingWait(s, now: now) {
                        Label("Açılışa \(clockText(wait))", systemImage: "timer").font(.system(.body, design: .monospaced).weight(.heavy)).foregroundStyle(ink)
                    }
                }
                Spacer(minLength: 0)
            }
            if let age = model.liveAge {
                let next = max(0, age.addingTimeInterval(interval).timeIntervalSince(now))
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(ink)
                    Text("Son canlı çekim \(Int(now.timeIntervalSince(age))) sn önce · sonraki ~\(Int(next)) sn").font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            chart(s, tint: tint, ink: ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("\(lines) aktif hat", "bus", Color(red: 0.05, green: 0.30, blue: 0.80))
                    pill("\(Int(interval)) sn yenileme", "arrow.triangle.2.circlepath", Color(red: 0.30, green: 0.20, blue: 0.75))
                    pill("~\(Int(Double(lines) * 3600 / interval)) istek/sa", "speedometer", ink)
                }
            }
            Text("İBB canlı konum servisi saatte 100 isteğe izin verir; uygulama 90'ın altında kalır ve hat sayısına göre yenileme aralığını otomatik uzatır.").font(.footnote).foregroundStyle(.primary.opacity(0.7))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).clipShape(.rect(cornerRadius: 26))
        .background(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 26))
        .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(tint.opacity(0.7), lineWidth: 2))
        .shadow(color: tint.opacity(0.25), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Canlı konum kotası: \(s.used) kullanıldı, \(s.remaining) kaldı. \(state.text)")
    }

    /// Son bir saat, 10'ar dakikalık dilimler (en soldaki en eski).
    private func chart(_ s: QuotaSnapshot, tint: Color, ink: Color) -> some View {
        let peak = max(1, s.buckets.max() ?? 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(s.buckets.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 2) {
                        Text("\(count)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(count == 0 ? .clear : ink)
                        RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [tint, tint.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(5, 52 * CGFloat(count) / CGFloat(peak))).opacity(count == 0 ? 0.25 : 1)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 76, alignment: .bottom).animation(.spring(duration: 0.7), value: s.buckets)
            HStack { Text("1 sa önce"); Spacer(); Text("30 dk önce"); Spacer(); Text("şimdi") }.font(.caption.weight(.semibold)).foregroundStyle(.primary.opacity(0.7))
        }
    }
    private func pill(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon).font(.subheadline.weight(.bold)).lineLimit(1).fixedSize().foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 8).background(color.opacity(0.14), in: .capsule)
    }
}
