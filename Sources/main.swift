import AppKit
import ServiceManagement

/// 窓を出しているあいだだけ Dock に出す。メニューバーに居て窓が無いときは Dock から外す
@MainActor
enum Dock {
    /// 窓を出す前に呼ぶ。外したままだと、前に出てもアプリのメニューが出ない
    static func show() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// 窓を閉じたあとに呼ぶ。メニューバーに居なければ、窓を閉じた時点でアプリが終わる
    static func hideIfIdle() {
        guard Preferences.showsMenuBar else { return }
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !hasWindow { NSApp.setActivationPolicy(.accessory) }
    }
}

/// 起動のしかたで、窓を出すかを決める
@MainActor
enum Launch {
    /// ログイン時に起こされたか。applicationDidFinishLaunching の中で呼ぶ。起動の Apple Event はそのあいだしか読めない
    static var isLoginItem: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication,
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        {
            return true
        }
        // SMAppService で入れたログイン項目にも印が付くかは確かめられていない。「再ログイン時にウインドウを
        // 再度開く」で戻されたときは付かない。なので、ログイン項目が有効で、ログインの直後に起きたならログイン時とみなす
        return SMAppService.mainApp.status == .enabled && isJustAfterLogin(consoleLogin, now: Date())
    }

    /// ログインから1分以内か。手元の Mac ではログインの3秒後に起きていた
    static func isJustAfterLogin(_ login: Date?, now: Date) -> Bool {
        guard let login else { return false }
        return (0..<60).contains(now.timeIntervalSince(login))
    }

    /// この利用者が画面からログインした時刻（`who` の console の行）
    private static var consoleLogin: Date? {
        let user = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            var record = entry.pointee
            guard record.ut_type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: &record.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let name = withUnsafeBytes(of: &record.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard line == "console", name == user else { continue }
            let time = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
            if latest.map({ time > $0 }) ?? true { latest = time }
        }
        return latest
    }

    /// ログイン時に起こすのはメニューバーに居るため。窓まで出すと、Mac を起動するたびに窓が出る。
    /// メニューバーに出さない設定なら、窓を出さないとどこにも現れないので出す
    static func showsWindow(loginItem: Bool, showsMenuBar: Bool, settings: Bool) -> Bool {
        settings || !loginItem || !showsMenuBar
    }
}

/// 窓を出す。閉じたら、メニューバーから開き直せる
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let main = MainWindowController()
    private lazy var menuBar = MenuBar(open: { [weak self] job in self?.main.show(job: job) })

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
            }
        }
        // 閉じきるのは willClose のあとなので、一巡待ってから数える
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { Dock.hideIfIdle() } }
        }
        // 更新の画面のように、こちらの show を通らずに出る窓もある
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
            _ in
            MainActor.assumeIsolated {
                if NSApp.keyWindow?.styleMask.contains(.titled) == true { Dock.show() }
            }
        }
        let settings = CommandLine.arguments.contains("--settings")
        let loginItem = Launch.isLoginItem
        if Launch.showsWindow(loginItem: loginItem, showsMenuBar: Preferences.showsMenuBar, settings: settings) {
            main.show(settings: settings)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        Updater.shared.checkQuietly()
        Reload.ifUpdated()
    }

    /// メニューバーに居るなら、窓を閉じても終わらない
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.showsMenuBar
    }

    @objc func openSettings() { main.show(settings: true) }

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
