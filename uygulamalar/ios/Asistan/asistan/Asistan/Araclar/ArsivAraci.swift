import FoundationModels

@MainActor struct ArsivAraci: Tool {
    let name = "arsivler"
    let description = "iPhone'da ZIP oluşturma veya ZIP/RAR açma ekranını gösterir. Dosya seçimini kullanıcı Dosyalar arayüzünden yapar. RAR oluşturmaz; RAR açabilir."
    @Generable struct Arguments {
        @Guide(description: "İşlem: ac veya olustur") var islem: String
    }
    func call(arguments: Arguments) async throws -> String {
        ArsivMerkezi.ortak.ekranAcik = true
        return arguments.islem == "olustur" ? "ZIP oluşturma ekranı açıldı; dosyaları seçebilirsin." : "ZIP/RAR açma ekranı açıldı; arşivi seçebilirsin."
    }
}
