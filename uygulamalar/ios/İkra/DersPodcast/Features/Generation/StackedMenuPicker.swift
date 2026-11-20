import SwiftUI

/// Etiketi üstte, seçili değeri altında gösteren menü seçici. Uzun değer ("Hugging Face · MMS Türkçe") 320 nokta
/// genişlikte etiketle aynı satıra sığmaz; burada değer gerekirse ikinci satıra kırılır, kırpılmaz.
struct StackedMenuPicker<Selection: Hashable, Options: View>: View {
    let title: String
    /// Seçili değerin görünen adı.
    let value: String
    @Binding var selection: Selection
    @ViewBuilder let options: () -> Options

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline)
            Menu {
                Picker(title, selection: $selection, content: options)
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }
}
