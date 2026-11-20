import SwiftUI

/// İlk görevleri gösteren kısa tanıtım; izinler ihtiyaç duyulduğunda istenir.
/// İlk açılışta MainTabView, sonradan Ayarlar > Yardım açar. Son adım okulu tanıtır; son düğmeler
/// Ekle sekmesine ya da tablodan içe aktarmaya götürür.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingShown") private var onboardingShown = false
    @AppStorage("schoolName") private var okulAdi = ""
    @AppStorage("loanDurationDays") private var oduncGunu = 15
    @AppStorage(Tasarim.sadeModAnahtari) private var sadeMod = false
    @State private var page = 0
    /// Son düğmeyle Ekle'ye geçilince haber verilir: tanıtımı bir sayfanın içinden açan ekran
    /// (Ayarlar) kendini de kapatsın, Ekle arkada kalmasın.
    var ekleyeGecildi: (() -> Void)? = nil

    private struct Step {
        let icon: String
        let title: String
        let detail: String
    }
    private let steps = [
        Step(icon: "plus.viewfinder", title: "İlk kitabını ekle", detail: "Ekle’de barkod, kapak fotoğrafı, ses veya elle giriş seç. Okunan bilgileri incele; aynı kitabın başka bir nüshası varsa mevcut kayda ekle."),
        Step(icon: "books.vertical", title: "Kitabı yerinde bul", detail: "Kitaplar’da ad, yazar veya ISBN ile ara. Dolap, raf ve nüsha bilgileri kitabın nerede ve kaç adet olduğunu gösterir. Kategori ve seri görünümlerini de kullanabilirsin."),
        Step(icon: "person.badge.clock", title: "Ödünç ver, iade al", detail: "Ödünç’te öğrenci seçip kitabı ver; son tarihi, gecikmeleri ve iade işlemlerini takip et. Öğrenciler, raporlar, yedek ve ayarlar Yönetim’de bir arada.")
    ]
    /// Bilgi adımları + "Okulunu tanıt" adımı.
    private var toplamAdim: Int { steps.count + 1 }
    private var sonAdim: Bool { page == toplamAdim - 1 }

    var body: some View {
        VStack(spacing: 18) {
            Text("\(page + 1) / \(toplamAdim)").font(.subheadline).foregroundStyle(.secondary)
                .accessibilityLabel("Tanıtım, \(toplamAdim) adımın \(page + 1). adımı")
            TabView(selection: $page) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ScrollView {
                        VStack(spacing: 20) {
                            Image(systemName: step.icon).font(.system(size: 60)).foregroundStyle(KitapTema.ana).accessibilityHidden(true)
                            Text(step.title).font(.title.weight(.bold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                            Text(step.detail).font(.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Text("Kamera ve mikrofon izinleri ilgili işlemi başlatınca sorulur. Yapay zekâ için bağlantı ve veri paylaşım tercihlerini Ayarlar’dan yönetebilirsin.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                    .tag(index)
                }
                okulAdimi.tag(steps.count)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            if sonAdim {
                VStack(spacing: 10) {
                    Button("Kitap ekle") {
                        DerinBaglanti.shared.hedefSekme = .katalog
                        ekleyeGecildi?()
                        finish()
                    }
                    .buttonStyle(.kitapDolu())
                    .accessibilityIdentifier("onboarding.addBook")
                    Button("Tablodan içe aktar") {
                        KutuphaneRotasi.shared.bekleyenYonetimAraci = .csvImport
                        DerinBaglanti.shared.hedefSekme = .yonetim
                        ekleyeGecildi?()
                        finish()
                    }
                    .buttonStyle(.kitapTonlu())
                    .accessibilityIdentifier("onboarding.importTable")
                }
                .padding(.horizontal, 24)
            } else {
                Button("Devam") {
                    withAnimation(reduceMotion ? nil : .default) { page += 1 }
                }
                .buttonStyle(.kitapDolu())
                .padding(.horizontal, 24)
            }
            Button("Atla") { finish() }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
        // Aşağı çekerek kapatma da tanıtımı "görüldü" sayar; her açılışta geri gelmez.
        .onDisappear { onboardingShown = true }
    }

    private var okulAdimi: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "building.columns").font(.system(size: 60)).foregroundStyle(KitapTema.ana).accessibilityHidden(true)
                Text("Okulunu tanıt").font(.title.weight(.bold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    TextField("Okul adı", text: $okulAdi)
                        .textContentType(.organizationName)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("onboarding.schoolName")
                    Divider().padding(.leading, 16)
                    Stepper("Ödünç süresi: \(oduncGunu) gün", value: $oduncGunu, in: 1...180)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                    Divider().padding(.leading, 16)
                    Toggle("Sade mod (büyük yazı, temel işlemler)", isOn: $sadeMod)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                Text("Rol kilidi: Ayarlar > Güvenlik’ten açarsan öğrenci görevli ödünç verir ve iade alır; silme ve ayarlar Face ID ister.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Bunları sonra Ayarlar’dan değiştirebilirsin. Kitaplarını tek tek ekleyebilir ya da Excel/CSV tablosundan içe aktarabilirsin.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func finish() {
        onboardingShown = true
        dismiss()
    }
}
