import Charts
import SwiftData
import SwiftUI

/// Gelişim: son 14 gün çalışma süresi, ders bazında odak, en verimli saatler, yanlış defteri eğrisi.
struct ProgressChartsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var days: [ListeningDay]
    @Query private var sessions: [StudySession]
    @Query private var courses: [Course]
    @Query private var mistakes: [MistakeEntry]
    @Query private var cards: [ReviewCard]
    @State private var showClassic = false

    struct DayPoint: Identifiable { var id: String { "\(date.timeIntervalSince1970)-\(kind)" }; var date: Date; var minutes: Double; var kind: String }

    private var daily: [DayPoint] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        return (0..<14).reversed().flatMap { offset -> [DayPoint] in
            let day = cal.date(byAdding: .day, value: -offset, to: start)!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let listen = (days.first { $0.day == ListeningDay.key(for: day) }?.seconds ?? 0) / 60
            let focus = sessions.filter { $0.kind == "focus" && $0.startedAt >= day && $0.startedAt < next }.reduce(0) { $0 + $1.seconds } / 60
            return [DayPoint(date: day, minutes: listen, kind: "Dinleme"), DayPoint(date: day, minutes: focus, kind: "Odak")]
        }
    }

    private var byCourse: [(name: String, minutes: Double, color: Color)] {
        Dictionary(grouping: sessions.filter { $0.kind == "focus" }, by: \.courseID).map { id, list in
            let c = courses.first { $0.id == id }
            return (c?.name ?? "Ders seçilmedi", list.reduce(0) { $0 + $1.seconds } / 60, Course.color(c?.colorHex ?? "#999999"))
        }.sorted { $0.minutes > $1.minutes }
    }

    /// #33: derslere göre video izleme süresi (`StudySession.kind == "video"`; ders = bağlı Derslerim dersi).
    private var videoByCourse: [(name: String, minutes: Double, color: Color)] {
        Dictionary(grouping: sessions.filter { $0.kind == "video" }, by: \.courseID).map { id, list in
            let c = courses.first { $0.id == id }
            return (c?.name ?? "Ders seçilmedi", list.reduce(0) { $0 + $1.seconds } / 60, Course.color(c?.colorHex ?? "#999999"))
        }.sorted { $0.minutes > $1.minutes }
    }

    private var videoLastWeek: Double {
        let from = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return sessions.filter { $0.kind == "video" && $0.startedAt >= from }.reduce(0) { $0 + $1.seconds } / 60
    }

    private var byHour: [(hour: Int, minutes: Double)] {
        let grouped = Dictionary(grouping: sessions.filter { $0.kind == "focus" }) { Calendar.current.component(.hour, from: $0.startedAt) }
        return (6...23).map { h in (h, (grouped[h] ?? []).reduce(0) { $0 + $1.seconds } / 60) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Son 14 gün (dakika)") {
                    Chart(daily) { p in
                        BarMark(x: .value("Gün", p.date, unit: .day), y: .value("Dakika", p.minutes))
                            .foregroundStyle(by: .value("Tür", p.kind))
                    }
                    // Üç günde bir, yalnız gün numarası: büyük yazıda ve dar ekranda etiketler üst üste binmesin.
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day(), centered: true)
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .frame(height: 200)
                    let total = daily.reduce(0) { $0 + $1.minutes }
                    Text("Toplam \(Int(total)) dk · günlük ortalama \(Int(total / 14)) dk").font(.caption).foregroundStyle(.secondary)
                }
                // #27: geri çağırma günlüğü, eminlik ve kalıcılık eğrisi (P6).
                RecallInsightsSection()
                if !byCourse.isEmpty {
                    Section("Derslere göre odak") {
                        Chart(byCourse, id: \.name) { item in
                            BarMark(x: .value("Dakika", item.minutes), y: .value("Ders", item.name)).foregroundStyle(item.color)
                        }
                        .frame(height: CGFloat(max(80, byCourse.count * 34)))
                    }
                }
                if !videoByCourse.isEmpty {
                    Section {
                        Chart(videoByCourse, id: \.name) { item in
                            BarMark(x: .value("Dakika", item.minutes), y: .value("Ders", item.name)).foregroundStyle(item.color)
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .frame(height: CGFloat(max(80, videoByCourse.count * 34)))
                        let total = videoByCourse.reduce(0) { $0 + $1.minutes }
                        Text("Toplam \(Int(total)) dk video · son 7 gün \(Int(videoLastWeek)) dk").font(.caption).foregroundStyle(.secondary)
                    } header: {
                        Text("Video izleme (derslere göre)")
                    } footer: {
                        Text("Derse bağlanmamış videolar ‘Ders seçilmedi’ altında toplanır; ders ekranından videoyu bir derse bağlayabilirsin.")
                    }
                }
                if byHour.contains(where: { $0.minutes > 0 }) {
                    Section("En çok odak süresi ayırdığın saatler") {
                        Chart(byHour, id: \.hour) { item in
                            BarMark(x: .value("Saat", item.hour), y: .value("Dakika", item.minutes))
                        }
                        .frame(height: 140)
                        if let best = byHour.max(by: { $0.minutes < $1.minutes }), best.minutes > 0 {
                            Text("En çok odak süresini \(best.hour):00 civarında kaydettin. Bu süre ölçümüdür; öğrenme verimini veya doğruluğu tek başına göstermez.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Yanlışlar ve kartlar") {
                    LabeledContent("Açık yanlış", value: "\(mistakes.filter { !$0.resolved }.count)")
                    LabeledContent("Çözülen yanlış", value: "\(mistakes.filter(\.resolved).count)")
                    LabeledContent("Kart (toplam / zor)", value: "\(cards.count) / \(cards.filter(\.isWeak).count)")
                    let mature = cards.filter { $0.intervalDays >= 21 }.count
                    LabeledContent("Tekrar aralığı 21+ gün olan kart", value: "\(mature)")
                }
                Section { Button("Ayrıntılı istatistik ve haftalık özet") { showClassic = true } }
            }
            .navigationTitle("Gelişim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .debugNarrowScreen()
            .sheet(isPresented: $showClassic) { StatsView() }
        }
    }
}
