import SwiftUI

/// Dosya üretme, dönüştürme ve arşiv işlerini tek, iPhone yerel çalışma alanında toplar.
struct UretkenlikEkrani: View {
    @Environment(\.dismiss) private var kapat
    @State private var donusturmeAcik = false
    @State private var arsivAcik = false
    @State private var indirmelerAcik = false
    @State private var kayitAcik = false

    var body: some View {
        NavigationStack {
            List {
                Section("Üretkenlik araçları") {
                    Button { donusturmeAcik = true } label: {
                        Label("Dosya dönüştür", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    }
                    Button { arsivAcik = true } label: {
                        Label("ZIP oluştur veya ZIP / RAR aç", systemImage: "archivebox")
                    }
                    Button { indirmelerAcik = true } label: {
                        Label("Oluşturulan ve indirilen dosyalar", systemImage: "folder")
                    }
                    Button { kayitAcik = true } label: {
                        Label("Toplantı kaydı ve tutanak", systemImage: "waveform")
                    }
                    .accessibilityIdentifier("uretkenlik-toplanti-kaydi")
                }
                Section("Hızlı kullanım") {
                    Label("Sohbette + düğmesiyle belge veya fotoğraf ekle; düzenleme isteği yeni dosya olarak üretilir.", systemImage: "plus.circle")
                    Label("Dönüşüm özgün dosyayı değiştirmez. Sonuçlar İndirmeler'de açılır, Dosyalar'a kaydedilir veya paylaşılır.", systemImage: "doc.badge.arrow.up")
                }
                Section {
                    Text("DOCX, XLSX, PPTX, PDF, CSV, Markdown, metin ve JSON desteklenir. RAR açılabilir; RAR oluşturma yerine ZIP kullanılır.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Üretkenlik")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .sheet(isPresented: $donusturmeAcik) { OfisDonusturmeEkrani() }
            .sheet(isPresented: $arsivAcik) { ArsivEkrani() }
            .sheet(isPresented: $indirmelerAcik) { IndirmelerEkrani() }
            // P4.6: tutanak isteği sohbete gidince Üretkenlik de kapanır (yanıt sohbette görünsün).
            .sheet(isPresented: $kayitAcik) { KayitEkrani { kapat() } }
        }
    }
}
