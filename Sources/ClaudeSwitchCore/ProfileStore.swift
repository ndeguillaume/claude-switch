import Foundation

public struct Profile: Codable, Equatable {
    public let id: String
    public var name: String
    public var email: String?
    public var colorHex: String?
    public var oauthAccountData: Data?

    public var isCaptured: Bool { oauthAccountData != nil }

    public init(
        id: String = UUID().uuidString,
        name: String,
        email: String? = nil,
        colorHex: String? = nil,
        oauthAccountData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.colorHex = colorHex
        self.oauthAccountData = oauthAccountData
    }
}

public final class ProfileStore {
    public private(set) var profiles: [Profile]
    private let fileURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = saved
        } else {
            profiles = []
        }
    }

    public func profile(named name: String) -> Profile? {
        profiles.first { $0.name == name }
    }

    @discardableResult
    public func add(name: String, colorHex: String? = nil) throws -> Profile {
        let trimmed = try validated(name)
        guard profile(named: trimmed) == nil else {
            throw SwitchError.profileAlreadyExists(trimmed)
        }
        let profile = Profile(name: trimmed, colorHex: colorHex)
        profiles.append(profile)
        try save()
        return profile
    }

    public func rename(_ currentName: String, to newName: String) throws {
        let trimmed = try validated(newName)
        guard let index = profiles.firstIndex(where: { $0.name == currentName }) else {
            throw SwitchError.profileUnknown(currentName)
        }
        if trimmed == currentName { return }
        guard profile(named: trimmed) == nil else {
            throw SwitchError.profileAlreadyExists(trimmed)
        }
        profiles[index].name = trimmed
        try save()
    }

    @discardableResult
    public func remove(_ name: String) throws -> Profile {
        guard let index = profiles.firstIndex(where: { $0.name == name }) else {
            throw SwitchError.profileUnknown(name)
        }
        let removed = profiles.remove(at: index)
        try save()
        return removed
    }

    public func update(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw SwitchError.profileUnknown(profile.name)
        }
        profiles[index] = profile
        try save()
    }

    private func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SwitchError.invalidProfileName }
        return trimmed
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: fileURL, options: [.atomic])
    }
}
