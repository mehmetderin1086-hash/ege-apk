import SwiftUI
import ProxyKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Durum", systemImage: "antenna.radiowaves.left.and.right") { NavigationStack { DurumView() } }
            Tab("Hesaplar", systemImage: "person.2.badge.key") { NavigationStack { HesaplarView() } }
            Tab("Sohbet", systemImage: "bubble.left.and.text.bubble.right") { NavigationStack { SohbetView() } }
            Tab("Tasarruf", systemImage: "leaf") { NavigationStack { TasarrufView() } }
            Tab("Kayıtlar", systemImage: "list.bullet.rectangle") { NavigationStack { KayitlarView() } }
            Tab("Ayarlar", systemImage: "gearshape") { NavigationStack { AyarlarView() } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .top) {
            if let b = model.banner {
                Text(b)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(model.bannerIsError ? Color.red.opacity(0.9) : Color.green.opacity(0.9), in: .capsule)
                    .foregroundStyle(.white)
                    .padding(.top, 8).padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.banner = nil }
            }
        }
        .animation(.spring(duration: 0.35), value: model.banner)
    }
}

struct CopyRow: View {
    let title: String
    let value: String
    var secret = false
    @State private var reveal = false
    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(secret && !reveal ? String(repeating: "•", count: 16) + value.suffix(4) : value)
                    .font(.footnote.monospaced()).lineLimit(2).textSelection(.enabled)
            }
            Spacer()
            if secret {
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.buttonStyle(.borderless)
            }
            Button {
                UIPasteboard.general.string = value
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }.buttonStyle(.borderless)
        }
    }
}

extension Date {
    var kisaGoreli: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
