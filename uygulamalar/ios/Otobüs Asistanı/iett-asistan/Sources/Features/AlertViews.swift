import SwiftUI

extension AlertSeverity {
    var color: Color { switch self { case .info: .blue; case .warning: .orange; case .critical: .red } }
    var icon: String { switch self { case .info: "info.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .critical: "xmark.octagon.fill" } }
}

/// Takip ekranının renkli uyarı panosu: canlı gecikmeler ve duyurular şiddetine göre (kırmızı iptal/ertelendi, turuncu uyarı, mavi bilgi).
struct AlertBoard: View {
    @Environment(AppModel.self) private var model
    @State private var sharing: ShareMessage?
    var body: some View {
        let notices = model.boardNotices
        if !model.liveAlerts.isEmpty || !notices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange).symbolEffect(.bounce, value: notices.count + model.liveAlerts.count)
                    Text("Uyarılar").font(.subheadline.weight(.bold))
                    Spacer()
                    let counts = NoticeClassifier.summary(notices).counts
                    ForEach([AlertSeverity.critical, .warning, .info], id: \.self) { severity in
                        if let n = counts[severity] { Text("\(n)").font(.caption.weight(.heavy)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(severity.color, in: .capsule) }
                    }
                }
                ForEach(model.liveAlerts) { alert in row(icon: AlertSeverity.warning.icon, color: .orange, title: "Gecikme", text: alert.text) }
                ForEach(notices.prefix(4)) { notice in
                    let severity = NoticeClassifier.severity(notice.message)
                    row(icon: severity.icon, color: severity.color, title: "\(notice.line) · \(severity.title)", text: notice.message)
                        .contextMenu { Button("Paylaş", systemImage: "square.and.arrow.up") { sharing = ShareBuilder.notice(notice) } }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
            .modifier(PulsingStroke(color: (NoticeClassifier.summary(notices).top ?? .warning).color, active: NoticeClassifier.summary(notices).top == .critical))
            .transition(.move(edge: .top).combined(with: .opacity))
            .shareSheet($sharing)
        }
    }
    private func row(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            Image(systemName: icon).foregroundStyle(color).symbolEffect(.pulse, options: .repeating, isActive: color == .red).symbolEffect(.bounce, value: text)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption.weight(.bold)).foregroundStyle(color); Text(text).font(.caption).lineLimit(3) }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.12), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Başlık altındaki renkli durum çipleri: canlı, gecikme, iptal/uyarı sayıları.
struct StatusChips: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let live = model.favorites.filter { model.favoriteETAs[$0.id]?.first != nil }.count
        let counts = NoticeClassifier.summary(model.boardNotices).counts
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("\(live) canlı", .green, "dot.radiowaves.left.and.right", visible: live > 0)
                chip("\(model.liveAlerts.count) gecikme", .orange, "clock.badge.exclamationmark", visible: !model.liveAlerts.isEmpty)
                chip("\(counts[.critical] ?? 0) iptal/ertelendi", .red, "xmark.octagon", visible: (counts[.critical] ?? 0) > 0)
                chip("\(counts[.warning] ?? 0) uyarı", .yellow, "exclamationmark.triangle", visible: (counts[.warning] ?? 0) > 0)
            }
        }.animation(.spring, value: model.liveAlerts.count + model.boardNotices.count)
    }
    @ViewBuilder private func chip(_ text: String, _ color: Color, _ icon: String, visible: Bool) -> some View {
        if visible { Label(text, systemImage: icon).font(.caption.weight(.bold)).lineLimit(1).fixedSize().foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.18), in: .capsule).transition(.scale.combined(with: .opacity)) }
    }
}

/// Favori (hat, durak) bildirim kuralı: hangi gün/saatlerde, hangi türde, kaç dakika önce; önizleme ve test bildirimi.
struct AlertRuleEditor: View {
    let favorite: Favorite
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rule: AlertRule
    @State private var preview: [PlannedAlert] = []
    @State private var authorized = true
    private let dayOrder = [2, 3, 4, 5, 6, 7, 1], dayNames = [2: "Pzt", 3: "Sal", 4: "Çar", 5: "Per", 6: "Cum", 7: "Cmt", 1: "Paz"]

    init(favorite: Favorite, initial: AlertRule?) { self.favorite = favorite; _rule = State(initialValue: initial ?? .morning) }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { IETTDates.calendar.date(byAdding: .minute, value: minutes.wrappedValue, to: IETTDates.calendar.startOfDay(for: .now)) ?? .now },
                set: { let c = IETTDates.calendar.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) { LineBadge(code: favorite.line); Text(favorite.stopName).font(.headline) }
                    Toggle("Bildirimler açık", isOn: $rule.enabled.animation())
                    if !authorized { Label("Bildirim izni kapalı. Ayarlar › Otobüs Asistanı › Bildirimler.", systemImage: "bell.slash").font(.footnote).foregroundStyle(.orange) }
                }
                if rule.enabled {
                    Section("Ne zaman") {
                        HStack { ForEach([("Sabah", AlertRule.morning), ("Akşam", AlertRule.evening), ("Tüm gün", AlertRule.allDay)], id: \.0) { item in
                            Button(item.0) { withAnimation(.snappy) { rule.startMinute = item.1.startMinute; rule.endMinute = item.1.endMinute } }.buttonStyle(.bordered).controlSize(.small)
                        } }
                        DatePicker("Başlangıç", selection: time($rule.startMinute), displayedComponents: .hourAndMinute)
                        DatePicker("Bitiş", selection: time($rule.endMinute), displayedComponents: .hourAndMinute)
                        HStack(spacing: 6) {
                            ForEach(dayOrder, id: \.self) { day in
                                Button(dayNames[day] ?? "") { withAnimation(.snappy) { if rule.days.contains(day) { rule.days.remove(day) } else { rule.days.insert(day) } } }
                                    .font(.caption.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(rule.days.contains(day) ? Theme.accent : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 8)).foregroundStyle(rule.days.contains(day) ? Color.white : Color.primary)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Section("Hangi bildirimler") {
                        Toggle(isOn: $rule.passing) { Label("Durağa geçişten önce", systemImage: "bus") }
                        Toggle(isOn: $rule.origin) { Label("Hat çıkış durağından kalkarken", systemImage: "arrow.up.right.circle") }
                        Picker("Kaç dakika önce", selection: $rule.leadMinutes) { ForEach([0, 2, 5, 10, 15, 20, 30], id: \.self) { Text($0 == 0 ? "Tam zamanında" : "\($0) dk önce").tag($0) } }
                        Toggle(isOn: $rule.live) { Label("Yaklaşıyor / durakta (canlı)", systemImage: "dot.radiowaves.left.and.right") }
                        Toggle(isOn: $rule.delay) { Label("Gecikme uyarısı", systemImage: "clock.badge.exclamationmark") }
                        Toggle(isOn: $rule.notices) { Label("İptal / ertelendi / duyuru", systemImage: "exclamationmark.bubble") }
                    }
                    Section {
                        if preview.isEmpty { Text("Seçilen gün ve saatlerde planlı bildirim yok.").foregroundStyle(.secondary).font(.footnote) }
                        ForEach(preview.prefix(6)) { alert in
                            HStack { Image(systemName: alert.kind == .passing ? "bus" : "arrow.up.right.circle").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 1) { Text(alert.body).font(.subheadline); Text(alert.fireDate.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "tr_TR")))).font(.caption).foregroundStyle(.secondary) } }
                        }
                        Button { Task { await Notifier.post(id: "test|\(UUID())", title: "🟢 \(favorite.line) yaklaşıyor: 4 dk", body: "\(favorite.stopName) · 3 durak kaldı", important: true, delay: 3) } } label: { Label("Test bildirimi gönder (3 sn)", systemImage: "bell.badge") }
                    } header: { Text("Önizleme · planlı bildirimler") } footer: { Text("Planlı geçiş ve kalkış bildirimleri sefer saatlerinden önceden kurulur; uygulama kapalıyken de gelir. Canlı, gecikme ve iptal uyarıları uygulama açıkken ya da iOS arka plan yenilemesi çalışırken gelir (garanti edilmez).") }
                }
            }
            .navigationTitle("Bildirim ayarları").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Kaydet") { model.setRule(rule, for: favorite); dismiss() }.bold() }
            }
            .task { authorized = await Notifier.status() != .denied }
            .task(id: rule) {
                guard rule.enabled else { preview = []; return }
                preview = await AlertScheduler.alerts(for: favorite, rule: rule, hat: { model.line($0) })
            }
        }
        .presentationDetents([.large])
    }
}
