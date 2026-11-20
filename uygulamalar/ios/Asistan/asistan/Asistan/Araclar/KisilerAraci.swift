import Foundation
import FoundationModels
import Contacts

nonisolated struct KisilerAraci: Tool {
    let name = "kisiler"
    let description = "Rehberde ada göre kişi arar; telefon numaralarını ve e-postalarını döndürür."

    @Generable
    struct Arguments {
        @Guide(description: "Aranan ad ya da adın parçası") var ad: String
    }

    func call(arguments a: Arguments) async throws -> String {
        let depo = CNContactStore()
        guard try await depo.requestAccess(for: .contacts) else {
            await IzinKarti.ekle(.kisiler)
            return "Kişiler izni verilmedi."
        }
        let anahtarlar: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let p = CNContact.predicateForContacts(matchingName: a.ad)
        let kisiler = try depo.unifiedContacts(matching: p, keysToFetch: anahtarlar)
        if kisiler.isEmpty { return "'\(a.ad)' adında kişi bulunamadı." }
        return kisiler.prefix(8).map { k in
            let tel = k.phoneNumbers.map { "\($0.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)) ?? "tel"): \($0.value.stringValue)" }
            let ep = k.emailAddresses.map { "e-posta: \($0.value)" }
            return "• \(k.givenName) \(k.familyName): " + (tel + ep).joined(separator: ", ")
        }.joined(separator: "\n")
    }
}
