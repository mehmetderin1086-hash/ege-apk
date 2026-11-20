import SwiftData
import SwiftUI

/// Henüz bölümü olmayan üretim (kocum://generation/<UUID>, bildirim): "Senaryo yazılıyor · Konu 4/12".
struct PendingGenerationView: View {
    let id: UUID
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Query private var requests: [QueuedRequest]

    init(id: UUID) {
        self.id = id
        _requests = Query(filter: #Predicate<QueuedRequest> { $0.id == id })
    }

    var body: some View {
        let request = requests.first
        let draft = generator.drafts[id]
        if request == nil, draft == nil {
            ContentUnavailableView("Üretim kuyrukta değil", systemImage: "tray",
                                   description: Text("Bölüm hazırsa kütüphanende görünür."))
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    if draft != nil { PulsingWave() } else { Image(systemName: "hourglass").font(.system(size: 44)).foregroundStyle(.tint) }
                    Text(request?.title ?? "Podcast").font(.title3.bold()).multilineTextAlignment(.center)
                    Text(draft.map(\.title) ?? OfflineQueue.stateTitle(request?.stateRaw ?? QueueState.waiting))
                        .font(.headline)
                    if let text = generator.progressText(for: id) ?? request?.progressText {
                        Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let draft {
                        ProgressView(value: draft.draftFraction).padding(.horizontal, 40)
                    }
                    if let request, draft == nil {
                        if let next = request.nextRetryAt, next > .now {
                            HStack(spacing: 4) {
                                Text("Otomatik yeniden deneme:")
                                Text(next, style: .timer).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                        if let error = request.lastError {
                            Text(error).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                        }
                        Button("Şimdi dene", systemImage: "arrow.clockwise") { generator.retryNow(id, context: context) }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                    }
                    if let request {
                        Button("Vazgeç", role: .destructive) { OfflineQueue.remove(request, context: context) }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                    Text("Senaryo hazır olunca bölüm kütüphanende açılır; seslendirme arka planda sürer.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
    }
}
