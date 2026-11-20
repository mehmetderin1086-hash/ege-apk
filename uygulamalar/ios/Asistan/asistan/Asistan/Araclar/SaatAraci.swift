import Foundation
import FoundationModels

nonisolated struct SaatAraci: Tool {
    let name = "suankiSaat"
    let description = "Cihazın şu anki tarihini, saatini, haftanın gününü ve saat dilimini döndürür. Göreli zaman ifadelerini çözmek için önce bunu çağır."
    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let simdi = Date.now
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM yyyy EEEE HH:mm:ss"
        return "Şu an: \(f.string(from: simdi)). ISO: \(AracYardim.isoSaniyesiz.string(from: simdi)). Saat dilimi: \(TimeZone.current.identifier)."
    }
}
