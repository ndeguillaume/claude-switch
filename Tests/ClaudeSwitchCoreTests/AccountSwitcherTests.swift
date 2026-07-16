import XCTest
@testable import ClaudeSwitchCore

final class AccountSwitcherTests: XCTestCase {
    private var directory: URL!
    private var configURL: URL!
    private var keychain: InMemoryKeychainClient!
    private var store: ProfileStore!
    private var switcher: AccountSwitcher!

    override func setUpWithError() throws {
        directory = try makeTempDirectory()
        configURL = directory.appendingPathComponent(".claude.json")
        keychain = InMemoryKeychainClient()
        store = try ProfileStore(directory: directory)
        switcher = AccountSwitcher(
            keychain: keychain,
            config: ClaudeConfigFile(url: configURL),
            store: store
        )
        try switcher.addProfile(named: "Perso")
        try switcher.addProfile(named: "Pro")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    // A distinct but structurally valid credential blob: the guard against empty
    // accessToken must pass, while the marker keeps each fixture's data comparable.
    private func credential(_ marker: String) -> Data {
        Data(#"{"claudeAiOauth":{"accessToken":"\#(marker)","refreshToken":"r"}}"#.utf8)
    }

    private func logIn(email: String, tokens: String) throws {
        try writeConfigFixture(to: configURL, email: email)
        try keychain.upsert(
            service: AccountSwitcher.activeService,
            item: KeychainItem(account: "nicolas", data: credential(tokens))
        )
    }

    private func service(_ name: String) -> String {
        switcher.profileService(for: store.profile(named: name)!)
    }

    func testCaptureStoresKeychainCopyAndEmail() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")

        try switcher.captureActiveAccount(into: "Perso")

        let copy = keychain.items[service("Perso")]
        XCTAssertEqual(copy?.data, credential("tokens-perso"))
        XCTAssertEqual(copy?.account, "nicolas")
        let profile = store.profile(named: "Perso")!
        XCTAssertEqual(profile.email, "perso@example.com")
        XCTAssertEqual(switcher.activeProfileName(), "Perso")
    }

    func testCaptureWithoutActiveAccountThrows() throws {
        try writeConfigFixture(to: configURL, email: "perso@example.com")

        XCTAssertThrowsError(try switcher.captureActiveAccount(into: "Perso")) { error in
            XCTAssertEqual(error as? SwitchError, .notLoggedIn)
        }
    }

    func testCaptureRejectsEmptyTokenCredential() throws {
        try writeConfigFixture(to: configURL, email: "perso@example.com")
        try keychain.upsert(
            service: AccountSwitcher.activeService,
            item: KeychainItem(account: "nicolas", data: credential(""))
        )

        XCTAssertThrowsError(try switcher.captureActiveAccount(into: "Perso")) { error in
            XCTAssertEqual(error as? SwitchError, .notLoggedIn)
        }
        XCTAssertNil(keychain.items[service("Perso")])
    }

    func testActivateRejectsProfileWithEmptyToken() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        // Simule une copie empoisonnée par une capture antérieure à tokens vides.
        try keychain.upsert(
            service: service("Perso"),
            item: KeychainItem(account: "nicolas", data: credential(""))
        )

        XCTAssertThrowsError(try switcher.activate("Perso")) { error in
            XCTAssertEqual(error as? SwitchError, .credentialEmpty("Perso"))
        }
    }

    func testActivateRestoresKeychainAndConfig() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro")
        try switcher.captureActiveAccount(into: "Pro")

        try switcher.activate("Perso")

        let active = keychain.items[AccountSwitcher.activeService]
        XCTAssertEqual(active?.data, credential("tokens-perso"))
        XCTAssertEqual(try ClaudeConfigFile(url: configURL).activeEmail(), "perso@example.com")
        XCTAssertEqual(switcher.activeProfileName(), "Perso")
    }

    func testActivateRecapturesCurrentProfileFirst() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro-v1")
        try switcher.captureActiveAccount(into: "Pro")

        // Le CLI claude rafraîchit ses tokens : l'item actif diverge du snapshot Pro.
        try keychain.upsert(
            service: AccountSwitcher.activeService,
            item: KeychainItem(account: "nicolas", data: credential("tokens-pro-v2"))
        )

        try switcher.activate("Perso")

        XCTAssertEqual(keychain.items[service("Pro")]?.data, credential("tokens-pro-v2"))
    }

    func testActivateAfterRenameStillWorks() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro")
        try switcher.captureActiveAccount(into: "Pro")

        try switcher.renameProfile("Perso", to: "Boulot")
        try switcher.activate("Boulot")

        XCTAssertEqual(keychain.items[AccountSwitcher.activeService]?.data, credential("tokens-perso"))
        XCTAssertEqual(switcher.activeProfileName(), "Boulot")
    }

    func testActivateUncapturedProfileThrows() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")

        XCTAssertThrowsError(try switcher.activate("Pro")) { error in
            XCTAssertEqual(error as? SwitchError, .profileNotCaptured("Pro"))
        }
    }

    func testActivateUnknownProfileThrows() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")

        XCTAssertThrowsError(try switcher.activate("Inconnu")) { error in
            XCTAssertEqual(error as? SwitchError, .profileUnknown("Inconnu"))
        }
    }

    func testDeleteRemovesProfileAndKeychainCopy() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        let persoService = service("Perso")

        try switcher.deleteProfile("Perso")

        XCTAssertNil(store.profile(named: "Perso"))
        XCTAssertNil(keychain.items[persoService])
        XCTAssertNotNil(keychain.items[AccountSwitcher.activeService])
    }

    func testActiveProfileNameUnknownWhenNoMatch() throws {
        try writeConfigFixture(to: configURL, email: "autre@example.com")
        XCTAssertNil(switcher.activeProfileName())
    }

    func testUsageTokenServiceUsesLiveItemForActiveProfile() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")

        XCTAssertEqual(switcher.usageTokenService(forProfileNamed: "Perso"), AccountSwitcher.activeService)
    }

    func testUsageTokenServiceUsesSnapshotForInactiveProfile() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro")
        try switcher.captureActiveAccount(into: "Pro")
        // Perso is now inactive (Pro is active).
        XCTAssertEqual(switcher.activeProfileName(), "Pro")

        XCTAssertEqual(switcher.usageTokenService(forProfileNamed: "Perso"), service("Perso"))
    }

    func testUsageTokenServiceUnknownProfileIsNil() {
        XCTAssertNil(switcher.usageTokenService(forProfileNamed: "Inconnu"))
    }
}
