import SwiftUI

struct QiblaView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PrayerTimeStore
    @StateObject private var qibla = QiblaManager()

    private static let hmFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                VStack(spacing: 24) {
                    EzanPageHeader(eyebrow: "Yönünüzü bulun", title: "Kıble", subtitle: qibla.usingLiveLocation ? "Anlık konumunuzdan Kâbe yönü" : "Kayıtlı konum: \(settings.location?.name ?? "Konum seçilmedi")")
                        .padding(.horizontal, 24)

                    if qibla.bearingAvailable {
                        compass

                        VStack(spacing: 4) {
                            Text("\(Int(qibla.qiblaBearing.rounded()))°")
                                .font(SekineFont.hugeTime(settings.fontScale).monospacedDigit())
                                .foregroundStyle(Palette.accent)
                            Text("Kuzeyden Kâbe yönüne açı")
                                .font(SekineFont.caption(settings.fontScale))
                                .foregroundStyle(Palette.textSecondary)
                        }

                        if !qibla.headingAvailable {
                            Text("Pusula bu cihazda kullanılamıyor. Yukarıdaki açı, kuzeye göre kıble yönünü gösterir.")
                                .font(SekineFont.caption(settings.fontScale))
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("Telefonu düz tutun ve oku yeşil işarete hizalayın.")
                                .font(SekineFont.caption(settings.fontScale))
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    } else {
                        // Kıble açısı hesaplanamıyor: yanlış yön göstermektense hiç
                        // göstermeyip konum izni isteriz.
                        needsLocationNotice
                    }

                    if let qiblaTime = store.today?.qiblaTime {
                        VStack(spacing: 2) {
                            Label("Kıble saati \(Self.hmFormatter.string(from: qiblaTime))",
                                  systemImage: "sun.max.fill")
                                .font(SekineFont.caption(settings.fontScale))
                                .foregroundStyle(Palette.gold)
                            Text("Bu saatte güneşe döndüğünüzde tam kıbleye bakarsınız.")
                                .font(SekineFont.caption(settings.fontScale))
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                    }

                    NavigationLink {
                        NearbyMosquesView()
                    } label: {
                        Label("Yakındaki Camileri Haritada Gör", systemImage: "building.columns.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Palette.accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 6)

                    Spacer()
                }
                .padding(.top, 24).padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear { qibla.start(from: settings.location) }
        .onDisappear { qibla.stop() }
    }

    /// Kıble açısı hesaplanamadığında gösterilir. Yanlış bir yön göstermek yerine
    /// kullanıcıdan konum izni istenir; vakitler bundan etkilenmez.
    @ViewBuilder private var needsLocationNotice: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Palette.textSecondary)
            Text("Kıble yönü için konumunuz gerekiyor")
                .font(SekineFont.row(settings.fontScale))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("Doğru yönü gösterebilmek için konumunuzu bilmemiz gerekiyor. Kıble yönü cihazınızda hesaplanır. Namaz vakitleri konum izni olmadan da çalışmaya devam eder.")
                .font(SekineFont.caption(settings.fontScale))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            if qibla.authorizationStatus == .denied || qibla.authorizationStatus == .restricted {
                Button("Ayarlar'da konum iznini aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Konum iznine izin ver") {
                    qibla.requestPermission()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 32)
    }

    private var compass: some View {
        ZStack {
            Circle().fill(EzanDesign.heroGradient)
            Circle().stroke(EzanDesign.gold.opacity(0.45), lineWidth: 1).padding(14)
            ForEach(0..<60, id: \.self) { tick in
                Capsule().fill(tick.isMultiple(of: 5) ? EzanDesign.gold : .white.opacity(0.25))
                    .frame(width: tick.isMultiple(of: 5) ? 2 : 1, height: tick.isMultiple(of: 5) ? 12 : 5)
                    .offset(y: -113).rotationEffect(.degrees(Double(tick) * 6))
            }
            VStack { Text("K"); Spacer(); Text("G") }.padding(37)
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            HStack { Text("B"); Spacer(); Text("D") }.padding(37)
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).padding(65)
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 75, weight: .ultraLight)).foregroundStyle(EzanDesign.gold)
                .rotationEffect(.degrees(qibla.qiblaBearing - qibla.heading))
            Circle().fill(.white).frame(width: 8, height: 8)
        }.frame(width: 280, height: 280)
            .shadow(color: EzanDesign.forest.opacity(0.2), radius: 18, y: 8)
            .accessibilityLabel("Kıble pusulası, kuzeyden \(Int(qibla.qiblaBearing)) derece")
    }
}
