import XCTest
@testable import Ritim

final class SecureSettingsTests: XCTestCase {
    func testCredentialPersistsInKeychain() throws {
        let original = SecureSettings.readToken()
        defer { try? SecureSettings.saveToken(original) }
        let temporary = "test-" + UUID().uuidString
        try SecureSettings.saveToken(temporary)
        // Avoid assertion output that could expose credential values.
        XCTAssertTrue(SecureSettings.readToken() == temporary, "Anahtar zinciri yazma/okuma eşleşmeli")
    }
}
