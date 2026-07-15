import XCTest
@testable import ClaudeSwitchCore

final class ProfileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try makeTempDirectory()
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStartsEmpty() throws {
        let store = try ProfileStore(directory: directory)
        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testAddAndPersistAcrossReload() throws {
        let store = try ProfileStore(directory: directory)
        let added = try store.add(name: "  Perso  ")
        XCTAssertEqual(added.name, "Perso")
        XCTAssertFalse(added.isCaptured)

        let reloaded = try ProfileStore(directory: directory)
        XCTAssertEqual(reloaded.profiles.map(\.name), ["Perso"])
        XCTAssertEqual(reloaded.profiles[0].id, added.id)
    }

    func testAddDuplicateThrows() throws {
        let store = try ProfileStore(directory: directory)
        try store.add(name: "Perso")
        XCTAssertThrowsError(try store.add(name: "Perso")) { error in
            XCTAssertEqual(error as? SwitchError, .profileAlreadyExists("Perso"))
        }
    }

    func testAddEmptyNameThrows() throws {
        let store = try ProfileStore(directory: directory)
        XCTAssertThrowsError(try store.add(name: "   ")) { error in
            XCTAssertEqual(error as? SwitchError, .invalidProfileName)
        }
    }

    func testRenameKeepsIdAndData() throws {
        let store = try ProfileStore(directory: directory)
        var profile = try store.add(name: "Perso")
        profile.oauthAccountData = Data("{}".utf8)
        try store.update(profile)

        try store.rename("Perso", to: "Boulot")

        let renamed = store.profile(named: "Boulot")!
        XCTAssertEqual(renamed.id, profile.id)
        XCTAssertTrue(renamed.isCaptured)
        XCTAssertNil(store.profile(named: "Perso"))
    }

    func testRenameToExistingNameThrows() throws {
        let store = try ProfileStore(directory: directory)
        try store.add(name: "Perso")
        try store.add(name: "Pro")
        XCTAssertThrowsError(try store.rename("Perso", to: "Pro")) { error in
            XCTAssertEqual(error as? SwitchError, .profileAlreadyExists("Pro"))
        }
    }

    func testRenameToSameNameIsNoOp() throws {
        let store = try ProfileStore(directory: directory)
        try store.add(name: "Perso")
        try store.rename("Perso", to: "Perso")
        XCTAssertEqual(store.profiles.map(\.name), ["Perso"])
    }

    func testRemove() throws {
        let store = try ProfileStore(directory: directory)
        try store.add(name: "Perso")
        try store.add(name: "Pro")

        let removed = try store.remove("Perso")

        XCTAssertEqual(removed.name, "Perso")
        XCTAssertEqual(store.profiles.map(\.name), ["Pro"])
        let reloaded = try ProfileStore(directory: directory)
        XCTAssertEqual(reloaded.profiles.map(\.name), ["Pro"])
    }

    func testRemoveUnknownThrows() throws {
        let store = try ProfileStore(directory: directory)
        XCTAssertThrowsError(try store.remove("Inconnu")) { error in
            XCTAssertEqual(error as? SwitchError, .profileUnknown("Inconnu"))
        }
    }

    func testLegacyFileWithoutIdsIsDiscarded() throws {
        let legacy = #"[{"name": "Perso"}, {"name": "Pro"}]"#
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("profiles.json"))

        let store = try ProfileStore(directory: directory)
        XCTAssertTrue(store.profiles.isEmpty)
    }
}
