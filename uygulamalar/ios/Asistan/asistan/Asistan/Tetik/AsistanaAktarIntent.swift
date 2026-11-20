import AppIntents

struct AsistanaAktarIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'a metin aktar"
    static let description = IntentDescription("Kestirmelerden veya paylaşım kestirmesinden metni Asistan'da taslak olarak açar.")
    static let openAppWhenRun = true
    @Parameter(title: "Metin") var metin: String
    static var parameterSummary: some ParameterSummary { Summary("\(\.$metin) metnini Asistan'a aktar") }
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        var url = URLComponents()
        url.scheme = "asistan"; url.host = "taslak"
        url.queryItems = [URLQueryItem(name: "metin", value: String(metin.prefix(8000)))]
        return .result(opensIntent: OpenURLIntent(url.url!))
    }
}
