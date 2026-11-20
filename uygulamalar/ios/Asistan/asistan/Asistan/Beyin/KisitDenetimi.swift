import Foundation

/// Kullanıcının koştuğu kısıtların (rakam ve özel ad) yanıtta/dosyada karşılanıp karşılanmadığını kodla denetler (P2.10).
/// İlk aşamada yalnız rakam ve özel ad kısıtları denetlenir; kaynak, site ve tür kısıtları denetlenmez.
/// Yazıyla sayılar `TurkceSayi.normalize` ile (yalnız karşılaştırma için) rakama iner: "on beşinci cüz" isteği "15" ister.
nonisolated enum KisitDenetimi {
    /// Büyük harfle yazılsa da özel ad kısıtı sayılmayan sözcükler: biçim/uygulama adları, ay/gün adları, sık cümle başları.
    static let ozelAdDisi: Set<String> = ["word", "excel", "powerpoint", "docx", "xlsx", "pptx", "json", "markdown", "google", "safari", "siri",
                                          "iphone", "ipad", "claude", "chatgpt", "gemini", "youtube", "whatsapp", "instagram", "spotify", "drive",
                                          "icloud", "dosya", "dosyasi", "lutfen", "bana", "bunu", "sonra", "simdi", "hemen", "acaba", "merhaba",
                                          "selam", "tamam", "evet", "hayir", "pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi",
                                          "pazar", "ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim",
                                          "kasim", "aralik", "bugun", "yarin"]

    /// `AtolyeYonlendirme.normalize` edilmiş metinde rakam + miktar birimi ("3 sayfalik", "5 madde", "10 dakika").
    static let birimliMiktarDeseni = #"\b\d+\s*-?\s*(sayfa|madde|adet|tane|kelime|sozcuk|satir|dakika|dk|saniye|sn|paragraf|cumle|karakter|slayt|soru|kisi)\w*"#

    /// Kısıt, tek başına birimli miktar mı (süzgeç "3 sayfalık" gibi bir kısıt döndürmüşse dosya adı denetiminden çıkar).
    static func birimliMiktarMi(_ kisit: String) -> Bool {
        let n = AtolyeYonlendirme.normalize(kisit).trimmingCharacters(in: .whitespaces)
        return n.range(of: "^" + birimliMiktarDeseni + "$", options: .regularExpression) != nil
    }

    /// Süzgeç yokken ham istekten çıkan kısıtlar: rakamlar (yazıyla söylenenler dahil; saat "14.30" ve "saat 9" ve birimli miktarlar "3 sayfalık" atlanır) ile
    /// ilk sözcükten sonra büyük harfle başlayan, en az 4 harfli özel adlar. İş sözcükleri (`IstemSuzgeci.kisaEmirler`/`isKokleri`)
    /// ve dikte hatası kısa sözcükler ("Çöz") kısıt olmaz; cümle başındaki büyük harf özel ad sayılmaz. En çok 6.
    static func yerelKisitlar(_ ham: String) -> [String] {
        var sonuc: [String] = []
        var gorulen = Set<String>()
        func ekle(_ s: String) { if gorulen.insert(AtolyeYonlendirme.normalize(s)).inserted { sonuc.append(s) } }

        // Saat kalıpları zorunlu kısıt değildir (dosya adında geçmez): "14.30", "9:15", "saat 9".
        var sayiMetni = TurkceSayi.normalize(AtolyeYonlendirme.normalize(ham))
        sayiMetni = sayiMetni.replacingOccurrences(of: #"(?<!\d)\d{1,2}[.:]\d{2}(?!\d)"#, with: " ", options: .regularExpression)
        sayiMetni = sayiMetni.replacingOccurrences(of: #"\bsaat\s+\d+\S*"#, with: " ", options: .regularExpression)
        // Birimli miktarlar ("3 sayfalık rapor", "5 madde", "10 dakika") dosya adında/yanıtta rakamla geçmek zorunda değildir.
        sayiMetni = sayiMetni.replacingOccurrences(of: birimliMiktarDeseni, with: " ", options: .regularExpression)
        for s in IndirmeEslesme.simgeler(sayiMetni) where s.allSatisfy(\.isNumber) { ekle(s) }

        let sozcukler = ham.split(whereSeparator: \.isWhitespace).map(String.init)
        for (k, sozcuk) in sozcukler.enumerated() where k > 0 {
            let onceki = sozcukler[k - 1]
            // Cümle başı: önceki sözcük . ! ? ile bitiyorsa (yalnız "15." gibi sıra sayısı değilse) büyük harf özel ad değildir.
            if let son = onceki.last, ".!?".contains(son), !onceki.dropLast().allSatisfy(\.isNumber) { continue }
            var w = sozcuk.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            if let r = w.firstIndex(where: { $0 == "'" || $0 == "’" }) { w = String(w[..<r]) }   // "Kaya'nın" → "Kaya"
            guard let ilk = w.first, ilk.isUppercase, w.count >= 4, w.allSatisfy(\.isLetter) else { continue }
            let n = AtolyeYonlendirme.normalize(w)
            if ozelAdDisi.contains(n) || IstemSuzgeci.kisaEmirler.contains(n) || IstemSuzgeci.isKokleri.contains(where: { n.hasPrefix($0) }) { continue }
            ekle(w)
        }
        return Array(sonuc.prefix(6))
    }

    /// Kısıtların (`IndirmeEslesme.kisitMetni` simgeleri) metinlerde (yanıt + dosya adları) geçmeyenleri; en çok 3.
    /// Eşleşme `IndirmeEslesme.uyar` iledir (çekim eki payı; "15" ≠ "1"). Dönen değerler kısıttaki yazılışıyla verilir ("Ayhan", "15").
    static func eksikKisitlar(kisitlar: [String], metinler: [String]) -> [String] {
        let kisitMetni = IndirmeEslesme.kisitMetni(kisitlar)
        var gorunen: [String: String] = [:]
        var istenen: [String] = []
        for w in kisitMetni.split(whereSeparator: \.isWhitespace).map(String.init) {
            let simgeler = IndirmeEslesme.simgeler(w)
            var temiz = w.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
            if let r = temiz.firstIndex(where: { $0 == "'" || $0 == "’" }) { temiz = String(temiz[..<r]) }
            for s in simgeler where !istenen.contains(s) {
                istenen.append(s)
                gorunen[s] = simgeler.count == 1 && !temiz.isEmpty ? temiz : s
            }
        }
        guard !istenen.isEmpty else { return [] }
        let mevcut = IndirmeEslesme.simgeler(metinler.joined(separator: " "))
        let eksik = istenen.filter { i in !mevcut.contains { IndirmeEslesme.uyar(i, $0) } }
        return eksik.prefix(3).map { gorunen[$0] ?? $0 }
    }

    /// Yanıt balonuna bağlanan dosya/indirme eklerinin adları; dosya ya da indirme eki yoksa nil (denetim yapılmaz).
    @MainActor static func ekAdlari(_ ekler: [MesajEki], kayitlar: [IndirmeKaydi]) -> [String]? {
        var adlar: [String] = []
        var dosyaVar = false
        for e in ekler {
            switch e.tur {
            case .dosya(let url, let ad):
                dosyaVar = true
                adlar += [ad, url.lastPathComponent]
            case .indirme(let id):
                dosyaVar = true
                if let k = kayitlar.first(where: { $0.id == id }) {
                    adlar.append(k.ad)
                    if let d = k.dosya { adlar.append(URL(fileURLWithPath: d).lastPathComponent) }
                }
            default:
                continue
            }
        }
        return dosyaVar ? adlar : nil
    }

    static func uyusmazlikNotu(_ eksik: [String]) -> String {
        "Uyuşmazlık: istenen \(eksik.joined(separator: ", ")) yanıtta ve dosya adında geçmiyor. Yanlış olabilir."
    }
}

extension Beyin {
    /// Yanıt dosya/indirme eki taşıyorsa ve etkin kısıtların (süzgeç ya da yerel) bir rakamı/özel adı ne yanıtta ne dosya adında
    /// geçiyorsa var olan turuncu kontrol notu satırına "Uyuşmazlık … Yanlış olabilir." eklenir. Cihaz içi (iPhone) model denetlenmez.
    func kisitUyusmazliginiDenetle(_ id: UUID, yanit: String, ekler: [MesajEki]) {
        guard !(aktifModel ?? "").hasPrefix("iPhone"),
              let adlar = KisitDenetimi.ekAdlari(ekler, kayitlar: IndirmeYoneticisi.ortak.kayitlar) else { return }
        let eksik = KisitDenetimi.eksikKisitlar(kisitlar: IstemSuzgeci.etkinKisitlar, metinler: [yanit] + adlar)
        guard !eksik.isEmpty else { return }
        kontrolNotuEkle(id, KisitDenetimi.uyusmazlikNotu(eksik))
    }
}
