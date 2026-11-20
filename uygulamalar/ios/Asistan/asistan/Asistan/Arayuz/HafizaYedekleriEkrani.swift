import SwiftUI

extension HafizaDeposu.AcilisDurumu {
    /// Açılış şeridinin metni; `.normal` için nil.
    var seritMetni: String? {
        switch self {
        case .normal: return nil
        case .kurtarildi: return "Hafıza dosyası bozuktu; kenara alındı ve boş hafıza açıldı. Yedekten geri yükleyebilirsin."
        case .bellekte(let hata): return "Hafıza açılamadı; bu oturumdaki konuşmalar kaydedilmeyecek. \(hata)."
        case .geriYuklendi: return "Hafıza yedekten geri yüklendi."
        }
    }

    /// Bilgi niteliğindeki durumlar kapatılabilir; kaydedilmeyen oturum uyarısı kapatılamaz.
    var kapatilabilir: Bool {
        switch self {
        case .bellekte: return false
        default: return true
        }
    }
}

/// Hafıza → "Yedekler ve kurtarma": günlük yedekler, kurtarma kopyaları, geri yükleme isteği.
/// Geri yükleme çalışan uygulamada yapılamaz (kap değişmez): istek yazılır, bir sonraki açılışta uygulanır.
/// Dosya işleri `Task.detached(priority: .utility)` ile ana iş parçacığı dışında; sonuç ana aktörde gösterilir.
struct HafizaYedekleriEkrani: View {
    @Environment(\.colorScheme) private var sema
    @State private var yedekler: [HafizaKurtarma.Yedek] = []
    @State private var kopyalar: [HafizaKurtarma.KurtarmaKopyasi] = []
    @State private var bekleyen: HafizaKurtarma.Isaret?
    @State private var calisiyor = false
    @State private var mesaj: String?
    @State private var geriYuklenecek: URL?
    @State private var silinecek: HafizaKurtarma.KurtarmaKopyasi?
    private var depo: URL? { HafizaDeposu.depoURL }
    private var durum: HafizaDeposu.AcilisDurumu { HafizaAcilisSeridi.gorunenDurum }

    var body: some View {
        List {
            Section("Bu açılış") {
                Label(durum.seritMetni ?? "Hafıza sorunsuz açıldı.", systemImage: durum == .normal ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(durum == .normal ? Color.secondary : UyariRengi.renk(sema == .dark))
                    .font(.callout)
                if let bekleyen {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Geri yükleme bekliyor").font(.callout.weight(.semibold))
                        Text("\(kaynakAdi(bekleyen.kaynak)) · uygulamayı kapatıp yeniden aç.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Geri yükleme isteğini iptal et", role: .destructive) { istegiIptalEt() }
                }
            }
            Section {
                if yedekler.isEmpty { Text("Henüz yedek yok. Asistan günde bir kez kendiliğinden yedek alır.").foregroundStyle(.secondary) }
                ForEach(yedekler) { y in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(y.tarih.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(Int64(y.boyut).formatted(.byteCount(style: .file))).foregroundStyle(.secondary).font(.caption)
                        }
                        Button("Bu yedekten geri yükle") { geriYuklenecek = y.url }.font(.caption).buttonStyle(.borderless)
                    }
                }
                Button { simdiYedekle() } label: { Label("Şimdi yedekle", systemImage: "externaldrive.badge.plus") }
                    .disabled(depo == nil || calisiyor)
                    .accessibilityIdentifier("hafiza-simdi-yedekle")
            } header: {
                Text("Günlük yedekler (son 7)")
            } footer: {
                Text("Yedekler yalnız bu telefonda durur; iCloud ya da bilgisayar yedeğine girmez.")
            }
            Section {
                if kopyalar.isEmpty { Text("Kurtarma kopyası yok.").foregroundStyle(.secondary) }
                ForEach(kopyalar) { k in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(k.tarih.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(Int64(k.boyut).formatted(.byteCount(style: .file))).foregroundStyle(.secondary).font(.caption)
                        }
                        Text(Self.nedenMetni(k.neden)).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            if k.depoVar { Button("Bu kopyayı geri yükle") { geriYuklenecek = k.url.appending(path: depo?.lastPathComponent ?? "Asistan.store") } }
                            Button("Kurtarma klasörünü sil", role: .destructive) { silinecek = k }
                        }
                        .font(.caption).buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Kurtarma kopyaları")
            } footer: {
                Text("Açılamayan hafıza silinmez; buraya taşınır ya da kopyalanır.")
            }
            if let mesaj { Text(mesaj).font(.footnote).foregroundStyle(.secondary) }
            if depo == nil { Text("Hafıza dosyası bu oturumda kullanılmıyor (bellek içi).").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Yedekler ve kurtarma")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if calisiyor { ProgressView() } }
        .task { await yenile() }
        .confirmationDialog("Geri yüklensin mi?", isPresented: Binding(get: { geriYuklenecek != nil }, set: { if !$0 { geriYuklenecek = nil } }), titleVisibility: .visible) {
            Button("Geri yükle", role: .destructive) { if let u = geriYuklenecek { geriYukle(u) } }
            Button("Vazgeç", role: .cancel) { geriYuklenecek = nil }
        } message: {
            Text("Şu anki hafıza Kurtarma klasörüne taşınır; yedek bir sonraki açılışta yüklenir. Uygulamayı kapatıp yeniden aç.")
        }
        .confirmationDialog("Kurtarma klasörü silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let k = silinecek { sil(k) } }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        } message: {
            Text("Bu kopya kalıcı olarak silinir.")
        }
    }

    static func nedenMetni(_ neden: String) -> String {
        switch neden {
        case "bozuk": return "Bozuk hafıza dosyası (taşındı)"
        case "sema-uyumsuz": return "Şeması açılamayan hafıza (kopya)"
        case "geri-yukleme-oncesi": return "Geri yüklemeden önceki hafıza"
        default: return "Açılamayan hafıza (kopya)"
        }
    }

    private func kaynakAdi(_ goreli: String) -> String {
        let parcalar = goreli.split(separator: "/")
        if parcalar.first == "Kurtarma", parcalar.count > 1 { return "Kurtarma kopyası \(parcalar[1])" }
        return String(parcalar.last ?? "")
    }

    private func yenile() async {
        guard let depo else { return }
        let sonuc = await Task.detached(priority: .utility) {
            (HafizaKurtarma.yedekler(klasor: HafizaKurtarma.yedekKlasoru(depo)),
             HafizaKurtarma.kurtarmaKopyalari(store: depo),
             HafizaKurtarma.bekleyenIstek(store: depo))
        }.value
        yedekler = sonuc.0; kopyalar = sonuc.1; bekleyen = sonuc.2
    }

    private func simdiYedekle() {
        guard let depo, !calisiyor else { return }
        calisiyor = true
        Task {
            let url = await Task.detached(priority: .utility) {
                HafizaKurtarma.gunlukYedek(store: depo, klasor: HafizaKurtarma.yedekKlasoru(depo), zorla: true)
            }.value
            mesaj = url == nil ? "Yedek alınamadı (yer yetersiz olabilir)." : "Yedek alındı."
            await yenile()
            calisiyor = false
        }
    }

    private func geriYukle(_ kaynak: URL) {
        geriYuklenecek = nil
        guard let depo else { return }
        Task {
            let hata = await Task.detached(priority: .utility) { () -> String? in
                do { try HafizaKurtarma.geriYuklemeIste(kaynak, store: depo); return nil }
                catch { return error.localizedDescription }
            }.value
            mesaj = hata ?? "Geri yükleme hazır: uygulamayı kapatıp yeniden aç."
            await yenile()
        }
    }

    private func istegiIptalEt() {
        guard let depo else { return }
        Task {
            await Task.detached(priority: .utility) { HafizaKurtarma.geriYuklemeIptal(store: depo) }.value
            mesaj = "Geri yükleme isteği iptal edildi."
            await yenile()
        }
    }

    private func sil(_ k: HafizaKurtarma.KurtarmaKopyasi) {
        silinecek = nil
        guard let depo else { return }
        let klasor = k.url
        Task {
            let hata = await Task.detached(priority: .utility) { () -> String? in
                do { try HafizaKurtarma.kurtarmaSil(klasor, store: depo); return nil }
                catch { return error.localizedDescription }
            }.value
            mesaj = hata ?? "Kurtarma klasörü silindi."
            await yenile()
        }
    }
}

/// Hafıza normal açılmadıysa sohbet ekranının üstünde turuncu şerit; dokununca yedekler ekranı açılır.
/// Kimlik `hafiza-kurtarma-seridi`; önizleme bayrağı `--hafiza-kurtarma-ornek` (DEBUG) şeridi örnek durumla gösterir.
struct HafizaAcilisSeridi: View {
    @Environment(\.colorScheme) private var sema
    @State private var kapatildi = false
    @State private var ekranAcik = false

    static var gorunenDurum: HafizaDeposu.AcilisDurumu {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--hafiza-kurtarma-ornek") { return .bellekte(hata: "Örnek durum") }
        #endif
        return HafizaDeposu.acilisDurumu
    }

    var body: some View {
        let durum = Self.gorunenDurum
        if let metin = durum.seritMetni, !kapatildi {
            let renk = UyariRengi.renk(sema == .dark)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                Text(metin).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                if durum.kapatilabilir {
                    Button { kapatildi = true } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Şeridi kapat")
                }
            }
            .foregroundStyle(renk)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background { ZStack { Rectangle().fill(.bar); renk.opacity(0.14) } }
            .contentShape(Rectangle())
            .onTapGesture { ekranAcik = true }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Yedekler ve kurtarma ekranını açar")
            .accessibilityIdentifier("hafiza-kurtarma-seridi")
            .sheet(isPresented: $ekranAcik) {
                NavigationStack {
                    HafizaYedekleriEkrani()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { ekranAcik = false } } }
                }
            }
        }
    }
}
