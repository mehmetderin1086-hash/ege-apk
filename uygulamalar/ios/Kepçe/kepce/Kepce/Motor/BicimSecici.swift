import Foundation
import VideoToolbox

nonisolated enum IndirmeTuru: String, Codable, Sendable, CaseIterable, Identifiable {
    case video, ses, ham
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .video: "Video"
        case .ses: "Ses"
        case .ham: "Özgün dosya"
        }
    }
}

/// Neyin indirileceği: bir video akışı, bir ses akışı (ya da ikisi birden) ve çıkış biçimi.
nonisolated struct IndirmePlani: Codable, Sendable, Hashable {
    var video: Bicim?
    var ses: Bicim?
    var tur: IndirmeTuru
    var uzanti: String
    var etiket: String
    var tahminiBoyut: Int64?
}

nonisolated struct KaliteSecenegi: Sendable, Hashable, Identifiable {
    var id: String
    var yukseklik: Int
    var fps: Int
    var video: Bicim
    var etiket: String
    var ayrinti: String
}

/// iPhone'da oynatılabilen biçimleri seçer: H.264/HEVC (donanım destekliyse AV1) + AAC, MP4 kabında.
/// VP9/WebM/Opus Apple'ın çerçevelerinde birleştirilemez; bunlar yalnız "Özgün dosya" ile indirilir.
nonisolated enum BicimSecici {
    static let av1Donanim: Bool = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    static let hevcDonanim: Bool = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)

    static let mp4Kaplari: Set<String> = ["mp4", "m4v", "mov", "m4a", "3gp"]

    static func protokolUygun(_ b: Bicim) -> Bool {
        guard b.url != nil || b.parcali else { return false }
        let p = (b.protokol ?? "https").lowercased()
        return p.hasPrefix("http") || p.hasPrefix("m3u8") || p.contains("dash")
    }

    static func videoKodegiUygun(_ b: Bicim, av1: Bool = av1Donanim) -> Bool {
        switch b.videoKodegi {
        case "avc1": true
        case "hvc1": hevcDonanim
        case "av01": av1
        default: false
        }
    }

    static func sesKodegiBirlesir(_ b: Bicim) -> Bool { ["aac", "ac3", "eac3"].contains(b.sesKodegi) }

    /// Yalnız video içeren (ya da sesli tek dosya), iPhone'da birleştirilebilir akış.
    static func oynatilabilirVideo(_ b: Bicim, av1: Bool = av1Donanim) -> Bool {
        guard b.videoVar, !b.resim, b.hasDRM != true, protokolUygun(b), videoKodegiUygun(b, av1: av1) else { return false }
        if b.sesVar && !sesKodegiBirlesir(b) { return false }
        return mp4Kaplari.contains((b.ext ?? "mp4").lowercased()) || b.hls
    }

    static func oynatilabilirSes(_ b: Bicim) -> Bool {
        guard b.sesVar, !b.videoVar, !b.resim, b.hasDRM != true, protokolUygun(b) else { return false }
        let ext = (b.ext ?? "").lowercased()
        switch b.sesKodegi {
        case "aac", "ac3", "eac3": return ext.isEmpty || mp4Kaplari.contains(ext) || ext == "aac" || b.hls
        case "mp3": return true
        default: return false
        }
    }

    static func kodekAdi(_ kod: String) -> String {
        switch kod {
        case "avc1": "H.264"
        case "hvc1": "HEVC"
        case "av01": "AV1"
        case "vp9": "VP9"
        case "aac": "AAC"
        case "mp3": "MP3"
        case "opus": "Opus"
        default: kod.uppercased()
        }
    }

    private static func kodekSirasi(_ kod: String) -> Int {
        switch kod {
        case "avc1": 0
        case "hvc1": 1
        case "av01": 2
        default: 3
        }
    }

    private static func protokolSirasi(_ b: Bicim) -> Int { b.dogrudan ? 0 : (b.parcali ? 1 : 2) }

    /// Her (yükseklik, kare hızı) için en uygun video akışı; yüksekten düşüğe.
    static func kaliteler(_ bilgi: MedyaBilgisi, av1: Bool = av1Donanim) -> [KaliteSecenegi] {
        let adaylar = (bilgi.formats ?? []).filter { oynatilabilirVideo($0, av1: av1) && ($0.height ?? 0) > 0 }
        var gruplar: [String: [Bicim]] = [:]
        for b in adaylar {
            let fps = (b.fps ?? 30) >= 49 ? 60 : 30
            gruplar["\(b.height ?? 0)p\(fps == 60 ? "60" : "")", default: []].append(b)
        }
        return gruplar.compactMap { anahtar, liste -> KaliteSecenegi? in
            // Önce sessiz (ayrı) akışlar: daha yüksek bit hızlı; sonra kodek uyumu, protokol, bit hızı.
            let sirali = liste.sorted { a, b in
                if a.sesVar != b.sesVar { return !a.sesVar }
                if kodekSirasi(a.videoKodegi) != kodekSirasi(b.videoKodegi) { return kodekSirasi(a.videoKodegi) < kodekSirasi(b.videoKodegi) }
                if (a.dynamicRange ?? "SDR") != (b.dynamicRange ?? "SDR") { return (a.dynamicRange ?? "SDR") == "SDR" }
                if protokolSirasi(a) != protokolSirasi(b) { return protokolSirasi(a) < protokolSirasi(b) }
                return (a.tbr ?? 0) > (b.tbr ?? 0)
            }
            guard let en = sirali.first else { return nil }
            let fps = (en.fps ?? 30) >= 49 ? 60 : 30
            var ayrinti = [kodekAdi(en.videoKodegi)]
            if let aralik = en.dynamicRange, aralik != "SDR" { ayrinti.append(aralik) }
            if en.sesVar { ayrinti.append("tek dosya") }
            return KaliteSecenegi(id: anahtar, yukseklik: en.height ?? 0, fps: fps, video: en, etiket: anahtar, ayrinti: ayrinti.joined(separator: " · "))
        }
        .sorted { ($0.yukseklik, $0.fps) > ($1.yukseklik, $1.fps) }
    }

    /// Birleştirilebilir ses akışları: dil tercihi, sonra bit hızı; aynı bit hızında DRC'siz (ses sıkıştırmasız) olan önce.
    static func sesler(_ bilgi: MedyaBilgisi, dil: String? = nil) -> [Bicim] {
        let adaylar = (bilgi.formats ?? []).filter(oynatilabilirSes)
        return adaylar.sorted { a, b in
            if let dil {
                let ad = a.language?.hasPrefix(dil) == true, bd = b.language?.hasPrefix(dil) == true
                if ad != bd { return ad }
            }
            if (a.languagePreference ?? 0) != (b.languagePreference ?? 0) { return (a.languagePreference ?? 0) > (b.languagePreference ?? 0) }
            let (ah, bh) = ((a.abr ?? a.tbr ?? 0).rounded(), (b.abr ?? b.tbr ?? 0).rounded())
            if abs(ah - bh) > 2 { return ah > bh }
            if a.drc != b.drc { return !a.drc }
            if (a.sesKodegi == "aac") != (b.sesKodegi == "aac") { return a.sesKodegi == "aac" }
            return protokolSirasi(a) < protokolSirasi(b)
        }
    }

    /// Birden çok ses dili varsa (YouTube çok dilli seslendirme) dil kodları; asıl dil başta.
    static func diller(_ bilgi: MedyaBilgisi) -> [String] {
        var gorulen: [String] = []
        for b in sesler(bilgi) {
            guard let dil = b.language, !gorulen.contains(dil) else { continue }
            gorulen.append(dil)
        }
        return gorulen.count > 1 ? gorulen : []
    }

    /// Kullanıcının seçimine göre indirme planı. `enFazla`: en yüksek çözünürlük (0 = sınırsız).
    static func plan(_ bilgi: MedyaBilgisi, tur: IndirmeTuru, enFazla: Int = 0, kaliteID: String? = nil, sesID: String? = nil,
                     dil: String? = nil, av1: Bool = av1Donanim) -> IndirmePlani? {
        let sure = bilgi.duration
        let sesListesi = sesler(bilgi, dil: dil)
        let secilenSes = sesID.flatMap { id in sesListesi.first { $0.formatID == id } } ?? sesListesi.first

        switch tur {
        case .video:
            let liste = kaliteler(bilgi, av1: av1)
            let secilen: KaliteSecenegi? = if let kaliteID, let k = liste.first(where: { $0.id == kaliteID }) { k }
                else if enFazla > 0 { liste.first { $0.yukseklik <= enFazla } ?? liste.last }
                else { liste.first }
            guard let secilen else { return nil }
            let ses = secilen.video.sesVar ? nil : secilenSes
            if !secilen.video.sesVar && ses == nil {
                // Ses akışı yoksa sesli tek dosyaya dön (varsa).
                if let tek = liste.first(where: { $0.video.sesVar && (enFazla == 0 || $0.yukseklik <= enFazla) }) {
                    return IndirmePlani(video: tek.video, ses: nil, tur: .video, uzanti: "mp4", etiket: "\(tek.etiket) · \(tek.ayrinti)",
                                        tahminiBoyut: tek.video.boyut(sure: sure))
                }
            }
            let boyut = [secilen.video.boyut(sure: sure), ses?.boyut(sure: sure)].compactMap { $0 }.reduce(0, +)
            let sessiz = !secilen.video.sesVar && ses == nil ? " · sessiz" : ""
            return IndirmePlani(video: secilen.video, ses: ses, tur: .video, uzanti: "mp4", etiket: "\(secilen.etiket) · \(secilen.ayrinti)\(sessiz)",
                                tahminiBoyut: boyut > 0 ? boyut : nil)

        case .ses:
            if let ses = secilenSes {
                let mp3 = ses.sesKodegi == "mp3"
                let kbps = (ses.abr ?? ses.tbr).map { " · \(Int($0.rounded())) kb/sn" } ?? ""
                return IndirmePlani(video: nil, ses: ses, tur: .ses, uzanti: mp3 ? "mp3" : "m4a",
                                    etiket: "\(kodekAdi(ses.sesKodegi))\(kbps)", tahminiBoyut: ses.boyut(sure: sure))
            }
            // Yalnız sesli video dosyası varsa: indirip ses izini ayırırız.
            if let tek = kaliteler(bilgi, av1: av1).filter({ $0.video.sesVar }).last {
                return IndirmePlani(video: tek.video, ses: nil, tur: .ses, uzanti: "m4a", etiket: "AAC (videodan)", tahminiBoyut: tek.video.boyut(sure: sure))
            }
            return nil

        case .ham:
            let bicimler = (bilgi.formats ?? []).filter { !$0.resim && $0.hasDRM != true && protokolUygun($0) }
            // yt-dlp biçimleri kötüden iyiye sıralar: önce sesli videoların en iyisi.
            // Sesli tek dosya yoksa (YouTube'da çoğu zaman) özgün dosya sessiz bir akış olurdu: birleştirilmiş videoya dön.
            guard let en = bicimler.last(where: { $0.videoVar && $0.sesVar }) else {
                if let video = plan(bilgi, tur: .video, enFazla: enFazla, av1: av1) { return video }
                guard let tek = bicimler.last(where: \.dogrudan) ?? bicimler.last else { return nil }
                return IndirmePlani(video: tek.videoVar ? tek : nil, ses: tek.videoVar ? nil : tek, tur: .ham, uzanti: (tek.ext ?? "bin").lowercased(),
                                    etiket: [tek.height.map { "\($0)p" }, tek.ext?.uppercased()].compactMap { $0 }.joined(separator: " · "),
                                    tahminiBoyut: tek.boyut(sure: sure))
            }
            let ext = (en.ext ?? "bin").lowercased()
            let etiket = [en.height.map { "\($0)p" }, en.videoVar ? kodekAdi(en.videoKodegi) : nil, en.sesVar ? kodekAdi(en.sesKodegi) : nil, ext.uppercased()]
                .compactMap { $0 }.joined(separator: " · ")
            return IndirmePlani(video: en.videoVar ? en : nil, ses: en.videoVar ? nil : en, tur: .ham, uzanti: ext == "m3u8" ? "ts" : ext,
                                etiket: etiket, tahminiBoyut: en.boyut(sure: sure))
        }
    }

    static func boyutMetni(_ bayt: Int64?) -> String {
        guard let bayt, bayt > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bayt, countStyle: .file)
    }

    static func sureMetni(_ saniye: Double?) -> String {
        guard let saniye, saniye.isFinite, saniye >= 0 else { return "" }
        let toplam = Int(saniye.rounded())
        let (s, d, sn) = (toplam / 3600, (toplam % 3600) / 60, toplam % 60)
        return s > 0 ? String(format: "%d:%02d:%02d", s, d, sn) : String(format: "%d:%02d", d, sn)
    }
}
