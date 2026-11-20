import SwiftData
import SwiftUI

/// Çalış > Antrenör: aktif öğrenme modlarına giriş.
struct CoachHub: View {
    var episode: Episode
    @State private var showSocratic = false
    @State private var showFeynman = false
    @State private var showExam = false
    @State private var showVoiceReview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                CoachTile(symbol: "bubble.left.and.text.bubble.right.fill", title: "Sokratik sınama",
                          detail: "Sorular sesli sorulur, sen sesli cevaplarsın; cevabın belgeye göre değerlendirilir.") { showSocratic = true }
                    .disabled(episode.study?.quiz.isEmpty ?? true)
                CoachTile(symbol: "person.wave.2.fill", title: "Feynman modu",
                          detail: "Konuyu sen anlat; eksik ve hatalı noktaların listelensin.") { showFeynman = true }
                CoachTile(symbol: "headphones", title: "Sesli kart tekrarı",
                          detail: "Ekrana bakmadan: kart okunur, \"bildim\" ya da \"bilemedim\" dersin.") { showVoiceReview = true }
                CoachTile(symbol: "timer", title: "Sınav simülasyonu",
                          detail: "Seçtiğin bölümlerden süreli, karışık test; sonunda net ve bölüm analizi.") { showExam = true }
                if episode.study?.quiz.isEmpty ?? true {
                    Text("Sokratik sınama için önce Quiz sekmesinden çalışma paketi oluştur.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showSocratic) { SocraticView(episode: episode) }
        .sheet(isPresented: $showFeynman) { FeynmanView(episode: episode) }
        .sheet(isPresented: $showExam) { ExamSimulatorView() }
        .sheet(isPresented: $showVoiceReview) { VoiceReviewView() }
    }
}

private struct CoachTile: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.gradient)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kelime kartları (öneri 19)

struct VocabView: View {
    @Bindable var episode: Episode
    @Environment(\.modelContext) private var context
    @AppStorage("vocab.target") private var target = "tr"
    @State private var items: [VocabItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var added = false

    private var storeKey: String { "vocab.\(episode.id.uuidString)" }

    var body: some View {
        List {
            Section {
                Picker("Çeviri dili", selection: $target) {
                    Text("Türkçe").tag("tr")
                    Text("İngilizce").tag("en")
                }
                .modifier(AccessiblePickerStyle())
                Button {
                    Task { await generate() }
                } label: {
                    HStack { if loading { ProgressView() }; Text(items.isEmpty ? "Terimleri çıkar" : "Yeniden çıkar") }
                }
                .disabled(loading)
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
            } footer: {
                Text("Bölümdeki akademik terimler, çevirisi ve örnek cümlesiyle listelenir. YDS ve yabancı dilde ders çalışırken işe yarar.")
            }
            if !items.isEmpty {
                Section {
                    Button(added ? "Tekrar destesine eklendi" : "Hepsini tekrar destesine ekle", systemImage: "rectangle.stack.badge.plus") {
                        ReviewDeck.add(flashcards: items.map { Flashcard(front: $0.term, back: "\($0.translation)\n\n\($0.example)\n\($0.exampleTranslation)") },
                                       episode: episode, context: context)
                        added = true
                    }
                    .disabled(added)
                }
                Section("\(items.count) terim") {
                    ForEach(items, id: \.term) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.term).font(.headline)
                                Spacer()
                                Button { Task { await SpeechOut.shared.speak(item.term, language: target == "tr" ? "en-US" : "tr-TR") } } label: {
                                    Image(systemName: "speaker.wave.2")
                                }
                                .buttonStyle(.borderless)
                            }
                            Text(item.translation).foregroundStyle(.tint)
                            Text(item.example).font(.caption)
                            Text(item.exampleTranslation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear { load() }
    }

    private func load() {
        guard items.isEmpty, let data = UserDefaults.standard.data(forKey: storeKey),
              let saved = try? JSONDecoder().decode([VocabItem].self, from: data) else { return }
        items = saved
    }

    private func generate() async {
        let text = episode.timeline?.turns.map(\.text).joined(separator: "\n") ?? episode.script?.sourceNotes ?? ""
        guard !text.isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            items = try await APIClient.shared.vocab(VocabRequest(text: String(text.prefix(20_000)), targetLang: target, count: 25))
            UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: storeKey)
            added = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
