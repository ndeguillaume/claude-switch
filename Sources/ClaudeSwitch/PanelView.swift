import SwiftUI
import ClaudeSwitchCore

struct PanelView: View {
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        Group {
            if let message = model.initError {
                InitErrorView(message: message, quit: actions.quit)
            } else {
                panel
            }
        }
        .frame(width: 320)
    }

    private var panel: some View {
        let accent = model.activeRow?.accent
        return VStack(spacing: 0) {
            PillSegmentedControl(
                selection: $model.tab,
                segments: [
                    .init(value: .usage, label: L("panel.tab.usage")),
                    .init(value: .accounts, label: L("panel.tab.accounts")),
                ]
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)

            SelfSizingScrollView(maxHeight: 420) {
                ProfileList(tab: model.tab, rows: model.rows, actions: actions)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.tab)
            }

            Divider()
            FooterView(model: model, actions: actions)
        }
        .tint(accent)
    }
}

// MARK: - Profile list

/// A single list of profile cards kept mounted across tabs. Only each card's body
/// swaps between the usage gauges and the account actions, so a profile's card —
/// and its avatar — keeps its view identity and updates in place instead of being
/// torn down and rebuilt (which made the avatar flicker on every tab change).
private struct ProfileList: View {
    let tab: PanelModel.Tab
    let rows: [ProfileRow]
    let actions: PanelActions

    // Usage lists captured profiles only; accounts lists them all.
    private var visibleRows: [ProfileRow] {
        tab == .usage ? rows.filter(\.isCaptured) : rows
    }

    var body: some View {
        VStack(spacing: 8) {
            if rows.isEmpty {
                EmptyProfilesView(addProfile: actions.addProfile)
            } else if tab == .usage && visibleRows.isEmpty {
                HintView(text: L("panel.usage.empty"))
            } else {
                ForEach(visibleRows) { row in
                    ProfileCard(tab: tab, row: row, actions: actions)
                }
                if tab == .accounts {
                    AddProfileRow(action: actions.addProfile)
                        // Enter only once the cards above have settled their new
                        // heights, otherwise the fade-in-down fights the layout
                        // still shifting the button's final position under it.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8))
                                .animation(.easeOut(duration: 0.22).delay(0.18)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))
                        ))
                }
            }
        }
    }
}

// MARK: - Pill segmented control

/// A capsule-outlined segmented control: the selected segment is a neutral filled
/// pill, sliding between positions on selection.
private struct PillSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    @Binding var selection: Value
    let segments: [Segment]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        )
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        return Text(segment.label)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .matchedGeometryEffect(id: "selectedPill", in: namespace)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                guard !isSelected else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selection = segment.value
                }
            }
    }
}

// MARK: - Card

/// One profile's card. The chrome (rounded wrapper) and header stay mounted across
/// tabs; only the body swaps, so the avatar never re-renders. The card grows and
/// shrinks in place as the body changes, animated by the caller.
private struct ProfileCard: View {
    let tab: PanelModel.Tab
    let row: ProfileRow
    let actions: PanelActions

    private var canSwitch: Bool { row.isCaptured && !row.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(row: row) {
                if tab == .usage, case .ready(_, _, .some(let reason)) = row.usage {
                    Image(systemName: "bolt.slash.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help(L("panel.usage.stale", reason))
                        .accessibilityLabel(L("panel.usage.stale", reason))
                }
            }

            body(for: tab)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Sequence the swap instead of stacking it on the resize: the old
                // body clears fast, the card settles its new height, then the new
                // body fades in once the frame has stopped moving.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.16)),
                    removal: .opacity.animation(.easeOut(duration: 0.1))
                ))
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .contextMenu {
            Button(L("panel.action.edit")) { actions.edit(row.name) }
            if canSwitch {
                Button(L("panel.action.switch")) { actions.switchTo(row.name) }
            }
            Button(L("panel.action.capture")) { actions.capture(row.name) }
            Divider()
            Button(role: .destructive) { actions.delete(row.name) } label: {
                Text(L("menu.delete"))
            }
        }
    }

    @ViewBuilder
    private func body(for tab: PanelModel.Tab) -> some View {
        switch tab {
        case .usage:
            UsageBody(row: row)
        case .accounts:
            AccountBody(row: row, canSwitch: canSwitch, actions: actions)
        }
    }
}

// MARK: - Usage body

private struct UsageBody: View {
    let row: ProfileRow

    var body: some View {
        Group {
            switch row.usage {
            case .notCaptured:
                EmptyView()
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("menu.usage.loading"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .unavailable(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .ready(let session, let weekly, _):
                VStack(spacing: 8) {
                    UsageGauge(title: L("panel.session"), window: session)
                    if let weekly {
                        UsageGauge(title: L("panel.week"), window: weekly)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UsageGauge: View {
    let title: String
    let window: WindowDisplay

    // Neutral while comfortable; color only appears as a warning: orange from 70%,
    // red from 90%. Muted variants of the system colors, the vivid ones shout too
    // loud on a small bar.
    private static let mutedOrange = Color(red: 0.72, green: 0.42, blue: 0.10)
    private static let mutedRed = Color(red: 0.68, green: 0.18, blue: 0.15)

    private var barColor: Color {
        switch UsageSeverity(percent: window.percent) {
        case .normal: .primary
        case .elevated: Self.mutedOrange
        case .critical: Self.mutedRed
        }
    }

    private var fraction: Double {
        min(1, max(0, Double(window.percent) / 100))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let resetsAt = window.resetsAt {
                    Text(L("panel.resets", ResetLabel.text(for: resetsAt)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        if window.percent > 0 {
                            Capsule()
                                .fill(barColor)
                                .frame(width: max(5, geometry.size.width * fraction))
                        }
                    }
                }
                .frame(height: 5)
                Text(L("panel.percent", window.percent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(barColor)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Accounts body

private struct AccountBody: View {
    let row: ProfileRow
    let canSwitch: Bool
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 2) {
            if canSwitch {
                Button(L("panel.action.switchShort")) { actions.switchTo(row.name) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.primary)
                    .help(L("panel.action.switch"))
            } else if !row.isCaptured {
                Button(L("panel.action.captureShort")) { actions.capture(row.name) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L("panel.action.capture"))
            }
            Spacer()
            if row.isCaptured {
                RowIconButton(symbol: "square.and.arrow.down", help: L("panel.action.capture")) {
                    actions.capture(row.name)
                }
            }
            RowIconButton(symbol: "pencil", help: L("panel.action.editHelp")) {
                actions.edit(row.name)
            }
            RowIconButton(symbol: "trash", help: L("panel.action.delete")) {
                actions.delete(row.name)
            }
        }
    }
}

private struct AddProfileRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L("panel.addProfile"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("n")
        .help(L("menu.addProfile"))
    }
}

private struct RowIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Footer

private struct FooterView: View {
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 2) {
            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                FooterIconButton(symbol: "arrow.clockwise", help: L("menu.refreshUsage"), action: actions.refresh)
                    .keyboardShortcut("r")
                    .disabled(!model.hasCapturedProfile)
            }
            FooterIconButton(symbol: "gearshape", help: L("menu.settings"), action: actions.openSettings)
                .keyboardShortcut(",")
            FooterIconButton(symbol: "power", help: L("menu.quit"), action: actions.quit)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct FooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Shared pieces

/// The one card header used by every tab: avatar, name + status badge, full email
/// below. Tabs only differ by the optional trailing accessory (e.g. the stale icon).
private struct CardHeader<Trailing: View>: View {
    let row: ProfileRow
    let trailing: Trailing

    init(row: ProfileRow, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.row = row
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(accent: row.accent, name: row.name, dimmed: !row.isCaptured, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if row.isActive {
                        BadgeView(text: L("panel.badge.active"), tint: row.accent)
                    } else if !row.isCaptured {
                        BadgeView(text: L("panel.badge.notCaptured"), tint: .gray)
                    }
                }
                // The exact address is how profiles are told apart: never truncate,
                // wrap instead, and let it be copied.
                Text(row.email ?? L("panel.row.noEmail"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

private struct AvatarView: View {
    let accent: Color
    let name: String?
    var dimmed = false
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.gradient)
                .opacity(dimmed ? 0.35 : 1)
            if let initial = name?.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct BadgeView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct EmptyProfilesView: View {
    let addProfile: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(L("panel.empty.title"))
                .font(.system(size: 13, weight: .semibold))
            Text(L("panel.empty.message"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("panel.addProfile"), action: addProfile)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }
}

private struct HintView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
    }
}

private struct InitErrorView: View {
    let message: String
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
            Button(L("menu.quit"), action: quit)
                .keyboardShortcut("q")
        }
        .padding(20)
    }
}

/// ScrollView that hugs its content until maxHeight, then scrolls. A plain ScrollView
/// always fills the proposed height, which would pad short panels with empty space.
private struct SelfSizingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content
    @State private var contentHeight: CGFloat = 1

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
