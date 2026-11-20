import Foundation
import FoundationModels

/// Cihaz içi Apple Intelligence modeli; araçlar canlı İETT verisini çağırır, uydurma yapmaz.
@available(iOS 26.0, *)
@MainActor final class AIAssistant {
    private let session: LanguageModelSession
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    init(brain: TransitBrain) {
        session = LanguageModelSession(tools: [LineStatusTool(brain: brain), StopETATool(brain: brain), NearbyTool(brain: brain), NoticeTool(brain: brain), FindLineTool(brain: brain), StopLinesTool(brain: brain), ScheduleTool(brain: brain)],
            instructions: """
            Sen İstanbul İETT otobüsleri için Türkçe bir asistansın. Hat, durak, canlı konum, kaç dakikada geleceği ve duyuru sorularını
            YALNIZCA araçlarla yanıtla; araç sonucunda olmayan saat, süre veya hat bilgisi uydurma. Süreler canlı konumdan hesaplanan tahmindir, bunu kısaca belirt.
            Kullanıcı hat kodu verdiyse (500T, 14M gibi) kodu aynen kullan. Kısa, net ve samimi yaz.
            """)
    }
    func respond(_ text: String) async throws -> String { try await session.respond(to: text).content }
}

@available(iOS 26.0, *)
struct LineStatusTool: Tool {
    let brain: TransitBrain
    let name = "hat_durumu"
    let description = "Bir hattın şu an yoldaki araç sayısını, sonraki planlı kalkışlarını ve duyurusunu verir."
    @Generable struct Arguments { @Guide(description: "Hat kodu, örn. 500T") var hat: String }
    func call(arguments: Arguments) async throws -> String { await brain.lineStatus(arguments.hat) }
}
@available(iOS 26.0, *)
struct StopETATool: Tool {
    let brain: TransitBrain
    let name = "durak_varis"
    let description = "Bir hat için bir durağa gelecek araçların canlı konumdan hesaplanan kaç dakikada geleceğini verir."
    @Generable struct Arguments {
        @Guide(description: "Hat kodu, örn. 14M") var hat: String
        @Guide(description: "Durak adı veya adının bir kısmı, örn. Kadıköy iskele") var durak: String
    }
    func call(arguments: Arguments) async throws -> String { await brain.stopETA(line: arguments.hat, stopQuery: arguments.durak) }
}
@available(iOS 26.0, *)
struct NearbyTool: Tool {
    let brain: TransitBrain
    let name = "yakin_duraklar"
    let description = "Kullanıcının konumuna en yakın durakları listeler."
    @Generable struct Arguments { @Guide(description: "Kullanılmaz, boş bırak") var not: String? }
    func call(arguments: Arguments) async throws -> String { await brain.nearby() }
}
@available(iOS 26.0, *)
struct NoticeTool: Tool {
    let brain: TransitBrain
    let name = "duyurular"
    let description = "İETT güncel duyurularını (güzergâh değişikliği, aksama) verir; hat verilirse yalnız o hattınkini."
    @Generable struct Arguments { @Guide(description: "İsteğe bağlı hat kodu") var hat: String? }
    func call(arguments: Arguments) async throws -> String { await brain.notices(line: arguments.hat) }
}
@available(iOS 26.0, *)
struct FindLineTool: Tool {
    let brain: TransitBrain
    let name = "hat_ara"
    let description = "Hat kodu ya da güzergâh adına (örn. Kadıköy, Taksim) göre hat arar."
    @Generable struct Arguments { @Guide(description: "Arama metni") var sorgu: String }
    func call(arguments: Arguments) async throws -> String { await brain.findLines(arguments.sorgu) }
}

@available(iOS 26.0, *)
struct StopLinesTool: Tool {
    let brain: TransitBrain
    let name = "durak_hatlari"
    let description = "Bir durağa uğrayan hatları ve her birinin canlı varış süresini listeler."
    @Generable struct Arguments { @Guide(description: "Durak adı veya adının bir kısmı") var durak: String }
    func call(arguments: Arguments) async throws -> String { await brain.stopLines(arguments.durak) }
}

@available(iOS 26.0, *)
struct ScheduleTool: Tool {
    let brain: TransitBrain
    let name = "sefer_saatleri"
    let description = "Bir hattın bugünkü planlı sefer saatlerini (ilk/son sefer, aralık, sıradaki kalkışlar) verir."
    @Generable struct Arguments { @Guide(description: "Hat kodu, örn. 500T") var hat: String }
    func call(arguments: Arguments) async throws -> String { await brain.schedule(arguments.hat) }
}
