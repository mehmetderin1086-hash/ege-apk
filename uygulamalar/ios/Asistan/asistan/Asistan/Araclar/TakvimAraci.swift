import Foundation
import FoundationModels
import EventKit

nonisolated struct TakvimAraci: Tool {
    let name = "takvim"
    let description = "Takvim etkinliklerini listeler, ekler, siler ya da günceller. Tarihler yerel saatte ISO 8601 (örn. 2026-10-15T18:30). Haftalık program gibi birden çok etkinlikte 'ekle' + 'toplu' (metin listesi) kullan. haftalik: true her hafta tekrarlar (tekrarBitis tarihine kadar), uyariDakika kaç dakika önce uyarılacağını belirler. Silme/güncellemede önce 'listele' ile kimliği bul, sonra 'kimlik' ile 'sil'/'guncelle'."

    /// Dış kaynaklı turda (paylaşım, bağlantı, web içeriği okunduktan sonra) 'sil'/'guncelle' kullanıcıya sorulur;
    /// doğrudan komutta onay yok (kullanıcı kararı). nil → hiç sorulmaz (yerel komut ve testler).
    var onay: OnayKapisi? = nil
    /// 'listele' satırlarının sonuna " [kimlik: …]" eklensin mi (model sil/guncelle için kullanır). Yerel "bugün takvim"
    /// komutu kullanıcıya doğrudan gösterdiği için kapalı kalır; araç kaydı açık kurar.
    var kimlikGoster = false

    @Generable
    struct Arguments {
        @Guide(description: "Yapılacak iş: 'listele', 'ekle', 'sil' ya da 'guncelle'") var islem: String
        @Guide(description: "listele/sil/guncelle: aralık başlangıcı (boşsa şimdi); ekle: etkinlik başlangıcı (ISO 8601); toplu eklemede gerekmez") var baslangic: String?
        @Guide(description: "listele: aralık bitişi; sil/guncelle: arama aralığı bitişi (boşsa 370 gün); ekle: etkinlik bitişi (ISO 8601). Boşsa ekle'de 1 saat sonrası.") var bitis: String?
        @Guide(description: "ekle: etkinlik başlığı; sil/guncelle: kimlik yoksa aranacak başlık parçası") var baslik: String?
        @Guide(description: "ekle/guncelle: yer (isteğe bağlı; guncelle'de boş = değişmez)") var yer: String?
        @Guide(description: "ekle/guncelle: not (isteğe bağlı; guncelle'de boş = değişmez)") var not: String?
        @Guide(description: "ekle: her hafta tekrar etsin mi") var haftalik: Bool?
        @Guide(description: "ekle: haftalık tekrarın son günü ISO 8601") var tekrarBitis: String?
        @Guide(description: "ekle/guncelle: kaç dakika önce uyarı (varsayılan 15)") var uyariDakika: Int?
        @Guide(description: "ekle: aynı anda eklenecek birden çok etkinlik (en çok 60). Her madde tek metin: 'başlık | başlangıç ISO 8601 | bitiş ISO 8601 (boş olabilir) | yer (boş olabilir) | haftalık (evet/hayır)'. Örn: '9B Biyoloji | 2026-10-19T08:30 | 2026-10-19T09:10 | B-12 | evet'") var toplu: [String]?
        @Guide(description: "Takvim adı (var olan bir takvim); boş = ekle'de varsayılan takvim, listele/sil/guncelle'de bütün takvimler") var takvim: String?
        @Guide(description: "sil/guncelle: listele çıktısındaki [kimlik: …] değeri; verilirse başlık araması yerine kullanılır") var kimlik: String?
        @Guide(description: "sil/guncelle: tekrarlı etkinlikte bu ve sonraki tekrarlar dahil mi (varsayılan true; false = yalnız aralıktaki ilk tekrar). Geçmiş tekrarlar hiçbir zaman değişmez.") var tumSeri: Bool?
        @Guide(description: "guncelle: yeni başlık") var yeniBaslik: String?
        @Guide(description: "guncelle: yeni başlangıç ISO 8601 (süre korunur; yalnız tek eşleşmede)") var yeniBaslangic: String?
        @Guide(description: "guncelle: yeni bitiş ISO 8601 (yalnız tek eşleşmede)") var yeniBitis: String?
    }

    static let islemler = ["listele", "ekle", "sil", "guncelle"]
    static func gecersizIslemMetni(_ islem: String) -> String {
        "Bilinmeyen işlem: \(islem). 'listele', 'ekle', 'sil' ya da 'guncelle' kullan."
    }

    struct Etkinlik: Equatable {
        var baslik: String, baslangic: String
        var bitis: String?, yer: String?
        var haftalik: Bool?
        var uyariDakika: Int?
    }

    /// "başlık | başlangıç | bitiş | yer | haftalık" metnini ayrıştırır (düz metin listesi: Gemini biçimli arka uçlar $ref'li iç içe şemayı reddeder).
    static func etkinlikCoz(_ satir: String) -> Etkinlik? {
        let p = satir.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard p.count >= 2, !p[0].isEmpty, !p[1].isEmpty else { return nil }
        func var_(_ i: Int) -> String? { p.count > i && !p[i].isEmpty ? p[i] : nil }
        let h = var_(4).map { ["evet", "e", "true", "haftalik", "haftalık", "1"].contains($0.lowercased()) }
        return Etkinlik(baslik: p[0], baslangic: p[1], bitis: var_(2), yer: var_(3), haftalik: h)
    }

    /// Tüm gün etkinliğinde uyarı, gün başına göre: o günün 09:00'undan `uyariDakika` önce (gece 23:45'te çalmaz).
    static func tumGunUyariOfseti(_ uyariDakika: Int) -> TimeInterval { 9 * 3600 - Double(uyariDakika) * 60 }

    /// Toplu ekleme uyarı özeti: tüm gün etkinliklerinin uyarısı o gün 09:00'a göredir; `dk < 0` iken uyarı kurulmaz (`etkinlikKur` ile aynı).
    static func topluUyariNotu(dk: Int, eklenen: Int, tumGun: Int) -> String {
        if dk < 0 { return " Uyarı kurulmadı." }
        if tumGun == 0 { return " Uyarı: \(dk) dk önce." }
        if tumGun >= eklenen { return " Tüm gün etkinlikleri; uyarı o gün 09:00'dan \(dk) dk önce." }
        return " Uyarı: \(dk) dk önce; \(tumGun) tanesi tüm gün, onların uyarısı o gün 09:00'dan \(dk) dk önce."
    }

    /// 'listele' aralık bitişi: saatsiz gün o günü de kapsar (ertesi gün 00:00; predicate bitişi dışlayıcıdır).
    /// Boş/çözülemeyen ya da başlangıçtan önce kalan bitiş: başlangıçtan 24 saat.
    static func listeBitisi(_ bitis: String?, bas: Date) -> Date {
        guard let b = bitis.flatMap(AracYardim.tarih) else { return bas.addingTimeInterval(86_400) }
        let son = AracYardim.yalnizGun(bitis) ? (Calendar.current.date(byAdding: .day, value: 1, to: b) ?? b.addingTimeInterval(86_400)) : b
        return son > bas ? son : bas.addingTimeInterval(86_400)
    }

    /// 'sil'/'guncelle' arama bitişi: boşsa başlangıçtan 370 gün (bir öğretim yılını aşan seri de bulunur); saatsiz gün o günü kapsar.
    static func degisiklikBitisi(_ bitis: String?, bas: Date) -> Date {
        guard bitis.flatMap(AracYardim.tarih) != nil else { return bas.addingTimeInterval(370 * 86_400) }
        return listeBitisi(bitis, bas: bas)
    }

    /// Toplu eklemenin eylem kartı: commit'ten sonra okunan kimlikler (nil olanlar atlanır), ilk başlangıca açılır.
    static func topluKart(_ olaylar: [EKEvent], haftalik: Int) -> EylemKaydi {
        let ids = olaylar.compactMap { $0.eventIdentifier as String? }.filter { !$0.isEmpty }
        let ilk = olaylar.compactMap { $0.startDate as Date? }.min() ?? .now
        let adlar = olaylar.compactMap { $0.title as String? }.prefix(3).joined(separator: ", ")
        return EylemKaydi(tur: .takvim, baslik: "Takvime \(olaylar.count) etkinlik eklendi",
                          ozet: adlar + (olaylar.count > 3 ? "…" : "") + (haftalik > 0 ? " · \(haftalik) haftalık seri" : ""),
                          kimlikler: ids, acAdresi: EylemKaydi.takvimAdresi(ilk))
    }

    /// Etkinliği kurar (kaydetmez). Haftalık tekrar `tekrarBitis`e kadar; uyarı dakika olarak.
    /// `tumGun`: saatsiz gün verildiyse tüm gün etkinliği (bitiş günü dahil). `takvim` nil → varsayılan takvim.
    static func etkinlikKur(_ depo: EKEventStore, baslik: String, bas: Date, bit: Date, yer: String? = nil, not: String? = nil,
                            haftalik: Bool = false, tekrarBitis: Date? = nil, uyariDakika: Int = 15, tumGun: Bool = false,
                            takvim: EKCalendar? = nil) -> EKEvent {
        let e = EKEvent(eventStore: depo)
        e.title = baslik; e.startDate = bas; e.endDate = tumGun ? max(bit, bas) : max(bit, bas.addingTimeInterval(60))
        e.isAllDay = tumGun
        e.location = yer; e.notes = not
        e.calendar = takvim ?? depo.defaultCalendarForNewEvents
        if uyariDakika >= 0 { e.addAlarm(EKAlarm(relativeOffset: tumGun ? tumGunUyariOfseti(uyariDakika) : -Double(uyariDakika) * 60)) }
        if haftalik {
            e.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: tekrarBitis.map { EKRecurrenceEnd(end: $0) }))
        }
        return e
    }

    /// Okuma işlemleri (listele/sil/guncelle) için takvim süzgeci: nil = bütün takvimler; hata metni → işlem yapılmaz.
    static func okumaTakvimi(_ depo: EKEventStore, ad: String?) -> (takvimler: [EKCalendar]?, hata: String?) {
        guard let ad = ad?.trimmingCharacters(in: .whitespacesAndNewlines), !ad.isEmpty else { return (nil, nil) }
        let hepsi = depo.calendars(for: .event)
        let tr = Locale(identifier: "tr_TR")
        guard let c = hepsi.first(where: { $0.title.lowercased(with: tr) == ad.lowercased(with: tr) }) else {
            return (nil, "\"\(ad)\" adlı takvim yok. Var olanlar: \(hepsi.map(\.title).prefix(12).joined(separator: ", ")).")
        }
        return ([c], nil)
    }

    /// 'ekle' hedef takvimi: nil = varsayılan; ad verilirse var olan takvim; salt okunur takvime eklenmez.
    static func yazmaTakvimi(_ depo: EKEventStore, ad: String?) -> (takvim: EKCalendar?, hata: String?) {
        guard let ad = ad?.trimmingCharacters(in: .whitespacesAndNewlines), !ad.isEmpty else { return (nil, nil) }
        let s = okumaTakvimi(depo, ad: ad)
        if let h = s.hata { return (nil, h) }
        guard let c = s.takvimler?.first, c.allowsContentModifications else { return (nil, "\"\(ad)\" takvimi salt okunur; etkinlik eklenemez.") }
        return (c, nil)
    }

    // MARK: Sil / güncelle (saf yardımcılar)

    /// Takvim örneğinin saf görüntüsü: `sira` olay listesindeki yer; `seri` calendarItemIdentifier (aynı serinin bütün tekrarlarında aynı),
    /// `kimlik` eventIdentifier (listele çıktısındaki; tekrarlı serinin bütün örneklerinde aynıdır).
    struct Ornek: Equatable, Sendable {
        var sira: Int
        var kimlik: String
        var seri: String
        var baslik: String
        var baslangic: Date
        var bitis: Date
        var tekrarli: Bool
    }

    static func ornekler(_ olaylar: [EKEvent]) -> [Ornek] {
        olaylar.enumerated().map { i, e in
            let k = (e.eventIdentifier as String?) ?? ""
            let s = e.calendarItemIdentifier.isEmpty ? k : e.calendarItemIdentifier
            return Ornek(sira: i, kimlik: k, seri: s, baslik: e.title ?? "(adsız)", baslangic: e.startDate, bitis: e.endDate, tekrarli: e.hasRecurrenceRules)
        }
    }

    /// tr_TR, büyük/küçük harf ve aksan duyarsız içerme.
    static func baslikEslesir(_ baslik: String, _ arama: String) -> Bool {
        let a = sade(arama.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !a.isEmpty else { return false }
        return sade(baslik).contains(a)
    }

    /// Karşılaştırma biçimi: tr_TR küçük harf ("BİYOLOJİ" → "biyoloji"), aksansız ("Ödev" → "odev"), ı → i.
    static func sade(_ s: String) -> String {
        let tr = Locale(identifier: "tr_TR")
        return s.precomposedStringWithCanonicalMapping.lowercased(with: tr).folding(options: [.diacriticInsensitive], locale: tr)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// Kimlik (verildiyse) ya da başlık eşleşen ve `baslangic` anında bitmemiş örnekler (geçmiş tekrarlar hedef olmaz).
    static func eslesenler(_ o: [Ornek], kimlik: String?, baslik: String?, baslangic: Date) -> [Ornek] {
        o.filter { x in
            guard x.bitis > baslangic else { return false }
            if let kimlik, !kimlik.isEmpty { return x.kimlik == kimlik }
            if let baslik { return baslikEslesir(x.baslik, baslik) }
            return false
        }
    }

    /// Kimlikli hedef: `event(withIdentifier:)` tekrarlı serinin İLK örneğini (geçmişte kalmış olabilir) döndürdüğü için kullanılmaz;
    /// aralıktaki örneklerden kimliği tutan ve `baslangic`ta bitmemiş en erken örnek seçilir.
    static func hedefOrnek(olaylar: [Ornek], kimlik: String, baslangic: Date) -> Ornek? {
        seriBasinaIlk(eslesenler(olaylar, kimlik: kimlik, baslik: nil, baslangic: baslangic)).first
    }

    /// Seri başına en erken örnek (zamana göre sıralı): sil/guncelle her seride bir kez çalışır.
    static func seriBasinaIlk(_ o: [Ornek]) -> [Ornek] {
        var ilk: [String: Ornek] = [:]
        for x in o where ilk[x.seri].map({ x.baslangic < $0.baslangic }) ?? true { ilk[x.seri] = x }
        return ilk.values.sorted { ($0.baslangic, $0.sira) < ($1.baslangic, $1.sira) }
    }

    /// Etkilenecek etkinlik sayısı: tekrarlı seride `tumSeri` iken aralıktaki farklı tekrar sayısı, değilse seri başına 1.
    /// Aynı örnek (aynı seri + aynı başlangıç) iki kez gelse de bir kez sayılır.
    static func etkilenecekSayi(olaylar: [Ornek], tumSeri: Bool) -> Int {
        var seriler: [String: (tekrarli: Bool, anlar: Set<Date>)] = [:]
        for x in olaylar {
            var g = seriler[x.seri] ?? (tekrarli: x.tekrarli, anlar: Set<Date>())
            g.tekrarli = g.tekrarli || x.tekrarli
            g.anlar.insert(x.baslangic)
            seriler[x.seri] = g
        }
        return seriler.values.reduce(0) { $0 + (tumSeri && $1.tekrarli ? $1.anlar.count : 1) }
    }

    /// Güncellemede yeni zaman: yalnız başlangıç verilirse süre korunur; bitiş başlangıçtan sonra değilse nil.
    static func yeniZaman(bas: Date, bit: Date, yeniBas: Date?, yeniBit: Date?) -> (bas: Date, bit: Date)? {
        let sure = bit.timeIntervalSince(bas)
        let b = yeniBas ?? bas
        let s = yeniBit ?? (yeniBas != nil ? b.addingTimeInterval(sure) : bit)
        return s > b ? (b, s) : nil
    }

    static func hedefListesi(_ h: [Ornek]) -> String {
        h.prefix(5).map { "• \($0.baslik) — \(AracYardim.kisa($0.baslangic))" }.joined(separator: "\n") + (h.count > 5 ? "\n…ve \(h.count - 5) etkinlik daha" : "")
    }

    // MARK: Çağrı

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.islemler.contains(islem) else { return Self.gecersizIslemMetni(a.islem) }
        let depo = EKEventStore()
        guard try await depo.requestFullAccessToEvents() else {
            await IzinKarti.ekle(.takvim)
            return "Takvim izni verilmedi. Ayarlar > Asistan'dan izin verin."
        }
        if islem == "sil" || islem == "guncelle" { return await degistir(a, sil: islem == "sil", depo: depo) }
        // Tek 'ekle'de başlangıç zorunlu: verilmezse etkinlik sessizce "şimdi"ye kurulmaz.
        guard let bas = a.baslangic.flatMap(AracYardim.tarih) ?? ((a.toplu?.isEmpty == false || islem == "listele") ? Date() : nil) else {
            return a.baslangic == nil ? "Başlangıç zamanı gerekli (ISO 8601, ör. 2026-10-15T18:30)." : "Başlangıç tarihi anlaşılmadı: \(a.baslangic ?? "")"
        }
        switch islem {
        case "listele":
            let bit = Self.listeBitisi(a.bitis, bas: bas)
            let secim = Self.okumaTakvimi(depo, ad: a.takvim)
            if let h = secim.hata { return h }
            let p = depo.predicateForEvents(withStart: bas, end: bit, calendars: secim.takvimler)
            let olaylar = depo.events(matching: p).sorted { $0.startDate < $1.startDate }
            if olaylar.isEmpty { return "Bu aralıkta etkinlik yok (\(AracYardim.kisa(bas)) – \(AracYardim.kisa(bit)))." }
            let satirlar = olaylar.prefix(25).map { e in
                let z = e.isAllDay ? "tüm gün" : "\(AracYardim.kisa(e.startDate))–\(AracYardim.kisa(e.endDate))"
                let k = kimlikGoster ? ((e.eventIdentifier as String?).map { " [kimlik: \($0)]" } ?? "") : ""
                return "• \(e.title ?? "(adsız)") — \(z)\(e.location.map { " @ \($0)" } ?? "")\(k)"
            }.joined(separator: "\n")
            return satirlar + (olaylar.count > 25 ? "\n…ve \(olaylar.count - 25) etkinlik daha (aralığı daralt)." : "")
        case "ekle":
            let hedef = Self.yazmaTakvimi(depo, ad: a.takvim)
            if let h = hedef.hata { return h }
            let takvimNotu = hedef.takvim.map { " Takvim: \($0.title)." } ?? ""
            // Saatsiz tekrar bitişi ("dönem sonu") günün sonuna çekilir; yoksa son günün dersi tekrarın dışında kalır.
            let tekrarBitis = a.tekrarBitis.flatMap(AracYardim.tarih).map { AracYardim.yalnizGun(a.tekrarBitis) ? $0.addingTimeInterval(86_399) : $0 }
            if let toplu = a.toplu, !toplu.isEmpty {
                var eklenen = 0, haftalikSayi = 0, tumGunSayi = 0
                var atlanan: [String] = []
                // Kimlikler commit'ten SONRA okunur (commit'ten önce nil olabilir).
                var kaydedilen: [EKEvent] = []
                let kesilen = max(0, toplu.count - 60)
                for (i, ham) in toplu.prefix(60).enumerated() {
                    guard let m = Self.etkinlikCoz(ham), let b = AracYardim.tarih(m.baslangic) else { atlanan.append("\(i + 1). \(ham.prefix(60))"); continue }
                    let h = m.haftalik ?? a.haftalik ?? false
                    let tg = AracYardim.yalnizGun(m.baslangic)
                    let e = Self.etkinlikKur(depo, baslik: m.baslik, bas: b, bit: m.bitis.flatMap(AracYardim.tarih) ?? (tg ? b : b.addingTimeInterval(40 * 60)),
                                             yer: m.yer, haftalik: h, tekrarBitis: tekrarBitis, uyariDakika: a.uyariDakika ?? 15, tumGun: tg, takvim: hedef.takvim)
                    try depo.save(e, span: .futureEvents, commit: false)
                    kaydedilen.append(e)
                    eklenen += 1; if h { haftalikSayi += 1 }; if tg { tumGunSayi += 1 }
                }
                let ozet = AracYardim.topluOzet(atlanan: atlanan, kesilen: kesilen, sinir: 60)
                guard eklenen > 0 else { return "Hiç etkinlik eklenmedi." + ozet }
                try depo.commit()
                let kart = Self.topluKart(kaydedilen, haftalik: haftalikSayi)
                await kart.kartaEkle()
                let tekrar = haftalikSayi > 0 ? " \(haftalikSayi) tanesi her hafta tekrarlanıyor\(tekrarBitis.map { " (\(AracYardim.kisaGun($0)) tarihine kadar)" } ?? "")." : ""
                return "\(eklenen) etkinlik takvime eklendi.\(tekrar)\(Self.topluUyariNotu(dk: a.uyariDakika ?? 15, eklenen: eklenen, tumGun: tumGunSayi))\(takvimNotu)\(ozet)\(kart.kimlikler.isEmpty ? "" : EylemKaydi.geriAlNotu)"
            }
            guard let baslik = a.baslik, !baslik.isEmpty else { return "Etkinlik başlığı gerekli." }
            let tumGun = AracYardim.yalnizGun(a.baslangic)
            let e = Self.etkinlikKur(depo, baslik: baslik, bas: bas, bit: a.bitis.flatMap(AracYardim.tarih) ?? (tumGun ? bas : bas.addingTimeInterval(3600)),
                                     yer: a.yer, not: a.not, haftalik: a.haftalik ?? false, tekrarBitis: tekrarBitis, uyariDakika: a.uyariDakika ?? 15,
                                     tumGun: tumGun, takvim: hedef.takvim)
            try depo.save(e, span: .futureEvents, commit: true)
            let haftalik = a.haftalik ?? false
            let tekrarNotu = (haftalik ? " Her hafta tekrarlanıyor." : "") + takvimNotu
            let dk = a.uyariDakika ?? 15
            let zamanMetni = tumGun ? "\(AracYardim.kisaGun(e.startDate)) · tüm gün" : "\(AracYardim.kisa(e.startDate))–\(AracYardim.kisa(e.endDate))"
            let kart = EylemKaydi(tur: .takvim, baslik: baslik, ozet: zamanMetni + (haftalik ? " · haftalık seri" : ""),
                                  kimlikler: (e.eventIdentifier as String?).map { [$0] } ?? [], acAdresi: EylemKaydi.takvimAdresi(e.startDate))
            await kart.kartaEkle()
            let geriAlNotu = kart.kimlikler.isEmpty ? "" : EylemKaydi.geriAlNotu
            if tumGun {
                return "Tüm gün etkinliği eklendi: \(baslik), \(AracYardim.kisaGun(e.startDate)).\(dk < 0 ? " Uyarı kurulmadı." : " Uyarı o gün 09:00'dan \(dk) dk önce.")\(tekrarNotu)\(geriAlNotu)"
            }
            return "Etkinlik eklendi: \(baslik), \(AracYardim.kisa(e.startDate))–\(AracYardim.kisa(e.endDate)).\(dk < 0 ? " Uyarı kurulmadı." : " \(dk) dk önce uyarı var.")\(tekrarNotu)\(geriAlNotu)"
        default:
            return Self.gecersizIslemMetni(a.islem)
        }
    }

    /// 'sil' / 'guncelle': hedefler aralık yüklemiyle bulunur (kimlik ya da başlık + takvim süzgeci), seri başına bir kez
    /// işlenir; geçmiş tekrarlar korunur. Onay yalnız dış kaynaklı turda sorulur; dönüş metni etkilenen sayıyı ve ilk 5 başlığı söyler.
    private func degistir(_ a: Arguments, sil: Bool, depo: EKEventStore) async -> String {
        if let s = a.baslangic, AracYardim.tarih(s) == nil { return "Başlangıç tarihi anlaşılmadı: \(s)" }
        let bas = a.baslangic.flatMap(AracYardim.tarih) ?? Date()
        let bit = Self.degisiklikBitisi(a.bitis, bas: bas)
        let kimlik = a.kimlik?.trimmingCharacters(in: .whitespacesAndNewlines).bosIseNil
        let arama = a.baslik?.trimmingCharacters(in: .whitespacesAndNewlines).bosIseNil
        guard kimlik != nil || arama != nil else { return "Hangi etkinlik? 'kimlik' (listele çıktısından) ya da 'baslik' ver." }
        // Güncellemede yeni değerler önce doğrulanır (onay sorulduktan sonra "anlaşılmadı" denmesin).
        var yeniBas: Date?, yeniBit: Date?
        if !sil {
            if let s = a.yeniBaslangic?.bosIseNil { guard let d = AracYardim.tarih(s) else { return "Yeni başlangıç anlaşılmadı: \(s)" }; yeniBas = d }
            if let s = a.yeniBitis?.bosIseNil { guard let d = AracYardim.tarih(s) else { return "Yeni bitiş anlaşılmadı: \(s)" }; yeniBit = d }
            let degisiklik = a.yeniBaslik?.bosIseNil != nil || a.yer?.bosIseNil != nil || a.not?.bosIseNil != nil || a.uyariDakika != nil || yeniBas != nil || yeniBit != nil
            guard degisiklik else { return "Neyi değiştireyim? yeniBaslik, yeniBaslangic, yeniBitis, yer, not ya da uyariDakika ver." }
        }
        let secim = Self.okumaTakvimi(depo, ad: a.takvim)
        if let h = secim.hata { return h }
        let tumu = depo.events(matching: depo.predicateForEvents(withStart: bas, end: bit, calendars: secim.takvimler))
        // Salt okunur takvimler (abonelik, doğum günleri) hedef olmaz.
        let olaylar = tumu.filter { $0.calendar?.allowsContentModifications == true }
        let eslesen = Self.eslesenler(Self.ornekler(olaylar), kimlik: kimlik, baslik: arama, baslangic: bas)
        let hedefler = Self.seriBasinaIlk(eslesen)
        guard !hedefler.isEmpty else {
            let salt = Self.eslesenler(Self.ornekler(tumu), kimlik: kimlik, baslik: arama, baslangic: bas).isEmpty ? "" : " (eşleşen etkinlikler salt okunur takvimde)"
            return "Eşleşen etkinlik yok\(salt): \(AracYardim.kisa(bas)) – \(AracYardim.kisa(bit))."
        }
        let tumSeri = a.tumSeri ?? true
        let sayi = Self.etkilenecekSayi(olaylar: eslesen, tumSeri: tumSeri)
        let liste = Self.hedefListesi(hedefler)
        let tekrarliVar = hedefler.contains(where: \.tekrarli)
        let seriNotu = !tekrarliVar ? "" : (tumSeri ? "Tekrarlı etkinliklerde bu ve sonraki tekrarlar da etkilenir; geçmiş tekrarlar korunur."
                                                   : "Tekrarlı etkinliklerde yalnız aralıktaki ilk tekrar etkilenir.")
        if !sil, (yeniBas != nil || yeniBit != nil), hedefler.count > 1 {
            return "Zaman değişikliği tek etkinlikte yapılır; \(hedefler.count) eşleşme var:\n\(liste)\nKimlikle (listele çıktısındaki [kimlik: …]) tekrar dene."
        }
        if let onay {
            let soru = sil ? "\(sayi) etkinlik silinsin mi?" : "\(sayi) etkinlik güncellensin mi?"
            guard await onay.disKaynaktaIste(baslik: soru, ayrinti: String((liste + (seriNotu.isEmpty ? "" : "\n" + seriNotu)).prefix(600))) else {
                return "Kullanıcı onaylamadı; takvim değişmedi."
            }
        }
        do {
            for h in hedefler {
                let e = olaylar[h.sira]
                let span: EKSpan = tumSeri && e.hasRecurrenceRules ? .futureEvents : .thisEvent
                if sil {
                    try depo.remove(e, span: span, commit: false)
                    continue
                }
                if let t = a.yeniBaslik?.bosIseNil { e.title = t }
                if let y = a.yer?.bosIseNil { e.location = y }
                if let n = a.not?.bosIseNil { e.notes = n }
                if let dk = a.uyariDakika {
                    for alarm in e.alarms ?? [] { e.removeAlarm(alarm) }
                    if dk >= 0 { e.addAlarm(EKAlarm(relativeOffset: e.isAllDay ? Self.tumGunUyariOfseti(dk) : -Double(dk) * 60)) }
                }
                if yeniBas != nil || yeniBit != nil {
                    guard let z = Self.yeniZaman(bas: e.startDate, bit: e.endDate, yeniBas: yeniBas, yeniBit: yeniBit) else {
                        depo.reset()
                        return "Yeni bitiş başlangıçtan sonra olmalı; takvim değişmedi."
                    }
                    e.startDate = z.bas; e.endDate = z.bit
                }
                try depo.save(e, span: span, commit: false)
            }
            try depo.commit()
        } catch {
            depo.reset()
            return "Takvim \(sil ? "silinemedi" : "güncellenemedi"): \(error.localizedDescription). Hiçbir değişiklik kaydedilmedi."
        }
        let fiil = sil ? "silindi" : "güncellendi"
        let tekrarSayisi = sayi != hedefler.count ? " (aralıkta \(sayi) tekrar)" : ""
        return "\(hedefler.count) etkinlik \(fiil)\(tekrarSayisi):\n\(liste)\(seriNotu.isEmpty ? "" : "\n" + seriNotu)\(sil ? "\nSilme geri alınamaz." : "")"
    }
}

private extension String {
    nonisolated var bosIseNil: String? { isEmpty ? nil : self }
}
