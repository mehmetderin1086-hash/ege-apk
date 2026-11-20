import SwiftUI
import UniformTypeIdentifiers

struct AcademyView: View {
    @EnvironmentObject var game: GameStore
    @State private var section = 0
    @State private var importing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Bilgi Akademisi").font(.largeTitle.bold())
                    Text("Öğrendiklerini yanında taşı.").foregroundStyle(.secondary)
                    Picker("İçerik", selection: $section) { Text("Tekrar").tag(0); Text("Paketler").tag(1); Text("Defterim").tag(2); Text("Havuz").tag(3) }.pickerStyle(.segmented)
                    if section == 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("\(game.dueCards.count) soru seni bekliyor", systemImage: "arrow.clockwise").font(.title3.bold()).foregroundStyle(aqua)
                            Text("Yanlış veya boş bıraktığın sorular buraya gelir. Doğru cevapladıkça tekrar aralığı uzar.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Tekrara başla") { game.startReview() }.buttonStyle(PrimaryButton()).disabled(game.dueCards.isEmpty).accessibilityIdentifier("startReview")
                        }.padding(18).arenaPanel(tint:aqua,radius:22)
                        ForEach(game.reviews.sorted { $0.due < $1.due }) { card in
                            VStack(alignment: .leading, spacing: 8) { Text(card.question.text).font(.headline); HStack { Text(card.due <= Date() ? "Tekrar zamanı" : "Sonraki tekrar").foregroundStyle(card.due <= Date() ? aqua : .secondary); Spacer(); Text(card.due, style: .date) }.font(.caption); Text("\(card.attempts) deneme · \(card.correct) doğru").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).arenaPanel(radius:20)
                        }
                        if game.reviews.isEmpty { empty("Tekrar defterin hazır", text: "Bir tur oyna; zorlandığın soruları burada birlikte pekiştirelim.", icon: "brain") }
                    } else if section == 1 {
                        QuestionTransferControls()
                        ForEach(game.packs) { pack in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(aqua); VStack(alignment: .leading) { Text(pack.title).font(.headline); Text("\(pack.questions.count) soru · Çevrimdışı hazır").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                                Text(pack.models.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                HStack { Button("Oyna") { game.startPack(pack) }.buttonStyle(.borderedProminent).tint(aqua).foregroundStyle(ink); Spacer(); ShareLink(item: export(pack)) { Label("Paylaş", systemImage: "square.and.arrow.up") }.font(.subheadline) }
                            }.padding(17).arenaPanel(tint:aqua,radius:22)
                        }
                        if game.packs.isEmpty { empty("Kendi soru arşivin", text: "Üretilen yapay zekâ paketleri otomatik kaydedilir. Daha sonra internetsiz oynayabilirsin.", icon: "tray.full.fill") }
                    } else if section == 3 { QuestionPoolSection() } else {
                        if game.saved.isEmpty { empty("Merak ettiklerini biriktir", text: "Cevap ekranındaki yer işaretine dokunarak soruları bilgi defterine ekle.", icon: "bookmark.fill") }
                        ForEach(game.saved) { q in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { Text(q.category.rawValue.uppercased()).font(.caption.bold()).foregroundStyle(aqua); Spacer(); Button { game.toggleSaved(q) } label: { Image(systemName: "bookmark.fill") }.accessibilityLabel("Kaydı kaldır") }
                                Text(q.text).font(.headline); if let visual = q.visual { QuestionVisualCard(visual:visual) }; if let activity = q.activity { ActivitySummaryCard(activity:activity) }; Text(q.correctAnswerText).font(.subheadline.bold()); Text(q.explanation).font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).arenaPanel(radius:20)
                        }
                    }
                }.padding(20)
            }.background(ArenaBackdrop()).toolbar(.hidden, for: .navigationBar)

        }.tint(aqua)
    }
    func empty(_ title: String, text: String, icon: String) -> some View {
        VStack(spacing: 14) { VictoryMedallion(symbol:icon,tint:aqua).frame(height:150); Text(title).font(.title3.bold()); Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    func export(_ pack: QuestionPack) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BilgiArenasi-\(pack.id.uuidString).json")
        if !FileManager.default.fileExists(atPath: url.path), let data = try? JSONEncoder().encode(pack) { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
        return url
    }
}
