import SwiftUI
import UniformTypeIdentifiers

struct DosyaKasasiEkrani: View {
    var tur = "research"
    var kaynakEkle: ((KasaDosyasi) -> Void)?
    @Environment(\.dismiss) private var kapat
    @State private var yukleyici = BuyukDosyaYukleyici.ortak
    @State private var sunucu = CalismaSunucusu.ortak
    @State private var secici = false
    @State private var silinecek: KasaDosyasi?
    @State private var paylasilacak: URL?
    @State private var indiriliyor = false
    @State private var hata: String?

    var body: some View {
        List {
            Section {
                Text("Dosya başına 10 GB’a kadar").font(.headline).accessibilityIdentifier("kasa-sinir")
                Text("Dosyalar 8 MB’lık parçalarla yüklenir ve bütünlükleri doğrulanır. Bağlantı kesilirse aynı dosyayı seçerek kaldığın yerden devam edebilirsin.").font(.footnote)
                Text("Uygulama arka plana geçince yükleme duraklar. Devam etmek için uygulamayı açıp aynı dosyayı seç.").font(.footnote).foregroundStyle(.secondary)
                Button("Dosya seç ve yükle", systemImage: "arrow.up.doc") { secici = true }
                    .disabled(yukleyici.etkin).accessibilityIdentifier("kasa-dosya-sec")
                Text("Sunucu toplam kotası ve boş disk alanı ayrıca kontrol edilir. Büyük dosyanın kasada saklanması, tamamının model tarafından işlenmesi anlamına gelmez.").font(.footnote).foregroundStyle(.secondary)
            }
            if yukleyici.etkin || !yukleyici.asama.isEmpty {
                Section("Aktarım") {
                    Text(yukleyici.asama).accessibilityIdentifier("kasa-durum")
                    if yukleyici.toplam > 0 {
                        ProgressView(value: Double(yukleyici.aktarilan), total: Double(yukleyici.toplam))
                        Text("\(boyut(yukleyici.aktarilan)) / \(boyut(yukleyici.toplam))").font(.caption).monospacedDigit()
                        if yukleyici.saniyede > 0 {
                            Text("\(boyut(Int64(yukleyici.saniyede)))/sn · yaklaşık \(Int(Double(yukleyici.toplam - yukleyici.aktarilan) / yukleyici.saniyede)) sn kaldı").font(.caption)
                        }
                    } else if yukleyici.etkin { ProgressView() }
                    if yukleyici.etkin {
                        Button("Duraklat") { yukleyici.duraklat() }.accessibilityIdentifier("kasa-duraklat")
                    }
                }
            }
            if !yukleyici.bekleyenler.isEmpty {
                Section("Yarım kalan yüklemeler") {
                    ForEach(yukleyici.bekleyenler) { k in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(k.ad).lineLimit(2)
                            Text("\(boyut(k.ofset)) / \(boyut(k.boyut)) kaydedildi").font(.caption)
                            HStack {
                                Button("Aynı dosyayı seç ve devam et") { secici = true }.buttonStyle(.borderless)
                                Button("Yüklemeyi sil", role: .destructive) { Task { await yukleyici.iptal(k) } }.buttonStyle(.borderless)
                            }.disabled(yukleyici.etkin)
                        }
                    }
                }
            }
            Section("Yüklenen dosyalar") {
                if yukleyici.dosyalar.isEmpty { Text("Henüz dosya yok.").foregroundStyle(.secondary) }
                ForEach(yukleyici.dosyalar) { d in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(d.name).lineLimit(2)
                        Text(boyut(d.size)).font(.caption).foregroundStyle(.secondary)
                        if let kaynakEkle, d.kaynakOlabilir(tur: tur, arastirmaSiniri: arastirmaSiniri) {
                            Button("Çalışmaya kaynak olarak ekle") { kaynakEkle(d); kapat() }.buttonStyle(.borderless)
                        } else if kaynakEkle == nil, d.kaynakOlabilir(tur: "research", arastirmaSiniri: arastirmaSiniri) {
                            NavigationLink("Bu dosyayla araştırma başlat") { CalismaMerkezi(kaynak: d) }
                        } else if kaynakEkle != nil {
                            Text("Bu dosya kasada saklanabilir. Bu tür veya boyut, seçili çalışma tarafından doğrudan işlenemiyor.").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("İndir ve paylaş", systemImage: "square.and.arrow.down") {
                                indiriliyor = true
                                Task {
                                    defer { indiriliyor = false }
                                    do { paylasilacak = try await yukleyici.indir(d); hata = nil } catch { hata = error.localizedDescription }
                                }
                            }.buttonStyle(.borderless).disabled(indiriliyor)
                            Spacer()
                            Button("Sil", role: .destructive) { silinecek = d }.buttonStyle(.borderless).disabled(yukleyici.etkin)
                        }
                    }.padding(.vertical, 4)
                }
                if indiriliyor { ProgressView("Dosya indiriliyor ve doğrulanıyor…") }
                if let paylasilacak { ShareLink("İndirilen dosyayı paylaş", item: paylasilacak) }
            }
            Section("İşleme sınırları") {
                Text("Araştırma metni: dosya başına \(boyut(arastirmaSiniri)). TXT, Markdown, CSV veya JSON içinden soruyla ilgili bölümler seçilir; bu işlem belgenin tamamının incelendiği anlamına gelmez.").font(.footnote).accessibilityIdentifier("kasa-arastirma-siniri")
                Text("Diğer metin çalışmaları: dosya başına 200 KB, toplam 120.000 karakter. Veri analizi: dosya başına 25 MB. PDF metin çıkarımı için Çalışma alanı → Kaynak dosya ekle kullanılır; 25 MB, 200 sayfa ve 120.000 karakter sınırı geçerlidir.").font(.footnote)
            }
            if let mesaj = hata ?? yukleyici.hata { Section { Text(mesaj).foregroundStyle(.red) } }
        }
        .navigationTitle("Dosya kasası")
        .task { async let kasa: Void = yukleyici.yenile(); async let bilgi: Void = sunucu.yenile(); _ = await (kasa, bilgi) }
        .refreshable { await yukleyici.yenile(); await sunucu.yenile() }
        .fileImporter(isPresented: $secici, allowedContentTypes: [.data], allowsMultipleSelection: false) { sonuc in
            do { if let yol = try sonuc.get().first { yukleyici.baslat(yol); hata = nil } }
            catch { hata = error.localizedDescription }
        }
        .confirmationDialog("Dosya sunucudan silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } })) {
            if let d = silinecek { Button("Dosyayı sil", role: .destructive) { Task { await yukleyici.sil(d) }; silinecek = nil } }
        } message: { Text("Çalışmalara bağlı dosyalar korunur. Diğer dosyalar için bu işlem geri alınamaz.") }
    }

    private func boyut(_ sayi: Int64) -> String { ByteCountFormatter.string(fromByteCount: sayi, countStyle: .binary) }
    private var arastirmaSiniri: Int64 { sunucu.yetenekler?.arastirmaKaynakSiniri ?? 200_000 }
}
