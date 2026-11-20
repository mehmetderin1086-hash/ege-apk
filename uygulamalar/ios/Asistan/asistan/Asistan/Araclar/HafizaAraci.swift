import Foundation
import FoundationModels

nonisolated struct HafizaAraci: Tool {
    let name = "hafiza"
    let description = "Kullanıcı hakkında kalıcı olguları kaydeder ('hatirla'; kategori ve önem verilebilir), siler ('unut'), listeler ('listele') ya da hafızada VE geçmiş sohbetlerde anlamca arar ('ara'). Tercihler, isimler, adresler, alışkanlıklar gibi sonraki sohbetlerde işe yarayacak bilgiler için."

    @Generable
    struct Arguments {
        @Guide(description: "'hatirla', 'unut', 'listele' ya da 'ara'") var islem: String
        @Guide(description: "hatirla: tek cümlelik olgu; unut: silinecek olgunun tam metni ya da ayırt edici bir parçası (birden çok olguya uyarsa hiçbiri silinmez); ara: aranan konu") var metin: String?
        @Guide(description: "hatirla için kategori: kisi, tercih, yer, is, saglik, tarih, proje, diger") var kategori: String?
        @Guide(description: "hatirla için önem 1-5 (5 çok önemli, 3 genel)") var onem: Int?
    }

    let depo: HafizaDeposu
    /// Dış kaynaklı ya da güvenilmeyen içerik okunmuş turda kayıt/silme sorulur (kullanıcının kendi komutunda soru yok).
    var onay: OnayKapisi? = nil

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.lowercased()
        if let onay, islem == "hatirla" || islem == "unut", let m = a.metin, !m.isEmpty {
            let izin = await onay.disKaynaktaIste(baslik: islem == "hatirla" ? "Hafızaya kaydedilsin mi?" : "Hafızadan silinsin mi?",
                                                  ayrinti: String(m.prefix(300)))
            guard izin else { return "Kullanıcı onaylamadı; hafıza değişmedi." }
        }
        if islem == "ara" {
            guard let m = a.metin, !m.isEmpty else { return "Ne aranacak?" }
            return await Self.araYaniti(depo: depo, m)
        }
        return await MainActor.run {
            switch a.islem.lowercased() {
            case "hatirla":
                guard let m = a.metin, !m.isEmpty else { return "Kaydedilecek metin yok." }
                let k = a.kategori.flatMap { OlguKategorisi(rawValue: $0.lowercased()) }
                let onceki = Set(depo.olgular().map(\.kimlik))
                guard let o = depo.hatirlaZengin(m, kaynak: "asistan", kategori: k, onem: a.onem.map { min(5, max(1, $0)) }) else { return "Kaydedilemedi (boş ya da çok uzun)." }
                if o.durum == OlguDurumu.celiski {
                    return "Bu bilgi kullanıcının daha önce verdiği bilgiyle çelişiyor; eskisi korundu. Hangisinin doğru olduğunu kullanıcı sohbet ekranındaki onay çipinden seçecek: \(o.metin)"
                }
                if o.durum == OlguDurumu.bekliyor { return "Kaydedildi, kullanıcı onaylayınca kullanılacak: \(o.metin)" }
                return onceki.contains(o.kimlik) ? "Hafızadaki benzer olgu güncellendi: \(o.metin)" : "Hatırlandı: \(o.metin)"
            case "unut":
                guard let m = a.metin, !m.isEmpty else { return "Neyi unutayım? Bir parça ver." }
                switch depo.unutTekil(m) {
                case .silindi(let metin): return "Silindi: \(metin)"
                case .cokEslesme(let l):
                    return "'\(m)' \(l.count) olguya uyuyor; hiçbirini silmedim. Kullanıcıya hangisi olduğunu sor, sonra o olgunun tam metniyle tekrar 'unut' çağır:\n"
                        + l.prefix(10).map { "• \($0)" }.joined(separator: "\n")
                case .sabitKorundu: return "Bu olgu sabitlenmiş; silmek için Hafıza ekranından sabitlemeyi kaldır."
                case .kaydedilemedi: return "Silme kaydedilemedi; olgu yerinde duruyor."
                case .yok: return "'\(m)' ile eşleşen olgu yok (en az 3 harflik bir parça gerekir)."
                }
            default:
                let l = depo.olgular()
                return l.isEmpty ? "Hafızada olgu yok." : l.map { o in
                    let durum = o.durum == OlguDurumu.bekliyor ? " (onay bekliyor)" : o.durum == OlguDurumu.celiski ? " (çelişiyor, onay bekliyor)" : ""
                    return "• \(o.kategori.flatMap(OlguKategorisi.init(rawValue:)).map { "[\($0.ad)] " } ?? "")\(o.metin)\(durum)"
                }.joined(separator: "\n")
            }
        }
    }

    /// 'ara': hafıza + geçmiş sohbetler; anlamsal hafıza açıksa BM25 + bge-m3 (RRF). Talimattaki olgular da döner (araç
    /// sonucu talimattan bağımsız okunur).
    @MainActor static func araYaniti(depo: HafizaDeposu, _ m: String) async -> String {
        let g = await depo.geriCagirMelez(m, olguAdet: 8, gecmisAdet: 5, isaretle: false, talimattakileriDus: false)
        if g.bos { return "Hafızada ve geçmiş sohbetlerde '\(m)' ile ilgili bir şey bulunamadı." }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM yyyy"
        return (g.olgular.isEmpty ? "" : "Olgular:\n" + g.olgular.map { "• \($0.metin)" }.joined(separator: "\n") + "\n")
            + (g.parcalar.isEmpty ? "" : "Geçmiş sohbetlerden:\n" + g.parcalar.map { "• (\(f.string(from: $0.zaman))) \(String($0.metin.prefix(260)))" }.joined(separator: "\n"))
    }
}
