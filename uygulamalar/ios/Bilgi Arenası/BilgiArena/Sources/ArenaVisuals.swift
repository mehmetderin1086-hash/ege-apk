import SwiftUI

extension Topic {
    var accent: Color {
        switch self {
        case .mixed: return aqua
        case .science: return Color(red:0.42,green:0.71,blue:1)
        case .history: return gold
        case .geography: return Color(red:0.42,green:0.88,blue:0.64)
        case .art: return Color(red:0.94,green:0.49,blue:0.72)
        case .sport: return Color(red:1,green:0.58,blue:0.35)
        case .culture: return Color(red:0.78,green:0.65,blue:1)
        case .cinema: return Color(red:0.67,green:0.62,blue:1)
        case .language: return Color(red:0.35,green:0.83,blue:0.89)
        case .exam: return Color(red:0.96,green:0.72,blue:0.38)
        case .custom: return Color(red:0.60,green:0.72,blue:1)
        }
    }
    var invitation: String {
        switch self {
        case .mixed: return "Her alandan keşif"
        case .science: return "Merakının peşinden"
        case .history: return "Zamanda bir yolculuk"
        case .geography: return "Dünyayı keşfet"
        case .art: return "İlhamını bul"
        case .sport: return "Bilginle sahaya çık"
        case .culture: return "Yeni şeyler öğren"
        case .cinema: return "Perdenin ötesine geç"
        case .language: return "Kelimelerle keşfet"
        case .exam: return "Hedefine bir adım"
        case .custom: return "Konuyu sen belirle"
        }
    }
}

struct ArenaBackdrop: View {
    var body: some View {
        ZStack {
            Color(red:0.025,green:0.045,blue:0.105)
            GeometryReader { g in
                Ellipse().fill(Color(red:0.12,green:0.28,blue:0.55).opacity(0.32)).frame(width:g.size.width*1.4,height:420).blur(radius:75).offset(x:-g.size.width*0.6,y:-170)
                Ellipse().fill(aqua.opacity(0.055)).frame(width:280,height:420).blur(radius:80).position(x:g.size.width+50,y:g.size.height*0.65)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ArenaPanel: ViewModifier {
    var tint: Color = .white
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius:radius,style:.continuous)
                .fill(LinearGradient(colors:[panel.opacity(0.96),ink.opacity(0.90)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(LinearGradient(colors:[tint.opacity(0.20),.white.opacity(0.025)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
        }
    }
}
extension View {
    func arenaPanel(tint: Color = .white, radius: CGFloat = 22) -> some View { modifier(ArenaPanel(tint:tint,radius:radius)) }
}

struct ArenaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response:0.25,dampingFraction:0.7),value:configuration.isPressed)
    }
}

struct LevelEmblem: View {
    let level: Int
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[gold.opacity(0.2),gold.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Circle().stroke(gold.opacity(0.45),lineWidth:1)
            VStack(spacing:0) { Image(systemName:"sparkle").font(.system(size:10,weight:.bold)); Text("\(level)").font(.system(.headline,design:.rounded,weight:.heavy)) }.foregroundStyle(gold)
        }.frame(width:48,height:48).accessibilityElement(children:.ignore).accessibilityLabel("Seviye \(level)")
    }
}

/// A small vector illustration; redraws only while visible and active.
struct KnowledgeOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = true
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:reduceMotion || phase != .active || !visible)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Canvas { canvas,size in
                    let center = CGPoint(x:size.width/2,y:size.height/2)
                    for orbit in 0..<3 {
                        let radius = CGFloat(orbit)*16 + size.width*0.25
                        let rect = CGRect(x:center.x-radius,y:center.y-radius*0.64,width:radius*2,height:radius*1.28)
                        var transform = CGAffineTransform(translationX:center.x,y:center.y)
                        transform = transform.rotated(by:CGFloat(orbit)*0.7-0.6).translatedBy(x:-center.x,y:-center.y)
                        let path = Path(ellipseIn:rect).applying(transform)
                        canvas.stroke(path,with:.color(aqua.opacity(0.15+Double(orbit)*0.05)),lineWidth:1)
                        let angle = time*0.24 + Double(orbit)*2.15
                        let x = center.x + cos(angle)*radius
                        let y = center.y + sin(angle)*radius*0.64
                        canvas.fill(Path(ellipseIn:CGRect(x:x-3,y:y-3,width:6,height:6)),with:.color(orbit == 1 ? gold : aqua))
                    }
                    for n in 0..<12 {
                        let x = CGFloat((n*47+17)%137)/137*size.width
                        let y = CGFloat((n*73+31)%149)/149*size.height
                        let radius = CGFloat(n%3 == 0 ? 2 : 1)
                        canvas.fill(Path(ellipseIn:CGRect(x:x,y:y,width:radius,height:radius)),with:.color(.white.opacity(0.2+0.15*sin(time+Double(n)))))
                    }
                }
                Circle().fill(RadialGradient(colors:[aqua.opacity(0.28),aqua.opacity(0.02)],center:.center,startRadius:8,endRadius:55)).frame(width:110,height:110)
                ZStack {
                    RoundedRectangle(cornerRadius:24).fill(LinearGradient(colors:[Color(red:0.18,green:0.45,blue:0.55),Color(red:0.07,green:0.20,blue:0.32)],startPoint:.topLeading,endPoint:.bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius:24).stroke(aqua.opacity(0.6),lineWidth:1))
                    Image(systemName:"brain.head.profile").font(.system(size:43,weight:.light)).foregroundStyle(LinearGradient(colors:[.white,aqua],startPoint:.top,endPoint:.bottom))
                }.frame(width:82,height:90).rotationEffect(.degrees(-9)).offset(y:reduceMotion ? 0 : sin(time*0.8)*4).shadow(color:aqua.opacity(0.17),radius:16,y:8)
                Image(systemName:"sparkle").font(.system(size:19,weight:.light)).foregroundStyle(gold).offset(x:43,y:-43)
            }
        }.onScrollVisibilityChange(threshold:0.1) { visible = $0 }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct ArenaHero: View {
    let level: Int
    let xp: Int
    var body: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack(spacing:4) {
                VStack(alignment:.leading,spacing:9) {
                    Label("MERAKLA BAŞLAR",systemImage:"sparkle").font(.system(size:9,weight:.bold)).tracking(1.4).foregroundStyle(aqua)
                    Text("Her soruda\nbir adım ileri.").font(.system(.title,design:.rounded,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                    Text("Bugün ne keşfedeceksin?").font(.caption).foregroundStyle(.white.opacity(0.6))
                }.frame(maxWidth:.infinity,alignment:.leading).layoutPriority(1)
                KnowledgeOrbit().frame(width:125,height:145)
            }
            VStack(spacing:7) {
                HStack { Text("Seviye \(level)").font(.caption.bold()); Spacer(); Text("\(xp % 250) / 250 XP").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.55)) }
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors:[aqua,Color(red:0.32,green:0.65,blue:1)],startPoint:.leading,endPoint:.trailing)).frame(width:max(5,g.size.width*Double(xp%250)/250))
                }.frame(height:5)
            }
        }.padding(20).arenaPanel(tint:aqua,radius:26)
    }
}

struct CategoryTile: View {
    let topic: Topic
    let selected: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Image(systemName:topic.icon).font(.system(size:23,weight:.medium)).symbolRenderingMode(.hierarchical).foregroundStyle(topic.accent)
                Spacer()
                if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(topic.accent).font(.subheadline) }
            }
            VStack(alignment:.leading,spacing:4) {
                Text(topic.rawValue).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(topic.invitation).font(.system(size:10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }.frame(maxWidth:.infinity,minHeight:91,alignment:.leading).padding(14)
            .background {
                ZStack(alignment:.topTrailing) {
                    RoundedRectangle(cornerRadius:19).fill(panel.opacity(0.65))
                    Circle().fill(topic.accent.opacity(selected ? 0.18 : 0.075)).frame(width:95,height:95).offset(x:25,y:-25)
                }.clipShape(RoundedRectangle(cornerRadius:19))
            }
            .overlay(RoundedRectangle(cornerRadius:19).stroke(topic.accent.opacity(selected ? 0.8 : 0.10),lineWidth:selected ? 1.5 : 1))
            .shadow(color:topic.accent.opacity(selected ? 0.10 : 0),radius:12,y:5)
    }
}

/// The small fixed catalog is eager so every category remains reachable to accessibility.
struct TopicGrid: View {
    @Binding var selection: Topic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:9) {
            ForEach(0..<((Topic.allCases.count+1)/2),id:\.self) { row in
                HStack(spacing:9) {
                    ForEach(Array(Topic.allCases.dropFirst(row*2).prefix(2))) { topic in
                        Button { withAnimation(reduceMotion ? nil : .spring(response:0.32,dampingFraction:0.8)) { selection = topic } } label: {
                            CategoryTile(topic:topic,selected:selection == topic)
                        }.buttonStyle(ArenaPressStyle()).accessibilityLabel(topic.rawValue).accessibilityAddTraits(selection == topic ? .isSelected : [])
                    }
                    if row*2+1 >= Topic.allCases.count { Color.clear.frame(maxWidth:.infinity).accessibilityHidden(true) }
                }
            }
        }
    }
}

struct CountdownDial: View {
    let remaining: Int
    let total: Int
    let training: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var color: Color { !training && remaining < 5 ? Color(red:1,green:0.40,blue:0.49) : aqua }
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.06),lineWidth:4)
            Circle().trim(from:0,to:training ? 1 : min(1,Double(remaining)/Double(max(1,total)))).stroke(color,style:StrokeStyle(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration:0.35),value:remaining)
            Text(training ? "∞" : "\(remaining)").font(.system(.title3,design:.rounded,weight:.bold)).monospacedDigit().foregroundStyle(color).contentTransition(.numericText())
        }.frame(width:52,height:52).accessibilityElement(children:.ignore).accessibilityLabel(training ? "Süresiz öğrenme" : "Kalan süre \(remaining) saniye")
    }
}

struct AnswerShake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(CGAffineTransform(translationX:sin(animatableData * .pi * 6)*amount,y:0)) }
}

struct ScoreCounter: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text("\(Int(value.rounded()))").monospacedDigit() }
}

struct VictoryMedallion: View {
    var symbol = "trophy.fill"
    var tint = gold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors:[tint.opacity(0.20),.clear],center:.center,startRadius:20,endRadius:90)).frame(width:180,height:180)
            Circle().stroke(tint.opacity(0.18),lineWidth:1).frame(width:142,height:142)
            Circle().stroke(tint.opacity(0.10),style:StrokeStyle(lineWidth:1,dash:[3,8])).frame(width:166,height:166)
            ZStack {
                Circle().fill(LinearGradient(colors:[tint.opacity(0.23),tint.opacity(0.05)],startPoint:.topLeading,endPoint:.bottomTrailing))
                Circle().stroke(LinearGradient(colors:[tint.opacity(0.9),tint.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.5)
                Image(systemName:symbol).font(.system(size:49,weight:.medium)).foregroundStyle(LinearGradient(colors:[Color.white,tint],startPoint:.topLeading,endPoint:.bottomTrailing)).shadow(color:tint.opacity(0.4),radius:12,y:5)
            }.frame(width:116,height:116).rotationEffect(.degrees(entered ? 0 : -12)).scaleEffect(entered || reduceMotion ? 1 : 0.7)
            ForEach(0..<4) { n in
                Image(systemName:"sparkle").font(.system(size:n%2 == 0 ? 14 : 9)).foregroundStyle(tint.opacity(0.85)).offset(x:n%2 == 0 ? -74 : 74,y:n<2 ? -42 : 48)
            }
        }.onAppear { withAnimation(reduceMotion ? nil : .spring(response:0.65,dampingFraction:0.65)) { entered = true } }.accessibilityHidden(true)
    }
}

struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var start = Date()
    @State private var finished = false
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion || finished || phase != .active)) { context in
            Canvas { canvas,size in
                let elapsed = context.date.timeIntervalSince(start)
                guard !reduceMotion, !finished, elapsed < 2.8 else { return }
                let t = max(0,elapsed)
                for n in 0..<42 {
                    let angle = Double(n)*2.39996
                    let speed = 40 + Double(n%7)*23
                    let x = size.width/2 + cos(angle)*speed*t
                    let y = 90 - (90+Double(n%5)*22)*t + 110*t*t
                    var c = canvas
                    c.opacity = min(1,max(0,(2.8-t)/0.7))
                    c.translateBy(x:x,y:y); c.rotate(by:.radians(angle+t*Double(n%4+1)))
                    let colors: [Color] = [aqua,gold,Color(red:0.8,green:0.6,blue:1),.white]
                    c.fill(Path(roundedRect:CGRect(x:-3,y:-5,width:6,height:10),cornerRadius:2),with:.color(colors[n%4]))
                }
            }
        }.task {
            start = Date()
            if reduceMotion { finished = true; return }
            try? await Task.sleep(for:.seconds(2.8))
            if !Task.isCancelled { finished = true }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GenerationIndicator: View {
    @Environment(\.scenePhase) private var phase
    let progress: Double
    let status: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing:14) {
            ZStack {
                Circle().stroke(aqua.opacity(0.13),lineWidth:3)
                Circle().trim(from:0,to:max(0.05,progress)).stroke(aqua,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .easeInOut(duration:0.4),value:progress)
                Image(systemName:"sparkles").foregroundStyle(aqua).symbolEffect(.pulse,options:.repeating,isActive:!reduceMotion && phase == .active)
            }.frame(width:44,height:44)
            VStack(alignment:.leading,spacing:5) { Text("Bilgi hazırlanıyor").font(.subheadline.bold()); Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            Spacer(minLength:0)
            Text("%\(Int(progress*100))").font(.caption.bold().monospacedDigit()).foregroundStyle(aqua).contentTransition(.numericText())
        }
    }
}
