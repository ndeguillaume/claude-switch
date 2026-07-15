import Foundation

public enum SwitchError: LocalizedError, Equatable {
    case notLoggedIn
    case profileUnknown(String)
    case profileNotCaptured(String)
    case profileAlreadyExists(String)
    case invalidProfileName
    case keychain(OSStatus)
    case configUnreadable(String)
    case oauthAccountMissing
    case usageTokenMissing
    case usageRequestFailed(Int)
    case usageResponseUnreadable

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return localized("error.notLoggedIn")
        case .profileUnknown(let name):
            return localized("error.profileUnknown", name)
        case .profileNotCaptured(let name):
            return localized("error.profileNotCaptured", name)
        case .profileAlreadyExists(let name):
            return localized("error.profileAlreadyExists", name)
        case .invalidProfileName:
            return localized("error.invalidProfileName")
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            return localized("error.keychain", message)
        case .configUnreadable(let path):
            return localized("error.configUnreadable", path)
        case .oauthAccountMissing:
            return localized("error.oauthAccountMissing")
        case .usageTokenMissing:
            return localized("error.usageTokenMissing")
        case .usageRequestFailed(let status):
            return localized("error.usageRequestFailed", status)
        case .usageResponseUnreadable:
            return localized("error.usageResponseUnreadable")
        }
    }
}
