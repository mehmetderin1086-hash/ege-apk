import CryptoKit
import SwiftUI

/// Destedeki madde, sayı ve tabloların kaynakta dayanağı var mı? (/v1/verify-deck)
/// Sonuç bölüm klasöründe deckissues.json; deste değişince (içerik özeti farklıysa) geçersiz sayılır.
nonisolated struct DeckVerification: Codable, Sendable {
    var signature: String
    var issues: [DeckIssue]
    /// Sunucuya gönderilen (denetlenen) slaytların indeksleri. Eski kayıtlarda yoktur (nil): uyarısız slayt temiz sayılır.
    var checked: [Int]?
}

enum DeckVerifier {
    /// Süreçler arasında kararlı içerik özeti (Hasher her açılışta farklı tohumlanır).
    static func signature(_ deck: Deck) -> String {
        let text = deck.slides.map { s in
            [s.title, (s.bullets ?? []).joined(separator: "|"), s.stat?.value ?? "", (s.table?.rows ?? []).map { $0.joined(separator: ",") }.joined(separator: ";")]
                .joined(separator: "§")
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func stored(for episode: Episode, deck: Deck) -> DeckVerification? {
        let url = episode.directory.appending(path: "deckissues.json")
        guard let data = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(DeckVerification.self, from: data),
              v.signature == signature(deck) else { return nil }
        return v
    }

    /// Bir partide gönderilebilen slayt sayısı (sunucu sınırı).
    nonisolated static let batchSize = 30

    /// Denetlenebilir slaytlar (saf; test edilir): yalnız madde, istatistik ya da tablo içerenler; indeks destedeki sıradır.
    /// Şema, zaman çizgisi, grafik, alıntı ve görsel slaytları kaynakla karşılaştırılmaz.
    nonisolated static func requestSlides(_ deck: Deck) -> [VerifyDeckRequest.Slide] {
        deck.slides.enumerated().compactMap { i, s -> VerifyDeckRequest.Slide? in
            guard s.bullets?.isEmpty == false || s.stat != nil || s.table != nil else { return nil }
            return .init(index: i, title: s.title, bullets: s.bullets,
                         stat: s.stat.map { .init(value: $0.value, label: $0.label) }, table: s.table)
        }
    }

    /// Slaytları sunucu sınırına göre partilere böler (sıra korunur).
    nonisolated static func batches(_ slides: [VerifyDeckRequest.Slide], size: Int = batchSize) -> [[VerifyDeckRequest.Slide]] {
        let size = max(1, size)
        return stride(from: 0, to: slides.count, by: size).map { Array(slides[$0..<min($0 + size, slides.count)]) }
    }

    /// İstek gövdeleri (saf; test edilir), parti başına bir tane. Kaynak notları sunucu sınırına UTF-16 birimiyle kırpılır
    /// (`ServerText`): grafem sayan `prefix`, emojili ya da ayrışık (NFD) metinde sınırı aşıp 400 döndürüyordu.
    nonisolated static func requests(sourceNotes: String, deck: Deck) -> [VerifyDeckRequest] {
        let notes = ServerText.prefix(sourceNotes, 15_000)
        return batches(requestSlides(deck)).map { VerifyDeckRequest(sourceNotes: notes, slides: $0) }
    }

    /// İlk partinin isteği (30 slayta kadar olan destede tek istek).
    nonisolated static func request(sourceNotes: String, deck: Deck) -> VerifyDeckRequest {
        requests(sourceNotes: sourceNotes, deck: deck).first
            ?? VerifyDeckRequest(sourceNotes: ServerText.prefix(sourceNotes, 15_000), slides: [])
    }

    /// Bir slaydın doğrulama durumu: uyarılı, denetlenip temiz bulunmuş ya da hiç denetlenmemiş.
    nonisolated enum SlideStatus: Equatable { case issues([DeckIssue]), clean, unchecked }

    nonisolated static func status(page: Int, in v: DeckVerification) -> SlideStatus {
        let here = v.issues.filter { $0.slideIndex == page }
        if !here.isEmpty { return .issues(here) }
        guard let checked = v.checked else { return .clean }
        return checked.contains(page) ? .clean : .unchecked
    }

    /// Uyarı içeren slaytların indeksleri (sıralı, yinelemesiz; deste dışına taşan indeks atılır).
    nonisolated static func flaggedPages(_ v: DeckVerification, slideCount: Int) -> [Int] {
        Set(v.issues.map(\.slideIndex)).filter { $0 >= 0 && $0 < slideCount }.sorted()
    }

    /// Partiler sırayla gönderilir ve birleştirilir. Bir parti hata verirse tümü hata sayılır: kısmi sonuç kaydedilmez.
    static func run(for episode: Episode, deck: Deck) async throws -> DeckVerification {
        // Bölüm istek sürerken silinebilir: modelden gerekenler baştan alınır.
        let url = episode.directory.appending(path: "deckissues.json")
        let bodies = requests(sourceNotes: episode.script?.sourceNotes ?? "", deck: deck)
        var issues: [DeckIssue] = []
        for body in bodies {
            try Task.checkCancellation()
            issues += try await APIClient.shared.verifyDeck(body)
        }
        let result = DeckVerification(signature: signature(deck), issues: issues.sorted { $0.slideIndex < $1.slideIndex },
                                      checked: bodies.flatMap { $0.slides.map(\.index) })
        try? JSONEncoder().encode(result).write(to: url)
        return result
    }
}

/// Slayt altında: doğrulama düğmesi ya da o slaydın durumu (uyarılar, temiz, denetlenmedi) ve uyarılı slaytlara kısayol.
struct DeckIssuesBanner: View {
    var episode: Episode
    var deck: Deck
    var page: Int
    /// Uyarılı slayta atlama (görüntüleyici sayfayı değiştirir).
    var select: (Int) -> Void = { _ in }
    @State private var result: DeckVerification?
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                switch DeckVerifier.status(page: page, in: result) {
                case .issues(let here):
                    ForEach(Array(here.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(issue.kind == "contradiction" ? "Kaynakla çelişiyor" : issue.kind == "number" ? "Sayı kaynakta yok" : "Kaynakta dayanağı yok",
                                  systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundStyle(.orange)
                            Text("“\(issue.text)”").font(.caption).italic()
                            if !issue.note.isEmpty { Text(issue.note).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                case .clean:
                    Label(result.issues.isEmpty ? "Destede kaynakta dayanağı olmayan madde bulunmadı." : "Bu slayt temiz · destede \(result.issues.count) uyarı var",
                          systemImage: "checkmark.seal").font(.caption).foregroundStyle(.green)
                case .unchecked:
                    Label("Bu slayt denetlenmedi: yalnız madde, sayı ve tablolar kaynakla karşılaştırılır.", systemImage: "minus.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                flaggedRow(DeckVerifier.flaggedPages(result, slideCount: deck.slides.count))
                Button {
                    Task { await verify() }
                } label: {
                    Label(running ? "Kaynakla karşılaştırılıyor…" : "Yeniden doğrula", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .font(.caption).disabled(running)
            } else {
                Button {
                    Task { await verify() }
                } label: {
                    Label(running ? "Kaynakla karşılaştırılıyor…" : "Slaytları kaynakla doğrula", systemImage: "checkmark.shield")
                }
                .font(.subheadline).disabled(running)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: DeckVerifier.signature(deck)) { result = DeckVerifier.stored(for: episode, deck: deck) }
    }

    /// Uyarı olan slaytlara tek dokunuşla geçiş (hangi slaytlarda uyarı olduğunu aramak gerekmesin).
    @ViewBuilder private func flaggedRow(_ pages: [Int]) -> some View {
        if !pages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("Uyarılı slaytlar", systemImage: "exclamationmark.triangle").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pages, id: \.self) { index in
                            Button { select(index) } label: {
                                // Çerçeveli düğmenin iç boşluğuyla birlikte en az 44 nokta dokunma hedefi.
                                Text("\(index + 1)").font(.subheadline.monospacedDigit().weight(index == page ? .bold : .regular))
                                    .frame(minWidth: 22, minHeight: 30)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(index == page ? "Slayt \(index + 1), uyarılı, şu anki slayt" : "Slayt \(index + 1), uyarılı")
                        }
                    }
                }
            }
        }
    }

    private func verify() async {
        running = true; error = nil
        defer { running = false }
        do { result = try await DeckVerifier.run(for: episode, deck: deck) } catch { self.error = error.localizedDescription }
    }
}
