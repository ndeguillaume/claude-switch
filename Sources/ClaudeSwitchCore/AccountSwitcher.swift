import Foundation

public final class AccountSwitcher {
    public static let activeService = "Claude Code-credentials"

    private let keychain: KeychainClient
    private let config: ClaudeConfigFile
    private let store: ProfileStore

    public init(keychain: KeychainClient, config: ClaudeConfigFile, store: ProfileStore) {
        self.keychain = keychain
        self.config = config
        self.store = store
    }

    public var profiles: [Profile] { store.profiles }

    // Keyed by id, not name: renaming a profile must not break the link to its Keychain copy.
    public func profileService(for profile: Profile) -> String {
        "ClaudeSwitch.profile.\(profile.id)"
    }

    @discardableResult
    public func addProfile(named name: String) throws -> Profile {
        try store.add(name: name)
    }

    public func renameProfile(_ currentName: String, to newName: String) throws {
        try store.rename(currentName, to: newName)
    }

    public func deleteProfile(_ name: String) throws {
        let removed = try store.remove(name)
        try keychain.delete(service: profileService(for: removed))
    }

    public func captureActiveAccount(into name: String) throws {
        guard var profile = store.profile(named: name) else {
            throw SwitchError.profileUnknown(name)
        }
        guard let active = try keychain.read(service: Self.activeService),
              ClaudeCredential.hasAccessToken(active.data)
        else {
            throw SwitchError.notLoggedIn
        }
        let oauthAccountData = try config.readOAuthAccount()
        try keychain.upsert(service: profileService(for: profile), item: active)
        profile.oauthAccountData = oauthAccountData
        profile.email = ClaudeConfigFile.email(fromOAuthAccountData: oauthAccountData)
        try store.update(profile)
    }

    public func activate(_ name: String) throws {
        guard let profile = store.profile(named: name) else {
            throw SwitchError.profileUnknown(name)
        }
        guard profile.isCaptured,
              let oauthAccountData = profile.oauthAccountData,
              let item = try keychain.read(service: profileService(for: profile))
        else {
            throw SwitchError.profileNotCaptured(name)
        }
        guard ClaudeCredential.hasAccessToken(item.data) else {
            throw SwitchError.credentialEmpty(name)
        }
        // Re-capture the current profile before overwriting it: the claude CLI refreshes
        // its tokens in the background, and a stale snapshot would make switching back impossible.
        if let current = activeProfileName(), current != name {
            try? captureActiveAccount(into: current)
        }
        try keychain.upsert(service: Self.activeService, item: item)
        try config.writeOAuthAccount(oauthAccountData)
    }

    /// Keychain service to read a profile's usage token from. The active profile is
    /// read from the live item the CLI keeps refreshed; the others from their snapshot,
    /// whose token may have expired since capture.
    public func usageTokenService(forProfileNamed name: String) -> String? {
        guard let profile = store.profile(named: name) else { return nil }
        return name == activeProfileName() ? Self.activeService : profileService(for: profile)
    }

    public func activeProfileName() -> String? {
        guard let email = try? config.activeEmail(), email.isEmpty == false else { return nil }
        return store.profiles.first { $0.email == email }?.name
    }
}
