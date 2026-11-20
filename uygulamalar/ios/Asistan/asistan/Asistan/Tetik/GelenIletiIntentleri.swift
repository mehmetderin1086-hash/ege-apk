import AppIntents

struct GelenIletiKaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Gelen iletiyi kaydet"
    static let description = IntentDescription("Açıkça aktarılan Mail, Mesajlar, WhatsApp veya bildirim metnini yerel Gelen Kutusu'na kaydeder.")
    static let openAppWhenRun = false
    @Parameter(title: "Kaynak") var kaynak: String
    @Parameter(title: "Gönderen") var gonderen: String?
    @Parameter(title: "İçerik") var icerik: String
    static var parameterSummary: some ParameterSummary { Summary("\(\.$kaynak) iletisini kaydet") { \.$gonderen; \.$icerik } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let basarili = GelenKutusu.ortak.ekle(kaynak: kaynak, gonderen: gonderen, metin: icerik)
        return .result(dialog: basarili ? "İleti Asistan Gelen Kutusu'na kaydedildi." : "İleti kaydedilemedi.")
    }
}

struct GelenKutusunuAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Gelen kutusunu aç"
    static let description = IntentDescription("Asistan'a aktarılmış iletileri açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "asistan://gelen-kutusu")!)) }
}

private enum HazirGelenIletiKaydi {
    @MainActor static func kaydet(kaynak: String, gonderen: String?, icerik: String) -> Bool {
        GelenKutusu.ortak.ekle(kaynak: kaynak, gonderen: gonderen, metin: icerik)
    }
    static func yanit(_ basarili: Bool) -> IntentDialog {
        basarili ? "İleti Asistan Gelen Kutusu'na kaydedildi." : "İleti kaydedilemedi."
    }
}

struct WhatsAppIletisiKaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "WhatsApp bildirimini kaydet"
    static let description = IntentDescription("WhatsApp bildirim otomasyonundan gelen başlık ve mesajı yerel Gelen Kutusu'na kaydeder.")
    static let openAppWhenRun = false
    @Parameter(title: "Gönderen") var gonderen: String?
    @Parameter(title: "Bildirim Mesajı") var icerik: String
    static var parameterSummary: some ParameterSummary { Summary("WhatsApp iletisini kaydet: \(\.$icerik)") { \.$gonderen } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let sonuc = HazirGelenIletiKaydi.kaydet(kaynak: "WhatsApp", gonderen: gonderen, icerik: icerik)
        return .result(dialog: HazirGelenIletiKaydi.yanit(sonuc))
    }
}

struct MailIletisiKaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Mail iletisini kaydet"
    static let description = IntentDescription("E-posta otomasyonundan gelen gönderen ve içeriği yerel Gelen Kutusu'na kaydeder.")
    static let openAppWhenRun = false
    @Parameter(title: "Gönderen") var gonderen: String?
    @Parameter(title: "E-posta İçeriği") var icerik: String
    static var parameterSummary: some ParameterSummary { Summary("Mail iletisini kaydet: \(\.$icerik)") { \.$gonderen } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let sonuc = HazirGelenIletiKaydi.kaydet(kaynak: "Mail", gonderen: gonderen, icerik: icerik)
        return .result(dialog: HazirGelenIletiKaydi.yanit(sonuc))
    }
}

struct MesajIletisiKaydetIntent: AppIntent {
    static let title: LocalizedStringResource = "Mesajlar iletisini kaydet"
    static let description = IntentDescription("Mesaj otomasyonundan gelen gönderen ve içeriği yerel Gelen Kutusu'na kaydeder.")
    static let openAppWhenRun = false
    @Parameter(title: "Gönderen") var gonderen: String?
    @Parameter(title: "Mesaj İçeriği") var icerik: String
    static var parameterSummary: some ParameterSummary { Summary("Mesajlar iletisini kaydet: \(\.$icerik)") { \.$gonderen } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let sonuc = HazirGelenIletiKaydi.kaydet(kaynak: "Mesajlar", gonderen: gonderen, icerik: icerik)
        return .result(dialog: HazirGelenIletiKaydi.yanit(sonuc))
    }
}
