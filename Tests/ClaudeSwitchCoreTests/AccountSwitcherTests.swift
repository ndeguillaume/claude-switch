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

    private func logIn(email: String, tokens: String) throws {
        try writeConfigFixture(to: configURL, email: email)
        try keychain.upsert(
            service: AccountSwitcher.activeService,
            item: KeychainItem(account: "nicolas", data: Data(tokens.utf8))
        )
    }

    private func service(_ name: String) -> String {
        switcher.profileService(for: store.profile(named: name)!)
    }

    func testCaptureStoresKeychainCopyAndEmail() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")

        try switcher.captureActiveAccount(into: "Perso")

        let copy = keychain.items[service("Perso")]
        XCTAssertEqual(copy?.data, Data("tokens-perso".utf8))
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

    func testActivateRestoresKeychainAndConfig() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro")
        try switcher.captureActiveAccount(into: "Pro")

        try switcher.activate("Perso")

        let active = keychain.items[AccountSwitcher.activeService]
        XCTAssertEqual(active?.data, Data("tokens-perso".utf8))
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
            item: KeychainItem(account: "nicolas", data: Data("tokens-pro-v2".utf8))
        )

        try switcher.activate("Perso")

        XCTAssertEqual(keychain.items[service("Pro")]?.data, Data("tokens-pro-v2".utf8))
    }

    func testActivateAfterRenameStillWorks() throws {
        try logIn(email: "perso@example.com", tokens: "tokens-perso")
        try switcher.captureActiveAccount(into: "Perso")
        try logIn(email: "pro@example.com", tokens: "tokens-pro")
        try switcher.captureActiveAccount(into: "Pro")

        try switcher.renameProfile("Perso", to: "Boulot")
        try switcher.activate("Boulot")

        XCTAssertEqual(keychain.items[AccountSwitcher.activeService]?.data, Data("tokens-perso".utf8))
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
}
