import CryptoKit
import XCTest
@testable import BrowserEngine

final class PasswordKeyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testCreatesAPrivateKeyFileAndReusesIt() throws {
        let keyURL = folder.appending(path: "Passwords.key"), vaultURL = folder.appending(path: "Passwords.vault")
        let first = try PasswordVault.localKey(at: keyURL, vaultURL: vaultURL, legacyKey: { XCTFail("sin contraseñas no hay que ir al Llavero"); return SymmetricKey(size: .bits256) })
        let second = try PasswordVault.localKey(at: keyURL, vaultURL: vaultURL, legacyKey: { XCTFail(); return SymmetricKey(size: .bits256) })

        XCTAssertEqual(first, second)
        let permissions = try FileManager.default.attributesOfItem(atPath: keyURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testBringsTheKeychainKeyWhenThereAreSavedPasswords() throws {
        let keyURL = folder.appending(path: "Passwords.key"), vaultURL = folder.appending(path: "Passwords.vault")
        try Data("cifrado".utf8).write(to: vaultURL)
        let legacy = SymmetricKey(data: Data(repeating: 7, count: 32))

        XCTAssertEqual(try PasswordVault.localKey(at: keyURL, vaultURL: vaultURL, legacyKey: { legacy }), legacy)
        XCTAssertEqual(try PasswordVault.localKey(at: keyURL, vaultURL: vaultURL, legacyKey: { XCTFail(); return legacy }), legacy)
    }
}
