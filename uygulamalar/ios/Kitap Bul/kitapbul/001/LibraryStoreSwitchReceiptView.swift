import SwiftUI
import SwiftData

/// Uzun geçiş sonucu içeriği kayar; Kapat araç çubuğunda her metin boyutunda
/// erişilebilir kalır. Context, MyApp'in yeni kap etkinleştirildikten sonra açtığı sheet'ten gelir.
struct LibraryStoreSwitchReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    let receipt: ArchiveSwitchCoordinator.Receipt
    let context: ModelContext
    @State private var previousPreview: ArchiveSwitchCoordinator.Preparation?
    @State private var error: String?
    @State private var preparing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Katalog değiştirildi") {
                    Text(receipt.summary).font(.body).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("archive.switch.receipt.summary")
                    LabeledContent("Önceki katalogdaki eser", value: "\(receipt.beforeBooks)")
                    LabeledContent("Yeni katalogdaki eser", value: "\(receipt.afterBooks)")
                }
                Section("İşlem öncesi tam yedek") {
                    Text("Eski katalog silinmedi. Geçişten önce oluşturulan tam ZIP doğrulandı ve bu cihazda saklandı.")
                        .fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: receipt.backupURL) {
                        Label("Önceki tam yedeği paylaş", systemImage: "square.and.arrow.up")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44).accessibilityIdentifier("archive.switch.receipt.shareBackup")
                    ShareLink(item: receipt.scopeReportURL) {
                        Label("Geçiş kapsam raporunu paylaş", systemImage: "doc.text")
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(minHeight: 44)
                    Button {
                        guard !preparing else { return }; preparing = true
                        Task { @MainActor in
                            defer { preparing = false }
                            do { previousPreview = try await ArchiveSwitchCoordinator.prepareAsync(from: receipt.backupURL, context: context); self.error = nil }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        Label("Önceki kataloğu açma önizlemesi", systemImage: "arrow.uturn.backward")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44).accessibilityIdentifier("archive.switch.reopenPrevious").disabled(preparing)
                    if preparing { ProgressView("Önizleme arka planda hazırlanıyor…") }
                }
                if let error {
                    Section("Önizleme hazırlanamadı") {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    Text("Bu ekranı kapattıktan veya uygulamayı yeniden açtıktan sonra Yönetim → Katalog geçişi yedekleri bölümünden aynı yedeğe ulaşabilirsiniz.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Katalog geçişi sonucu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }.accessibilityIdentifier("archive.switch.receipt.close")
                }
            }
            .sheet(item: $previousPreview) { preparation in
                ArchiveSwitchReviewView(preparation: preparation, context: context)
            }
        }
    }
}
