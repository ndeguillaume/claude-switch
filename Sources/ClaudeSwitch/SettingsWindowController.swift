import AppKit

/// A macOS-style preferences window: a toolbar of icon items across the top, one
/// selectable item per pane, the window resizing to each pane's fitting size when
/// the selection changes.
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    struct Pane {
        let identifier: String
        let label: String
        let symbolName: String
        let view: NSView
    }

    let window: NSWindow
    private let panes: [Pane]

    init(title: String, panes: [Pane]) {
        precondition(!panes.isEmpty)
        self.panes = panes
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = title
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: "settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        select(panes[0].identifier)
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(panes[0].identifier)
        window.center()
    }

    private func select(_ identifier: String) {
        guard let pane = panes.first(where: { $0.identifier == identifier }) else { return }
        let size = pane.view.fittingSize
        window.contentView = pane.view
        // fittingSize is the content size; the toolbar sits outside it, so resize
        // by content rather than frame.
        window.setContentSize(size)
        window.title = pane.label
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        select(sender.itemIdentifier.rawValue)
    }

    // MARK: - NSToolbarDelegate

    private var itemIdentifiers: [NSToolbarItem.Identifier] {
        panes.map { NSToolbarItem.Identifier($0.identifier) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = panes.first(where: { $0.identifier == itemIdentifier.rawValue }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.label
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}
