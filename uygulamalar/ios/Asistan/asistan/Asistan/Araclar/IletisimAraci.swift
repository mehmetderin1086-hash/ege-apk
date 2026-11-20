import Foundation
import FoundationModels
import UIKit

nonisolated struct IletisimAraci: Tool {
    let name = "iletisim"
    let description = "Telefon/FaceTime araması başlatır; SMS/iMessage veya WhatsApp için alıcısı ve metni hazır gönderim ekranını açar. Yanıt yazarken kullanıcı mesaj içeriğini paylaşmalı; gelen mesaj kutusunu okuyamaz. Numara bilinmiyorsa kisiler aracını kullan, birden fazla sonuç varsa alıcıyı sor. WhatsApp gönderim kestirmesi bağlıysa istek ona iletilir; yoksa son Gönder adımı kullanıcıdadır. Gelen aramayı cevaplama isteğinde aramaCevapla kullan; kurulum yolunu açıklar."

    @Generable
    struct Arguments {
        @Guide(description: "ara, facetime, mesaj, whatsapp veya aramaCevapla; mesaj ve whatsapp yanıt göndermek için de kullanılır") var islem: String
        @Guide(description: "Telefon numarası, FaceTime için e-posta; aramaCevapla için boş olabilir. WhatsApp ülke koduyla olmalı.") var hedef: String
        @Guide(description: "Gönderilecek/yanıt olarak hazırlanacak metin") var metin: String?
    }
    let onay: OnayKapisi

    func call(arguments a: Arguments) async throws -> String {
        let islem = a.islem.lowercased()
        if islem == "aramacevapla" {
            return "Asistan gelen hücresel/FaceTime aramasını devralamaz. Sesle cevap için Ayarlar > Siri (veya Apple Intelligence ve Siri) > Aramaları Duyur seçeneğini aç; Siri arayanı duyurduğunda yanıt verebilirsin. Otomatik yanıtlama istersen Ayarlar > Erişilebilirlik > Dokunma > Arama Ses Yolu > Aramaları Otomatik Yanıtla yolunu kullan. Bu ayarları değiştirmedim."
        }
        guard let url = Self.adres(islem: islem, hedef: a.hedef, metin: a.metin) else {
            return "İşlem veya alıcı geçersiz. Numara ve ülke kodunu doğrula. WhatsApp için örnek biçim +90 5xx xxx xx xx; numara uydurma."
        }
        if islem == "whatsapp", let mesaj = a.metin,
           let girdi = await UygulamaBaglantilari.whatsappGirdisi(hedef: a.hedef, metin: mesaj),
           let bag = await UygulamaBaglantilari.ortak.kayitlar.first(where: \.whatsapp),
           let kestirmeURL = TelefonAdresleri.kisayol(bag.kestirme, girdi: girdi) {
            // Kestirme mesajı doğrudan gönderir: kullanıcının kendi komutunda sorulmaz, dış kaynaklı turda sorulur.
            guard await onay.disKaynaktaIste(baslik: "WhatsApp mesajı gönderilsin mi: \(a.hedef)", ayrinti: mesaj) else { return "Kullanıcı WhatsApp gönderimini onaylamadı; mesaj gönderilmedi." }
            try Task.checkCancellation()
            let ok = await TelefonAdresleri.ac(kestirmeURL)
            return ok ? "WhatsApp gönderim isteği kayıtlı '\(bag.kestirme)' kestirmesine alıcı ve mesajla iletildi. Gönderim veya teslim doğrulanmadı; kestirme sonucu kontrol edilmeli." : "WhatsApp kestirmesi açılamadı; mesaj gönderilmedi."
        }
        let eylem = ["ara": "Aranacak", "facetime": "FaceTime açılacak", "mesaj": "SMS/iMessage taslağı", "whatsapp": "WhatsApp taslağı"][islem] ?? islem
        // WhatsApp taslağında son Gönder kullanıcıda; yine de dış kaynaklı turda açılmadan sorulur.
        let izin: Bool
        if islem == "whatsapp" { izin = await onay.disKaynaktaIste(baslik: "\(eylem): \(a.hedef)", ayrinti: a.metin ?? "") }
        else { izin = await onay.iste(baslik: "\(eylem): \(a.hedef)", ayrinti: a.metin ?? "") }
        guard izin else {
            return "Kullanıcı \(a.islem) işlemini reddetti."
        }
        try Task.checkCancellation()
        if islem == "mesaj" {
            let s = await MesajTaslagi.ortak.gosterSonuclu(alici: url.path, metin: a.metin ?? "")
            // Kart yalnız sistem mesajı gönderim için kabul ettiyse (iptal/hata/kapatmada yok); SMS geri alınamaz, yalnız Aç.
            if s.gonderildi, let k = Self.kartKaydi(islem: islem, hedef: a.hedef, metin: a.metin, url: url) { await k.kartaEkle() }
            return s.metin
        }
        let acildi = await TelefonAdresleri.ac(url)
        guard acildi else { return "\(eylem) açılamadı. Uygulamanın kurulu olduğunu ve telefon özelliklerinin kullanılabildiğini kontrol et. Mesaj gönderilmedi." }
        if let k = Self.kartKaydi(islem: islem, hedef: a.hedef, metin: a.metin, url: url) { await k.kartaEkle() }
        if islem == "mesaj" || islem == "whatsapp" {
            return "\(eylem) \(a.hedef) için açıldı. Henüz gönderildiği doğrulanmadı; kullanıcı alıcıyı/metni kontrol edip Gönder'e dokunmalı. Gelen mesajları otomatik okuyamam."
        }
        return "\(eylem): \(a.hedef). Telefonun arama ekranı açıldı; görüşmenin bağlandığı doğrulanmadı."
    }

    /// Yalnız Aç düğmeli eylem kartı (iOS arama/mesajı geri almaya izin vermez: kimlik yok).
    /// Aç adresi sorgusuz: yeniden açınca aynı metin ikinci kez taslağa dolmaz.
    static func kartKaydi(islem: String, hedef: String, metin: String?, url: URL) -> EylemKaydi? {
        let tur: EylemKaydi.Tur
        let baslik: String, ozet: String
        let kisaMetin = (metin ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
        switch islem {
        case "ara": tur = .arama; baslik = "Arama: \(hedef)"; ozet = "Arama ekranı açıldı"
        case "facetime": tur = .arama; baslik = "FaceTime: \(hedef)"; ozet = "FaceTime açıldı"
        case "mesaj": tur = .mesaj; baslik = "Mesaj gönderildi: \(hedef)"; ozet = kisaMetin.isEmpty ? "SMS/iMessage" : String(kisaMetin)
        case "whatsapp": tur = .whatsapp; baslik = "WhatsApp taslağı: \(hedef)"; ozet = kisaMetin.isEmpty ? "Taslak açıldı; Gönder sende" : String(kisaMetin)
        default: return nil
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = nil
        return EylemKaydi(tur: tur, baslik: baslik, ozet: ozet, kimlikler: [], acAdresi: (c?.url ?? url).absoluteString)
    }

    /// Reject URI injection, USSD and ambiguous local WhatsApp numbers.
    static func adres(islem: String, hedef: String, metin: String?) -> URL? {
        let temiz = hedef.trimmingCharacters(in: .whitespacesAndNewlines)
        if islem == "facetime", temiz.contains("@") {
            guard temiz.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
            var c = URLComponents(); c.scheme = "facetime"; c.path = temiz; return c.url
        }
        guard temiz.allSatisfy({ "0123456789+ ()-".contains($0) }) else { return nil }
        var numara = temiz.filter { "0123456789+".contains($0) }
        if numara.hasPrefix("00") { numara = "+" + numara.dropFirst(2) }
        guard numara.range(of: #"^\+?[0-9]{3,15}$"#, options: .regularExpression) != nil else { return nil }
        var c = URLComponents()
        switch islem {
        case "ara", "facetime": c.scheme = islem == "ara" ? "tel" : "facetime"; c.path = numara
        case "mesaj":
            c.scheme = "sms"; c.path = numara
            if let metin, !metin.isEmpty { c.queryItems = [.init(name: "body", value: metin)] }
        case "whatsapp":
            // International digits without '+' are accepted too. Never assume a country.
            let sayilar = numara.replacingOccurrences(of: "+", with: "")
            guard (8...15).contains(sayilar.count), !sayilar.hasPrefix("0"),
                  numara.hasPrefix("+") || sayilar.count >= 11 else { return nil }
            c.scheme = "https"; c.host = "wa.me"; c.path = "/" + sayilar
            if let metin, !metin.isEmpty { c.queryItems = [.init(name: "text", value: metin)] }
        default: return nil
        }
        return c.url
    }
}
