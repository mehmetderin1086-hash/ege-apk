import SwiftUI

/// Kullanım ve dönem raporu aynı kimlik, tarih ve koleksiyon hesaplarını paylaşır.
struct UsageReportView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DonemRaporuSayfasi(reportTitle: "KÜTÜPHANE KULLANIM RAPORU", screenTitle: "Kullanım Raporu")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                }
        }
    }
}
