import SwiftUI

struct QuestionVoiceSettings: View {
    @EnvironmentObject var game: GameStore
    @AppStorage("questionVoiceEngine") private var engine = QuestionVoiceEngine.chirp.rawValue
    @AppStorage("questionChirpVoice") private var chirp = "Kore"
    @AppStorage("questionAzureVoice") private var azure = "Elif"
    @AppStorage("questionProxyVoice") private var proxyVoice = "marin"
    @AppStorage("questionVoiceModel") private var model = "gpt-4o-mini-tts"
    @State private var config = QuestionVoiceConfiguration.load()
    @State private var editingConnection = false
    @State private var status = ""
    @State private var sampleLanguage = "tr-TR"
    @StateObject private var sample = QuestionSpeaker()
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Dinleme ve telaffuz sesi").font(.headline)
            Picker("Soru sesi",selection:$engine) { ForEach(QuestionVoiceEngine.allCases) { Text($0.title).tag($0.rawValue) } }.accessibilityIdentifier("questionVoiceEngine")
            if engine == QuestionVoiceEngine.chirp.rawValue {
                Picker("Chirp sesi",selection:$chirp) { ForEach(QuestionVoiceAPI.chirpVoices,id:\.self) { Text($0).tag($0) } }
            } else if engine == QuestionVoiceEngine.azure.rawValue {
                Picker("Azure sesi",selection:$azure) { Text("Elif / Ava").tag("Elif"); Text("Aydın / Andrew").tag("Aydın") }
                Text("Türkçede İkra'nın Elif/Aydın HD sesleri; İngilizcede Ava/Andrew kullanılır.").font(.caption).foregroundStyle(.secondary)
            } else if engine == QuestionVoiceEngine.proxy.rawValue {
                let models = game.models.filter { $0.id.localizedCaseInsensitiveContains("tts") }
                Picker("Ses modeli",selection:$model) {
                    Text(model).tag(model)
                    ForEach(models.filter { $0.id != model }) { Text($0.id).tag($0.id) }
                }
                Picker("Proxy sesi",selection:$proxyVoice) { ForEach(model.localizedCaseInsensitiveContains("gemini") ? QuestionVoiceAPI.chirpVoices : QuestionVoiceAPI.openAIVoices,id:\.self) { Text($0).tag($0) } }
                Text("Bu ses yapay zekâ tarafından üretilir. Seçilen model ve sesin sağlayıcı tarafından desteklenmesi gerekir. API kotası geçerlidir.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Örnek dili",selection:$sampleLanguage) { Text("Türkçe").tag("tr-TR"); Text("English").tag("en-US") }.pickerStyle(.segmented)
            Button {
                if sample.playing { sample.cancel() }
                else {
                    let text = sampleLanguage == "tr-TR" ? "Merhaba, bilgi yarışmasına hoş geldin." : "Good morning. Welcome to the quiz."
                    sample.speak(.init(kind:.listening,title:"Ses örneği",transcript:text,language:sampleLanguage)) { _ in }
                }
            } label: { Label(sample.playing ? "Örnek sesi durdur" : "Seçtiğim soru sesini dinle",systemImage:sample.playing ? "stop.fill" : "speaker.wave.2.fill") }.accessibilityIdentifier("previewQuestionVoice")
            if let error = sample.error { Text(error).font(.caption).foregroundStyle(gold) }
            Text("Azure, Chirp ve Proxy sesi ilk üretimde internet kullanır. Hazırlanan örnek ses cihazda saklanır. Mikrofon yanıtını Whisper cihazda çözümler.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Ses API bağlantısı",isExpanded:$editingConnection) {
                VStack(alignment:.leading,spacing:10) {
                    TextField("Google Cloud proje kimliği",text:$config.googleProject)
                    SecureField("Azure Speech anahtarı",text:$config.azureKey)
                    TextField("Azure bölgesi",text:$config.azureRegion)
                    Button("Bağlantıyı güvenli kaydet") { do { try config.save(); status = "Ses bağlantısı kaydedildi." } catch { status = "Ses bağlantısı kaydedilemedi." } }
                    Text("Google hesabı CLI Proxy'nin ortak kasasından okunur. Anahtarlar iPhone Anahtar Zinciri'nde tutulur.").font(.caption2).foregroundStyle(.secondary)
                    if !status.isEmpty { Text(status).font(.caption).foregroundStyle(gold) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).padding(.top,10)
            }.font(.caption)
        }.onDisappear { sample.cancel() }
        .onChange(of:engine) { _,_ in sample.cancel() }
        .onChange(of:sampleLanguage) { _,_ in sample.cancel() }
        .onChange(of:model) { _,value in
            if value.localizedCaseInsensitiveContains("gemini") { proxyVoice = "Kore" }
            else { proxyVoice = "marin" }
        }
    }
}
