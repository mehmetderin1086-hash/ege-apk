import Foundation
import FoundationModels
import UIKit

/// P2.12: pdfIslem kaynak kimliklerini dosya yollarına çözer.
/// "ek:<uuid>" → sohbete eklenen/paylaşılan PDF'nin kopyası (BelgeOkuyucu.ekKlasoru);
/// "indirme:<uuid>" ya da çıplak uuid → İndirmeler kaydı; "gorsel:son" → son gönderilen fotoğraflar/taranmış sayfalar.
nonisolated enum PdfKaynaklari {
    nonisolated enum Hata: LocalizedError, Equatable {
        case bulunamadi(String), klasorDisi(String), tur(String), bos
        var errorDescription: String? {
            switch self {
            case .bulunamadi(let k): "Kaynak bulunamadı: \(k). Kimlik uydurma; indirmeler aracıyla 'listele' de ya da dosyayı + ile ekle."
            case .klasorDisi(let k): "Kaynak izin verilen klasörün dışında: \(k)."
            case .tur(let k): "Kaynak PDF ya da görsel değil: \(k)."
            case .bos: "Kaynak verilmedi. Mesajdaki 'Dosya kimliği: ek:…' değerini, indirme kimliğini ya da 'gorsel:son' ver; indirmeler aracıyla 'listele' de ya da dosyayı + ile ekle."
            }
        }
    }

    static let gorselUzantilari: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif"]

    /// Virgüllü kimlik listesini sırayla çözer.
    static func coz(liste: String, indirmeler: [IndirmeKaydi], indirmeKlasoru: URL = URL(fileURLWithPath: IndirmeYoneticisi.klasorYolu, isDirectory: true)) throws -> [PdfIslemci.Kaynak] {
        let kimlikler = liste.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !kimlikler.isEmpty else { throw Hata.bos }
        return try kimlikler.flatMap { try coz($0, indirmeler: indirmeler, indirmeKlasoru: indirmeKlasoru) }
    }

    static func coz(_ kimlik: String, indirmeler: [IndirmeKaydi], indirmeKlasoru: URL = URL(fileURLWithPath: IndirmeYoneticisi.klasorYolu, isDirectory: true)) throws -> [PdfIslemci.Kaynak] {
        let k = kimlik.trimmingCharacters(in: .whitespacesAndNewlines)
        let kucuk = k.lowercased()
        if kucuk.hasPrefix(BelgeOkuyucu.ekOneki) {
            let uuid = String(k.dropFirst(BelgeOkuyucu.ekOneki.count))
            guard let u = BelgeOkuyucu.ekDosyasi(uuid) else { throw Hata.bulunamadi(k) }
            return [try kaynak(u, kimlik: k)]
        }
        if kucuk == "gorsel:son" || kucuk == "görsel:son" {
            let adlar = EkKalici.sonKaydedilenler
            guard !adlar.isEmpty else { throw Hata.bulunamadi(k) }
            let kok = EkKalici.gorselKlasoru.standardizedFileURL
            return try adlar.map { ad in
                let u = kok.appendingPathComponent(ad).standardizedFileURL
                guard u.deletingLastPathComponent().path == kok.path else { throw Hata.klasorDisi(ad) }
                guard FileManager.default.fileExists(atPath: u.path) else { throw Hata.bulunamadi(k) }
                return .gorsel(u)
            }
        }
        let ham = kucuk.hasPrefix("indirme:") ? String(k.dropFirst("indirme:".count)) : k
        guard let id = UUID(uuidString: ham.trimmingCharacters(in: .whitespaces)),
              let kayit = indirmeler.first(where: { $0.id == id }), let dosya = kayit.dosya, !dosya.isEmpty else { throw Hata.bulunamadi(k) }
        let kok = indirmeKlasoru.standardizedFileURL
        let u = kok.appendingPathComponent(dosya).standardizedFileURL
        // "../" ya da alt klasör kaçışı: dosya doğrudan İndirmeler klasöründe olmalı.
        guard u.deletingLastPathComponent().path == kok.path else { throw Hata.klasorDisi(k) }
        guard FileManager.default.fileExists(atPath: u.path) else { throw Hata.bulunamadi(k) }
        return [try kaynak(u, kimlik: k)]
    }

    private static func kaynak(_ u: URL, kimlik: String) throws -> PdfIslemci.Kaynak {
        let uzanti = u.pathExtension.lowercased()
        if uzanti == "pdf" { return .pdf(u) }
        if gorselUzantilari.contains(uzanti) { return .gorsel(u) }
        throw Hata.tur(kimlik)
    }

    /// Kopya/indirme adındaki "<uuid>-" önekini atar ("3F…-Ödev.pdf" → "Ödev").
    static func gorunenAd(_ u: URL) -> String {
        var ad = u.deletingPathExtension().lastPathComponent
        if ad.count > 37, UUID(uuidString: String(ad.prefix(36))) != nil, ad.dropFirst(36).first == "-" { ad = String(ad.dropFirst(37)) }
        return ad.isEmpty ? "Belge" : ad
    }
}

/// P2.12: Var olan PDF'yi birleştir, böl, döndür, küçült, form doldur, imzala. Çıktı her zaman yeni bir dosyadır (İndirmeler).
@MainActor struct PdfAraci: Tool {
    let name = "pdfIslem"
    let description = "Var olan PDF'ler üzerinde iş yapar: birleştir (PDF ve görseller), böl/sayfa ayır, döndür, sıkıştır/küçült, form alanlarını listele ve doldur, kayıtlı imzayı ekle (önizleme onayıyla), bilgi. Özgün dosyayı değiştirmez; sonuç yeni bir PDF dosyasıdır."
    @Generable nonisolated struct Arguments {
        @Guide(description: "birlestir, bol, dondur, sikistir, alanlar, doldur, imzala veya bilgi") var islem: String
        @Guide(description: "Virgüllü kaynak kimlikleri: mesajdaki 'ek:…', indirme kimliği 'indirme:…' ya da son fotoğraflar/taranmış sayfalar için 'gorsel:son'. Kimlik uydurma.") var kaynaklar: String
        @Guide(description: "Sayfalar (1 tabanlı): '1-3,5'; bol için ';' ayrı dosya demektir ('1-2;3-5'). dondur'da boşsa bütün sayfalar; imzala'da tek sayfa, boşsa son sayfa.") var sayfalar: String?
        @Guide(description: "dondur: 90, 180, 270 ya da -90") var derece: Int?
        @Guide(description: "doldur: düz JSON nesnesi, alan adı → değer (örn. {\"ad\":\"Ali\",\"onay\":\"evet\"}); alan adları için önce 'alanlar'") var degerlerJSON: String?
        @Guide(description: "imzala: sagAlt, solAlt, ortaAlt veya sagUst (varsayılan sagAlt)") var konum: String?
        @Guide(description: "sikistir: hedef boyut MB; 0 ya da boş = hedef yok") var hedefMB: Double?
        @Guide(description: "Çıktı dosya adı (isteğe bağlı, uzantısız)") var dosyaAdi: String?
    }
    let onay: OnayKapisi
    /// İmza görüntüsü; testler gerçek imza dosyasına dokunmadan bellekte üretilen görüntü verir.
    var imzaSaglayici: @Sendable () -> CGImage? = { ImzaDeposu.yukle() }

    /// Ağır işin Sendable sonucu.
    private nonisolated enum Sonuc: Sendable {
        case dosyalar([(veri: Data, ad: String, sayfa: Int)], not: String)
        case metin(String)
    }

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["birlestir", "bol", "dondur", "sikistir", "alanlar", "doldur", "imzala", "bilgi"].contains(islem) else {
            return "İşlem geçersiz. Şunlardan biri: birlestir, bol, dondur, sikistir, alanlar, doldur, imzala, bilgi."
        }
        let kaynaklar: [PdfIslemci.Kaynak]
        do { kaynaklar = try PdfKaynaklari.coz(liste: a.kaynaklar, indirmeler: IndirmeYoneticisi.ortak.kayitlar) }
        catch { return error.localizedDescription }
        let pdfler = kaynaklar.compactMap { if case .pdf(let u) = $0 { u } else { nil } }
        if islem != "birlestir", pdfler.isEmpty { return "Bu işlem için bir PDF kaynağı gerekli. Görselleri PDF yapmak için 'birlestir' kullan." }
        let ilk = pdfler.first
        let temelAd = (a.dosyaAdi?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? ilk.map(PdfKaynaklari.gorunenAd) ?? "Belge"
        if islem == "imzala" { return await imzala(a, kaynak: ilk!, temelAd: temelAd) }

        let sayfalar = a.sayfalar?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let derece = a.derece ?? 90
        let degerler = Self.degerler(a.degerlerJSON)
        let hedefMB = a.hedefMB
        let ozelAd = a.dosyaAdi?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        do {
            let sonuc: Sonuc = try await Task.detached(priority: .userInitiated) { () throws -> Sonuc in
                try Self.isle(islem, kaynaklar: kaynaklar, ilk: ilk, sayfalar: sayfalar, derece: derece, degerler: degerler,
                              hedefMB: hedefMB, temelAd: temelAd, ozelAd: ozelAd)
            }.value
            try Task.checkCancellation()
            switch sonuc {
            case .metin(let m): return m
            case .dosyalar(let d, let not):
                var satirlar: [String] = []
                for c in d {
                    let (url, kimlik) = try kaydet(c.veri, ad: c.ad)
                    satirlar.append("Yeni dosya: \(url.lastPathComponent.dropFirst(37)) (\(c.sayfa) sayfa, \(Self.mb(c.veri.count)) MB)." + (kimlik.map { " Kimlik: indirme:\($0.uuidString)." } ?? ""))
                }
                return (satirlar + [not, "Özgün dosya değiştirilmedi."]).filter { !$0.isEmpty }.joined(separator: "\n")
            }
        } catch is CancellationError {
            return "İşlem iptal edildi; dosya oluşturulmadı."
        } catch {
            return "PDF işlemi yapılamadı: \(error.localizedDescription)"
        }
    }

    // MARK: Ağır iş (ana iş parçacığı dışında)

    private nonisolated static func isle(_ islem: String, kaynaklar: [PdfIslemci.Kaynak], ilk: URL?, sayfalar: String, derece: Int,
                                         degerler: [String: String]?, hedefMB: Double?, temelAd: String, ozelAd: Bool) throws -> Sonuc {
        func ad(_ ek: String) -> String { ozelAd ? temelAd : temelAd + ek }
        switch islem {
        case "birlestir":
            let d = try PdfIslemci.birlestir(kaynaklar)
            guard let v = d.dataRepresentation() else { throw PdfIslemci.Hata.okunamadi }
            return .dosyalar([(v, ad(kaynaklar.count > 1 ? "-birlesik" : ""), d.pageCount)], not: "")
        case "bol":
            let d = try PdfIslemci.ac(ilk!)
            guard !sayfalar.isEmpty else { return .metin("bol için sayfa aralığı gerekli (örn. '1-2;3-5' iki dosya, '4' tek sayfa). PDF \(d.pageCount) sayfa.") }
            let gruplar = try PdfIslemci.araliklar(sayfalar, sayfaSayisi: d.pageCount)
            guard gruplar.count <= 20 else { throw PdfIslemci.Hata.aralik("en çok 20 ayrı dosya") }
            let parcalar = PdfIslemci.bol(d, gruplar: gruplar)
            var dosyalar: [(veri: Data, ad: String, sayfa: Int)] = []
            for (i, p) in parcalar.enumerated() {
                guard let v = p.dataRepresentation() else { continue }
                dosyalar.append((v, gruplar.count > 1 ? temelAd + "-bolum\(i + 1)" : ad("-sayfalar"), p.pageCount))
            }
            return .dosyalar(dosyalar, not: "")
        case "dondur":
            let d = try PdfIslemci.ac(ilk!)
            var secili: [Int]?
            if !sayfalar.isEmpty { secili = try PdfIslemci.araliklar(sayfalar, sayfaSayisi: d.pageCount).flatMap { $0 } }
            try PdfIslemci.dondur(d, sayfalar: secili, derece: derece)
            guard let v = d.dataRepresentation() else { throw PdfIslemci.Hata.okunamadi }
            return .dosyalar([(v, ad("-donduruldu"), d.pageCount)], not: "")
        case "sikistir":
            let (v, not) = try PdfIslemci.sikistir(ilk!, hedefMB: hedefMB)
            let ozgun = (try? ilk!.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sayfa = PDFDocumentSayac.sayfa(v)
            return .dosyalar([(v, ad("-kucuk"), sayfa)], not: "Özgün \(mb(ozgun)) MB → \(mb(v.count)) MB. " + not)
        case "alanlar":
            let d = try PdfIslemci.ac(ilk!)
            let alanlar = PdfIslemci.alanlar(d)
            guard !alanlar.isEmpty else { return .metin(PdfIslemci.Hata.alanYok([]).errorDescription ?? "") }
            let satirlar = alanlar.prefix(80).map { "- \($0.ad) (\($0.tur), sayfa \($0.sayfa))" + ($0.deger.isEmpty ? "" : ": \($0.deger)") }
            return .metin("Form alanları (\(alanlar.count)):\n" + satirlar.joined(separator: "\n") + "\nDoldurmak için islem 'doldur', degerlerJSON alan adı → değer.")
        case "doldur":
            guard let degerler, !degerler.isEmpty else { return .metin("degerlerJSON düz bir JSON nesnesi olmalı (alan adı → değer). Alan adları için önce islem 'alanlar'.") }
            let d = try PdfIslemci.ac(ilk!)
            let alanlar = PdfIslemci.alanlar(d)
            guard !alanlar.isEmpty else { throw PdfIslemci.Hata.alanYok([]) }
            let (dolan, bulunamayan) = PdfIslemci.doldur(d, degerler)
            guard dolan > 0 else { throw PdfIslemci.Hata.alanYok(bulunamayan) }
            guard let v = d.dataRepresentation() else { throw PdfIslemci.Hata.okunamadi }
            let not = bulunamayan.isEmpty ? "\(dolan) alan dolduruldu." : "\(dolan) alan dolduruldu; bulunamayan: \(bulunamayan.joined(separator: ", "))."
            return .dosyalar([(v, ad("-doldurulmus"), d.pageCount)], not: not)
        default:   // bilgi
            var satirlar: [String] = []
            for u in kaynaklar.compactMap({ if case .pdf(let u) = $0 { u } else { nil } }) {
                let boyut = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                do {
                    let d = try PdfIslemci.ac(u)
                    let metinli = (0..<min(d.pageCount, 5)).contains { (d.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }
                    satirlar.append("\(PdfKaynaklari.gorunenAd(u)): \(d.pageCount) sayfa, \(mb(boyut)) MB, form alanı \(PdfIslemci.alanlar(d).count), " + (metinli ? "metin katmanı var" : "metin katmanı yok (taranmış olabilir)"))
                } catch {
                    satirlar.append("\(PdfKaynaklari.gorunenAd(u)): \(error.localizedDescription)")
                }
            }
            return .metin(satirlar.joined(separator: "\n"))
        }
    }

    // MARK: İmza (her kullanımda zorunlu önizleme onayı)

    private func imzala(_ a: Arguments, kaynak: URL, temelAd: String) async -> String {
        guard let imza = imzaSaglayici() else { return PdfIslemci.Hata.imzaYok.errorDescription ?? "" }
        let konum = PdfIslemci.ImzaKonumu.coz(a.konum)
        let sayfaMetni = a.sayfalar?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hazir: (veri: Data, png: Data?, sayfa: Int, toplam: Int)
        do {
            hazir = try await Task.detached(priority: .userInitiated) { () throws -> (veri: Data, png: Data?, sayfa: Int, toplam: Int) in
                let d = try PdfIslemci.ac(kaynak)
                let sayfa: Int
                if sayfaMetni.isEmpty { sayfa = max(0, d.pageCount - 1) }
                else {
                    let g = try PdfIslemci.araliklar(sayfaMetni, sayfaSayisi: d.pageCount).flatMap { $0 }
                    guard g.count == 1 else { throw PdfIslemci.Hata.aralik("imza için tek sayfa ver") }
                    sayfa = g[0]
                }
                let veri = try PdfIslemci.imzala(d, imza: imza, sayfa: sayfa, konum: konum)
                let png = PdfIslemci.onizleme(veri, sayfa: sayfa).flatMap { UIImage(cgImage: $0).pngData() }
                return (veri, png, sayfa, d.pageCount)
            }.value
        } catch {
            return "İmza eklenemedi: \(error.localizedDescription)"
        }
        let ad = temelAd + (a.dosyaAdi?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "" : "-imzali")
        var onizleme: URL?
        if let png = hazir.png {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("imza-onizleme-\(UUID().uuidString).png")
            if (try? png.write(to: u, options: .atomic)) != nil { onizleme = u }
        }
        defer { if let onizleme { try? FileManager.default.removeItem(at: onizleme) } }
        // Kullanıcı kararı (doğrudan komutta onay yok) imzaya uygulanmaz: imza geri alınamaz, her kullanımda önizlemeyle sorulur.
        let onaylandi = await onay.iste(baslik: "İmza eklensin mi?",
                                        ayrinti: "\(PdfKaynaklari.gorunenAd(kaynak)) · sayfa \(hazir.sayfa + 1)/\(hazir.toplam) · \(konum.gorunenAd)",
                                        zorunlu: true, onizleme: onizleme)
        guard onaylandi, !Task.isCancelled else { return "Kullanıcı imzayı onaylamadı; dosya oluşturulmadı." }
        do {
            let (url, kimlik) = try kaydet(hazir.veri, ad: ad)
            return "Yeni dosya: \(url.lastPathComponent.dropFirst(37)) (\(hazir.toplam) sayfa, \(Self.mb(hazir.veri.count)) MB). İmza sayfa \(hazir.sayfa + 1)'e eklendi." +
                (kimlik.map { " Kimlik: indirme:\($0.uuidString)." } ?? "") + " Özgün dosya değiştirilmedi."
        } catch {
            return "İmzalı dosya kaydedilemedi: \(error.localizedDescription)"
        }
    }

    // MARK: Kayıt

    /// İndirmeler/<uuid>-<ad>.pdf; İndirmeler listesine ve sohbete dosya kartı olarak eklenir. Dönen kimlik İndirmeler kaydıdır.
    func kaydet(_ veri: Data, ad: String) throws -> (URL, UUID?) {
        var dosyaAdi = IndirmeYoneticisi.dosyaAdi(ad)
        if !dosyaAdi.lowercased().hasSuffix(".pdf") { dosyaAdi += ".pdf" }
        try FileManager.default.createDirectory(at: IndirmeYoneticisi.klasor, withIntermediateDirectories: true)
        let url = IndirmeYoneticisi.klasor.appending(path: UUID().uuidString + "-" + dosyaAdi)
        try veri.write(to: url, options: .atomic)
        IndirmeYoneticisi.ortak.yerelDosyaEkle(url: url, gorunenAd: dosyaAdi)
        let kimlik = IndirmeYoneticisi.ortak.kayitlar.first { $0.dosya == url.lastPathComponent }?.id
        EkDefteri.ortak.ekle(MesajEki(tur: .dosya(url: url, ad: dosyaAdi)))
        return (url, kimlik)
    }

    // MARK: Yardımcılar

    /// Düz JSON nesnesi → [alan: değer]; sayı/mantıksal değerler metne çevrilir. Geçersizse nil.
    nonisolated static func degerler(_ json: String?) -> [String: String]? {
        guard let json, let v = json.data(using: .utf8),
              let nesne = try? JSONSerialization.jsonObject(with: v) as? [String: Any] else { return nil }
        var sonuc: [String: String] = [:]
        for (k, d) in nesne {
            switch d {
            case let s as String: sonuc[k] = s
            case let n as NSNumber: sonuc[k] = CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "evet" : "hayır") : n.stringValue
            default: continue
            }
        }
        return sonuc
    }

    nonisolated static func mb(_ bayt: Int) -> String {
        (Double(bayt) / 1_048_576).formatted(.number.precision(.fractionLength(bayt < 1_048_576 ? 2 : 1)).locale(Locale(identifier: "tr_TR")))
    }
}

/// Sıkıştırılmış verinin sayfa sayısı (ayrı belge açmadan raporlamak için küçük yardımcı).
nonisolated enum PDFDocumentSayac {
    static func sayfa(_ veri: Data) -> Int { (try? PdfIslemci.ac(veri))?.pageCount ?? 0 }
}
