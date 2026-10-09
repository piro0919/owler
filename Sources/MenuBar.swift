import AppKit

extension Notification.Name {
    static let menuBarSettingChanged = Notification.Name("owler.menuBarSettingChanged")
}

/// 設定。UserDefaults に置く
enum Preferences {
    private static let showsMenuBarKey = "showsMenuBar"

    /// メニューバーに出すか。既定は出す
    static var showsMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: showsMenuBarKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: showsMenuBarKey)
            NotificationCenter.default.post(name: .menuBarSettingChanged, object: nil)
        }
    }
}

/// メニューバーの入口。各ジョブの前回の成否だけを並べ、押すと窓でそのジョブを開く。
/// 前回が失敗のジョブがあれば、アイコンの横にその数を出す
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    private let open: (String?) -> Void
    private let openSettings: () -> Void

    init(open: @escaping (String?) -> Void, openSettings: @escaping () -> Void) {
        self.open = open
        self.openSettings = openSettings
        super.init()
    }

    /// 設定に合わせて出し入れする
    func apply() {
        if Preferences.showsMenuBar {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = NSMenu()
            item.menu?.delegate = self
            self.item = item
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    private func lastRuns() -> [(Job, RunRecord?)] {
        JobStore.all().map { ($0, RunStore.all($0.id, limit: 1).first) }
    }

    private func refresh() {
        guard let button = item?.button else { return }
        let failures = lastRuns().filter { [.failed, .interrupted].contains($0.1?.state) }.count
        button.image = Self.statusIcon
        button.imagePosition = .imageLeading
        button.title = failures > 0 ? " \(failures)" : ""
        button.toolTip = failures > 0 ? Strings.failedJobs(failures) : "Owler"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let runs = lastRuns()
        if runs.isEmpty {
            let empty = NSMenuItem(title: Strings.noJobs, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (job, run) in runs {
            let item = NSMenuItem(title: job.displayName, action: #selector(openJob(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = job.id
            item.image = Self.dot(run?.state)
            item.toolTip = job.summary.isEmpty ? nil : job.summary
            // 2行目に前回の結果を出す。subtitle の無い版では1行に並べる
            let last = run.map { "\(Format.dateTime($0.start))  \(Strings.stateText($0))" } ?? Strings.noRuns
            if #available(macOS 14.4, *) {
                item.subtitle = last
            } else {
                item.title = "\(job.displayName)  —  \(last)"
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(action(Strings.openOwler, #selector(openWindow)))
        menu.addItem(action(Strings.settings, #selector(settings)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.quit, action: #selector(NSApp.terminate), keyEquivalent: "q"))
        refresh()
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openJob(_ sender: NSMenuItem) { open(sender.representedObject as? String) }
    @objc private func openWindow() { open(nil) }
    @objc private func settings() { openSettings() }

    /// フクロウの影絵。テンプレート画像にして、明暗の色付けは macOS に任せる
    private static let statusIcon: NSImage? = {
        guard let image = NSImage(named: "StatusIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    /// 状態の丸。窓の一覧と同じ色
    static func dot(_ state: RunRecord.State?) -> NSImage {
        let color: NSColor =
            switch state {
            case .running: .systemBlue
            case .succeeded: .systemGreen
            case .failed: .systemRed
            case .interrupted: .systemOrange
            case nil: .tertiaryLabelColor
            }
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}
