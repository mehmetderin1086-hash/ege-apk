import SwiftUI

/// Hat ya da durak için kalıcı kişisel not. Anahtar: "line:500T" / "stop:301341".
struct NoteCard: View {
    let key: String
    var title = "Notum"
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "note.text").font(.headline)
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text("Örn. 8:10 servisi hep dolu, ön kapıdan bin…").font(.subheadline).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8) }
                TextEditor(text: $text).focused($focused).scrollContentBackground(.hidden).frame(minHeight: 84)
            }
            .padding(6).background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
            if focused { Button("Bitti", systemImage: "checkmark") { focused = false }.font(.footnote.weight(.semibold)) }
        }
        .card()
        .onAppear { if !loaded { text = model.note(for: key); loaded = true } }
        .onChange(of: text) { if loaded { model.setNote(text, for: key) } }
    }
}

/// Bütün notlar: hat ve duraklar, dokununca ilgili ekran.
struct NotesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if model.notes.isEmpty {
                ContentUnavailableView("Henüz notun yok", systemImage: "note.text", description: Text("Hat ya da durak ekranının altındaki “Notum” alanına yazdıkların burada toplanır."))
                    .listRowBackground(Color.clear)
            }
            ForEach(model.notes.sorted { $0.key < $1.key }, id: \.key) { key, text in
                NavigationLink(value: route(for: key)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) { icon(for: key); Text(title(for: key)).font(.headline) }
                        Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .swipeActions { Button("Sil", role: .destructive) { model.setNote("", for: key) } }
            }
        }
        .scrollContentBackground(.hidden).background { AuroraBackground() }
        .navigationTitle("Notlarım")
    }
    private func split(_ key: String) -> (kind: String, id: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init); return (parts.first ?? "", parts.last ?? "")
    }
    @ViewBuilder private func icon(for key: String) -> some View {
        let s = split(key)
        if s.kind == "line" { LineBadge(code: s.id) }
        else if s.kind == "marker" { LineBadge(code: markerParts(s.id).line) }
        else { Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.accent) }
    }
    private func title(for key: String) -> String {
        let s = split(key)
        if s.kind == "line" { return model.line(s.id)?.name ?? "" }
        if s.kind == "marker" { let m = markerParts(s.id); return "(\(m.marker)) işareti · \(m.direction == "G" ? "gidiş" : "dönüş")" }
        return Int(s.id).flatMap { code in model.stops.first { $0.code == code }?.name } ?? "Durak \(s.id)"
    }
    private func route(for key: String) -> Route {
        let s = split(key)
        if s.kind == "marker" { let m = markerParts(s.id); return .timetable(code: m.line, direction: m.direction, stop: nil) }
        return s.kind == "line" ? .lineInfo(code: s.id) : .stop(code: Int(s.id) ?? 0)
    }
    /// "137:G:-1" → hat, yön, işaret
    private func markerParts(_ id: String) -> (line: String, direction: String, marker: String) {
        let p = id.split(separator: ":", maxSplits: 2).map(String.init)
        return (p.first ?? "", p.count > 1 ? p[1] : "", p.count > 2 ? p[2] : "")
    }
}
