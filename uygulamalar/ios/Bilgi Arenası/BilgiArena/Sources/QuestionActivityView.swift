import SwiftUI

struct ListeningQuestionCard: View {
    let question: Question
    @ObservedObject var speaker: QuestionSpeaker
    @EnvironmentObject var game: GameStore
    @State private var showTranscript = false
    var body: some View {
        if let activity = question.activity {
            VStack(alignment:.leading,spacing:14) {
                Label(activity.title,systemImage:"headphones").font(.headline).foregroundStyle(aqua)
                if !speaker.source.isEmpty { Text(speaker.source).font(.caption.bold()).foregroundStyle(gold) }
                if activity.kind == .pronunciation { Text(activity.transcript ?? "").font(.title2.bold()).foregroundStyle(gold) }
                Text(speaker.playing ? speaker.everStarted ? "Dinleniyor · saat bekliyor" : "Ses hazırlanıyor · saat bekliyor" : game.round?.awaitsListening == true ? "Önce dinle, sonra yanıtla. Süre ses bitince başlar." : "Hazır · tekrar dinlerken saat durur.")
                    .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("listeningStatus")
                HStack {
                    Button { if speaker.playing { game.stopListening() } else { game.startListening() } } label: {
                        Label(speaker.playing ? "Dinlemeyi durdur" : "Dinle / tekrar dinle",systemImage:speaker.playing ? "stop.fill" : "play.fill")
                    }.buttonStyle(.borderedProminent).tint(aqua).foregroundStyle(ink).accessibilityIdentifier("playQuestionAudio")
                    Spacer()
                }
                if let error = speaker.error { Text(error).font(.caption).foregroundStyle(gold).accessibilityIdentifier("questionAudioError") }
                Button(showTranscript ? "Metni gizle" : "Metni aç ve devam et") {
                    if !showTranscript { game.useListeningTranscript() }
                    showTranscript.toggle()
                }.font(.caption.bold()).accessibilityIdentifier("showListeningTranscript")
                if showTranscript || game.round?.revealed == true { Text(activity.transcript ?? "").font(.body).lineSpacing(3).accessibilityIdentifier("listeningTranscript") }
                Text("Dinlemeyi başlatınca sessiz modda da ses çalar. Uygulamadan çıkınca durur. Ses açılamazsa metinle devam edebilirsin.").font(.caption2).foregroundStyle(.secondary)
            }.padding(16).arenaPanel(tint:aqua,radius:20)
                .disabled(game.round?.paused == true || game.round?.revealed == true)
        }
    }
}

struct ActivityAnswerBoard: View {
    let activity: QuestionActivity
    let disabled: Bool
    let submit: (ActivityResponse) -> Void
    var draft: ActivityResponse? = nil
    var saveDraft: (ActivityResponse) -> Void = { _ in }
    @State private var order: [Int] = []
    @State private var selectedLeft: Int?
    @State private var assignments: [Int:Int] = [:]
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label(activity.kind.title,systemImage:activity.kind.icon).font(.headline).foregroundStyle(aqua)
            if activity.kind == .ordering {
                Text("Öğelere istediğin sırayla dokun. Sonra yanıtını gönder.").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<4,id:\.self) { i in
                    Button { if !order.contains(i) { order.append(i) } } label: {
                        HStack {
                            Text(order.firstIndex(of:i).map { "\($0+1)" } ?? "·").monospacedDigit().font(.headline).frame(width:30)
                            Text(activity.items![i]).frame(maxWidth:.infinity,alignment:.leading)
                            Image(systemName:order.contains(i) ? "checkmark.circle.fill" : "plus.circle")
                        }.padding(14).background(order.contains(i) ? aqua.opacity(0.14) : panel,in:RoundedRectangle(cornerRadius:14))
                    }.buttonStyle(.plain).accessibilityLabel(activity.items![i]).accessibilityValue(order.firstIndex(of:i).map { "Sıra \($0+1)" } ?? "Seçilmedi").accessibilityIdentifier("orderItem\(i)")
                }
                if !order.isEmpty { Text(order.map { activity.items![$0] }.joined(separator:" → ")).font(.subheadline.bold()).foregroundStyle(gold).accessibilityIdentifier("orderingPreview") }
                HStack { Button("Geri al") { if !order.isEmpty { order.removeLast() } }; Spacer(); Button("Başa al") { order = [] } }.font(.caption.bold())
            } else {
                Text("Önce soldan bir öğe, sonra sağdan karşılığını seç. Yeniden eşleştirerek düzeltebilirsin.").font(.caption).foregroundStyle(.secondary)
                HStack(alignment:.top,spacing:10) {
                    VStack(spacing:10) { ForEach(0..<4,id:\.self) { i in
                        Button { selectedLeft = i } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text("\(i+1). " + activity.left![i]).font(.subheadline.bold())
                                Text(assignments[i].map { "↔ " + activity.right![$0] } ?? "Eşini seç").font(.caption)
                            }.frame(maxWidth:.infinity,minHeight:65,alignment:.leading).padding(10)
                                .background(selectedLeft == i ? aqua.opacity(0.2) : panel,in:RoundedRectangle(cornerRadius:14))
                                .overlay(RoundedRectangle(cornerRadius:14).stroke(selectedLeft == i ? aqua : .clear))
                        }.buttonStyle(.plain).accessibilityLabel("Sol: "+activity.left![i]).accessibilityValue(assignments[i].map { activity.right![$0] } ?? "Eşleştirilmedi").accessibilityIdentifier("matchLeft\(i)")
                    } }
                    VStack(spacing:10) { ForEach(0..<4,id:\.self) { i in
                        Button {
                            guard let left = selectedLeft else { return }
                            if let owner = assignments.first(where:{ $0.value == i })?.key { assignments.removeValue(forKey:owner) }
                            assignments[left] = i; selectedLeft = nil
                        } label: {
                            HStack { Text("\(i+1). " + activity.right![i]).font(.subheadline.bold()); Spacer(minLength:0); if assignments.values.contains(i) { Image(systemName:"link").foregroundStyle(aqua) } }.frame(maxWidth:.infinity,minHeight:65,alignment:.leading).padding(10).background(panel,in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).disabled(selectedLeft == nil).accessibilityLabel("Sağ: "+activity.right![i]).accessibilityIdentifier("matchRight\(i)")
                    } }
                }
                Button("Eşleştirmeleri temizle") { assignments = [:]; selectedLeft = nil }.font(.caption.bold())
            }
            let response = ActivityResponse(indices:activity.kind == .ordering ? order : (0..<4).map { assignments[$0] ?? -1 })
            Button("Yanıtı gönder") { submit(response) }.buttonStyle(PrimaryButton()).disabled(!activity.accepts(response)).accessibilityIdentifier("submitActivity")
        }.onAppear {
            if let draft {
                if activity.kind == .ordering { order = draft.indices }
                else { assignments = Dictionary(uniqueKeysWithValues:draft.indices.enumerated().filter { $0.element >= 0 }.map { ($0.offset,$0.element) }) }
            }
        }
        .onChange(of:draft) { _,value in
            guard disabled, let value else { return }
            if activity.kind == .ordering { order = value.indices }
            else { assignments = Dictionary(uniqueKeysWithValues:value.indices.enumerated().filter { $0.element >= 0 }.map { ($0.offset,$0.element) }) }
        }
        .onChange(of:order) { _,value in if activity.kind == .ordering { saveDraft(.init(indices:value)) } }
        .onChange(of:assignments) { _,value in if activity.kind == .matching { saveDraft(.init(indices:(0..<4).map { value[$0] ?? -1 })) } }
        .disabled(disabled).accessibilityElement(children:.contain).accessibilityIdentifier("activityBoard-"+activity.kind.rawValue)
    }
}

struct ActivitySummaryCard: View {
    let activity: QuestionActivity
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Label(activity.kind.title,systemImage:activity.kind.icon).font(.caption.bold()).foregroundStyle(aqua)
            if let transcript = activity.transcript { Text(transcript).font(.subheadline) }
            else { Text(activity.solutionText).font(.subheadline.bold()) }
        }.padding(12).arenaPanel(tint:aqua,radius:14)
    }
}
