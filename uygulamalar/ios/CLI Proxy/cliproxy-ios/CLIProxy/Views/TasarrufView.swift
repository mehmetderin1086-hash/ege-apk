import SwiftUI
import ProxyKit

/// Kota ve token tasarrufu: ayarlar + canlı sayaçlar + hesap başına kota doluluğu.
struct TasarrufView: View {
    @Environment(AppModel.self) private var model
    @State private var durum: ProxyEngine.TasarrufDurumu?
    private let yenile = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var ayar: TasarrufAyarlari { model.state.tasarruf }
    private func degistir(_ f: @escaping @Sendable (inout TasarrufAyarlari) -> Void) { model.update { var a = $0.tasarruf; f(&a); $0.tasarruf = a } }
    private func sayi(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1f M", Double(n) / 1e6) : n >= 1000 ? String(format: "%.1f B", Double(n) / 1e3) : "\(n)" }

    var body: some View {
        List {
            if let d = durum {
                Section("Bugün") {
                    LabeledContent("Kullanılan token", value: sayi(d.bugunToken) + (ayar.gunlukTokenSiniri > 0 ? " / " + sayi(ayar.gunlukTokenSiniri) : ""))
                    if ayar.gunlukTokenSiniri > 0 {
                        ProgressView(value: min(1, Double(d.bugunToken) / Double(ayar.gunlukTokenSiniri))).tint(d.bugunToken > ayar.gunlukTokenSiniri * 9 / 10 ? .red : .accentColor)
                    }
                }
                Section {
                    LabeledContent("Önbellek isabeti", value: "\(d.sayaclar.onbellekIsabeti)")
                    LabeledContent("Tekilleştirilen istek", value: "\(d.sayaclar.tekillestirilen)")
                    LabeledContent("Kaçınılan token (tahmini)", value: sayi(d.sayaclar.tasarrufEdilenToken))
                    LabeledContent("Prompt önbelleğinden okunan", value: sayi(d.sayaclar.promptOnbellekOkunan))
                    LabeledContent("Prompt önbelleğine yazılan", value: sayi(d.sayaclar.promptOnbellekYazilan))
                    LabeledContent("Kota nedeniyle atlanan hesap", value: "\(d.sayaclar.kotaAtlama)")
                    LabeledContent("Kırpılan araç çıktısı", value: "\(d.sayaclar.kirpilanAracCiktisi)")
                    LabeledContent("Bütçe reddi", value: "\(d.sayaclar.butceReddi)")
                    LabeledContent("Saklanan yanıt", value: "\(d.onbellekBoyutu)")
                } header: { Text("Tasarruf sayaçları") } footer: { Text("Prompt önbelleğinden okunan tokenlar normal fiyatın yaklaşık %10'una sayılır. Sayaçlar uygulama kapanınca sıfırlanır.") }
                Section {
                    if d.kota.isEmpty { Text("Henüz kota başlığı görülmedi. Claude/Codex hesabıyla bir istek yapınca burada görünür.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(d.kota.sorted { $0.key < $1.key }, id: \.key) { ad, h in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(ad).font(.subheadline.weight(.medium)); Spacer()
                                if let y = h.doluluk { Text("%\(Int(y * 100))").font(.subheadline.monospacedDigit()).foregroundStyle(y >= 0.9 ? .red : y >= 0.7 ? .orange : .green) } else { Text("bilinmiyor").font(.caption).foregroundStyle(.secondary) } }
                            if let y = h.doluluk { ProgressView(value: y).tint(y >= 0.9 ? .red : y >= 0.7 ? .orange : .green) }
                            if let s = h.sifirlanma { Text("Sıfırlanma: ").font(.caption) + Text(s, style: .relative).font(.caption) }
                        }
                    }
                } header: { Text("Hesap kotaları") } footer: { Text("Değerler upstream yanıt başlıklarından okunur. Eşiği aşan hesap, başka hesap varsa otomatik atlanır.") }
            }
            Section {
                Toggle("Otomatik prompt önbelleği (Claude)", isOn: Binding(get: { ayar.otomatikPromptOnbellegi }, set: { v in degistir { $0.otomatikPromptOnbellegi = v } }))
                Toggle("Yanıt önbelleği", isOn: Binding(get: { ayar.yanitOnbellegi }, set: { v in degistir { $0.yanitOnbellegi = v } }))
                Toggle("Aynı anda gelen aynı isteği birleştir", isOn: Binding(get: { ayar.esZamanliTekillestirme }, set: { v in degistir { $0.esZamanliTekillestirme = v } }))
                Toggle("OpenAI / Codex önbellek anahtarı", isOn: Binding(get: { ayar.openAIAnahtariAcik }, set: { v in degistir { $0.openAIOnbellekAnahtari = v } }))
                Toggle("Eski araç çıktılarını kırp (deneysel)", isOn: Binding(get: { ayar.kirpmaAcik }, set: { v in degistir { $0.aracCiktisiKirpma = v } }))
                Picker("Hesap stratejisi", selection: Binding(get: { ayar.strateji }, set: { v in degistir { $0.hesapStratejisi = v } })) {
                    Text("Sırayla").tag(HesapStratejisi.sirayla); Text("Birini bitir").tag(HesapStratejisi.birBitir)
                }
                Stepper(value: Binding(get: { ayar.onbellekSuresi / 60 }, set: { v in degistir { $0.onbellekSuresi = v * 60 } }), in: 1...120) { LabeledContent("Önbellek ömrü", value: "\(ayar.onbellekSuresi / 60) dk") }
                Stepper(value: Binding(get: { ayar.gunlukTokenSiniri / 50_000 }, set: { v in degistir { $0.gunlukTokenSiniri = v * 50_000 } }), in: 0...400) {
                    LabeledContent("Günlük token sınırı", value: ayar.gunlukTokenSiniri == 0 ? "Sınırsız" : sayi(ayar.gunlukTokenSiniri))
                }
                Stepper(value: Binding(get: { ayar.kotaKorumaYuzdesi / 5 }, set: { v in degistir { $0.kotaKorumaYuzdesi = v * 5 } }), in: 0...20) {
                    LabeledContent("Kota koruma eşiği", value: ayar.kotaKorumaYuzdesi == 0 ? "Kapalı" : "%\(ayar.kotaKorumaYuzdesi)")
                }
            } header: { Text("Ayarlar") } footer: {
                Text("Yanıt önbelleği yalnız temperature=0 ya da `x-proxy-cache: 1` başlığı olan isteklerde çalışır (yeniden üretim bozulmasın). Prompt önbelleği tekrarlayan uzun sistem istemlerini ~%90 ucuza okur; aynı konuşma aynı hesapta tutulur. Günlük sınır dolunca yeni istekler 429 alır. \"Birini bitir\": ilk hesap soğuyana kadar kullanılır, sonra sıradakine geçilir. Araç çıktısı kırpma yalnız son 4 mesajdan önceki, 6000 karakteri aşan araç sonuçlarını (baş+son) kısaltır; varsayılan kapalıdır. Kota 429 hataları Retry-After kadar, harcama sınırı hataları 24 saat, model bazında dinlendirilir.")
            }
            Section {
                Button("Önbelleği ve sayaçları sıfırla", role: .destructive) { Task { await model.engine.onbellek.temizle(); await model.engine.sayac.sifirla(); durum = await model.engine.tasarrufDurumu() } }
            }
        }
        .navigationTitle("Tasarruf")
        .task { durum = await model.engine.tasarrufDurumu() }
        .onReceive(yenile) { _ in Task { durum = await model.engine.tasarrufDurumu() } }
    }
}
