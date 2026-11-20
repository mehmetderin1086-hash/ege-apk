import SwiftUI

/// Ajan merkezi: görev geçmişi + denetim günlüğü (11), araç izinleri (10), adım ve maliyet bütçesi (3, 12), eleştirmen / beceri önerisi (9, 6).
struct AjanEkrani: View {
    let yenidenCalistir: (String) -> Void
    @Environment(\.dismiss) private var kapat
    @State private var defter = AjanDefteri.ortak
    @State private var temizleSor = false

    /// İzin ayarı yapılabilen araçlar (görünen adla, alfabetik).
    private var araclar: [(String, String)] {
        (AracKaydi.adlar + ["webArastir", "arkaPlanGorevi", "rutinler"])
            .map { ($0, GorevGunlugu.adlar[$0] ?? $0) }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if defter.gorevler.isEmpty {
                        Text("Henüz görev yok. Asistan'a bir iş verdiğinde adımları burada görünür.").foregroundStyle(.secondary)
                    }
                    ForEach(defter.gorevler.prefix(60)) { g in
                        NavigationLink { GorevAyrintisi(gorev: g) { kapat(); yenidenCalistir(g.asil ?? g.istek) } } label: { GorevSatiri(gorev: g) }
                    }
                    if !defter.gorevler.isEmpty {
                        Button("Görev geçmişini temizle", systemImage: "trash", role: .destructive) { temizleSor = true }
                    }
                } header: { Text("Görev geçmişi") } footer: { Text("Her isteğin kullandığı araçlar, süreleri ve sonucu telefonda saklanır (en çok \(AjanDefteri.enFazlaGorev) görev). Araçlara giden kişisel veri kaydedilmez.") }

                Section {
                    Stepper(value: $defter.adimButcesi, in: 0...40, step: 2) {
                        LabeledContent("Adım bütçesi", value: defter.adimButcesi == 0 ? "Sınırsız" : "\(defter.adimButcesi) araç çağrısı")
                    }.accessibilityIdentifier("adim-butcesi")
                    Stepper(value: $defter.pahaliGunlukSinir, in: 0...200, step: 5) {
                        LabeledContent("Günlük Opus/Fable sınırı", value: defter.pahaliGunlukSinir == 0 ? "Sınırsız" : "\(defter.pahaliGunlukSinir) yanıt")
                    }.accessibilityIdentifier("pahali-sinir")
                    LabeledContent("Bugün Opus/Fable", value: "\(defter.bugunPahali) yanıt")
                } header: { Text("Bütçeler") } footer: { Text("Adım bütçesi dolunca ajan yeni araç çağırmaz, elindekiyle yanıtlar. Günlük sınır dolunca pahalı modeller atlanır ve Sonnet/GPT/Gemini kullanılır (elle yeniden üretim hariç).") }

                Section {
                    Toggle("Eleştirmen denetimi", isOn: $defter.elestirmen).accessibilityIdentifier("elestirmen")
                    Toggle("Çok adımlı işi beceri olarak öner", isOn: $defter.beceriOnerisi).accessibilityIdentifier("beceri-onerisi")
                } header: { Text("Davranış") } footer: { Text("Eleştirmen: hesaplı/uzun yanıtları ikinci bir hızlı model denetler, yanıttaki işlemler kodla yeniden hesaplanır; sorun varsa yanıtın altına not düşer.") }

                Section {
                    ForEach(araclar, id: \.0) { kimlik, ad in
                        Picker(ad, selection: Binding(get: { defter.politika(kimlik) }, set: { defter.politikaAta(kimlik, $0) })) {
                            ForEach(AjanDefteri.Politika.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .accessibilityIdentifier("izin-\(kimlik)")
                    }
                } header: { Text("Araç izinleri") } footer: { Text("Otomatik: ajan gerektiğinde kullanır. Her seferinde sor: her çağrıdan önce onay ister. Kapalı: ajan bu aracı hiç kullanamaz.") }
            }
            .navigationTitle("Ajan merkezi").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .confirmationDialog("Görev geçmişi silinsin mi?", isPresented: $temizleSor, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { defter.gecmisiTemizle() }
            }
        }
    }
}

private struct GorevSatiri: View {
    let gorev: AjanDefteri.GorevKaydi
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(gorev.istek).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: simge).foregroundStyle(renk)
                Text(gorev.durum)
                if !gorev.adimlar.isEmpty { Text("· \(gorev.adimlar.count) adım") }
                if gorev.sure > 0 { Text("· " + SureBicimi.metin(gorev.sure)) }
                Spacer()
                Text(gorev.baslangic, format: .dateTime.day().month().hour().minute())
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("gorev-satiri")
    }
    private var simge: String {
        switch gorev.durum { case "Tamamlandı": "checkmark.circle.fill"; case "Hata": "exclamationmark.triangle.fill"; case "İptal", "Kesildi": "stop.circle"; default: "clock" }
    }
    private var renk: Color {
        switch gorev.durum { case "Tamamlandı": .green; case "Hata": .orange; default: .secondary }
    }
}

private struct GorevAyrintisi: View {
    let gorev: AjanDefteri.GorevKaydi
    let yenidenCalistir: () -> Void
    var body: some View {
        Form {
            Section("İstek") { Text(gorev.istek).textSelection(.enabled) }
            Section("Özet") {
                LabeledContent("Durum", value: gorev.durum)
                if let m = gorev.model { LabeledContent("Model", value: TelefonProxy.Model.kisaAd(m)) }
                LabeledContent("Süre", value: gorev.sure > 0 ? SureBicimi.metin(gorev.sure) : "—")
                LabeledContent("Başlangıç", value: gorev.baslangic.formatted(date: .abbreviated, time: .standard))
            }
            Section("Adımlar (denetim günlüğü)") {
                if gorev.adimlar.isEmpty { Text("Araç kullanılmadı; yalnız model yanıtı.").foregroundStyle(.secondary) }
                ForEach(gorev.adimlar) { a in
                    HStack {
                        Text(GorevGunlugu.gorunenAd(a.arac))
                        Spacer()
                        Text(a.durum).foregroundStyle(a.durum == "Tamam" ? .green : (a.durum == "Hata" ? .orange : .secondary))
                        Text(String(format: "%.1f sn", a.sure).replacingOccurrences(of: ".", with: ",")).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            if !gorev.sonuc.isEmpty { Section("Sonuç (ilk satırlar)") { Text(gorev.sonuc).font(.callout).textSelection(.enabled) } }
            Section {
                Button("Bu görevi yeniden çalıştır", systemImage: "arrow.clockwise") { yenidenCalistir() }
                    .accessibilityIdentifier("gorevi-yeniden-calistir")
            }
        }
        .navigationTitle("Görev").navigationBarTitleDisplayMode(.inline)
    }
}
