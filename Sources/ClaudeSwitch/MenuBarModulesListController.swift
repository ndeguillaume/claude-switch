import AppKit

/// Checkable list of menu bar modules shown in the settings window as a bezeled
/// table, with chevron buttons to move each module up or down one position in the
/// display order.
final class MenuBarModulesListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Module {
        let key: String
        let title: String
    }

    private var modules: [Module]
    private let isEnabled: (String) -> Bool
    private let setEnabled: (String, Bool) -> Void
    private let orderChanged: ([String]) -> Void
    private let tableView = NSTableView()

    init(
        modules: [Module],
        isEnabled: @escaping (String) -> Bool,
        setEnabled: @escaping (String, Bool) -> Void,
        orderChanged: @escaping ([String]) -> Void
    ) {
        self.modules = modules
        self.isEnabled = isEnabled
        self.setEnabled = setEnabled
        self.orderChanged = orderChanged
    }

    var preferredHeight: CGFloat {
        CGFloat(modules.count) * (tableView.rowHeight + tableView.intercellSpacing.height) + 4
    }

    func makeView() -> NSView {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("module")))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = false
        scroll.borderType = .bezelBorder
        return scroll
    }

    // MARK: - Rows

    func numberOfRows(in tableView: NSTableView) -> Int {
        modules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        let module = modules[index]
        let checkbox = NSButton(checkboxWithTitle: module.title, target: self, action: #selector(toggle(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(module.key)
        checkbox.state = isEnabled(module.key) ? .on : .off

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let up = chevronButton(symbol: "chevron.up", tooltip: L("settings.menuBar.moveUp"), action: #selector(moveUp(_:)))
        up.tag = index
        up.isEnabled = index > 0

        let down = chevronButton(symbol: "chevron.down", tooltip: L("settings.menuBar.moveDown"), action: #selector(moveDown(_:)))
        down.tag = index
        down.isEnabled = index < modules.count - 1

        let row = NSStackView(views: [checkbox, spacer, up, down])
        row.orientation = .horizontal
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 6)
        return row
    }

    private func chevronButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!,
            target: self,
            action: action
        )
        button.isBordered = false
        button.toolTip = tooltip
        return button
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        setEnabled(key, sender.state == .on)
    }

    @objc private func moveUp(_ sender: NSButton) {
        move(from: sender.tag, to: sender.tag - 1)
    }

    @objc private func moveDown(_ sender: NSButton) {
        move(from: sender.tag, to: sender.tag + 1)
    }

    private func move(from source: Int, to target: Int) {
        guard modules.indices.contains(source), modules.indices.contains(target) else { return }
        modules.swapAt(source, target)
        tableView.reloadData()
        orderChanged(modules.map(\.key))
    }
}
