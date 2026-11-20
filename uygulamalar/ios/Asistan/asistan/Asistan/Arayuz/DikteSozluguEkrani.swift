import SwiftUI
import Combine

/// Dikte sözlüğü: "yanlış → doğru" düzeltmeleri (elle eklenenler hemen, süzgecin öğrendikleri iki kez görülünce uygulanır),
/// cihaz içi dil modelinin durumu.
struct DikteSozluguEkrani: View {
    @State private var kayitlar: [DikteDuzeltmeDefteri.Kayit] = []
    @State private var yanlis = ""
    @State private var dogru = ""
    @State private var bilgi: String?
    @State private var kuruluyor = false

    private var defter: DikteDuzeltmeDefteri { .ortak }

    var body: some View {
        List {
            Section {
                Text("Sesle söylediğinde yanlış yazılan sözcükleri burada düzelt. Elle eklediğin düzeltme hemen uygulanır; asistanın kendi öğrendiği düzeltme iki kez görülünce uygulanır. Hepsi telefonda kalır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Yeni düzeltme") {
                TextField("Yanlış (ör. mitos)", text: $yanlis)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("dikte-yanlis")
                TextField("Doğru (ör. mitoz)", text: $dogru)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("dikte-dogru")
                Button("Ekle", systemImage: "plus.circle", action: ekle)
                    .disabled(yanlis.trimmingCharacters(in: .whitespaces).isEmpty || dogru.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("dikte-ekle")
                if let bilgi { Text(bilgi).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Düzeltmeler (\(kayitlar.count))") {
                if kayitlar.isEmpty { Text("Henüz düzeltme yok.").foregroundStyle(.secondary) }
                ForEach(kayitlar) { k in
                    HStack {
                        Text("\(k.yanlis) → \(k.dogru)").font(.callout)
                        Spacer()
                        Text(k.kaynak == .kullanici ? "sen ekledin" : (k.etkin ? "\(k.sayac) kez" : "öğreniliyor"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("dikte-kayit")
                }
                .onDelete { idx in
                    idx.map { kayitlar[$0].yanlis }.forEach { defter.sil($0) }
                    yenile()
                }
            }
            Section("Dil modeli") {
                LabeledContent("Durum", value: DikteDilModeli.hazirlaniyor || kuruluyor ? "hazırlanıyor…"
                               : DikteDilModeli.hazirYapilandirma != nil ? "hazır (\(DikteDilModeli.ifadeSayisi) ifade)" : "kurulmadı")
                Button(kuruluyor ? "Kuruluyor…" : "Dil modelini yeniden kur", systemImage: "arrow.clockwise") {
                    kuruluyor = true
                    Task { await DikteDilModeli.hazirla(zorla: true); kuruluyor = false }
                }
                .disabled(kuruluyor || !DikteDilModeli.ayarAcik)
                .accessibilityIdentifier("dikte-yeniden-kur")
                if !DikteDilModeli.ayarAcik { Text("Ayarlar > Ses'teki 'Dikte sözlüğü' anahtarı kapalı.").font(.caption).foregroundStyle(.orange) }
                Text("Kişilerin adları (yalnız Kişiler izni verilmişse) ve düzeltmelerin doğru biçimleri telefondaki konuşma tanımaya öğretilir.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dikte sözlüğü")
        .accessibilityIdentifier("dikte-sozlugu")
        .onAppear(perform: yenile)
        .onReceive(NotificationCenter.default.publisher(for: DikteDuzeltmeDefteri.degisti).receive(on: RunLoop.main)) { _ in yenile() }
    }

    private func ekle() {
        if defter.ekle(yanlis: yanlis, dogru: dogru) {
            bilgi = "Eklendi: \(yanlis.trimmingCharacters(in: .whitespaces)) → \(dogru.trimmingCharacters(in: .whitespaces))"
            yanlis = ""; dogru = ""
        } else {
            bilgi = "Eklenemedi: iki alan dolu ve birbirinden farklı olmalı."
        }
        yenile()
    }

    private func yenile() { kayitlar = defter.liste() }
}
