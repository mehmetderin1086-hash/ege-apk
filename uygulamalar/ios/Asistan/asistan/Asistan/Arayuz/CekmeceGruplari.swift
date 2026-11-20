import Foundation

/// Çekmecedeki sohbet listesinin günlere göre gruplanması (saf mantık).
nonisolated enum CekmeceGruplari {
    struct Oge: Equatable, Sendable { let id: UUID; let baslik: String; let son: Date; let sabit: Bool }
    struct Grup: Equatable, Sendable { let baslik: String; let ogeler: [Oge] }

    static func grupla(_ ogeler: [Oge], simdi: Date = .now, takvim: Calendar = .current) -> [Grup] {
        var kovalar: [(String, [Oge])] = [("Sabitlenenler", []), ("Bugün", []), ("Dün", []), ("Son 7 gün", []), ("Son 30 gün", []), ("Daha eski", [])]
        let bugun = takvim.startOfDay(for: simdi)
        for o in ogeler.sorted(by: { $0.son > $1.son }) {
            let gun = takvim.startOfDay(for: o.son)
            let fark = takvim.dateComponents([.day], from: gun, to: bugun).day ?? 0
            let i: Int
            if o.sabit { i = 0 } else if fark <= 0 { i = 1 } else if fark == 1 { i = 2 } else if fark <= 7 { i = 3 } else if fark <= 30 { i = 4 } else { i = 5 }
            kovalar[i].1.append(o)
        }
        return kovalar.filter { !$0.1.isEmpty }.map { Grup(baslik: $0.0, ogeler: $0.1) }
    }

    /// Başlık ya da (varsa) içerik eşleşmesi; sorgu boşsa hepsi. Türkçe harf/büyüklük duyarsız.
    static func eslesir(baslik: String, icerik: String, sorgu: String) -> Bool {
        let q = GecmisArama.normalize(sorgu).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return GecmisArama.normalize(baslik).contains(q) || GecmisArama.normalize(icerik).contains(q)
    }
}
