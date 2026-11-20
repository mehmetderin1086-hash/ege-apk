#if DEBUG
import SwiftUI

/// P3.10-arıza: Ayarlar → Geliştirici → "Arıza modu ve sınamalar" ekranının görünüm durumu.
/// Tekil: Ayarlar'daki bölüm başlığı "arıza açık" uyarısını buradan okur (Observation ile kendiliğinden yenilenir).
@MainActor @Observable
final class SinamaDurumu {
    static let ortak = SinamaDurumu()

    private(set) var kayitlar: [ArizaTuru: ArizaDeposu.Kayit] = [:]
    /// Tür başına seçili tekrar: 1, 3 ya da −1 (sınırsız). Anahtar açılırken uygulanır.
    var tekrarlar: [ArizaTuru: Int] = [:]
    private(set) var sinamalar: [SinamaKaydi] = []
    var ileti: String?

    var herhangiAcik: Bool { !kayitlar.isEmpty }

    func tekrar(_ t: ArizaTuru) -> Int { tekrarlar[t] ?? 1 }

    func acikMi(_ t: ArizaTuru) -> Bool { kayitlar[t] != nil }

    /// Anahtarların süresi geçmişse burada düşer (depo okurken temizler).
    func anahtarlariYenile() { kayitlar = ArizaAnahtarlari.gecerli.kayitlar() }

    func ayarla(_ t: ArizaTuru, acik: Bool) {
        if acik {
            ArizaAnahtarlari.ac(t, tekrar: tekrar(t))
            TaniGunlugu.yaz("ARIZA AÇIK: \(t.rawValue) tekrar=\(tekrar(t))")
            if t.modelArizasi { gecisiBaslat() }
        } else {
            ArizaAnahtarlari.kapat(t)
            TaniGunlugu.yaz("ARIZA KAPALI: \(t.rawValue)")
        }
        anahtarlariYenile()
    }

    func hepsiniKapat() {
        ArizaAnahtarlari.hepsiniKapat()
        TaniGunlugu.yaz("ARIZA: hepsi kapatıldı")
        anahtarlariYenile()
        ileti = "Bütün arıza anahtarları kapatıldı."
    }

    /// Geçiş sunucusu `TelefonProxy.taban` eşzamanlı okunduğu için önceden kurulur; hazır olana dek trafik gerçek tabana gider.
    private func gecisiBaslat() {
        guard SahteModelSunucusu.gecis.tabanURL == nil else { return }
        let hedef = TelefonProxy.ortak.gercekTaban
        Task {
            do {
                let url = try await SahteModelSunucusu.gecis.baslatGecis(hedef: hedef)
                TaniGunlugu.yaz("ARIZA: geçiş sunucusu hazır \(url.absoluteString)")
            } catch {
                ileti = "Geçiş sunucusu başlatılamadı: \(error.localizedDescription)"
            }
        }
    }

    /// Tek seferlik eylem: iOS'un soketi kapatmasını taklit eder; 15 sn'lik bekçi toparlamalı (tani.log'da "BEKÇİ" satırı).
    func yerelSunucuyuOldur() {
        TelefonProxy.ortak.sunucuyuOldurTest()
        TaniGunlugu.yaz("ARIZA: yerel sunucu öldürüldü; bekçinin toparlaması bekleniyor")
        ileti = "Yerel sunucu durduruldu. Bekçi 15 sn içinde yeniden kurmalı (tani.log: BEKÇİ)."
    }

    func sinamalariYenile() async {
        sinamalar = await Task.detached(priority: .utility) { () -> [SinamaKaydi] in
            SinamaKaydi.iceAktar()
            return SinamaKaydi.oku()
        }.value
    }

    func sinamalariSil() {
        SinamaKaydi.temizle()
        sinamalar = []
    }
}

struct SinamaEkrani: View {
    private let durum = SinamaDurumu.ortak
    @State private var oldurOnayi = false

    var body: some View {
        Form {
            Section {
                ForEach(ArizaTuru.allCases.filter { !$0.eylem }, id: \.self) { t in
                    arizaSatiri(t)
                }
                Button(role: .destructive) { oldurOnayi = true } label: {
                    Label(ArizaTuru.yerelSunucuOlu.ad, systemImage: "bolt.horizontal.circle")
                }
                .accessibilityIdentifier("ariza-\(ArizaTuru.yerelSunucuOlu.rawValue)")
                Button("Hepsini kapat") { durum.hepsiniKapat() }
                    .disabled(!durum.herhangiAcik)
                    .accessibilityIdentifier("ariza-hepsini-kapat")
                if let ileti = durum.ileti {
                    Text(ileti).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Arıza modu")
            } footer: {
                Text("Yalnız Debug kurulumda vardır. Anahtarlar 30 dk sonra kendiliğinden kapanır. Model arızaları istekleri yerel geçiş sunucusundan geçirir; ayrıntı tani.log'da (ARIZA satırları).")
            }

            Section {
                LabeledContent("Kayıt", value: "\(durum.sinamalar.count)")
                    .accessibilityIdentifier("sinama-kayitlari")
                ForEach(Array(durum.sinamalar.reversed().enumerated()), id: \.element.id) { sira, k in
                    NavigationLink { HamRaporGorunumu(ad: k.ad) } label: { sinamaSatiri(k) }
                        .accessibilityIdentifier("sinama-satiri-\(sira)")
                }
                if !durum.sinamalar.isEmpty {
                    Button("Kayıtları sil", role: .destructive) { durum.sinamalariSil() }
                }
            } header: {
                Text("Sınama kayıtları")
            } footer: {
                Text("Documents/asistan-*.json raporlarından derlenir (Documents/sinama-kayitlari.jsonl, en çok 500 satır).")
            }
        }
        .navigationTitle("Arıza modu")
        .confirmationDialog("Yerel sunucu durdurulsun mu?", isPresented: $oldurOnayi, titleVisibility: .visible) {
            Button("Durdur", role: .destructive) { durum.yerelSunucuyuOldur() }
        } message: {
            Text("iOS'un soketi kapatmasını taklit eder; bekçinin toparlaması izlenir.")
        }
        .onAppear { durum.anahtarlariYenile() }
        .task { await durum.sinamalariYenile() }
        .refreshable { durum.anahtarlariYenile(); await durum.sinamalariYenile() }
    }

    @ViewBuilder
    private func arizaSatiri(_ t: ArizaTuru) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(t.ad, isOn: Binding(get: { durum.acikMi(t) }, set: { durum.ayarla(t, acik: $0) }))
                .accessibilityIdentifier("ariza-\(t.rawValue)")
            HStack {
                Picker("Tekrar", selection: Binding(get: { durum.tekrar(t) }, set: { durum.tekrarlar[t] = $0 })) {
                    Text("1").tag(1)
                    Text("3").tag(3)
                    Text("Sınırsız").tag(ArizaDeposu.sinirsiz)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .disabled(durum.acikMi(t))
                .accessibilityIdentifier("ariza-tekrar-\(t.rawValue)")
                Spacer()
                if let k = durum.kayitlar[t] {
                    Text(kalanMetni(k)).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func kalanMetni(_ k: ArizaDeposu.Kayit) -> String {
        let kalan = k.kalan < 0 ? "sınırsız" : "\(k.kalan) kez"
        return "\(kalan) · \(k.bitis.formatted(date: .omitted, time: .shortened))'e dek"
    }

    private func sinamaSatiri(_ k: SinamaKaydi) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: k.basarili ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(k.basarili ? .green : .red)
                .accessibilityLabel(k.basarili ? "başarılı" : "başarısız")
            VStack(alignment: .leading, spacing: 2) {
                Text(k.ad).font(.body.monospaced())
                Text("\(k.zaman.formatted(date: .abbreviated, time: .shortened)) · \(k.surum)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(k.ozet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let s = k.sureSn {
                Text(String(format: "%.1f sn", s)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// Documents/asistan-<ad>.json ham hâli.
private struct HamRaporGorunumu: View {
    let ad: String
    @State private var metin: String?

    var body: some View {
        ScrollView {
            Text(metin ?? "Rapor dosyası bulunamadı (asistan-\(ad).json).")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let a = ad
            metin = await Task.detached(priority: .utility) { SinamaKaydi.hamRapor(ad: a) }.value
        }
    }
}

/// Ayarlar'ın sonundaki "Geliştirici" bölümü; herhangi bir arıza açıkken başlıkta turuncu uyarı gösterir.
struct GelistiriciBolumu: View {
    private let durum = SinamaDurumu.ortak

    var body: some View {
        Section {
            NavigationLink { SinamaEkrani() } label: {
                Label("Arıza modu ve sınamalar", systemImage: "ant")
            }
            .accessibilityIdentifier("gelistirici-ariza-modu")
        } header: {
            HStack {
                Text("Geliştirici")
                if durum.herhangiAcik {
                    Text("arıza açık").foregroundStyle(.orange).accessibilityIdentifier("ariza-acik-uyarisi")
                }
            }
        }
        .onAppear { durum.anahtarlariYenile() }
    }
}
#endif
