import SwiftUI

/// Yanıt metninin blok yapısı (Markdown alt kümesi): başlık, paragraf, liste, kod, tablo, ayırıcı.
nonisolated enum ZenginBlok: Equatable, Sendable {
    case baslik(Int, String)
    case paragraf(String)
    case liste([ListeOgesi])
    case kod(dil: String, kod: String)
    case tablo(baslik: [String], satirlar: [[String]])
    case ayirici

    struct ListeOgesi: Equatable, Sendable { let numara: Int?; let metin: String }
}

nonisolated enum ZenginAyristirici {
    static func ayristir(_ metin: String) -> [ZenginBlok] {
        let satirlar = metin.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var bloklar: [ZenginBlok] = []
        var para: [String] = []
        var liste: [ZenginBlok.ListeOgesi] = []
        func paragrafiBitir() { if !para.isEmpty { bloklar.append(.paragraf(para.joined(separator: "\n"))); para = [] } }
        func listeyiBitir() { if !liste.isEmpty { bloklar.append(.liste(liste)); liste = [] } }
        func hepsiniBitir() { paragrafiBitir(); listeyiBitir() }

        var i = 0
        while i < satirlar.count {
            let s = satirlar[i]
            let k = s.trimmingCharacters(in: .whitespaces)
            // Kod çiti: kapanmayan çit (akış sırasında) kalanı kod sayar.
            if k.hasPrefix("```") {
                hepsiniBitir()
                let dil = String(k.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var kod: [String] = []; i += 1
                while i < satirlar.count, !satirlar[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { kod.append(satirlar[i]); i += 1 }
                bloklar.append(.kod(dil: dil, kod: kod.joined(separator: "\n"))); i += 1; continue
            }
            // Tablo: başlık satırı + ayırıcı satırı (|---|---|).
            if k.hasPrefix("|"), i + 1 < satirlar.count, ayiriciSatiri(satirlar[i + 1]) {
                hepsiniBitir()
                let baslik = hucreler(k); var satirlarT: [[String]] = []; i += 2
                while i < satirlar.count, satirlar[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { satirlarT.append(hucreler(satirlar[i])); i += 1 }
                bloklar.append(.tablo(baslik: baslik, satirlar: satirlarT.map { $0 + Array(repeating: "", count: max(0, baslik.count - $0.count)) }))
                continue
            }
            if k.isEmpty { hepsiniBitir(); i += 1; continue }
            if k.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { hepsiniBitir(); bloklar.append(.ayirici); i += 1; continue }
            if let m = k.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                hepsiniBitir()
                let seviye = k[m].filter { $0 == "#" }.count
                bloklar.append(.baslik(seviye, String(k[m.upperBound...]).trimmingCharacters(in: .whitespaces))); i += 1; continue
            }
            if let m = k.range(of: #"^([-*•]\s+|\d+[.)]\s+)"#, options: .regularExpression) {
                paragrafiBitir()
                let isaret = String(k[m]).trimmingCharacters(in: .whitespaces)
                let numara = Int(isaret.dropLast())
                liste.append(.init(numara: numara, metin: String(k[m.upperBound...]))); i += 1; continue
            }
            // Girintili devam satırı: önceki liste öğesine eklenir.
            if !liste.isEmpty, s.hasPrefix("  ") || s.hasPrefix("\t") {
                let son = liste.removeLast(); liste.append(.init(numara: son.numara, metin: son.metin + "\n" + k)); i += 1; continue
            }
            listeyiBitir(); para.append(s); i += 1
        }
        hepsiniBitir()
        return bloklar
    }

    /// Akan metnin kararlı öneki: kod çiti dışındaki son boş satırdan önceki kısım. Boş satırda ayrıştırıcının
    /// bütün durumu (paragraf, liste, tablo) sıfırlandığı için `ayristir(onek) + ayristir(kuyruk) == ayristir(metin)`.
    /// Akış sırasında önek önbellekten gelir, yalnız kuyruk yeniden ayrıştırılır. Uygun boş satır yoksa nil.
    static func kararliBolum(_ metin: String) -> (onek: String, kuyruk: String)? {
        let satirlar = metin.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var citIcinde = false
        var son: Int?
        for (i, s) in satirlar.enumerated() {
            let k = s.trimmingCharacters(in: .whitespaces)
            if k.hasPrefix("```") { citIcinde.toggle(); continue }
            if !citIcinde, k.isEmpty, i > 0 { son = i }
        }
        guard let j = son else { return nil }
        return (satirlar[..<j].joined(separator: "\n"), satirlar[(j + 1)...].joined(separator: "\n"))
    }

    static func hucreler(_ satir: String) -> [String] {
        var k = satir.trimmingCharacters(in: .whitespaces)
        if k.hasPrefix("|") { k.removeFirst() }; if k.hasSuffix("|") { k.removeLast() }
        return k.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    static func ayiriciSatiri(_ s: String) -> Bool {
        let k = s.trimmingCharacters(in: .whitespaces)
        return k.hasPrefix("|") && k.contains("-") && k.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) != nil
    }
}

/// Zengin yanıt görünümü. `imlec` açıkken (akış sürerken) son metin satırının sonunda yanıp sönen imleç gösterilir.
struct ZenginMetinGorunumu: View {
    let metin: String
    var imlec = false
    /// Görünüm > "Sohbet yazı boyutu" çarpanı (kullanıcı balonuyla aynı ölçek).
    var olcek: Double = 1.0
    @ScaledMetric(relativeTo: .body) private var punto = 18.0
    @Environment(\.colorScheme) private var sema

    private var boy: Double { punto * olcek }
    private var bloklar: [ZenginBlok] { ZenginBlokOnbellegi.bloklar(metin, akiyor: imlec) }

    var body: some View {
        let b = bloklar
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(b.enumerated()), id: \.offset) { i, blok in
                gorunum(blok, son: imlec && i == b.count - 1)
            }
            if b.isEmpty, imlec { Imlec() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func gorunum(_ blok: ZenginBlok, son: Bool) -> some View {
        switch blok {
        case .baslik(let seviye, let m):
            Text(satirIci(m)).font(.system(size: boy * (seviye <= 1 ? 1.25 : seviye == 2 ? 1.12 : 1.0), weight: .semibold)).padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .paragraf(let m):
            (Text(satirIci(m)) + (son ? Text(" ▍").foregroundStyle(.secondary) : Text(""))).font(.system(size: boy)).lineSpacing(boy * 0.28)
        case .liste(let ogeler):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(ogeler.enumerated()), id: \.offset) { i, o in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(o.numara.map { "\($0)." } ?? "•").font(.system(size: boy)).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .trailing)
                        (Text(satirIci(o.metin)) + (son && i == ogeler.count - 1 ? Text(" ▍").foregroundStyle(.secondary) : Text("")))
                            .font(.system(size: boy)).lineSpacing(boy * 0.25)
                    }
                }
            }
        case .kod(let dil, let kod):
            KodBlogu(dil: dil, kod: kod, punto: boy)
        case .tablo(let baslik, let satirlar):
            TabloGorunumu(baslik: baslik, satirlar: satirlar, punto: boy * 0.9)
        case .ayirici:
            Divider().padding(.vertical, 4)
        }
    }

    private func satirIci(_ m: String) -> AttributedString {
        let s = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: m, options: s)) ?? AttributedString(m)
    }
}

/// Ayrıştırma önbelleği: bitmiş yanıtlar her çizimde, akan yanıt her parçada baştan ayrıştırılmasın.
/// Akış sırasında yalnız kararlı önek saklanır (her parçanın tam metni saklanmaz); kuyruk her seferinde ayrıştırılır.
enum ZenginBlokOnbellegi {
    private final class Kutu {
        let bloklar: [ZenginBlok]
        init(_ bloklar: [ZenginBlok]) { self.bloklar = bloklar }
    }
    private static let onbellek: NSCache<NSString, Kutu> = {
        let c = NSCache<NSString, Kutu>(); c.countLimit = 400; return c
    }()

    static func bloklar(_ metin: String, akiyor: Bool) -> [ZenginBlok] {
        let anahtar = metin as NSString
        if let k = onbellek.object(forKey: anahtar) { return k.bloklar }
        guard akiyor else {
            let b = ZenginAyristirici.ayristir(metin)
            onbellek.setObject(Kutu(b), forKey: anahtar)
            return b
        }
        guard let bolum = ZenginAyristirici.kararliBolum(metin) else { return ZenginAyristirici.ayristir(metin) }
        let onekAnahtari = bolum.onek as NSString
        let onekBloklari: [ZenginBlok]
        if let k = onbellek.object(forKey: onekAnahtari) { onekBloklari = k.bloklar } else {
            onekBloklari = ZenginAyristirici.ayristir(bolum.onek)
            onbellek.setObject(Kutu(onekBloklari), forKey: onekAnahtari)
        }
        return onekBloklari + ZenginAyristirici.ayristir(bolum.kuyruk)
    }
}

private struct Imlec: View {
    /// Hareketi Azalt açıkken imleç sabit durur.
    @Environment(\.accessibilityReduceMotion) private var azHareket
    var body: some View { Text("▍").foregroundStyle(.secondary).symbolEffect(.pulse, isActive: !azHareket) }
}

struct KodBlogu: View {
    let dil: String
    let kod: String
    let punto: CGFloat
    @State private var kopyalandi = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dil.isEmpty ? "kod" : dil).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = kod
                    kopyalandi = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); kopyalandi = false }
                } label: {
                    Label(kopyalandi ? "Kopyalandı" : "Kopyala", systemImage: kopyalandi ? "checkmark" : "doc.on.doc").font(.caption)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Kodu kopyala").accessibilityIdentifier("kod-kopyala")
                .sensoryFeedback(.success, trigger: kopyalandi) { _, yeni in yeni }
            }
            .padding(.horizontal, 12).padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(kod).font(.system(size: punto * 0.82, design: .monospaced)).fontDesign(.monospaced).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
            }
        }
        .fontDesign(.default)   // sohbet temasının tırnaklı yazı tipi kod bloğuna geçmesin
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

struct TabloGorunumu: View {
    let baslik: [String]
    let satirlar: [[String]]
    let punto: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(baslik.enumerated()), id: \.offset) { _, h in
                        Text(satirIci(h)).font(.system(size: punto, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(minWidth: 70, maxWidth: 260, alignment: .leading)
                    }
                }.background(Color(uiColor: .tertiarySystemFill))
                ForEach(Array(satirlar.enumerated()), id: \.offset) { i, s in
                    GridRow {
                        ForEach(Array(s.prefix(baslik.count).enumerated()), id: \.offset) { _, h in
                            Text(satirIci(h)).font(.system(size: punto)).padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(minWidth: 70, maxWidth: 260, alignment: .leading)
                        }
                    }.background(i % 2 == 1 ? Color(uiColor: .quaternarySystemFill) : .clear)
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Tablo, \(satirlar.count) satır")
    }

    private func satirIci(_ m: String) -> AttributedString {
        (try? AttributedString(markdown: m, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(m)
    }
}
