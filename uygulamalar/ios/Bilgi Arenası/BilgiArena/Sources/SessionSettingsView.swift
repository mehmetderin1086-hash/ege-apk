import SwiftUI

struct SessionSettingsView: View {
    @EnvironmentObject var game: GameStore
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:16) {
                if game.mode != .training {
                    Picker("Toplam süre",selection:$game.roundSettings.minutes) {
                        if game.mode != .timed { Text("Sınırsız").tag(0) }
                        ForEach(1...30,id:\.self) { Text("\($0) dakika").tag($0) }
                    }.accessibilityIdentifier("roundMinutes")
                    if game.mode != .timed {
                        Picker("Soru süresi",selection:$game.roundSettings.seconds) {
                            Text("Moda göre").tag(0)
                            ForEach([5,7,10,15,20,30,45,60,90,120],id:\.self) { Text("\($0) saniye").tag($0) }
                        }.accessibilityIdentifier("questionSeconds")
                    }
                    Text("Toplam saat yalnız cevap verirken işler; açıklama, mola, büyütme ve arka planda durur. Süre bitince tur tamamlanır; görülmeyen sorular yanlış sayılmaz.").font(.caption).foregroundStyle(.secondary)
                } else { Text("Öğrenme turu süresizdir.").font(.caption).foregroundStyle(.secondary) }
                Label("Ses efektleri, soru sesi, sesli yanıt ve canlı tur ayarları Ayarlar sekmesinde.",systemImage:"gearshape").font(.caption).foregroundStyle(.secondary)
            }.padding(.top,12)
        } label: { Label("Süre ayarları",systemImage:"slider.horizontal.3").font(.subheadline.bold()) }
        .padding(16).arenaPanel(tint:aqua,radius:18).tint(aqua)
        .onChange(of:game.mode) { _,mode in if mode == .timed && game.roundSettings.minutes == 0 { game.roundSettings.minutes = 2 } }
    }
}
