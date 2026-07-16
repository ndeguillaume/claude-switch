import XCTest
@testable import ClaudeSwitchCore

final class MenuBarModuleOrderTests: XCTestCase {
    func testEmptySavedOrderFallsBackToDefault() {
        XCTAssertEqual(MenuBarModuleOrder.resolve(saved: [], known: ["usage", "reset"]), ["usage", "reset"])
    }

    func testSavedOrderWins() {
        XCTAssertEqual(MenuBarModuleOrder.resolve(saved: ["reset", "usage"], known: ["usage", "reset"]), ["reset", "usage"])
    }

    func testStaleSavedKeyIsDropped() {
        XCTAssertEqual(MenuBarModuleOrder.resolve(saved: ["removed", "reset", "usage"], known: ["usage", "reset"]), ["reset", "usage"])
    }

    func testUnknownNewModuleAppendsAfterSavedOrder() {
        XCTAssertEqual(
            MenuBarModuleOrder.resolve(saved: ["reset", "usage"], known: ["usage", "weekly", "reset"]),
            ["reset", "usage", "weekly"]
        )
    }
}
