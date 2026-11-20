import SwiftUI
import PhotosUI
import ProxyKit

struct SohbetMesaji: Identifiable, Equatable {
    let id = UUID()
    var role: String
    var text: String
    var image: Data?
    var meta: String?
}

struct SohbetView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sohbetModeli") private var modelId = "claude-sonnet-5-5"
    @State private var messages: [SohbetMesaji] = []
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            ContentUnavailableView("Vekili sına", systemImage: "bubble.left.and.text.bubble.right",
                                                   description: Text("Mesajlar telefondaki vekil motorundan geçer; hangi yolun kullanıldığı her yanıtın altında yazar."))
                                .padding(.top, 60)
                        }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                    }
                    .padding()
                }
                .onChange(of: messages.last?.text) { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: photoData == nil ? "photo" : "photo.fill").font(.title3)
                }
                TextField("Mesaj", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                if task != nil {
                    Button { task?.cancel(); task = nil } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                } else {
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .navigationTitle("Sohbet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    let local = ModelRouter(state: model.state).localModels().map(\.id)
                    Section("Telefonda") { ForEach(local, id: \.self) { id in Button(id) { modelId = id } } }
                    let remote = model.remoteModels.filter { !local.contains($0) }
                    if !remote.isEmpty { Section("Sunucuda") { ForEach(remote, id: \.self) { id in Button(id) { modelId = id } } } }
                } label: {
                    HStack(spacing: 4) { Text(modelId).font(.subheadline.weight(.semibold)); Image(systemName: "chevron.down").font(.caption) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { messages = [] } label: { Image(systemName: "square.and.pencil") }
                    .disabled(task != nil)   // akış sürerken temizlemek yazılan balonu yok eder
            }
        }
        .task { await model.loadRemoteModels() }
        .onChange(of: photo) {
            Task {
                guard let d = try? await photo?.loadTransferable(type: Data.self), let ui = UIImage(data: d) else { photoData = nil; return }
                photoData = ui.jpegData(compressionQuality: 0.8)
            }
        }
    }

    @ViewBuilder func bubble(_ m: SohbetMesaji) -> some View {
        let user = m.role == "user"
        VStack(alignment: user ? .trailing : .leading, spacing: 4) {
            if let d = m.image, let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 160).clipShape(.rect(cornerRadius: 10))
            }
            Text(m.text.isEmpty ? "…" : m.text)
                .textSelection(.enabled)
                .padding(10)
                .background(user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 14))
            if let meta = m.meta { Text(meta).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(SohbetMesaji(role: "user", text: text, image: photoData))
        input = ""; photoData = nil; photo = nil
        let reply = SohbetMesaji(role: "assistant", text: "")
        messages.append(reply)
        let rid = reply.id
        // Dizin yerine kimlikle güncelle: liste bu arada değişse de çökme ya da yanlış balona yazma olmaz.
        func append(_ t: String) { if let i = messages.firstIndex(where: { $0.id == rid }) { messages[i].text += t } }
        func set(_ t: String) { if let i = messages.firstIndex(where: { $0.id == rid }) { messages[i].text = t } }
        func meta(_ t: String) { if let i = messages.firstIndex(where: { $0.id == rid }) { messages[i].meta = t } }
        let history: [JSON] = messages.dropLast().map { m in
            if let d = m.image {
                return ["role": .string(m.role), "content": [["type": "text", "text": .string(m.text)],
                                                             ["type": "image_url", "image_url": ["url": .string("data:image/jpeg;base64," + d.base64EncodedString())]]]]
            }
            return ["role": .string(m.role), "content": .string(m.text)]
        }
        let body: JSON = ["model": .string(modelId), "stream": true, "max_tokens": 4096, "messages": .array(history)]
        let key = model.state.localKey
        let engine = model.engine
        task = Task {
            let t0 = Date()
            let r = await engine.handle(ProxyRequest(method: "POST", path: "/v1/chat/completions",
                                                     headers: ["authorization": "Bearer \(key)"], body: body.data()))
            if !r.streaming {
                var d = Data()
                do { for try await c in r.body { d.append(c) } } catch {}
                let j = try? JSON.parse(d)
                set(j?["choices"]?[0]?["message"]?["content"]?.string ?? "⚠️ " + (j?["error"]?["message"]?.string ?? "HTTP \(r.status)"))
            } else {
                var parser = SSEParser()
                var dec = OpenAIChatDecoder()
                do {
                    for try await chunk in r.body {
                        if Task.isCancelled { break }
                        for e in parser.feed(chunk) {
                            if let err = (try? JSON.parse(Data(e.data.utf8)))?["error"]?["message"]?.string { append("\n⚠️ " + err); continue }
                            for ev in (try? dec.decode(e)) ?? [] { if case .text(let t) = ev { append(t) } }
                        }
                    }
                } catch { append("\n⚠️ \(error.localizedDescription)") }
            }
            let route = await engine.log.records.first?.route ?? "-"
            meta("\(modelId) · \(route) · \(String(format: "%.1f", Date().timeIntervalSince(t0))) sn")
            task = nil
        }
    }
}
