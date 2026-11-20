import SwiftUI

/// #36: dinleme modu seçici (Rahat / Aktif / Sınav). Davranışın tek kaynağı `ListeningMode.current.policy`.
/// `compact` (varsayılan) oynatıcıdaki menü; işlemler sayfasında açık seçimli sürüm.
struct ListeningModePicker: View {
    var compact = true
    @AppStorage(ListeningMode.key) private var raw = ListeningMode.aktif.rawValue

    private var mode: ListeningMode { ListeningMode(rawValue: raw) ?? .aktif }

    private var selection: Binding<ListeningMode> {
        Binding(get: { mode }, set: { ListeningMode.current = $0; raw = $0.rawValue })
    }

    var body: some View {
        if compact {
            Menu {
                Picker("Dinleme modu", selection: selection) {
                    ForEach(ListeningMode.allCases) { mode in
                        Label {
                            Text(mode.title)
                            Text(Self.summary(mode))
                        } icon: { Image(systemName: Self.symbol(mode)) }
                        .tag(mode)
                    }
                }
            } label: {
                Label(mode.title, systemImage: Self.symbol(mode))
                    .font(.caption.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dinleme modu: \(mode.title)")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Dinleme modu", selection: selection) {
                    ForEach(ListeningMode.allCases) { Text($0.title).tag($0) }
                }
                .modifier(AccessiblePickerStyle())
                Text(Self.summary(mode))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func symbol(_ mode: ListeningMode) -> String {
        switch mode {
        case .rahat: "cup.and.saucer"
        case .aktif: "brain.head.profile"
        case .sinav: "checkmark.seal"
        }
    }

    static func summary(_ mode: ListeningMode) -> String {
        switch mode {
        case .rahat: "Düşünme payları atlanır, ara soru yok; yalnız bölüm sonu soruları."
        case .aktif: "Düşünme payı ve konu sonu soruları açık."
        case .sinav: "Ön test, eminlik sorusu ve sık yoklama da eklenir."
        }
    }
}
