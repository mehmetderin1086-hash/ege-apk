import SwiftUI

/// "Her yerde ara": Tuval, sohbetler, hafıza, indirilen dosyalar ve sunucu görevlerinde tek kutudan arama.
/// Puanlama ve vurgu `BirlesikArama`'da (saf); burada yalnız kaynaklar toplanır ve sonuç satırı açılır.
struct HerYerdeAraEkrani: View {
    @Environment(Beyin.self) private var beyin
    @Environment(\.dismiss) private var kapat
    @State private var sorgu = ""
    @State private var cikti = AramaCikti()
    @State private var turler: Set<AramaTuru> = []
    @State private var dosyaOnizleme: URL?
    @State private var aramaYapildi = false
    /// Ekran açılınca bir kez kurulur; her sorguda yalnız bu dizinde (arka planda) aranır.
    @State private var dizin: AramaDizini?
    @State private var atlanan: [AramaTuru] = []
    @AppStorage("herYerdeAra.son.v1") private var sonAramaVerisi = ""

    var body: some View {
        NavigationStack {
            List {
                suzgecler
                if sorgu.trimmingCharacters(in: .whitespaces).isEmpty {
                    sonAramalar
                } else if aramaYapildi && cikti.sonuclar.isEmpty {
                    ContentUnavailableView.search(text: sorgu)
                } else {
                    ForEach(AramaTuru.allCases) { tur in
                        let grup = cikti.sonuclar.filter { $0.oge.tur == tur }
                        if !grup.isEmpty {
                            Section("\(tur.etiket) · \(grup.count)") { ForEach(grup) { satir($0) } }
                        }
                    }
                    if !cikti.atlanan.isEmpty {
                        Text("Aranamadı: " + cikti.atlanan.map(\.etiket).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Her yerde ara")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $sorgu, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tuval, sohbet, hafıza, dosya…")
            .onSubmit(of: .search) { sonAramaVerisi = SonAramalar.ekle(sorgu, sonAramaListesi).joined(separator: "\n") }
            .task { await dizinKur() }
            .task(id: "\(sorgu)|\(turler.map(\.rawValue).sorted())|\(dizin != nil)") { await ara() }
            .quickLookPreview($dosyaOnizleme)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .accessibilityIdentifier("her-yerde-ara")
        }
    }

    private var sonAramaListesi: [String] { sonAramaVerisi.split(separator: "\n").map(String.init) }

    private var suzgecler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AramaTuru.allCases) { tur in
                    let secili = turler.contains(tur)
                    Button { if secili { turler.remove(tur) } else { turler.insert(tur) } } label: {
                        Label(tur.etiket, systemImage: tur.simge).font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(secili ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("arama-suzgec-\(tur.rawValue)")
                }
            }
        }.listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    @ViewBuilder private var sonAramalar: some View {
        if !sonAramaListesi.isEmpty {
            Section("Son aramalar") {
                ForEach(sonAramaListesi, id: \.self) { s in Button(s) { sorgu = s } }
                Button("Temizle", role: .destructive) { sonAramaVerisi = "" }
            }
        }
    }

    @ViewBuilder private func satir(_ s: AramaSonucu) -> some View {
        let icerik = VStack(alignment: .leading, spacing: 3) {
            Text(Self.vurgulu(s.oge.baslik, s.baslikVurgulari)).font(.body.weight(.medium)).lineLimit(2)
            if !s.ozet.isEmpty { Text(Self.vurgulu(s.ozet, s.ozetVurgulari)).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
            if let t = s.oge.tarih { Text(t, format: .dateTime.day().month().year()).font(.caption2).foregroundStyle(.tertiary) }
        }
        switch s.oge.hedef {
        case .tuval(let id): NavigationLink { TuvalDuzenleyici(kimlik: id) } label: { icerik }.accessibilityIdentifier("arama-sonuc")
        case .hafiza: NavigationLink { HafizaEkrani() } label: { icerik }.accessibilityIdentifier("arama-sonuc")
        case .gorev: NavigationLink { CalismaMerkezi() } label: { icerik }.accessibilityIdentifier("arama-sonuc")
        case .sohbet(let id):
            Button {
                // Yanıt akarken sohbet değiştirilemez (sohbetiAc yok sayar): sayfa kapanıp hiçbir şey olmamış gibi görünmesin.
                guard beyin.durum == .bosta else { TostDefteri.ortak.goster("Asistan yanıtını bitirince açabilirsin", simge: "hourglass"); return }
                if let sohbet = beyin.depo.tumSohbetler().first(where: { $0.kimlik == id }) { beyin.sohbetiAc(sohbet); kapat() }
            } label: { icerik }.buttonStyle(.plain).accessibilityIdentifier("arama-sonuc")
        case .dosya(let ad):
            Button { dosyaOnizleme = IndirmeYoneticisi.klasor.appending(path: ad) } label: { icerik }.buttonStyle(.plain).accessibilityIdentifier("arama-sonuc")
        }
    }

    private func dizinKur() async {
        let kaynaklar = Self.kaynaklar(beyin: beyin)
        let (d, a) = await Self.dizinleArkada(kaynaklar)
        dizin = d; atlanan = a
    }

    private func ara() async {
        let q = sorgu.trimmingCharacters(in: .whitespaces)
        // Tek harfli önek sorgusu FTS'de bütün indeksi tarar ve kilidi tutar (yazımları bekletir): en az 2 harf.
        guard q.count >= 2 else { cikti = AramaCikti(); aramaYapildi = false; return }
        try? await Task.sleep(for: .milliseconds(200))   // yazarken her harfte arama yapılmasın
        guard !Task.isCancelled, let dizin else { return }
        var sonuc = await Self.araArkada(q, dizin: dizin, turler: turler)
        guard !Task.isCancelled else { return }
        sonuc.atlanan = atlanan
        cikti = sonuc; aramaYapildi = true
    }

    /// Normalleştirme (Türkçe katlama) ve puanlama ana iş parçacığı dışında yapılır.
    @concurrent nonisolated static func dizinleArkada(_ k: [any AramaKaynagi]) async -> (AramaDizini, [AramaTuru]) {
        await BirlesikArama.dizinle(kaynaklar: k)
    }
    @concurrent nonisolated static func araArkada(_ q: String, dizin: AramaDizini, turler: Set<AramaTuru>) async -> AramaCikti {
        let c = BirlesikArama.ara(q, dizin: dizin, turler: turler)
        // Sohbetin derinindeki mesajlar: hafıza FTS indeksi (BM25, Türkçe normalleştirilmiş, önek eşleşmeli).
        let fts = HafizaIndeksi.ortak.ara(q, tur: .mesaj, adet: 80).compactMap { s in
            UUID(uuidString: s.sohbet).map { (sohbet: $0, metin: s.metin, yedekOzet: s.eslesme) }
        }
        return BirlesikArama.mesajEslesmeleriniKat(c, eslesmeler: fts, dizin: dizin, sorgu: q, turler: turler)
    }

    /// Kaynaklar ana aktörde anlık olarak okunur ve Sendable öğelere çevrilir (SwiftData nesneleri aktörden çıkmaz).
    static func kaynaklar(beyin: Beyin) -> [any AramaKaynagi] {
        let tuval = TuvalDeposu.ortak.belgeler.map {
            AramaOgesi(hedef: .tuval($0.id), baslik: $0.baslik, govde: String($0.guncel.metin.prefix(20_000)), tarih: $0.guncel.tarih)
        }
        // Yalnız başlık: mesaj içeriği arama anında hafıza FTS indeksinden gelir (ilişkiyi açmak bütün mesajları belleğe çekip donduruyordu).
        let sohbetler = beyin.depo.tumSohbetler().map { s in
            AramaOgesi(hedef: .sohbet(s.kimlik), baslik: s.baslik, tarih: s.olusturma)
        }
        let olgular = beyin.depo.olgular().map {
            AramaOgesi(hedef: .hafiza($0.kimlik), baslik: String($0.metin.prefix(80)), govde: $0.metin, tarih: $0.olusturma)
        }
        let dosyalar = IndirmeYoneticisi.ortak.kayitlar.compactMap { k -> AramaOgesi? in
            guard k.durum == "done", let d = k.dosya else { return nil }
            return AramaOgesi(hedef: .dosya(d), baslik: k.ad, govde: d)
        }
        let gorevler = CalismaSunucusu.ortak.gorevler.map {
            AramaOgesi(hedef: .gorev($0.id), baslik: String($0.request.input.prompt.prefix(80)), govde: $0.request.input.prompt)
        }
        return [(AramaTuru.tuval, tuval), (.sohbet, sohbetler), (.hafiza, olgular), (.dosya, dosyalar), (.gorev, gorevler)].map { tur, ogeler in
            KapanisAramaKaynagi(tur: tur) { ogeler }
        }
    }

    /// UTF-16 vurgu aralıklarını kalın + vurgu rengine çevirir.
    static func vurgulu(_ metin: String, _ araliklar: [NSRange]) -> AttributedString {
        var a = AttributedString(metin)
        for r in araliklar {
            guard let aralik = Range(r, in: metin), let ar = Range(aralik, in: a) else { continue }
            a[ar].foregroundColor = .accentColor
            a[ar].inlinePresentationIntent = .stronglyEmphasized
        }
        return a
    }
}
