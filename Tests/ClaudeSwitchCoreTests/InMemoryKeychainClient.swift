import Foundation
@testable import ClaudeSwitchCore

final class InMemoryKeychainClient: KeychainClient {
    private(set) var items: [String: KeychainItem] = [:]

    func read(service: String) throws -> KeychainItem? {
        items[service]
    }

    func upsert(service: String, item: KeychainItem) throws {
        items[service] = item
    }

    func delete(service: String) throws {
        items[service] = nil
    }
}
