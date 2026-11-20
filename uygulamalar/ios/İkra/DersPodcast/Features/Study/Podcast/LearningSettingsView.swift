import SwiftData
import SwiftUI

/// #25/#36: dinleme modu (P5 seçicisi) ve eller serbest yoklama ayarı. Ayar Settings'e değil buraya konur.
struct LearningSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LearningSettingsForm()
                .navigationTitle("Dinlerken öğren")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}

/// Dinleme modu formu: Çalış'taki sayfada ve Ayarlar › Çalış'ta aynı içerik.
struct LearningSettingsForm: View {
    @AppStorage(HandsFree.key) private var handsFree = true
    @AppStorage(ListeningMode.key) private var modeRaw = ListeningMode.aktif.rawValue

    private var policy: ListeningPolicy { (ListeningMode(rawValue: modeRaw) ?? .aktif).policy }

    var body: some View {
            Form {
                Section {
                    ListeningModePicker()
                } footer: {
                    Text(summary)
                }
                Section {
                    Toggle("Ekran kilitliyken konu sonu sorusu", isOn: $handsFree)
                        .disabled(!policy.handsFree)
                } header: {
                    Text("Eller serbest")
                } footer: {
                    Text(policy.handsFree
                         ? "Konu bitince soru ve şıklar sesli okunur, kısa bir düşünme payından sonra cevap gelir ve podcast kaldığı yerden sürer. Bilemediysen kulaklıkta \"sonraki\"ye bas: soru tekrar kartlarına ve yanlış defterine yazılır."
                         : "Rahat modda konu sonu soruları kapalıdır.")
                }
                Section("Yoklama takvimi") {
                    Text("Bölüm bitince \(policy.probeStages.map { "\($0)." }.joined(separator: ", ")) günlerde kısa yoklama kurulur ve Çalış sekmesinde görünür. Sınava 14 günden az kaldıysa aralıklar sıkışır.")
                        .font(.callout)
                }
            }
    }

    private var summary: String {
        var parts: [String] = []
        parts.append(policy.inlineQuestions ? "Konu sonunda soru" : "Yalnız bölüm sonu kartı")
        if policy.playThinkPauses { parts.append("düşünme payı") }
        if policy.recallPrompt { parts.append("anlatarak hatırla") }
        if policy.preTest { parts.append("ön test") }
        if policy.confidence { parts.append("eminlik") }
        return parts.joined(separator: " · ")
    }
}

/// Bekleyen yoklamalar ve yeniden dinleme görevleri (Çalış → Yoklamalar). Rozet (`StudyHub`) bu listedeki
/// dokunulabilir bölümleri sayar: düşük puanlı yoklamanın açtığı "yeniden dinle" görevi de burada görünür ve kapatılabilir.
struct ProbeListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<EpisodeProbe> { $0.completedAt == nil }, sort: \EpisodeProbe.dueDate) private var probes: [EpisodeProbe]
    @State private var open: ProbeTarget?

    private struct ProbeTarget: Identifiable { var id: UUID }

    var body: some View {
        NavigationStack {
            let now = Date.now
            let endOfToday = ProbeScheduler.endOfDay(now)
            let list = probes.filter { $0.kindRaw == "probe" && $0.episodeID != nil }
            let relisten = probes.filter { $0.kindRaw == "relisten" && $0.episodeID != nil }
            List {
                if list.isEmpty, relisten.isEmpty {
                    ContentUnavailableView("Yoklama yok", systemImage: "checklist",
                                           description: Text("Bir bölümü bitirince yoklamalar kendiliğinden kurulur."))
                }
                if !list.isEmpty {
                    Section {
                        ForEach(list) { probe in
                            let note = ProbeScheduler.dueNote(probe.dueDate, now: now)
                            Button {
                                if let id = probe.episodeID { open = ProbeTarget(id: id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(probe.episodeTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("\(probe.stage). gün · \(probe.dueDate.formatted(.dateTime.day().month().weekday()))\(note.map { " · \($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(note != nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                }
                            }
                            .disabled(probe.dueDate >= endOfToday)
                        }
                    } header: {
                        if !relisten.isEmpty { Text("Yoklamalar") }
                    } footer: {
                        if list.contains(where: { $0.dueDate >= endOfToday }) { Text("İleri tarihli yoklamalar gününde açılır.") }
                    }
                }
                if !relisten.isEmpty {
                    Section {
                        ForEach(relisten) { probe in
                            Button {
                                guard let id = probe.episodeID else { return }
                                dismiss()
                                AppState.current?.open(id, at: 0, play: true)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(probe.episodeTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(ProbeScheduler.relistenNote(score: probe.score)).font(.caption).foregroundStyle(.orange)
                                    }
                                } icon: {
                                    Image(systemName: "headphones")
                                }
                            }
                            .accessibilityHint("Bölümü baştan çalar")
                            .swipeActions {
                                Button("Tamamlandı", systemImage: "checkmark") {
                                    probe.completedAt = .now
                                    try? context.save()
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        Text("Yeniden dinle")
                    } footer: {
                        Text("Bölümü baştan sona dinleyince görev kendiliğinden kapanır. Elle kapatmak için satırı sola kaydır.")
                    }
                }
            }
            .navigationTitle("Yoklamalar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $open) { ProbeSessionView(episodeID: $0.id) }
            .debugNarrowScreen()
        }
    }
}
