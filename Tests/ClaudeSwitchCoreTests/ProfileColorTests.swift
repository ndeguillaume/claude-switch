import XCTest
@testable import ClaudeSwitchCore

final class ProfileColorTests: XCTestCase {
    func testHexRoundTrip() {
        let rgb = ProfileColorHex.rgb(from: "#FF9500")
        XCTAssertNotNil(rgb)
        XCTAssertEqual(ProfileColorHex.hex(red: rgb!.red, green: rgb!.green, blue: rgb!.blue), "#FF9500")
    }

    func testLowercaseAndBareHexParse() {
        XCTAssertNotNil(ProfileColorHex.rgb(from: "#ff9500"))
        XCTAssertNotNil(ProfileColorHex.rgb(from: "007aff"))
    }

    func testInvalidHexReturnsNil() {
        XCTAssertNil(ProfileColorHex.rgb(from: ""))
        XCTAssertNil(ProfileColorHex.rgb(from: "#FFF"))
        XCTAssertNil(ProfileColorHex.rgb(from: "#GGGGGG"))
        XCTAssertNil(ProfileColorHex.rgb(from: "#FF9500AA"))
    }

    func testHexClampsOutOfRangeComponents() {
        XCTAssertEqual(ProfileColorHex.hex(red: 2, green: -1, blue: 0.5), "#FF0080")
    }

    func testColorPersistsAcrossStoreReloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProfileStore(directory: directory)
        try store.add(name: "Perso", colorHex: "#FF9500")
        let reloaded = try ProfileStore(directory: directory)
        XCTAssertEqual(reloaded.profile(named: "Perso")?.colorHex, "#FF9500")
    }

    func testDefaultHexIsDeterministicAndInPalette() {
        let first = ProfileColorHex.defaultHex(forSeed: "ABC-123")
        XCTAssertEqual(first, ProfileColorHex.defaultHex(forSeed: "ABC-123"))
        XCTAssertTrue(ProfileColorHex.palette.contains(first))
        XCTAssertNotNil(ProfileColorHex.rgb(from: first))
    }
}
