import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: SearchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let controller = SearchWindowController()
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于秒搜", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏秒搜", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出秒搜", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "打开", action: #selector(SearchWindowController.openSelected(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "在访达中显示", action: #selector(SearchWindowController.revealSelected(_:)), keyEquivalent: "r")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "拷贝完整路径", action: #selector(SearchWindowController.copyPath(_:)), keyEquivalent: "c")
        editMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let searchItem = NSMenuItem()
        mainMenu.addItem(searchItem)
        let searchMenu = NSMenu(title: "搜索")
        searchMenu.addItem(withTitle: "聚焦搜索框", action: #selector(SearchWindowController.focusSearch(_:)), keyEquivalent: "l")
        searchMenu.addItem(withTitle: "聚焦搜索框", action: #selector(SearchWindowController.focusSearch(_:)), keyEquivalent: "f")
        searchItem.submenu = searchMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let info: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "秒搜",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(
                string: "macOS 上的文件名秒搜，对应 Windows 的 Everything。\n使用本机 Spotlight 索引，输入即搜。",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ]
        NSApp.orderFrontStandardAboutPanel(options: info)
    }
}
