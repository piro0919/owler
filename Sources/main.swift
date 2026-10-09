import AppKit

/// 窓を出す。閉じても Dock から開き直せる
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let main = MainWindowController()
    private var settingsWindow = SettingsWindowController()
    private lazy var menuBar = MenuBar(
        open: { [weak self] job in self?.main.show(job: job) },
        openSettings: { [weak self] in self?.settingsWindow.show() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        menuBar.apply()
        NotificationCenter.default.addObserver(forName: .menuBarSettingChanged, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.menuBar.apply() }
        }
        // 言語を変えたら、文字を焼き込んでいる窓とメニューを作り直す
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSApp.mainMenu = self.makeMenu()
                self.main.reloadLanguage()
                let wasVisible = self.settingsWindow.window?.isVisible ?? false
                self.settingsWindow.close()
                self.settingsWindow = SettingsWindowController()
                if wasVisible { self.settingsWindow.show() }
            }
        }
        main.show()
        Updater.shared.checkQuietly()
        if CommandLine.arguments.contains("--settings") { settingsWindow.show() }
    }

    /// メニューバーに居るなら、窓を閉じても終わらない
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.showsMenuBar
    }

    @objc func openSettings() { settingsWindow.show() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { main.show() }
        return true
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: Strings.settings, action: #selector(openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: Strings.quit, action: #selector(NSApp.terminate), keyEquivalent: "q")
        appItem.submenu = app
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: Strings.t("ファイル", "File"))
        file.addItem(withTitle: Strings.t("閉じる", "Close"), action: #selector(NSWindow.performClose), keyEquivalent: "w")
        fileItem.submenu = file
        menu.addItem(fileItem)

        // 出力や報告の文字を写せるように
        let editItem = NSMenuItem()
        let edit = NSMenu(title: Strings.t("編集", "Edit"))
        edit.addItem(withTitle: Strings.t("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(
            withTitle: Strings.t("すべてを選択", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        return menu
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--selftest" {
    exit(MainActor.assumeIsolated { SelfTest.run() })
}
// コマンドは `-` で始まらない（help の別名だけ例外）。Finder から開くと付く `-psn_…` や、
// 窓を開く `--settings` はアプリとして起動する
if let first = arguments.first, !first.hasPrefix("-") || ["--help", "-h"].contains(first) {
    exit(CLI.main(arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
