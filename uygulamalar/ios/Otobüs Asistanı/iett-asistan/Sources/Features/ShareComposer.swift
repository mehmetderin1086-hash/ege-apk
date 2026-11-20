import SwiftUI

/// Paylaşım penceresi: hazır mesajı düzenle, konum/uygulama bağlantısı ve zaman damgasını aç-kapat; WhatsApp, Mesajlar, genel paylaşım ya da kopyala.
struct ShareComposerSheet: View {
    let message: ShareMessage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var includeMap = true
    @State private var includeApp = true
    @State private var includeStamp = true
    @State private var copied = false
    @State private var whatsappInstalled = false

    private func regenerate() { text = message.text(includeMap: includeMap, includeApp: includeApp, stamp: includeStamp ? ShareBuilder.stamp() : nil) }
    private func encoded(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? s }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mesaj (düzenleyebilirsin)") {
                    TextEditor(text: $text).frame(minHeight: 200).font(.body)
                }
                Section("Eklenecekler") {
                    if message.maps != nil { Toggle(isOn: $includeMap) { Label("Konum bağlantısı (Haritalar)", systemImage: "mappin.and.ellipse") } }
                    if message.deep != nil { Toggle(isOn: $includeApp) { Label("Uygulama bağlantısı", systemImage: "link") } }
                    Toggle(isOn: $includeStamp) { Label("Zaman damgası", systemImage: "clock") }
                }
                Section {
                    if whatsappInstalled {
                        Button { if let url = URL(string: "whatsapp://send?text=\(encoded(text))") { openURL(url) } } label: { Label("WhatsApp ile gönder", systemImage: "message.fill").foregroundStyle(.green) }
                    }
                    Button { if let url = URL(string: "sms:&body=\(encoded(text))") { openURL(url) } } label: { Label("Mesajlar ile gönder", systemImage: "bubble.left.fill") }
                    ShareLink(item: text) { Label("Diğer uygulamalarla paylaş…", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = text; withAnimation { copied = true } } label: { Label(copied ? "Kopyalandı ✓" : "Metni kopyala", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .sensoryFeedback(.success, trigger: copied)
                }
            }
            .navigationTitle("Paylaş").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
            .onAppear { regenerate(); whatsappInstalled = UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!) }
            .onChange(of: includeMap) { regenerate() }
            .onChange(of: includeApp) { regenerate() }
            .onChange(of: includeStamp) { regenerate() }
        }
        .presentationDetents([.large])
    }
}

extension View {
    /// `item` doluyken paylaşım penceresini açar.
    func shareSheet(_ item: Binding<ShareMessage?>) -> some View { sheet(item: item) { ShareComposerSheet(message: $0) } }
}

/// Tek dokunuşla paylaşım penceresini açan simge düğmesi; mesaj dokunulduğu anda (güncel veriyle) üretilir.
struct ShareIconButton: View {
    var label = "Paylaş"
    var showsTitle = false
    let make: () -> ShareMessage
    @State private var message: ShareMessage?
    var body: some View {
        Button { message = make() } label: {
            if showsTitle { Label(label, systemImage: "square.and.arrow.up") } else { Image(systemName: "square.and.arrow.up") }
        }
        .accessibilityLabel(label)
        .shareSheet($message)
    }
}
