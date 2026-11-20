import Foundation
import FoundationModels
import SwiftData

/// Hermes Agent'ın oturumlar arası arama özelliği: tüm eski sohbetlerdeki mesajlarda anahtar sözcükle arama.
nonisolated enum GecmisArama {
    struct Bulgu: Equatable, Sendable {
        let sohbet: String
        let zaman: Date
        let rol: String
        let parca: String
        let puan: Int
    }

    /// Arama terimleri: normalleştirilmiş, ≥3 harfli, tekrarsız.
    static func terimler(_ sorgu: String) -> [String] {
        var gorulen = Set<String>(), sonuc: [String] = []
        for t in normalize(sorgu).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) where t.count >= 3 {
            if gorulen.insert(t).inserted { sonuc.append(t) }
        }
        return sonuc
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR")).replacingOccurrences(of: "ı", with: "i")
    }

    /// Eşleşme çevresinden en çok `uzunluk` karakterlik kesit.
    static func kesit(_ metin: String, terim: String, uzunluk: Int = 220) -> String {
        let n = normalize(metin)
        guard let r = n.range(of: terim) else { return String(metin.prefix(uzunluk)) }
        let konum = n.distance(from: n.startIndex, to: r.lowerBound)
        let bas = max(0, konum - uzunluk / 3)
        let dizi = Array(metin)
        let son = min(dizi.count, bas + uzunluk)
        return (bas > 0 ? "…" : "") + String(dizi[min(bas, dizi.count)..<son]) + (son < dizi.count ? "…" : "")
    }

    /// Her terim bir puan; tüm terimleri içerenler öne, eşitlikte yeni olan.
    static func sirala(_ adaylar: [(sohbet: String, zaman: Date, rol: String, metin: String)], sorgu: String, adet: Int) -> [Bulgu] {
        let ts = terimler(sorgu)
        guard !ts.isEmpty else { return [] }
        let bulgular: [Bulgu] = adaylar.compactMap { m in
            let n = normalize(m.metin)
            let ilk = ts.first(where: { n.contains($0) })
            let puan = ts.filter { n.contains($0) }.count
            guard puan > 0, let ilk else { return nil }
            return Bulgu(sohbet: m.sohbet, zaman: m.zaman, rol: m.rol, parca: kesit(m.metin, terim: ilk), puan: puan)
        }
        return Array(bulgular.sorted { $0.puan == $1.puan ? $0.zaman > $1.zaman : $0.puan > $1.puan }.prefix(adet))
    }
}

nonisolated extension GecmisArama {
    struct Etiket: Equatable, Sendable { let baslik: String; let rol: String }

    /// FTS sonuçlarını bulguya çevirir: kesit terimin (uzun sözcükte kökünün) çevresinden alınır, başlık/rol etiketlerden gelir.
    static func ftsBulgulari(_ sonuclar: [HafizaIndeksi.Sonuc], sorgu: String, etiketler: [String: Etiket]) -> [Bulgu] {
        let ts = HafizaIndeksi.terimler(sorgu).map { $0.count > 6 ? String($0.prefix(max(5, $0.count - 3))) : $0 }
        return sonuclar.map { r in
            let n = normalize(r.metin)
            let e = etiketler[r.kimlik]
            let parca = ts.first(where: { n.contains($0) }).map { kesit(r.metin, terim: $0) } ?? String(r.metin.prefix(240))
            return Bulgu(sohbet: e?.baslik ?? "Sohbet", zaman: r.zaman, rol: e?.rol ?? "", parca: parca, puan: Int(r.puan))
        }
    }

    static let anlamsalEsik: Float = 0.55

    /// Sözcük + anlam birleşik sıralama: sözcük eşleşmesi başına 1 puan, eşiği aşan benzerlik için 3×benzerlik.
    /// Sözcük geçmese de anlamca yakın mesajlar ("bütçe" ↔ "harcama tutarı") bulunur.
    static func birlestir(_ adaylar: [(sohbet: String, zaman: Date, rol: String, metin: String, benzerlik: Float?)], sorgu: String, adet: Int) -> [Bulgu] {
        let ts = terimler(sorgu)
        let bulgular: [(Bulgu, Double)] = adaylar.compactMap { m in
            let n = normalize(m.metin)
            let sozcuk = ts.filter { n.contains($0) }.count
            let anlam = (m.benzerlik ?? 0) >= anlamsalEsik ? Double(m.benzerlik ?? 0) * 3 : 0
            let skor = Double(sozcuk) + anlam
            guard skor > 0 else { return nil }
            let terim = ts.first(where: { n.contains($0) })
            return (Bulgu(sohbet: m.sohbet, zaman: m.zaman, rol: m.rol, parca: terim.map { kesit(m.metin, terim: $0) } ?? String(m.metin.prefix(220)), puan: sozcuk), skor)
        }
        return Array(bulgular.sorted { $0.1 == $1.1 ? $0.0.zaman > $1.0.zaman : $0.1 > $1.1 }.prefix(adet).map(\.0))
    }
}

/// Mesaj gömlemeleri ayrı dosyada (SwiftData şeması değişmez, taşıma riski yok): Application Support/mesaj-vektorleri.plist
nonisolated final class MesajVektorleri: @unchecked Sendable {
    static let ortak = MesajVektorleri()
    private let kilit = NSLock()
    private let dosya: URL
    private var vektorler: [String: Data]

    init(dosya: URL? = nil) {
        let taban = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        self.dosya = dosya ?? taban.appendingPathComponent("mesaj-vektorleri.plist")
        vektorler = (try? Data(contentsOf: self.dosya)).flatMap { try? PropertyListDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }
    func vektor(_ id: UUID) -> [Float]? { kilit.lock(); defer { kilit.unlock() }; return vektorler[id.uuidString].map(Gomlemci.vektor) }
    func var_(_ id: UUID) -> Bool { kilit.lock(); defer { kilit.unlock() }; return vektorler[id.uuidString] != nil }
    /// bge-m3 boyutunda (1024) gömmesi var mı; eski 512 boyutlu NL gömmesi yok sayılır ve yeniden doldurulur.
    func gecerliVar(_ id: UUID) -> Bool {
        kilit.lock(); defer { kilit.unlock() }
        return vektorler[id.uuidString].map { $0.count == UzakGomlemci.boyut * MemoryLayout<Float>.size } ?? false
    }
    /// Yalnız bge-m3 boyutundaki gömme (bkz. `gecerliVar`).
    func gecerliVektor(_ id: UUID) -> [Float]? { UzakGomlemci.gecerliDizi(vektor(id)) }
    func ekle(_ id: UUID, _ v: [Float]) { kilit.lock(); vektorler[id.uuidString] = Gomlemci.veri(v); kilit.unlock() }
    var sayi: Int { kilit.lock(); defer { kilit.unlock() }; return vektorler.count }
    func kaydet() {
        kilit.lock(); let v = vektorler; kilit.unlock()
        let e = PropertyListEncoder(); e.outputFormat = .binary
        try? e.encode(v).write(to: dosya, options: .atomic)
    }
}

extension HafizaDeposu {
    static let anlamsalEnKisa = 12
    /// Anlamsal hafıza ayarı (`ayar.anlamsalHafiza`, varsayılan KAPALI). Telefondaki Türkçe NLContextualEmbedding ayırt edici
    /// değil (19 Eki 2026 ölçümü: konuyla ilgisiz metinler dahi 0,69-0,87) ve KULLANILMAZ; açıkken yalnız vekildeki bge-m3
    /// (`UzakGomlemci`) gömmesi kullanılır. Vekil kimliği yoksa ayar açık olsa da gömme yapılmaz (`UzakGomlemci.etkin`).
    nonisolated static var anlamsalAramaAcik: Bool { UserDefaults.standard.bool(forKey: UzakGomlemci.ayarAnahtari) }

    /// Son 3000 mesajda sözcükle arar (araç mesajları hariç). Zaman uyumludur ve yalnız sözcük eşleşmesi kullanır (slash
    /// komutu ve FTS yedeği); anlamca arama `gecmisAraMelez`'dedir.
    func gecmisAra(_ sorgu: String, adet: Int = 6) -> [GecmisArama.Bulgu] {
        gecmisAra(sorgu, adet: adet, sorguVektoru: nil)
    }

    /// `gecmisAra`'nın anlamca eşi: sorgu vektörü bge-m3'ten en çok 1200 ms beklenir; gelmezse ya da ayar kapalıysa yalnız sözcük.
    func gecmisAraMelez(_ sorgu: String, adet: Int = 6) async -> [GecmisArama.Bulgu] {
        let q = UzakGomlemci.etkin ? await UzakGomlemci.sinirliVektor(sorgu) : nil
        return gecmisAra(sorgu, adet: adet, sorguVektoru: q)
    }

    private func gecmisAra(_ sorgu: String, adet: Int, sorguVektoru q: [Float]?) -> [GecmisArama.Bulgu] {
        var t = FetchDescriptor<Mesaj>(sortBy: [SortDescriptor(\.zaman, order: .reverse)])
        t.fetchLimit = 3000
        let mesajlar = ((try? baglam.fetch(t)) ?? []).filter { $0.rol != .arac }
        let q = UzakGomlemci.gecerliDizi(q)
        return GecmisArama.birlestir(mesajlar.map { m in
            let b: Float? = q.flatMap { q in MesajVektorleri.ortak.gecerliVektor(m.kimlik).map { Gomlemci.kosinus(q, $0) } }
            return (m.sohbet?.baslik ?? "Sohbet", m.zaman, m.rol == .kullanici ? "Kullanıcı" : "Asistan", m.metin, b)
        }, sorgu: sorgu, adet: adet)
    }

    /// Mesaj gömmelerini bge-m3'ten alıp dosyaya yazar (aktör dışı; ilk hatada sessizce durur). Yazılan sayı.
    @discardableResult
    nonisolated static func mesajlariGom(_ ciftler: [(UUID, String)]) async -> Int {
        guard UzakGomlemci.etkin else { return 0 }
        var n = 0, i = 0
        while i < ciftler.count {
            let parca = Array(ciftler[i..<min(ciftler.count, i + UzakGomlemci.enFazlaMetin)])
            guard let v = try? await UzakGomlemci.vektorler(parca.map(\.1)), v.count == parca.count else { break }
            for (j, c) in parca.enumerated() { MesajVektorleri.ortak.ekle(c.0, v[j]) }
            n += parca.count; i += parca.count
        }
        if n > 0 { MesajVektorleri.ortak.kaydet() }
        return n
    }

    /// FTS bulgularının sohbet başlığı ve rolü (en çok birkaç kimlik, tek sorgu). Bulunamayan kimlik sözlükte yer almaz.
    func mesajEtiketleri(_ kimlikler: [String]) -> [String: GecmisArama.Etiket] {
        let ids = kimlikler.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return [:] }
        let t = FetchDescriptor<Mesaj>(predicate: #Predicate<Mesaj> { ids.contains($0.kimlik) })
        let bulunan = ((try? baglam.fetch(t)) ?? []).map { ($0.kimlik.uuidString, GecmisArama.Etiket(baslik: $0.sohbet?.baslik ?? "Sohbet", rol: $0.rol == .kullanici ? "Kullanıcı" : "Asistan")) }
        return Dictionary(bulunan, uniquingKeysWith: { a, _ in a })
    }

    /// Gömmesi olmayan (ya da eski boyutlu) son mesajları 32'lik toplu isteklerle tamamlar; ağ işi aktör dışında koşar.
    func mesajVektorleriniTamamla(enFazla: Int = 600) async {
        guard UzakGomlemci.etkin else { return }
        var t = FetchDescriptor<Mesaj>(sortBy: [SortDescriptor(\.zaman, order: .reverse)])
        t.fetchLimit = 3000
        let eksik = ((try? baglam.fetch(t)) ?? [])
            .filter { $0.rol != .arac && $0.metin.count >= Self.anlamsalEnKisa && !MesajVektorleri.ortak.gecerliVar($0.kimlik) }
            .prefix(enFazla).map { ($0.kimlik, String($0.metin.prefix(UzakGomlemci.enFazlaKarakter))) }
        guard !eksik.isEmpty else { return }
        let ciftler = Array(eksik)
        let n = await Task.detached(priority: .utility) { await Self.mesajlariGom(ciftler) }.value
        if n > 0 { TaniGunlugu.yaz("MESAJ VEKTÖRLERİ: \(n) eklendi, toplam \(MesajVektorleri.ortak.sayi)") }
    }
}

extension GecmisAramaAraci {
    /// Sorguyu 4-8 Türkçe eşanlamlı/ilgili sözcükle genişletir; model yanıt vermezse nil.
    static func genislet(_ sorgu: String) async -> String? {
        let (taban, anahtar) = await MainActor.run { (TelefonProxy.ortak.taban, TelefonProxy.ortak.yerelAnahtar) }
        let sistem = "Kullanıcının eski sohbetlerinde arama yapılacak. Verilen arama ifadesi için anlamca yakın 4-8 Türkçe sözcük (eşanlamlı, üst/alt kavram, yaygın yazım) üret. Yalnız virgülle ayrılmış sözcükleri yaz, açıklama yazma."
        guard let s = try? await ParalelYaris.yaris(taban: taban, anahtar: anahtar, modeller: ["claude-haiku-4-5", "gemini-3.8-flash"], sistem: sistem,
                                                   mesajlar: [.init(rol: "user", metin: sorgu)], toplamSiniri: 12, akis: { _, _ in }) else { return nil }
        let t = Self.genislemeTemizle(s.metin)
        return t.isEmpty ? nil : t
    }

    /// Model çıktısını güvenli sözcük listesine indirger (en çok 8 sözcük, yalnız harf/rakam/boşluk).
    nonisolated static func genislemeTemizle(_ ham: String) -> String {
        let parcalar = ham.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 30 }
        return parcalar.prefix(8).joined(separator: " ")
    }

    /// Önce özgün sorgunun bulguları, sonra genişletilmiş aramadan yeni olanlar.
    nonisolated static func birlestir(_ a: [GecmisArama.Bulgu], _ b: [GecmisArama.Bulgu], adet: Int) -> [GecmisArama.Bulgu] {
        var sonuc = a
        for x in b where !sonuc.contains(where: { $0.parca == x.parca && $0.zaman == x.zaman }) { sonuc.append(x) }
        return Array(sonuc.prefix(adet))
    }
}

nonisolated struct GecmisAramaAraci: Tool {
    let name = "gecmisAra"
    let description = "Kullanıcıyla yapılmış ESKİ sohbetlerde sözcükle arar ('geçen hafta konuştuğumuz…', 'daha önce sana söylemiştim…'). Tarih, sohbet başlığı ve ilgili kesiti döndürür."

    @Generable
    struct Arguments {
        @Guide(description: "Aranacak anahtar sözcükler (2-4 kelime)") var sorgu: String
        @Guide(description: "En fazla kaç sonuç, 1-10 (varsayılan 5)") var adet: Int?
    }

    let depo: HafizaDeposu

    func call(arguments a: Arguments) async throws -> String {
        let adet = min(max(a.adet ?? 5, 1), 10)
        // Önce FTS5 indeksi (tüm geçmiş, BM25 sıralı). İndeks kilitli ve aktöre bağlı değil: ana iş parçacığı dışında aranır.
        // Ana iş parçacığında 3000 mesajı çeken alt dize taraması yalnız FTS hiç sonuç vermezse çalışır: FTS sözcük başı önekiyle
        // eşleşir ve mesajın ilk 4000 karakterini tutar; bitişik adın ortası (KitapKatalog ↔ katalog) ve uzun yanıtın sonu orada bulunur.
        let ix = HafizaIndeksi.ortak
        let depo = self.depo
        func ftsAra(_ s: String) async -> [GecmisArama.Bulgu] {
            let r = ix.ara(s, tur: .mesaj, adet: adet)
            guard !r.isEmpty else { return [] }
            let kimlikler = r.map(\.kimlik)
            let etiketler = await MainActor.run { depo.mesajEtiketleri(kimlikler) }
            return GecmisArama.ftsBulgulari(r, sorgu: s, etiketler: etiketler)
        }
        let indeksKullanilir = ix.hazir && ix.say(tur: .mesaj) > 0 && !HafizaIndeksi.terimler(a.sorgu).isEmpty
        var bulgular = await ftsAra(a.sorgu)
        if bulgular.isEmpty { bulgular = await depo.gecmisAraMelez(a.sorgu, adet: adet) }
        // Anlamca arama (madde 7): sözcük eşleşmesi azsa hızlı model sorguyu eşanlamlı/ilgili sözcüklerle genişletir
        // ("bütçe" → harcama, maliyet, gider). Telefondaki gömleme ayırt edici olmadığı için bu yol kullanılır.
        if bulgular.count < min(3, adet), let genis = await Self.genislet(a.sorgu) {
            let ek: [GecmisArama.Bulgu]
            if indeksKullanilir { ek = await ftsAra(a.sorgu + " " + genis) }   // özgün terimler önde (terimler ilk 8'i alır)
            else { ek = await depo.gecmisAraMelez(a.sorgu + " " + genis, adet: adet) }
            bulgular = Self.birlestir(bulgular, ek, adet: adet)
        }
        guard !bulgular.isEmpty else { return "Geçmiş sohbetlerde '\(a.sorgu)' ile eşleşen bir şey bulunamadı." }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM yyyy HH:mm"
        return bulgular.map { "[\(f.string(from: $0.zaman)) · \($0.sohbet) · \($0.rol)] \($0.parca)" }.joined(separator: "\n")
    }
}
