import SwiftUI

struct VoiceAnswerSheet: View {
    let question: Question
    @ObservedObject var voice: VoiceAnswerStore
    let submit: (SpokenAnswer,String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ArenaPreferences.Key.voiceAutoStart) private var autoStart = true
    @AppStorage(ArenaPreferences.Key.voiceAutoStop) private var autoStop = true
    @AppStorage(ArenaPreferences.Key.voiceAutoSubmit) private var autoSubmit = false
    @State private var autoStarted = false
    @State private var closing = false
    @State private var pending: (text: String, seconds: Int)?
    @State private var pendingTask: Task<Void,Never>?
    private var language: String { question.activity?.kind == .pronunciation ? String((question.activity?.language ?? "en-US").prefix(2)) : "tr" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Label("Cihazda Whisper",systemImage:"waveform.and.mic").font(.title2.bold()).foregroundStyle(aqua)
                    Text(question.text).font(.headline)
                    if let activity = question.activity, activity.kind == .pronunciation {
                        Text(activity.transcript ?? "").font(.title.bold()).foregroundStyle(gold)
                        Text("İfadeyi söyle. Algılanan kelimeler hedefle karşılaştırılır; bu bir aksan puanı değildir.").font(.subheadline).foregroundStyle(.secondary)
                    } else if question.activity?.isInteractive == true {
                        Text(question.activity?.kind == .ordering ? "Öğelerin ekrandaki numaralarını doğru sırayla söyle: örneğin iki, dört, bir, üç." : "Her sol öğe için doğru sağ öğenin numarasını söyle. Soldaki sıraya göre dört farklı numara kullan.").font(.subheadline)
                        if let activity = question.activity {
                            ForEach(0..<4,id:\.self) { i in Text("\(i+1). " + (activity.items?[i] ?? activity.left?[i] ?? "") + (activity.right.map { "  ↔  \(i+1). " + $0[i] } ?? "")).font(.subheadline) }
                        }
                    } else { Text("A, B, C, D şıkkını veya seçeneğin tamamını söyle. Algılanan yanıtı göndermeden önce kontrol et.").font(.subheadline) }
                    Text("Bu pencere açıkken oyun saati durur. Ses kaydı sunucuya gönderilmez; çözümlemeden sonra silinir.").font(.caption).foregroundStyle(.secondary)
                    if !voice.ready {
                        Text(LocalAnswerWhisper.downloaded ? "Telefondaki model kullanılacak." : "İlk kullanımda yaklaşık 470 MB model indirilir; ardından çevrimdışı çalışır.").font(.caption)
                        Button("Whisper'ı hazırla") { voice.prepare() }.buttonStyle(PrimaryButton()).disabled(voice.phase != .idle).accessibilityIdentifier("prepareWhisper")
                    }
                    if voice.phase == .preparing { ProgressView(); Text("Whisper hazırlanıyor… \(Int(voice.progress*100))%").font(.caption).accessibilityIdentifier("whisperPreparing") }
                    if voice.ready {
                        Button {
                            if voice.phase == .recording { voice.finishRecording() }
                            else { startRecording() }
                        } label: { Label(voice.phase == .recording ? "Kaydı bitir" : "Kaydı başlat",systemImage:voice.phase == .recording ? "stop.circle.fill" : "mic.fill") }.buttonStyle(PrimaryButton()).disabled(voice.phase != .idle && voice.phase != .recording).accessibilityIdentifier("recordVoiceAnswer")
                        if voice.phase == .requestingMicrophone { ProgressView("Mikrofon hazırlanıyor…") }
                        if voice.phase == .recording {
                            ProgressView(value:voice.level).tint(gold).accessibilityLabel("Mikrofon ses düzeyi")
                            Text(autoStop ? "Dinleniyor · susunca kayıt kendiliğinden biter" : "Dinleniyor · bitirince Kaydı bitir'e dokun").foregroundStyle(gold).accessibilityIdentifier("voiceAnswerListening")
                        }
                        if voice.phase == .transcribing { ProgressView("Ses cihazda yazıya çevriliyor…") }
                    }
                    if let error = voice.error { Text(error).foregroundStyle(gold).font(.subheadline) }
                    if !voice.transcript.isEmpty {
                        Text("Algılanan metin · düzenleyebilirsin").font(.caption.bold())
                        TextField("Sesli yanıtın",text:$voice.transcript,axis:.vertical).textFieldStyle(.roundedBorder).accessibilityIdentifier("voiceAnswerTranscript")
                        if let result = VoiceAnswerResolver.resolve(voice.transcript,for:question) {
                            Text(preview(result)).font(.headline).foregroundStyle(aqua).accessibilityIdentifier("voiceAnswerPreview")
                            if question.activity?.kind == .pronunciation {
                                let matches = question.activity?.isCorrect(.init(indices:[],spokenText:voice.transcript)) == true
                                Text(matches ? "Hedef ifade anlaşıldı." : "Hedefle farklı anlaşıldı. Örneği yeniden dinleyip tekrar deneyebilirsin.").font(.subheadline).foregroundStyle(matches ? aqua : gold)
                            }
                            if let pending, pending.text == voice.transcript {
                                HStack {
                                    Label("\(pending.seconds) saniye sonra gönderilecek",systemImage:"paperplane.fill").font(.subheadline.bold()).foregroundStyle(aqua)
                                    Spacer()
                                    Button("Vazgeç") { cancelPending() }.font(.subheadline.bold()).accessibilityIdentifier("cancelAutoSubmit")
                                }
                            }
                            Button(question.activity?.kind == .pronunciation ? "Bu denemeyi kaydet" : "Bu yanıtı gönder") { cancelPending(); submit(result,voice.transcript); dismiss() }.buttonStyle(PrimaryButton()).accessibilityIdentifier("confirmVoiceAnswer")
                        } else { Text("Tek bir yanıt belirlenemedi. Metni düzelt veya yeniden söyle.").foregroundStyle(gold).font(.subheadline) }
                    }
                }.padding(20)
            }.background(ArenaBackdrop()).navigationTitle("Sesli cevap").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Kapat") { closing = true; cancelPending(); dismiss() } } }
        }.tint(aqua).preferredColorScheme(.dark)
        .onAppear {
            // Ortak kayıt deposu önceki sorunun metnini taşımasın.
            if voice.phase == .idle { voice.transcript = "" }
            guard autoStart, !autoStarted, voice.phase == .idle else { return }
            if voice.ready { autoStarted = true; startRecording() }
            else if LocalAnswerWhisper.downloaded { voice.prepare() }
        }
        .onChange(of:voice.ready) { _,ready in
            // İndirilmiş model hazır olunca kayıt bir kez kendiliğinden açılır; ilk indirme kullanıcının dokunuşunu bekler.
            guard ready, autoStart, !autoStarted, voice.phase == .idle, voice.transcript.isEmpty else { return }
            autoStarted = true; startRecording()
        }
        .onChange(of:voice.phase) { old,new in if old == .transcribing && new == .idle { scheduleAutoSubmit() } else if new != .idle { cancelPending() } }
        .onDisappear { closing = true; cancelPending(); voice.cancel() }
        .interactiveDismissDisabled(pending != nil)
    }
    private func startRecording() { cancelPending(); voice.record(language:language,automaticStop:autoStop) }
    private func cancelPending() { pendingTask?.cancel(); pendingTask = nil; pending = nil }
    /// İsteğe bağlı: tek yanıt kesinse 2 saniyelik geri sayımla gönderir. Söyleme alıştırması her zaman elle kaydedilir.
    private func scheduleAutoSubmit() {
        cancelPending()
        let text = voice.transcript
        guard autoSubmit, question.activity?.kind != .pronunciation, let result = VoiceAnswerResolver.resolve(text,for:question) else { return }
        pending = (text,2)
        pendingTask = Task { @MainActor in
            for left in stride(from:2,through:1,by:-1) {
                pending = (text,left)
                try? await Task.sleep(for:.seconds(1))
                guard !Task.isCancelled, !closing, voice.transcript == text else { return }
            }
            guard !closing else { return }
            closing = true; pending = nil; submit(result,text); dismiss()
        }
    }
    private func preview(_ answer: SpokenAnswer) -> String {
        switch answer {
        case .choice(let index): return "\(String(UnicodeScalar(65+index)!)) · \(question.options[index])"
        case .activity(let response): return question.activity?.describe(response) ?? ""
        }
    }
}
