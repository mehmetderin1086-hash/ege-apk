import SwiftUI

/// Ayarlar › Ödünç bölümüne gömülen rezervasyon ayırma ayarları: süre okul günüyle sayılır,
/// hafta sonu ve tanımlı tatil aralıkları sayılmaz (`ReservationPolicy`).
struct OduncAyarlariBolumu: View {
    @AppStorage(ReservationPolicy.gunAnahtari) private var gun = ReservationPolicy.varsayilanGun
    @State private var tatiller = ReservationPolicy.ayarliTatiller()
    @State private var baslangic = Calendar.current.startOfDay(for: .now)
    @State private var bitis = Calendar.current.startOfDay(for: .now)

    private var aralikGecerli: Bool { bitis >= baslangic }

    var body: some View {
        Section {
            Stepper(value: $gun, in: ReservationPolicy.gunAraligi) {
                Text("Ayırma süresi: \(gun) okul günü")
            }
            .accessibilityIdentifier("loanSettings.holdDays")

            ForEach(tatiller) { tatil in
                HStack {
                    Label(Self.aralikMetni(tatil), systemImage: "calendar.badge.minus")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Kaldır", role: .destructive) { kaldir(tatil) }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
            DatePicker("Tatil başlangıcı", selection: $baslangic, displayedComponents: .date)
            DatePicker("Tatil bitişi", selection: $bitis, in: baslangic..., displayedComponents: .date)
            Button("Tatil aralığı ekle", systemImage: "plus.circle") { ekle() }
                .disabled(!aralikGecerli)
                .frame(minHeight: 44)
                .accessibilityIdentifier("loanSettings.addHoliday")
        } header: {
            Text("Rezervasyon ayırma süresi")
        } footer: {
            Text("Sıradaki öğrenciye haber verilince kitap bu kadar okul günü ayrılır. Hafta sonu ve eklediğiniz tatil aralıkları sayılmaz; Cuma 14.00'te haber verilen 2 günlük ayırma Salı 14.00'te biter. Değişiklik yeni haber verilen rezervasyonlara uygulanır.")
        }
        .onChange(of: gun) { _, yeni in
            let sinirli = min(max(yeni, ReservationPolicy.gunAraligi.lowerBound), ReservationPolicy.gunAraligi.upperBound)
            if sinirli != yeni { gun = sinirli }
        }
    }

    private func ekle() {
        guard aralikGecerli else { return }
        tatiller.append(ReservationPolicy.Tatil(baslangic: baslangic, bitis: bitis))
        tatiller.sort { $0.baslangic < $1.baslangic }
        ReservationPolicy.tatilleriKaydet(tatiller)
    }

    private func kaldir(_ tatil: ReservationPolicy.Tatil) {
        tatiller.removeAll { $0.id == tatil.id }
        ReservationPolicy.tatilleriKaydet(tatiller)
    }

    static func aralikMetni(_ tatil: ReservationPolicy.Tatil) -> String {
        let bicim = OduncMerkezi.tarihBicimi
        let aralik = tatil.aralik
        return aralik.start == aralik.end ? aralik.start.formatted(bicim) : "\(aralik.start.formatted(bicim)) – \(aralik.end.formatted(bicim))"
    }
}
