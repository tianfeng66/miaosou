import AppKit

final class SearchWindowController: NSWindowController, NSWindowDelegate {
    private let searchField = NSSearchField()
    private let kindPopup = NSPopUpButton()
    private let scopePopup = NSPopUpButton()
    private let hideSystemButton = NSButton(checkboxWithTitle: "隐藏系统文件", target: nil, action: nil)
    private let tableView = KeyTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    private let searcher = SpotlightSearch()
    private var hits: [FileHit] = []
    private var debounceWork: DispatchWorkItem?
    private var searchStartedAt = Date()
    private let sizeFormatter = ByteCountFormatter()
    private let dateFormatter = DateFormatter()
    private var iconCache: [String: NSImage] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "秒搜"
        window.minSize = NSSize(width: 720, height: 420)
        window.center()
        window.setFrameAutosaveName("Miaosou.MainWindow")
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.windowBackgroundColor
        self.init(window: window)
        window.delegate = self
        buildUI()
        wireSearch()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.makeFirstResponder(searchField)
    }

    private func buildUI() {
        guard let window else { return }
        let root = NSView()
        root.wantsLayer = true
        window.contentView = root

        searchField.placeholderString = "输入文件名，支持 * ? 通配符，空格表示同时包含，ext:pdf 按后缀"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        searchField.focusRingType = .default
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        searchField.delegate = self

        kindPopup.addItems(withTitles: ["全部", "文件", "文件夹", "图片", "视频", "文档"])
        kindPopup.target = self
        kindPopup.action = #selector(filtersChanged(_:))

        scopePopup.addItems(withTitles: ["主目录", "整台电脑"])
        scopePopup.target = self
        scopePopup.action = #selector(filtersChanged(_:))

        hideSystemButton.state = .on
        hideSystemButton.target = self
        hideSystemButton.action = #selector(filtersChanged(_:))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "准备就绪 · 输入文件名开始搜索"

        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        emptyLabel.stringValue = "在上方输入文件名，像 Windows 上的 Everything 一样即时列出结果。\n\n示例：截图   *.png   发票 ext:pdf   合同 /Downloads"
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = false

        sizeFormatter.countStyle = .file
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "zh_CN")

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 26
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = NSColor.separatorColor.withAlphaComponent(0.35)
        tableView.doubleAction = #selector(openSelected(_:))
        tableView.target = self
        tableView.menu = makeContextMenu()
        tableView.onEnter = { [weak self] in self?.openSelected(nil) }
        tableView.onCmdEnter = { [weak self] in self?.revealSelected(nil) }
        tableView.onEscape = { [weak self] in
            self?.searchField.stringValue = ""
            self?.window?.makeFirstResponder(self?.searchField)
            self?.runSearch()
        }

        addColumn("name", title: "名称", width: 260, min: 120)
        addColumn("parent", title: "路径", width: 420, min: 160)
        addColumn("size", title: "大小", width: 90, min: 70)
        addColumn("date", title: "修改时间", width: 150, min: 110)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let header = NSView()
        let footer = NSView()

        [searchField, kindPopup, scopePopup, hideSystemButton, header, scroll, footer, statusLabel, spinner, countLabel, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        header.addSubview(searchField)
        header.addSubview(kindPopup)
        header.addSubview(scopePopup)
        header.addSubview(hideSystemButton)
        footer.addSubview(spinner)
        footer.addSubview(statusLabel)
        footer.addSubview(countLabel)
        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(footer)
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 84),

            searchField.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            kindPopup.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            kindPopup.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            kindPopup.widthAnchor.constraint(equalToConstant: 110),

            scopePopup.centerYAnchor.constraint(equalTo: kindPopup.centerYAnchor),
            scopePopup.leadingAnchor.constraint(equalTo: kindPopup.trailingAnchor, constant: 8),
            scopePopup.widthAnchor.constraint(equalToConstant: 110),

            hideSystemButton.centerYAnchor.constraint(equalTo: kindPopup.centerYAnchor),
            hideSystemButton.leadingAnchor.constraint(equalTo: scopePopup.trailingAnchor, constant: 12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            spinner.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),

            countLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -20),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
    }

    private func addColumn(_ id: String, title: String, width: CGFloat, min: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = min
        column.resizingMask = .autoresizingMask
        if id == "size" || id == "date" {
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
        } else {
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        }
        tableView.addTableColumn(column)
    }

    private func wireSearch() {
        searcher.rememberHideSystem(hideSystemButton.state == .on)
        searcher.setHandler { [weak self] hits, total, finished in
            self?.applyResults(hits, total: total, finished: finished)
        }
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        scheduleSearch()
    }

    @objc private func filtersChanged(_ sender: Any) {
        searcher.rememberHideSystem(hideSystemButton.state == .on)
        runSearch()
    }

    private func scheduleSearch() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runSearch()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func runSearch() {
        let text = searchField.stringValue
        searchStartedAt = Date()
        let kind = KindFilter(rawValue: kindPopup.indexOfSelectedItem) ?? .all
        let scope = SearchScope(rawValue: scopePopup.indexOfSelectedItem) ?? .home
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            spinner.stopAnimation(nil)
            hits = []
            tableView.reloadData()
            emptyLabel.isHidden = false
            statusLabel.stringValue = "准备就绪 · 输入文件名开始搜索"
            countLabel.stringValue = ""
            searcher.stop()
            return
        }
        spinner.startAnimation(nil)
        statusLabel.stringValue = "正在搜索…"
        emptyLabel.isHidden = true
        searcher.search(
            text: text,
            kind: kind,
            scope: scope,
            hideSystem: hideSystemButton.state == .on
        )
    }

    private func applyResults(_ hits: [FileHit], total: Int, finished: Bool) {
        self.hits = hits
        tableView.reloadData()
        emptyLabel.isHidden = !hits.isEmpty || searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hits.isEmpty, !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyLabel.stringValue = "没有匹配的文件名"
            emptyLabel.isHidden = false
        }
        if finished {
            spinner.stopAnimation(nil)
        }
        let ms = Int(Date().timeIntervalSince(searchStartedAt) * 1000)
        let shown = hits.count
        if total > shown {
            statusLabel.stringValue = "找到 \(total.formatted()) 项，显示前 \(shown) 项 · \(ms) ms · Spotlight"
        } else {
            statusLabel.stringValue = "找到 \(total.formatted()) 项 · \(ms) ms · Spotlight"
        }
        countLabel.stringValue = scopePopup.indexOfSelectedItem == 0 ? "范围：主目录" : "范围：整台电脑"
        if tableView.selectedRow < 0, !hits.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func selectedHits() -> [FileHit] {
        tableView.selectedRowIndexes.compactMap { $0 >= 0 && $0 < hits.count ? hits[$0] : nil }
    }

    @objc func focusSearch(_ sender: Any?) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    @objc func openSelected(_ sender: Any?) {
        let items = selectedHits()
        guard !items.isEmpty else { return }
        for hit in items {
            NSWorkspace.shared.open(hit.fileURL)
        }
    }

    @objc func revealSelected(_ sender: Any?) {
        let urls = selectedHits().map(\.fileURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func copyPath(_ sender: Any?) {
        let paths = selectedHits().map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    @objc func copyName(_ sender: Any?) {
        let names = selectedHits().map(\.name).joined(separator: "\n")
        guard !names.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(names, forType: .string)
    }

    @objc func openTerminal(_ sender: Any?) {
        guard let hit = selectedHits().first else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: hit.path, isDirectory: &isDir)
        let dir = isDir.boolValue ? hit.path : hit.parent
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", dir]
        try? proc.run()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开", action: #selector(openSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "在访达中显示", action: #selector(revealSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "在终端中打开所在目录", action: #selector(openTerminal(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "拷贝完整路径", action: #selector(copyPath(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "拷贝文件名", action: #selector(copyName(_:)), keyEquivalent: "")
        return menu
    }
}

extension SearchWindowController: NSSearchFieldDelegate, NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(moveDown(_:)) {
            window?.makeFirstResponder(tableView)
            if tableView.numberOfRows > 0 {
                tableView.selectRowIndexes(IndexSet(integer: max(tableView.selectedRow, 0)), byExtendingSelection: false)
            }
            return true
        }
        if commandSelector == #selector(insertNewline(_:)) {
            openSelected(nil)
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                runSearch()
            }
            return true
        }
        return false
    }
}

extension SearchWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        hits.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < hits.count else { return nil }
        let hit = hits[row]
        let id = tableColumn.identifier
        let cellId = NSUserInterfaceItemIdentifier("cell-\(id.rawValue)")
        let cell = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView ?? makeCell(id: cellId, withIcon: id.rawValue == "name")

        switch id.rawValue {
        case "name":
            cell.textField?.stringValue = hit.name
            cell.textField?.lineBreakMode = .byTruncatingTail
            cell.imageView?.image = icon(for: hit)
        case "parent":
            cell.textField?.stringValue = hit.parent
            cell.textField?.lineBreakMode = .byTruncatingMiddle
            cell.imageView?.image = nil
        case "size":
            if hit.isDirectory {
                cell.textField?.stringValue = "—"
            } else if let size = hit.size {
                cell.textField?.stringValue = sizeFormatter.string(fromByteCount: size)
            } else {
                cell.textField?.stringValue = "—"
            }
            cell.textField?.alignment = .right
            cell.imageView?.image = nil
        case "date":
            if let modified = hit.modified {
                cell.textField?.stringValue = dateFormatter.string(from: modified)
            } else {
                cell.textField?.stringValue = "—"
            }
            cell.imageView?.image = nil
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
        let ascending = descriptor.ascending
        hits.sort { lhs, rhs in
            let result: ComparisonResult
            switch key {
            case "name":
                result = lhs.name.localizedStandardCompare(rhs.name)
            case "parent":
                result = lhs.parent.localizedStandardCompare(rhs.parent)
            case "size":
                result = (lhs.size ?? -1) < (rhs.size ?? -1) ? .orderedAscending : (lhs.size ?? -1) > (rhs.size ?? -1) ? .orderedDescending : .orderedSame
            case "date":
                result = (lhs.modified ?? .distantPast).compare(rhs.modified ?? .distantPast)
            default:
                result = .orderedSame
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < hits.count else { return nil }
        return hits[row].fileURL as NSURL
    }

    private func makeCell(id: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = NSFont.systemFont(ofSize: 12.5)
        label.drawsBackground = false
        label.isBordered = false
        label.isEditable = false
        cell.addSubview(label)
        cell.textField = label

        if withIcon {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(imageView)
            cell.imageView = imageView
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        return cell
    }

    private func icon(for hit: FileHit) -> NSImage {
        if let cached = iconCache[hit.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: hit.path)
        image.size = NSSize(width: 16, height: 16)
        if iconCache.count > 4000 {
            iconCache.removeAll(keepingCapacity: true)
        }
        iconCache[hit.path] = image
        return image
    }
}

final class KeyTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onCmdEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // return / keypad enter
            if event.modifierFlags.contains(.command) {
                onCmdEnter?()
            } else {
                onEnter?()
            }
        case 53: // escape
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        (target as? SearchWindowController)?.copyPath(sender)
    }
}
