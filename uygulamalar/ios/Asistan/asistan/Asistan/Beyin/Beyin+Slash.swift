import Foundation
import FoundationModels
import ClaudeForFoundationModels
import CoreGraphics
import UIKit

/// Eğik çizgi komutlarının yürütülmesi.
extension Beyin {
    // MARK: Eğik çizgi komutları

    func slashYanit(_ komut: String, _ yanit: String, ekler: [MesajEki] = []) {
        mesajlar.append(Goruntu(rol: .kullanici, metin: komut))
        mesajlar.append(Goruntu(rol: .asistan, metin: yanit, ekler: ekler))
    }

    func slashCalistir(_ komut: SlashKomut, metin: String) async {
        switch komut {
        case .yeni:
            yeniSohbet(); slashYanit(metin, "Yeni sohbet başladı.")
        case .sikistir:
            let n = nesil
            mesajlar.append(Goruntu(rol: .kullanici, metin: metin))
            durum = .dusunuyor
            await TelefonProxy.ortak.hazirla()
            let once = ozet
            await baglamSikistir()
            guard n == nesil else { return }   // durduruldu ya da yeni sohbet açıldı: bayat sonuç eklenmez (durumu iptal/yeniSohbet yönetir)
            durum = .bosta
            mesajlar.append(Goruntu(rol: .asistan, metin: ozet != once ? "Bağlam özetlendi:\n\(ozet)" : "Özetlenecek kadar eski mesaj yok ya da özet alınamadı."))
        case .model(let arg):
            slashYanit(metin, slashModel(arg))
        case .beceriler:
            slashYanit(metin, BeceriDeposu.dizin(enFazla: 60))
        case .mcp:
            let l = McpKaydi.ortak.sunucular
            slashYanit(metin, l.isEmpty ? "Bağlı MCP sunucusu yok (Ayarlar → MCP sunucuları)." : l.map { "• \($0.ad) — \($0.url)" }.joined(separator: "\n"))
        case .gecmis(let q):
            guard !q.isEmpty else { slashYanit(metin, "Kullanım: /gecmis <aranacak sözcük>"); return }
            let b = depo.gecmisAra(q, adet: 6)
            let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM HH:mm"
            slashYanit(metin, b.isEmpty ? "Eşleşen geçmiş mesaj yok." : b.map { "[\(f.string(from: $0.zaman)) · \($0.sohbet)] \($0.parca)" }.joined(separator: "\n"))
        case .kimlik:
            slashYanit(metin, CalismaAlani.Dosya.allCases.map { d in
                let m = CalismaAlani.oku(d).trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(d.rawValue).md: " + (m.isEmpty ? "boş" : String(m.prefix(160)))
            }.joined(separator: "\n"))
        case .gunluk:
            let g = CalismaAlani.gunlukOku(gun: 3)
            slashYanit(metin, g.isEmpty ? "Günlükte not yok." : g)
        case .plan:
            slashYanit(metin, PlanDefteri.ortak.metin)
        case .nabiz:
            let n = nesil
            mesajlar.append(Goruntu(rol: .kullanici, metin: metin))
            durum = .dusunuyor
            let s = await NabizMotoru.calistir(bildir: false)
            guard n == nesil else { return }   // durduruldu ya da yeni sohbet açıldı: bayat sonuç eklenmez
            durum = .bosta
            mesajlar.append(Goruntu(rol: .asistan, metin: s.hata ?? s.uyari ?? "Nabız: her şey yolunda (dikkat gerektiren bir şey yok)."))
        case .durum:
            slashYanit(metin, slashDurum())
        case .tani:
            // Özet ana aktörde kurulur; okuma, maskeleme ve sıkıştırma TaniPaketi içinde ana aktör dışında.
            let ozet = TaniPaketi.ozetMetni()
            do {
                let u = try await TaniPaketi.olustur(ozet: ozet)
                slashYanit(metin, "Tanı paketi hazır (maskeli). Kartı paylaşarak gönderebilirsin.",
                           ekler: [MesajEki(tur: .dosya(url: u, ad: u.lastPathComponent))])
            } catch {
                slashYanit(metin, "Tanı paketi oluşturulamadı: \(error.localizedDescription)")
            }
        case .yardim:
            slashYanit(metin, SlashKomutlari.yardimMetni)
        case .bilinmeyen(let ad):
            slashYanit(metin, "Bilinmeyen komut: /\(ad)\n\n" + SlashKomutlari.yardimMetni)
        }
    }

    func slashModel(_ arg: String) -> String {
        let a = arg.trimmingCharacters(in: .whitespaces).lowercased()
        let modeller = TelefonProxy.ortak.modeller.filter(\.sohbet).map(\.id)
        if a.isEmpty {
            return (ayarlar.otomatikModel ? "Otomatik: sohbet Haiku·GPT·Gemini paralel yarışır, araçlı işler sabit sırayla gider." : "Elle seçili: \(ayarlar.modelKimligi) (hata verirse yedeklere geçilir).")
                + "\nSon kullanılan: \(aktifModel ?? "—")\nDeğiştirmek için: /model otomatik  ya da  /model <ad>"
        }
        if a == "otomatik" || a == "auto" { ayarlar.otomatikModel = true; return "Model seçimi otomatik." }
        let secim = modeller.first(where: { $0.lowercased() == a }) ?? modeller.first(where: { $0.lowercased().contains(a) })
        guard let secim else { return "'\(arg)' ile eşleşen model yok.\nÖrnekler: " + modeller.prefix(8).joined(separator: ", ") }
        ayarlar.modelKimligi = secim; ayarlar.otomatikModel = false
        return "Model elle seçildi: \(secim)"
    }

    func slashDurum() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM HH:mm"
        let nabiz = ayarlar.nabizDakika > 0 ? "her \(ayarlar.nabizDakika) dk" : "kapalı"
        let son = NabizMotoru.sonSonuc().map { f.string(from: $0.zaman) + ($0.uyari != nil ? " (uyarı)" : $0.hata != nil ? " (hata)" : " (yolunda)") } ?? "—"
        return """
        Sürüm: \(SurumBilgisi.simdiki.uzun)
        Model: \(ayarlar.otomatikModel ? "otomatik" : ayarlar.modelKimligi) · çaba: \(ayarlar.caba)
        Son kullanılan model: \(aktifModel ?? "—")
        Mesaj: \(mesajlar.count) · bağlam özeti: \(ozet.isEmpty ? "yok" : "\(ozet.count) karakter")
        Beceri: \(BeceriDeposu.listele().count) · MCP sunucusu: \(McpKaydi.ortak.sunucular.count) · hafıza olgusu: \(depo.olgular().count)
        Nabız: \(nabiz) · son: \(son)
        Kullanım (bugün): \(KullanimDefteri.ortak.kayit().aileler.values.reduce(0) { $0 + $1.istek }) istek · yarış: \(ayarlar.yarisSaglayici) sağlayıcı
        Kota: \(kotaUyarisi ?? "bekleme yok")
        """
    }
}
