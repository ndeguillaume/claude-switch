import SwiftUI
import ClaudeSwitchCore

/// View state of the popover panel, rebuilt by the AppDelegate from the switcher and
/// the usage caches. Published on the main thread only.
final class PanelModel: ObservableObject {
    enum Tab: Hashable {
        case usage
        case accounts
    }

    @Published var tab: Tab = .usage
    @Published var rows: [ProfileRow] = []
    @Published var isRefreshing = false
    @Published var initError: String?

    var activeRow: ProfileRow? { rows.first { $0.isActive } }
    var hasCapturedProfile: Bool { rows.contains { $0.isCaptured } }
}

struct ProfileRow: Identifiable, Equatable {
    let id: String
    let name: String
    let email: String?
    let colorHex: String?
    let isActive: Bool
    let isCaptured: Bool
    let usage: UsageDisplay

    /// The profile's accent, falling back to the deterministic palette color for
    /// profiles that never chose one.
    var accent: Color {
        let hex = colorHex ?? ProfileColorHex.defaultHex(forSeed: id)
        guard let rgb = ProfileColorHex.rgb(from: hex) else { return .orange }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum UsageDisplay: Equatable {
    case notCaptured
    case loading
    case unavailable(String)
    /// staleReason non-nil = the last fetch failed transiently and these are the
    /// values from the last successful one.
    case ready(session: WindowDisplay, weekly: WindowDisplay?, staleReason: String?)
}

struct WindowDisplay: Equatable {
    let percent: Int
    let resetsAt: Date?
}

/// The panel never touches the switcher directly: every user intent goes through
/// these closures, owned by the AppDelegate.
struct PanelActions {
    var switchTo: (String) -> Void = { _ in }
    var capture: (String) -> Void = { _ in }
    var edit: (String) -> Void = { _ in }
    var delete: (String) -> Void = { _ in }
    var addProfile: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}
