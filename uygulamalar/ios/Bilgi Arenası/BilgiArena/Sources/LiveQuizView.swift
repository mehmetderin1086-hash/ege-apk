import SwiftUI

struct LiveQuizSetup: View {
    @EnvironmentObject var game: GameStore
    @AppStorage("quizLiveEngine") private var engine = QuizLiveEngine.chained.rawValue
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Canlı sesli yarışma",systemImage:"waveform.circle.fill").font(.title3.bold()).foregroundStyle(aqua)
            Text("Soruyu dinle, yanıtını söyle. Kısa sessizlikten sonra yanıtın Ayarlar'daki süre kadar gösterilir; iptal edebilir veya yeniden söyleyebilirsin. Sonuç okunur ve sıradaki soruya geçilir.").font(.subheadline).foregroundStyle(.secondary)
            Label("Motor: "+(QuizLiveEngine(rawValue:engine) ?? .chained).title+" · Ayarlar'dan değiştirilir",systemImage:"waveform").font(.caption.bold()).foregroundStyle(aqua).accessibilityIdentifier("liveEngineSummary")
            Text(engine == QuizLiveEngine.chained.rawValue ? "Asistan'ın sıralı yolu: seçtiğin Azure/Chirp/iPhone sesi + cihazdaki Whisper. Mikrofon kaydı gönderilmez." : "Canlı API: mikrofon sesi seçtiğin sağlayıcıya gönderilir. CLI Proxy'nin telefondaki API hesabı kullanılır; kota geçerlidir. Bağlantı kurulamazsa sıralı sesli yol ekranda belirtilir.").font(.caption).foregroundStyle(.secondary)
            Button { game.startLiveLocal() } label:{ Label(game.requestingLivePermission ? "Mikrofon izni bekleniyor" : "Canlı turu başlat",systemImage:"mic.badge.plus").frame(maxWidth:.infinity) }.buttonStyle(PrimaryButton()).disabled(game.loading || game.requestingLivePermission).accessibilityIdentifier("startLiveQuiz")
            Text("Seçtiğin kategori, seviye ve soru sayısıyla havuzdan süresiz açılır. Sesler yapay zekâ ile üretilir. 'Tekrar oku', 'dur' ve 'geç' diyebilirsin.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).arenaPanel(tint:aqua,radius:22)
    }
}
struct LiveQuizDock: View {
    @EnvironmentObject var game: GameStore
    @ObservedObject var live: LiveQuizController
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Image(systemName:live.phase == .listening ? "mic.fill" : live.phase == .transcribing ? "text.bubble.fill" : "waveform").foregroundStyle(aqua)
                Text(live.title).font(.subheadline.bold()).accessibilityIdentifier("liveDockStatus")
                Spacer()
                if live.phase == .listening { Button("Bitir") { live.finishHearing() }.accessibilityIdentifier("liveDockFinish") }
                if live.phase == .paused || live.phase == .failed { Button("Devam") { live.retry() }.accessibilityIdentifier("liveDockResume") }
                else { Button("Durdur") { game.pause() }.accessibilityIdentifier("liveDockPause") }
            }
            if live.phase == .listening { ProgressView(value:live.level).tint(gold).accessibilityLabel("Mikrofon ses düzeyi") }
            if let error = live.error { Text(error).font(.caption).foregroundStyle(gold) }
            else if live.phase == .reviewing { Text(live.preview).font(.caption).foregroundStyle(aqua) }
            else if live.phase == .transcribing { Text("Mikrofon kapandı; yanıt cihazda çözülüyor.").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(.ultraThinMaterial).accessibilityElement(children:.contain).accessibilityIdentifier("liveQuizDock")
    }
}
struct LiveQuizPanel: View {
    @EnvironmentObject var game: GameStore
    @ObservedObject var live: LiveQuizController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Label("CANLI SESLİ TUR",systemImage:"waveform").font(.caption.bold()).foregroundStyle(aqua); Spacer(); Text(live.phase == .listening ? "Mikrofon açık" : "").font(.caption.bold()).foregroundStyle(gold) }
            HStack(alignment:.center,spacing:5) {
                ForEach(0..<18,id:\.self) { i in
                    Capsule().fill(live.phase == .listening ? gold : aqua).frame(width:7,height:8+(live.phase == .listening ? live.level : live.phase == .speaking || live.phase == .feedback ? 0.45 : 0.05)*Double([16,28,40,24,36,50][i%6]))
                }
                Spacer(); if live.phase == .preparing { ProgressView() }
            }.frame(height:44).animation(reduceMotion ? nil : .easeOut(duration:0.1),value:live.level).accessibilityHidden(true)
            Text(live.title).font(.headline).accessibilityIdentifier("liveQuizStatus")
            if live.phase == .listening { Text("Şık harfini veya cevabı söyle. Bitirince kısa bir süre sus; istersen Cevabımı bitirdim'e dokun.").font(.caption).foregroundStyle(.secondary) }
            if live.phase == .transcribing { Text("Kayıt tamamlandı; mikrofon kapalı. Yanıt cihazda çözümleniyor.").font(.caption).foregroundStyle(.secondary) }
            if live.phase == .openingMicrophone { ProgressView().accessibilityLabel("Mikrofon açılıyor") }
            if !live.route.isEmpty { Text(live.route).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("liveQuizRoute") }
            if !live.notice.isEmpty { Text(live.notice).font(.caption).foregroundStyle(gold) }
            if let error = live.error { Text(error).font(.subheadline).foregroundStyle(gold).accessibilityIdentifier("liveQuizError") }
            if !live.transcript.isEmpty { Text("Duyduğum: "+live.transcript).font(.subheadline).accessibilityIdentifier("liveQuizTranscript") }
            if live.phase == .reviewing { Text(live.preview).font(.headline).foregroundStyle(aqua).accessibilityIdentifier("liveQuizPreview") }
            if let a = game.round?.current.activity, a.kind == .pronunciation { Text(a.transcript ?? "").font(.title3.bold()).foregroundStyle(gold) }
            if [.failed,.paused].contains(live.phase) {
                Button("Canlı devam / yeniden dene") { live.retry() }.buttonStyle(PrimaryButton()).accessibilityIdentifier("resumeLiveQuiz")
                if live.phase == .failed { Button("iPhone sesi ve Whisper ile devam et") { live.retry(local:true) }.font(.caption.bold()) }
            } else {
                HStack {
                    if live.phase == .listening { Button("Cevabımı bitirdim") { live.finishHearing() }.accessibilityIdentifier("finishLiveAnswer") }
                    else if live.phase == .reviewing { Button("İptal / yeniden söyle") { live.start(game,skipReading:true) }.accessibilityIdentifier("retryLiveAnswer") }
                    else { Button("Yeniden oku") { live.start(game) }.disabled(live.phase == .preparing || live.phase == .openingMicrophone || live.phase == .transcribing) }
                    Spacer(); Button("Durdur") { game.pause() }.accessibilityIdentifier("pauseLiveQuiz")
                }.font(.subheadline.bold())
            }
            Text("Soru ve puan havuzdan yönetilir. Sesi durdurabilir veya şıklara dokunabilirsin. Arka plana geçince mikrofon kapanır.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).arenaPanel(tint:live.phase == .listening ? gold : aqua,radius:22).accessibilityElement(children:.contain).accessibilityIdentifier("liveQuizPanel")
    }
}
