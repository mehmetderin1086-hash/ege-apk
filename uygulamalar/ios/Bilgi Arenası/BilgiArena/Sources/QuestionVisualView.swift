import SwiftUI
import Charts

extension VisualColor {
    var value: Color {
        switch self {
        case .mint: return aqua
        case .blue: return Color(red:0.42,green:0.71,blue:1)
        case .gold: return Color(red:1,green:0.76,blue:0.30)
        case .pink: return Color(red:0.96,green:0.48,blue:0.66)
        case .violet: return Color(red:0.75,green:0.62,blue:1)
        }
    }
}

struct QuestionVisualCard: View {
    let visual: QuestionVisual
    var onExpansionChange: (Bool) -> Void = { _ in }
    @State private var expanded = false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top) {
                Label(visual.kind.title,systemImage:visual.kind.icon).font(.caption.bold()).foregroundStyle(aqua)
                Spacer()
                Button { onExpansionChange(true); expanded = true } label: { Label("Büyüt",systemImage:"arrow.up.left.and.arrow.down.right") }.font(.caption.bold()).accessibilityIdentifier("enlargeVisual")
            }
            Text(visual.title).font(.subheadline.bold()).fixedSize(horizontal:false,vertical:true)
            QuestionVisualContent(visual:visual)
        }.padding(14).arenaPanel(tint:aqua,radius:18).accessibilityElement(children:.contain).accessibilityIdentifier("questionVisual-\(visual.kind.rawValue)")
            .sheet(isPresented:$expanded,onDismiss:{ onExpansionChange(false) }) { VisualDetail(visual:visual) }
    }
}

private struct VisualDetail: View {
    let visual: QuestionVisual
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing:0) {
                    HStack { Image(systemName:"minus.magnifyingglass"); Slider(value:$zoom,in:1...3,step:0.25).accessibilityLabel("Görsel büyütme oranı"); Image(systemName:"plus.magnifyingglass") }.padding(18).tint(aqua)
                    ScrollView([.horizontal,.vertical]) {
                        VStack(alignment:.leading,spacing:18) {
                            Text(visual.title).font(.title2.bold())
                            QuestionVisualContent(visual:visual,expanded:true,zoom:zoom)
                        }.frame(width:max(250,geometry.size.width-40)*zoom).padding(20)
                    }
                }
            }.background(ArenaBackdrop()).navigationTitle(visual.kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Kapat") { dismiss() }.accessibilityIdentifier("closeVisual") } }
        }.tint(aqua).preferredColorScheme(.dark)
    }
}

struct QuestionVisualContent: View {
    let visual: QuestionVisual
    var expanded = false
    var zoom = 1.0
    private var contentScale: Double { expanded ? zoom : 1 }
    var body: some View {
        Group {
            switch visual.kind {
            case .table: table
            case .barChart, .lineChart: chart
            case .diagram:
                VisualDiagram(elements:visual.elements ?? [],fontScale:expanded ? zoom : 1)
                    .frame(height:(expanded ? 280 : 205)*zoom)
                    .accessibilityElement(children:.ignore).accessibilityLabel(visual.summary)
            case .image:
                if let photo = QuestionPhotoCatalog.items.first(where:{ $0.id == visual.imageID }) {
                    Image(photo.asset).resizable().scaledToFit().frame(maxWidth:.infinity)
                        .frame(maxHeight:(expanded ? 360 : 225)*zoom).background(Color.white.opacity(0.95),in:RoundedRectangle(cornerRadius:12))
                        .clipShape(RoundedRectangle(cornerRadius:12)).accessibilityLabel(photo.description)
                }
            }
        }
    }
    private var table: some View {
        ScrollView(.horizontal) {
            Grid(alignment:.leading,horizontalSpacing:0,verticalSpacing:0) {
                GridRow {
                    ForEach(Array((visual.columns ?? []).enumerated()),id:\.offset) { _,column in
                        Text(column).font(.system(size:expanded ? 17*zoom : 12,weight:.bold)).foregroundStyle(aqua).padding(11*contentScale).frame(minWidth:80*contentScale,maxWidth:180*contentScale,alignment:.leading)
                    }
                }.background(aqua.opacity(0.11))
                ForEach(Array((visual.rows ?? []).enumerated()),id:\.offset) { index,row in
                    GridRow {
                        ForEach(Array(row.enumerated()),id:\.offset) { _,cell in
                            Text(cell).font(.system(size:expanded ? 17*zoom : 14)).fixedSize(horizontal:false,vertical:true).padding(11*contentScale).frame(minWidth:80*contentScale,maxWidth:180*contentScale,alignment:.leading)
                        }
                    }.background(index.isMultiple(of:2) ? Color.white.opacity(0.025) : Color.clear)
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel(zip(visual.columns ?? [],row).map { "\($0): \($1)" }.joined(separator:", "))
                }
            }.clipShape(RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(.white.opacity(0.08)))
        }.accessibilityLabel("Tablo: \(visual.title)")
    }
    private var chart: some View {
        let labels = visual.labels ?? [], values = visual.values ?? []
        let minimum = min(0,values.min() ?? 0), maximum = max(0,values.max() ?? 0)
        let span = max(1,maximum-minimum)
        return Chart {
            ForEach(Array(labels.enumerated()),id:\.offset) { index,label in
                if values.indices.contains(index) {
                    if visual.kind == .barChart {
                        BarMark(x:.value("Etiket",label),y:.value(visual.unit ?? "Değer",values[index]))
                            .foregroundStyle(aqua.gradient).cornerRadius(4)
                            .annotation(position:.top) { Text(values[index],format:.number.precision(.fractionLength(0...2))).font(.system(size:11*contentScale,weight:.bold)).foregroundStyle(.white) }
                    } else {
                        LineMark(x:.value("Etiket",label),y:.value(visual.unit ?? "Değer",values[index])).foregroundStyle(aqua).lineStyle(StrokeStyle(lineWidth:2.5))
                        PointMark(x:.value("Etiket",label),y:.value(visual.unit ?? "Değer",values[index])).foregroundStyle(gold)
                            .annotation(position:.top) { Text(values[index],format:.number.precision(.fractionLength(0...2))).font(.system(size:11*contentScale,weight:.bold)).foregroundStyle(.white) }
                    }
                }
            }
        }.chartXScale(domain:labels).chartYScale(domain:(minimum < 0 ? minimum-span*0.12 : 0)...(maximum+span*0.2))
            .chartYAxis { AxisMarks(position:.leading) { _ in AxisGridLine(); AxisTick(); AxisValueLabel().font(.system(size:11*contentScale)) } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size:11*contentScale)); AxisTick() } }
            .chartYAxisLabel(visual.unit ?? "Değer")
            .frame(height:(expanded ? 300 : 215)*zoom).padding(.top,10)
            .accessibilityElement(children:.ignore).accessibilityLabel(visual.accessibleData)
    }
}

private struct VisualDiagram: View {
    let elements: [VisualElement]
    let fontScale: Double
    var body: some View {
        Canvas { context,size in
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x:x/100*size.width,y:y/100*size.height) }
            for item in elements {
                let center = point(item.x,item.y), color = (item.color ?? .mint).value
                var path = Path()
                let width = (item.width ?? 0)/100*size.width, height = (item.height ?? 0)/100*size.height
                let rect = CGRect(x:center.x-width/2,y:center.y-height/2,width:width,height:height)
                switch item.shape {
                case .circle:
                    let diameter = min(width,height)
                    path.addEllipse(in:CGRect(x:center.x-diameter/2,y:center.y-diameter/2,width:diameter,height:diameter))
                case .rectangle: path.addRoundedRect(in:rect,cornerSize:CGSize(width:3,height:3))
                case .triangle:
                    path.move(to:CGPoint(x:rect.midX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY)); path.closeSubpath()
                case .point: path.addEllipse(in:CGRect(x:center.x-4,y:center.y-4,width:8,height:8))
                case .line, .arrow:
                    let end = point(item.endX ?? item.x,item.endY ?? item.y)
                    path.move(to:center); path.addLine(to:end)
                    if item.shape == .arrow {
                        let angle = atan2(end.y-center.y,end.x-center.x), length = 9*fontScale
                        path.move(to:CGPoint(x:end.x-cos(angle-0.45)*length,y:end.y-sin(angle-0.45)*length)); path.addLine(to:end)
                        path.addLine(to:CGPoint(x:end.x-cos(angle+0.45)*length,y:end.y-sin(angle+0.45)*length))
                    }
                case .text: break
                }
                if [.circle,.rectangle,.triangle,.point].contains(item.shape) { context.fill(path,with:.color(color.opacity(item.shape == .point ? 1 : 0.13))) }
                context.stroke(path,with:.color(color),lineWidth:2*fontScale)
                if let label = item.label {
                    context.draw(Text(label).font(.system(size:13*fontScale,weight:.semibold)).foregroundStyle(.white),at:center)
                }
            }
        }.background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
    }
}
