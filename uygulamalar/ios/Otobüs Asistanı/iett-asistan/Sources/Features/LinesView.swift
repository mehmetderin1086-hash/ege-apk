import SwiftUI

/// Hatlar sekmesi: arama, sabit ve son bakılan hatlar; "Canlı" ya da "Sefer saatleri" kipinde açılır.
struct LinesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @AppStorage("lines.mode") private var mode = 0     // 0 canlı, 1 sefer saatleri
    @State private var followHat: Hat?
    private var filtered: [Hat] {
        let needle = fold(query)
        guard !needle.isEmpty else { return model.lines }
        return model.lines.filter { fold($0.code).hasPrefix(needle) || fold($0.code + " " + $0.name).contains(needle) }
    }
    private func route(_ hat: Hat) -> Route { mode == 0 ? .line(code: hat.code, stop: nil) : .timetable(code: hat.code, direction: nil, stop: nil) }
    var body: some View {
        List {
            Section { SyncBanner() }.listRowBackground(Color.clear)
            Section {
                Picker("Kip", selection: $mode.animation(.spring(duration: 0.4))) { Label("Canlı takip", systemImage: "dot.radiowaves.left.and.right").tag(0); Label("Sefer saatleri", systemImage: "clock").tag(1) }
                    .pickerStyle(.segmented)
                if mode == 1 { Label("Sefer saatleri canlı kotayı kullanmaz; açtığın hat çevrimdışı da görünür.", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary) }
            }.listRowBackground(Color.clear)
            if query.isEmpty {
                if !model.pinnedLines.isEmpty { chips("Sabit hatlar", "pin.fill", model.pinnedLines) }
                if !model.recentLines.isEmpty { chips("Son baktıkların", "clock.arrow.circlepath", model.recentLines) }
            }
            Section(query.isEmpty ? "Tüm hatlar" : "\(filtered.count) sonuç") {
                ForEach(filtered.prefix(300)) { hat in
                    NavigationLink(value: route(hat)) {
                        HStack {
                            LineBadge(code: hat.code).frame(width: 84, alignment: .leading)
                            Text(hat.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(minLength: 4)
                            if model.pinnedLines.contains(hat.code) { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                            // Görünür Takip düğmesi: hattın duraklarını açar, durağa dokununca takibe alır.
                            let followed = model.isFollowing(line: hat.code)
                            Button { withAnimation(.spring(duration: 0.35)) { model.toggleFollow(line: hat.code) } } label: {
                                Label(followed ? "Takipte" : "Takip et", systemImage: followed ? "checkmark" : "plus").font(.caption.weight(.bold)).labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 10).padding(.vertical, 6).background((followed ? Color.green : Theme.accent).opacity(0.16), in: .capsule)
                                    .foregroundStyle(followed ? .green : Theme.accent)
                            }.buttonStyle(.borderless).accessibilityLabel(followed ? "\(hat.code) hattı takipte, bırak" : "\(hat.code) hattını takip et")
                                .sensoryFeedback(.success, trigger: followed)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Durak ekle", systemImage: "mappin.and.ellipse") { followHat = hat }.tint(.green)
                        Button(model.pinnedLines.contains(hat.code) ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: "pin") { withAnimation(.spring) { model.togglePin(line: hat.code) } }.tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        NavigationLink(value: Route.lineInfo(code: hat.code)) { Label("Bilgi", systemImage: "info.circle") }.tint(.blue)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background { AuroraBackground() }
        .navigationTitle("Hatlar")
        .sheet(item: $followHat) { FollowSheet(hat: $0) }
        .task {
            #if DEBUG
            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-follow=") }) { try? await Task.sleep(for: .milliseconds(900)); followHat = model.line(String(arg.dropFirst(8))) }
            #endif
        }
        .searchable(text: $query, prompt: "Hat kodu veya güzergâh (örn. 500T, Kadıköy)")
        .overlay { if model.lines.isEmpty { ProgressView("Hatlar yükleniyor…") } }
    }
    private func chips(_ title: String, _ icon: String, _ codes: [String]) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(codes, id: \.self) { code in
                        NavigationLink(value: mode == 0 ? Route.line(code: code, stop: nil) : Route.timetable(code: code, direction: nil, stop: nil)) { LineBadge(code: code) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 4)
            }
        } header: { Label(title, systemImage: icon) }
    }
}
