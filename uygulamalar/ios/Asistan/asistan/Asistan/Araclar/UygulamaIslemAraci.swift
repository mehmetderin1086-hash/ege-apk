import Foundation
import FoundationModels

@MainActor
struct UygulamaIslemAraci: Tool {
    let name = "uygulamaIslemi"
    let description = "Kullanıcının bağladığı uygulama eylemlerini listeler veya kayıt kimliğiyle çalıştırır. Önce listele; yalnız istenen işe uygun kayıt varsa calistir. Uygulama ekranını okuyamaz/dokunamaz. WhatsApp mesajları için iletisim kullan."
    @Generable struct Arguments {
        @Guide(description: "listele veya calistir") var islem: String
        @Guide(description: "calistir için listelenmiş kayıt kimliği; listele için boş") var kimlik: String
        @Guide(description: "Kestirmeye aktarılacak metin, kullanıcı isteğinden; gerekmiyorsa boş") var girdi: String
    }
    /// Dış kaynaklı turda çalıştırmadan önce sorulur; kullanıcının kendi komutunda soru yok.
    var onay: OnayKapisi? = nil
    func call(arguments a: Arguments) async throws -> String {
        let k = UygulamaBaglantilari.ortak
        if a.islem == "listele" {
            return k.kayitlar.isEmpty ? "Henüz uygulama eylemi bağlanmadı. Telefon işlemleri → Uygulama bağlantıları ekranından mevcut kestirmeyi bağlayabilirsin." : k.kayitlar.map { "Kimlik: \($0.id.uuidString), uygulama: \($0.uygulama), eylem: \($0.ad), girdi: \($0.whatsapp ? "WhatsApp için iletisim aracı" : "metin")" }.joined(separator: "\n")
        }
        guard a.islem == "calistir", let id = UUID(uuidString: a.kimlik), let kayit = k.kayitlar.first(where: { $0.id == id }), !kayit.whatsapp,
              a.girdi.count <= 8000, let url = TelefonAdresleri.kisayol(kayit.kestirme, girdi: a.girdi) else { return "Geçerli, kayıtlı uygulama eylemi bulunamadı. listele ile güncel kimliği al." }
        if let onay, !(await onay.disKaynaktaIste(baslik: "\(kayit.ad) çalıştırılsın mı?", ayrinti: String(a.girdi.prefix(300)))) {
            return "Kullanıcı onaylamadı; uygulama eylemi çalıştırılmadı."
        }
        try Task.checkCancellation()
        return await TelefonAdresleri.ac(url) ? "\(kayit.ad) isteği Kestirmeler’e iletildi. Uygulama içindeki işlemin tamamlandığı doğrulanmadı." : "Kestirme açılamadı; işlem tamamlanmadı."
    }
}
