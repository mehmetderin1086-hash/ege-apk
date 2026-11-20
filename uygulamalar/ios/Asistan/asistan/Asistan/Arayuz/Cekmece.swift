import SwiftUI

/// Çekmeceden SohbetEkrani'na iletilen eylemler.
enum CekmeceEylemi { case yeni, herYerdeAra, ayarlar, kullanim, gelenKutusu, atolye, indirmeler, donustur, arsiv, uretkenlik, telefon, gorunum, kisisel, ajan, tetikleyiciler, projeler }

/// Sol kenardan açılan çekmece: gruplu aramalı sohbet geçmişi, katlanmış araçlar, ses modu, altta profil/kota/ayarlar.
struct CekmeceGorunumu: View {
    @Environment(Beyin.self) private var beyin
    @Environment(Ayarlar.self) private var ayarlar
    @Environment(SesOturumu.self) private var ses
    @Binding var acik: Bool
    var eylem: (CekmeceEylemi) -> Void

    @State private var sohbetler: [Sohbet] = []
    @State private var sorgu = ""
    @State private var araclarAcik = false
    @State private var adlandirilan: Sohbet?
    @State private var yeniAd = ""
    @State private var silinecek: Sohbet?
    @State private var secimModu = false
    @State private var seciliSohbetler: Set<UUID> = []
    @State private var topluSilOnayi = false
    @State private var tumSohbetleriSilOnayi = false
    /// Yanıt sürerken dokunulan sohbet: sessizce yok sayılmasın, durdurup açmak sorulsun.
    @State private var bekleyenSohbet: Sohbet?
    /// Sohbet özetleri `yenile()` içinde bir kez çıkarılır; her çizimde 300 sohbetin mesaj ilişkisi açılmaz.
    @State private var ogeler: [CekmeceGruplari.Oge] = []
    @State private var kimlikle: [UUID: Sohbet] = [:]
    /// Normalize edilmiş birleşik içerik (yalnız içerik aramasında, ilk aramada doldurulur).
    @State private var icerikOnbellek: [UUID: String] = [:]
    /// Aramayla eşleşen sohbetler; nil = arama yok (hepsi).
    @State private var eslesen: Set<UUID>?

    private var gruplar: [CekmeceGruplari.Grup] {
        CekmeceGruplari.grupla(eslesen.map { e in ogeler.filter { e.contains($0.id) } } ?? ogeler)
    }

    var body: some View {
        let gs = gruplar
        VStack(spacing: 0) {
            ust
            List {
                ForEach(gs, id: \.baslik) { g in
                    Section(g.baslik) {
                        ForEach(g.ogeler, id: \.id) { o in
                            if let s = kimlikle[o.id] { satir(s) }
                        }
                    }
                }
                if gs.isEmpty { Text(sorgu.isEmpty ? "Henüz sohbet yok." : "Eşleşen sohbet yok.").foregroundStyle(.secondary).listRowBackground(Color.clear) }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .confirmationDialog("Yanıt sürüyor", isPresented: Binding(get: { bekleyenSohbet != nil }, set: { if !$0 { bekleyenSohbet = nil } }), titleVisibility: .visible) {
                Button("Yanıtı durdur ve aç") {
                    if let s = bekleyenSohbet {
                        beyin.iptal()
                        beyin.sohbetiAc(s)
                        if beyin.sohbet?.kimlik == s.kimlik { acik = false }
                    }
                    bekleyenSohbet = nil
                }
                Button("Vazgeç", role: .cancel) { bekleyenSohbet = nil }
            } message: {
                Text("Bu sohbeti açmak için süren yanıt durdurulur. Bir komut çalışıyorsa bitmesini bekle.")
            }
            .task(id: sorgu) {
                guard !sorgu.isEmpty else { eslesen = nil; return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                aramayiUygula()
            }
            if secimModu {
                HStack {
                    Text("\(seciliSohbetler.count) seçildi").font(.callout).accessibilityIdentifier("cekmece-secim-sayisi")
                    Spacer()
                    Button("Bu listedekileri seç") {
                        let gorunen = eslesen.map { e in ogeler.filter { e.contains($0.id) } } ?? ogeler
                        seciliSohbetler = Set(gorunen.map(\.id))
                    }.accessibilityIdentifier("cekmece-gorunenleri-sec")
                    Button("Sil", systemImage: "trash", role: .destructive) { topluSilOnayi = true }
                        .disabled(seciliSohbetler.isEmpty).accessibilityIdentifier("cekmece-toplu-sil")
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
            Divider()
            sesModu.padding(.horizontal, 16).padding(.top, 8)
            alt
        }
        .background(.regularMaterial)
        .onAppear(perform: yenile)
        .onChange(of: acik) { _, yeni in
            if yeni { yenile() }
            else { sorgu = ""; secimModu = false; seciliSohbetler.removeAll() }
        }
        .alert("Sohbeti yeniden adlandır", isPresented: Binding(get: { adlandirilan != nil }, set: { if !$0 { adlandirilan = nil } })) {
            TextField("Başlık", text: $yeniAd)
            Button("Kaydet") { if let s = adlandirilan { beyin.depo.sohbetAdlandir(s, yeniAd); yenile() }; adlandirilan = nil }
            Button("Vazgeç", role: .cancel) { adlandirilan = nil }
        }
        .confirmationDialog(silmeBasligi, isPresented: Binding(get: { silinecek != nil || topluSilOnayi || tumSohbetleriSilOnayi }, set: { acik in
            if !acik { silinecek = nil; topluSilOnayi = false; tumSohbetleriSilOnayi = false }
        }), titleVisibility: .visible) {
            if let s = silinecek {
                Button("Sohbeti sil", role: .destructive) {
                    if beyin.sohbet?.kimlik == s.kimlik { beyin.yeniSohbet() }
                    beyin.depo.sohbetSil(s); silinecek = nil; yenile()
                }
            } else if topluSilOnayi {
                Button("\(seciliSohbetler.count) sohbeti sil", role: .destructive) { secilenleriSil() }
            } else if tumSohbetleriSilOnayi {
                Button("Tümünü sil", role: .destructive) { tumunuSil() }
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil; topluSilOnayi = false; tumSohbetleriSilOnayi = false }
        } message: {
            Text(silmeAciklamasi)
        }
    }

    private var ust: some View {
        VStack(spacing: 10) {
            HStack {
                if secimModu {
                    Button("Vazgeç", systemImage: "xmark") { secimModu = false; seciliSohbetler.removeAll() }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).accessibilityIdentifier("cekmece-secim-iptal")
                } else {
                    Button { eylem(.yeni); acik = false } label: {
                        Label("Yeni sohbet", systemImage: "square.and.pencil").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("cekmece-yeni")
                }
                Button {
                    secimModu = true
                    seciliSohbetler.removeAll()
                } label: {
                    Image(systemName: "checklist").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.accessibilityLabel("Sohbetleri seç").accessibilityIdentifier("cekmece-sohbet-sec").disabled(secimModu)
                araclar
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Sohbetlerde ara", text: $sorgu).autocorrectionDisabled().accessibilityIdentifier("cekmece-ara")
                if !sorgu.isEmpty { Button { sorgu = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Aramayı temizle") }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12))
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private func satir(_ s: Sohbet) -> some View {
        let aktif = beyin.sohbet?.kimlik == s.kimlik
        return Button {
            if secimModu {
                if !seciliSohbetler.insert(s.kimlik).inserted { seciliSohbetler.remove(s.kimlik) }
            } else if beyin.durum == .bosta { beyin.sohbetiAc(s); acik = false } else if !aktif { bekleyenSohbet = s } else { acik = false }
        } label: {
            HStack(spacing: 8) {
                if secimModu {
                    Image(systemName: seciliSohbetler.contains(s.kimlik) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(seciliSohbetler.contains(s.kimlik) ? Color.accentColor : Color.secondary)
                }
                if s.sabit { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                Text(s.baslik).lineLimit(1).font(.callout.weight(aktif ? .semibold : .regular))
                Spacer(minLength: 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(aktif ? Color.accentColor.opacity(0.12) : Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { silinecek = s } label: { Label("Sil", systemImage: "trash") }
            Button { adlandirilan = s; yeniAd = s.baslik } label: { Label("Ad", systemImage: "pencil") }.tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button { beyin.depo.sohbetSabitle(s, !s.sabit); yenile() } label: { Label(s.sabit ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: s.sabit ? "pin.slash" : "pin") }.tint(.orange)
        }
        .contextMenu {
            if secimModu {
                Button(seciliSohbetler.contains(s.kimlik) ? "Seçimden çıkar" : "Seç", systemImage: seciliSohbetler.contains(s.kimlik) ? "checkmark.circle" : "circle") {
                    if !seciliSohbetler.insert(s.kimlik).inserted { seciliSohbetler.remove(s.kimlik) }
                }
            }
            Button(s.sabit ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: s.sabit ? "pin.slash" : "pin") { beyin.depo.sohbetSabitle(s, !s.sabit); yenile() }
            Button("Yeniden adlandır", systemImage: "pencil") { adlandirilan = s; yeniAd = s.baslik }
            Button("Sil", systemImage: "trash", role: .destructive) { silinecek = s }
        }
        .accessibilityIdentifier("cekmece-sohbet")
        .accessibilityValue(secimModu ? (seciliSohbetler.contains(s.kimlik) ? "Seçili" : "Seçili değil") : "")
    }

    /// Araçlar: başlık satırındaki menü (liste uzunluğundan bağımsız, her zaman erişilir).
    private var araclar: some View {
        Menu {
            ForEach([("Her yerde ara", "magnifyingglass", CekmeceEylemi.herYerdeAra), ("Gelen Kutusu", "tray.full", .gelenKutusu), ("Atölye", "sparkles", .atolye), ("İndirmeler", "arrow.down.circle", .indirmeler),
                     ("Dosya dönüştür", "arrow.triangle.2.circlepath.doc.on.clipboard", .donustur), ("ZIP / RAR", "archivebox", .arsiv), ("Üretkenlik", "briefcase", .uretkenlik),
                     ("Telefon işlemleri", "square.grid.2x2", .telefon), ("Görünümü düzenle", "paintpalette", .gorunum), ("Kişisel alanım", "bookmark", .kisisel), ("Ajan merkezi", "brain", .ajan), ("Tetikleyiciler", "bolt.badge.clock", .tetikleyiciler), ("Projeler", "folder", .projeler)], id: \.0) { ad, simge, e in
                Button { eylem(e); acik = false } label: { Label(ad, systemImage: simge) }
            }
            Divider()
            Button("Sohbetleri seç", systemImage: "checklist") {
                secimModu = true; seciliSohbetler.removeAll()
            }
            Button("Tüm sohbetleri sil", systemImage: "trash", role: .destructive) { tumSohbetleriSilOnayi = true }
        } label: {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Araçlar").accessibilityIdentifier("cekmece-araclar")
    }

    private var sesModu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Konuşma modu", selection: Binding(get: { ses.mod }, set: { yeni in Task { await ses.modSec(yeni) } })) {
                ForEach(SesOturumu.Mod.allCases) { mod in Text(mod.rawValue).tag(mod) }
            }.pickerStyle(.segmented).disabled(ses.gecisVar).accessibilityIdentifier("ses-modu")
        }.padding(.vertical, 6)
    }

    private var alt: some View {
        VStack(spacing: 6) {
            Button { eylem(.kullanim); acik = false } label: {
                HStack(spacing: 6) {
                    Image(systemName: beyin.kotaUyarisi == nil ? "gauge.with.dots.needle.33percent" : "exclamationmark.triangle.fill")
                        .foregroundStyle(beyin.kotaUyarisi == nil ? Color.secondary : Color.orange)
                    Text(beyin.kotaUyarisi ?? "Bugün \(KullanimDefteri.ortak.kayit().aileler.values.reduce(0) { $0 + $1.istek }) model isteği")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }.frame(minHeight: 36)
            }.buttonStyle(.plain).accessibilityIdentifier("cekmece-kota")
            Button { eylem(.ayarlar); acik = false } label: {
                HStack(spacing: 12) {
                    Text(String(ayarlar.gorunenAd.prefix(1))).font(.headline).foregroundStyle(.white).frame(width: 40, height: 40).background(ayarlar.gorunum.vurgu, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ayarlar.gorunenAd).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(beyin.aktifModel.map(Beyin.modelEtiketi) ?? (ayarlar.otomatikModel ? "Otomatik model" : Beyin.modelEtiketi(ayarlar.modelKimligi))).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    // P2.4: kurulumda eksik adım varsa Ayarlar'a giden satırda turuncu hap.
                    if KurulumDurumu.ortak.eksik > 0 {
                        Text("\(KurulumDurumu.ortak.eksik) eksik").font(.caption2.bold()).foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .accessibilityIdentifier("kurulum-hapi")
                    }
                    Image(systemName: "gearshape").font(.title3).foregroundStyle(.secondary)
                }.frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel(KurulumDurumu.ortak.eksik > 0 ? "Ayarlar, \(KurulumDurumu.ortak.eksik) kurulum adımı eksik" : "Ayarlar")
            .accessibilityIdentifier("cekmece-ayarlar")
            .task { await KurulumDurumu.ortak.yenile() }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func yenile() {
        sohbetler = beyin.depo.sonSohbetler(300)
        let dolu = sohbetler.filter { !$0.mesajlar.isEmpty }
        ogeler = dolu.map { .init(id: $0.kimlik, baslik: $0.baslik, son: HafizaDeposu.sonZaman($0), sabit: $0.sabit) }
        kimlikle = Dictionary(dolu.map { ($0.kimlik, $0) }, uniquingKeysWith: { a, _ in a })
        icerikOnbellek = [:]
        if !sorgu.isEmpty { aramayiUygula() }
    }

    private func secilenleriSil() {
        sil(sohbetler.filter { seciliSohbetler.contains($0.kimlik) })
    }

    private func tumunuSil() {
        sil(beyin.depo.tumSohbetler())
    }

    private var silmeBasligi: String {
        if silinecek != nil { "Bu sohbet silinsin mi?" }
        else if topluSilOnayi { "Seçilen sohbetler silinsin mi?" }
        else { "Tüm sohbetler silinsin mi?" }
    }

    private var silmeAciklamasi: String {
        if silinecek != nil { return "Sohbet ve mesajları kalıcı olarak silinir. Bu işlem geri alınamaz." }
        if topluSilOnayi { return "Seçilen sohbetler ve mesajları kalıcı olarak silinir. Açık sohbet seçildiyse mevcut yanıt durur. Bu işlem geri alınamaz." }
        return "Cihazdaki tüm sohbetler ve mesajları, çekmecede görünmeyen boş taslaklar dahil kalıcı olarak silinir. Açık sohbet varsa mevcut yanıt durur. Bu işlem geri alınamaz."
    }

    private func sil(_ hedefler: [Sohbet]) {
        guard !hedefler.isEmpty else { return }
        if let aktif = beyin.sohbet, hedefler.contains(where: { $0.kimlik == aktif.kimlik }) { beyin.yeniSohbet() }
        let adet = beyin.depo.sohbetleriSil(hedefler)
        seciliSohbetler.removeAll(); secimModu = false; yenile()
        if adet == 0 { TostDefteri.ortak.goster("Sohbetler silinemedi. Yeniden dene.", simge: "exclamationmark.triangle") }
        else { TostDefteri.ortak.goster("\(adet) sohbet silindi", simge: "trash") }
    }

    /// İçerik araması: normalize edilmiş birleşik metin sohbet başına bir kez üretilir (SwiftData modelleri Sendable değil; ana aktörde).
    private func aramayiUygula() {
        guard !sorgu.isEmpty else { eslesen = nil; return }
        if icerikOnbellek.isEmpty {
            var yeni: [UUID: String] = [:]
            for o in ogeler { if let s = kimlikle[o.id] { yeni[o.id] = GecmisArama.normalize(s.mesajlar.map(\.metin).joined(separator: " ")) } }
            icerikOnbellek = yeni
        }
        eslesen = Self.eslesenler(ogeler, icerik: icerikOnbellek, sorgu: sorgu)
    }

    /// Başlıkta ya da (önceden normalize edilmiş) içerikte geçen sohbetler; Türkçe harf/büyüklük duyarsız (`CekmeceGruplari.eslesir` ile aynı kural).
    nonisolated static func eslesenler(_ ogeler: [CekmeceGruplari.Oge], icerik: [UUID: String], sorgu: String) -> Set<UUID> {
        let q = GecmisArama.normalize(sorgu).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Set(ogeler.map(\.id)) }
        return Set(ogeler.filter { GecmisArama.normalize($0.baslik).contains(q) || (icerik[$0.id]?.contains(q) ?? false) }.map(\.id))
    }
}
