import SwiftUI
import ProxyKit

struct KayitlarView: View {
    @Environment(AppModel.self) private var model
    @State private var onlyErrors = false

    var body: some View {
        let list = onlyErrors ? model.records.filter { $0.status >= 400 || $0.error != nil } : model.records
        List {
            if list.isEmpty { ContentUnavailableView("Kayıt yok", systemImage: "tray") }
            ForEach(list) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(r.status)").font(.caption.monospaced().weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((r.status < 400 ? Color.green : .red).opacity(0.18), in: .capsule)
                        Text(r.model).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(r.date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Label(r.route, systemImage: r.route == "Sunucu" ? "server.rack" : "iphone").font(.caption)
                        if r.fellBack { Text("yedek").font(.caption2.weight(.semibold)).foregroundStyle(.orange) }
                        Text(r.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(r.millis) ms").font(.caption).foregroundStyle(.secondary)
                    }
                    if r.inputTokens + r.outputTokens > 0 {
                        Text("↑\(r.inputTokens) ↓\(r.outputTokens) token").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let e = r.error { Text(e).font(.caption).foregroundStyle(.red).lineLimit(3) }
                }
            }
        }
        .navigationTitle("Kayıtlar")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $onlyErrors) { Image(systemName: "exclamationmark.triangle") }.toggleStyle(.button)
                Button { Task { await model.log.clear() } } label: { Image(systemName: "trash") }
            }
        }
    }
}
