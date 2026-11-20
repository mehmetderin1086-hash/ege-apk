import SwiftUI

// Dinleme ve metin araçları: terim düzeltme (#9).

/// Küresel terim sözlüğünü yönetir; eklenen düzeltme bu dersin tüm metinlerine hemen uygulanır.
struct TermCorrectionView: View {
    var context: LessonContext

    @Environment(\.dismiss) private var dismiss
    @State private var rules = TermDictionary.rules
    @State private var current: VideoTranscript
    @State private var from = ""
    @State private var to = ""
    @State private var message: String?

    init(context: LessonContext) {
        self.context = context
        _current = State(initialValue: context.transcript)
    }

    private var canAdd: Bool {
        TermDictionary.isValid(TermRule(from: from.trimmingCharacters(in: .whitespacesAndNewlines),
                                        to: to.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Yanlış yazılan (ör. kuantım)", text: $from)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Doğrusu (ör. kuantum)", text: $to)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Ekle ve bu derste düzelt", systemImage: "plus.circle.fill", action: add)
                        .disabled(!canAdd)
                } header: {
                    Text("Yeni düzeltme")
                } footer: {
                    Text("Sözlük tüm derslerde geçerlidir; sonradan eklediğin derslere de otomatik uygulanır. Metindeki her yerde (altyazı, paragraf, notlar) tam sözcük olarak değiştirilir. Transkriptte bir paragrafa uzun basıp “Terimi düzelt” ile de ekleyebilirsin.")
                }
                if let message {
                    Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) }
                }
                Section("Sözlük (\(rules.count))") {
                    if rules.isEmpty {
                        Text("Henüz düzeltme yok.").foregroundStyle(.secondary)
                    }
                    ForEach(rules) { rule in
                        HStack(spacing: 6) {
                            Text(rule.from).foregroundStyle(.secondary).strikethrough()
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            Text(rule.to).fontWeight(.semibold)
                        }
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        offsets.map { rules[$0] }.forEach(TermDictionary.remove)
                        rules = TermDictionary.rules
                    }
                }
                if !rules.isEmpty {
                    Section {
                        Button("Sözlüğü bu derse yeniden uygula", systemImage: "arrow.triangle.2.circlepath") {
                            let changed = apply(to: rules)
                            message = changed > 0 ? "\(changed) paragrafta düzeltildi." : "Değişecek bir yer bulunamadı."
                        }
                    }
                }
            }
            .navigationTitle("Terim düzeltme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .debugNarrowScreen()
        }
    }

    private func add() {
        guard let rule = TermDictionary.add(from: from, to: to) else { return }
        rules = TermDictionary.rules
        let changed = apply(to: [rule])
        message = changed > 0 ? "“\(rule.from)” → “\(rule.to)”: \(changed) paragrafta düzeltildi." : "Eklendi; bu derste eşleşme yok."
        from = ""
        to = ""
    }

    /// Kuralları bu dersin transkriptine uygular; değişen paragraf sayısını döndürür.
    private func apply(to rules: [TermRule]) -> Int {
        let updated = TermDictionary.apply(to: current, rules: rules)
        let changed = zip(current.paragraphs, updated.paragraphs).filter { $0.text != $1.text }.count
        if updated != current {
            current = updated
            context.update(updated)
        }
        return changed
    }
}

/// Bir paragraftaki yanlış sözcüğü seçip doğrusunu yazma sayfası (transkriptte "Terimi düzelt").
struct TermPickerSheet: View {
    var text: String
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ClosedRange<Int>?
    @State private var to = ""

    private var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }

    private var from: String {
        guard let selection else { return "" }
        let picked = words[selection].joined(separator: " ")
        return picked.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private var canSave: Bool {
        TermDictionary.isValid(TermRule(from: from, to: to.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Düzeltilecek sözcüğe dokun. Birkaç sözcük için ilk ve son sözcüğe dokun.")
                        .font(.footnote).foregroundStyle(.secondary)
                    WrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                            let on = selection?.contains(i) ?? false
                            Button { choose(i) } label: {
                                Text(word)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                                    .overlay(Capsule().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if selection != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                Text(from).fontWeight(.semibold)
                            } icon: {
                                Image(systemName: "text.cursor")
                            }
                            TextField("Doğrusu", text: $to)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                onSave(from, to.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            } label: {
                                Text("Her yerde düzelt").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSave)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Terimi düzelt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .debugNarrowScreen()
        }
        .presentationDetents([.medium, .large])
    }

    /// Dokunulan sözcük aralığın dışındaysa aralık ona uzar; içindeyse yalnızca o sözcük seçilir.
    private func choose(_ index: Int) {
        guard let range = selection else { selection = index...index; return }
        if range.contains(index) {
            selection = index...index
        } else {
            selection = min(range.lowerBound, index)...max(range.upperBound, index)
        }
        to = ""
    }
}
