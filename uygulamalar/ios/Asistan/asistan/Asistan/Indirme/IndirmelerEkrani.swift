import SwiftUI
import QuickLook

struct IndirmelerEkrani: View {
    @State private var adres = ""
    @State private var tur = "file"
    @State private var ekleniyor = false
    @State private var onizleme: URL?
    @Environment(\.dismiss) private var kapat
    private let yonetici = IndirmeYoneticisi.ortak
    var body: some View {
        NavigationStack {
            List {
                Section("Yeni indirme") {
                    TextField("https://… bağlantısını yapıştır", text: $adres).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("indirme-adres")
                    Button {
                        do { yonetici.kazimaSayfasi = KazimaSayfasi(url: try IndirmeYoneticisi.dogrula(adres)) }
                        catch { yonetici.hata = error.localizedDescription }
                    } label: { Label("Bu web sayfasından veri çıkar", systemImage: "doc.text.magnifyingglass") }
                    .disabled(adres.isEmpty)
                    .accessibilityIdentifier("web-kazima-ac")
                    Picker("İndirme türü", selection: $tur) {
                        Text("Dosya").tag("file"); Text("Video").tag("video"); Text("Ses").tag("audio")
                    }.pickerStyle(.segmented)
                    Button(ekleniyor ? "Ekleniyor…" : "İndir") {
                        ekleniyor = true
                        Task {
                            defer { ekleniyor = false }
                            do {
                                let url = try IndirmeYoneticisi.dogrula(adres)
                                // YouTube ve benzeri sayfalar gömülü motorla iner; Kepçe/medya bulucu yalnız başarısız kayıtta yedek.
                                if tur != "file" && !IndirmeYoneticisi.dogrudanMedya(url) { _ = try yonetici.motorluEkle(adres, tur: tur); adres = "" }
                                else { _ = try await yonetici.ekle(adres, tur: tur); adres = "" }
                            }
                            catch { yonetici.hata = error.localizedDescription }
                        }
                    }.disabled(ekleniyor || adres.isEmpty).accessibilityIdentifier("indirme-baslat")
                    Text(tur == "file" ? "Doğrudan dosya bağlantısı iPhone’a indirilir. Dosya başına en fazla 1 GB." : "YouTube ve benzeri sayfalar iPhone’daki gömülü Kepçe motoruyla MP4/M4A olarak iner; sunucu kullanılmaz. Uygulama kapanırsa indirme yarım kalır. Olmazsa kayıttan Kepçe’ye aktarabilir ya da medya bulucuyu açabilirsin.").font(.footnote).foregroundStyle(.secondary)
                }
                if KepceBaglantisi.kurulu {
                    Section("Kepçe bağlantısı") {
                        Label("iPhone üzerinde hazır", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Kepçe indirmelerini aç") { KepceBaglantisi.ac() }
                        Text("Aktarıldı bilgisi indirme tamamlandı anlamına gelmez. Durumu ve indirilen dosyaları Kepçe’den takip et.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let hata = yonetici.hata { Text(hata).foregroundStyle(.red).font(.footnote) }
                let g = Self.gruplar(yonetici.kayitlar)
                Section("İndirmeler · \(g.indirmeler.count)") {
                    if g.indirmeler.isEmpty && g.arsiv.isEmpty { ContentUnavailableView("Henüz indirme yok", systemImage: "arrow.down.circle", description: Text("Bir bağlantı ekle veya asistana ‘Bu bağlantıyı indir’ de.")) }
                    else if g.indirmeler.isEmpty { Text("Bağlantıdan indirilen dosya yok.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(g.indirmeler) { k in satir(k) }
                }
                if !g.arsiv.isEmpty {
                    Section("Arşivden çıkanlar · \(g.arsiv.count)") {
                        ForEach(g.arsiv) { k in satir(k) }
                    }
                }
                Section {
                    Text("Site desteği değişebilir. Giriş isteyen, korumalı veya canlı içerikler indirilemeyebilir. Oynatma listesi yerine tek içerik bağlantısı ekle. Uygulamayı zorla kapatmak iOS indirmelerini durdurabilir.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("İndirmeler")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
            .quickLookPreview($onizleme)
            .sheet(item: Binding(get: { yonetici.medyaSayfasi }, set: { yonetici.medyaSayfasi = $0 })) { MedyaTarayiciEkrani(sayfa: $0) }
            .sheet(item: Binding(get: { yonetici.kazimaSayfasi }, set: { yonetici.kazimaSayfasi = $0 })) { WebKazimaEkrani(sayfa: $0) }
            .task { yonetici.baslat() }
        }
    }
    /// Kayıtları bağlantıdan inenler ve arşivden çıkanlar diye ayırır; her grupta özgün sıra korunur.
    /// Eski kayıtlar (tür 'file') göç edilmez: adresten kaynağı anlaşılamaz, İndirmeler'de kalır.
    static func gruplar(_ l: [IndirmeKaydi]) -> (indirmeler: [IndirmeKaydi], arsiv: [IndirmeKaydi]) {
        (l.filter { $0.tur != IndirmeYoneticisi.arsivTuru }, l.filter { $0.tur == IndirmeYoneticisi.arsivTuru })
    }
    @ViewBuilder private func satir(_ k: IndirmeKaydi) -> some View {
        // Düğme stili satırın VStack'inde: satıra dokunmak "İptal et" gibi davranmasın.
        VStack(alignment: .leading, spacing: 8) {
            Label(k.ad, systemImage: k.tur == IndirmeYoneticisi.arsivTuru ? "archivebox" : k.tur == "audio" ? "music.note" : k.tur == "video" ? "film" : "doc").font(.headline).lineLimit(2)
            Text(k.durumMetni).font(.caption).foregroundStyle(.secondary)
            if k.etkin {
                if k.toplam > 0 { ProgressView(value: min(Double(k.alinan) / Double(k.toplam), 1)) } else { ProgressView() }
                Text(ByteCountFormatter.string(fromByteCount: k.alinan, countStyle: .file) + (k.toplam > 0 ? " / " + ByteCountFormatter.string(fromByteCount: k.toplam, countStyle: .file) : "")).font(.caption)
                Button("İptal et", role: .cancel) { Task { await yonetici.iptal(k.id) } }
            }
            if let hata = k.hata, !hata.isEmpty { Text(hata).font(.caption).foregroundStyle(.red) }
            HStack {
                if let u = yonetici.dosyaURL(k) {
                    Button("Aç") { onizleme = u }
                    Spacer()
                    ShareLink(item: u) { Label("Kaydet / paylaş", systemImage: "square.and.arrow.up") }
                } else if k.durum == "external" { Button("Kepçe’de takip et") { KepceBaglantisi.ac() } } else if !k.etkin && !k.yerel {
                    // Dosyası silinmiş yerel kayıtta (iPhone'da üretilen/arşivden çıkan) yalnız 'Sil' kalır.
                    Button("Yeniden dene") { Task { await yonetici.tekrar(k) } }
                    // Gömülü motor başaramazsa yedek: Kepçe uygulaması ya da sayfada medya arama.
                    if k.motor == true, k.durum == "failed", let u = URL(string: k.adres) {
                        Spacer()
                        if KepceBaglantisi.kurulu {
                            Button("Kepçe’de dene") { Task { do { try await yonetici.kepceyeAktar(k.adres, tur: k.tur) } catch { yonetici.hata = error.localizedDescription } } }
                        } else {
                            Button("Medya bulucuda aç") { yonetici.medyaSayfasi = MedyaSayfasi(url: u, tur: k.tur) }
                        }
                    }
                }
            }
        }.buttonStyle(.borderless).padding(.vertical, 5)
        .swipeActions { if !k.etkin { Button("Sil", role: .destructive) { yonetici.sil(k) } } }
    }
}
