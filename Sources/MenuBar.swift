import AppKit

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

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
/// アイコンの横には、前回が失敗のジョブの数と、実行中のジョブの数を印つきで出す（StatusTitle）
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    /// 実行中の輪を回す。実行中が無いときと「視差効果を減らす」のときは止める
    private var animation: Timer?
    private var phase: CGFloat = 0.5
    private var failed = 0
    private var running = 0
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
            // 実行の始まりに気付くのが遅れないよう、窓と同じ3秒ごとに読み直す
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            animation?.invalidate()
            animation = nil
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    private func lastRuns() -> [(Job, RunRecord?)] {
        JobStore.all().map { ($0, RunStore.all($0.id, limit: 1).first) }
    }

    private func refresh() {
        guard item != nil else { return }
        let states = lastRuns().compactMap { $0.1?.state }
        failed = states.filter { [.failed, .interrupted].contains($0) }.count
        running = states.filter { $0 == .running }.count
        draw()
        animate()
    }

    private func draw() {
        guard let button = item?.button else { return }
        button.title = ""
        button.image =
            failed + running > 0
            ? StatusTitle.image(icon: Self.statusIcon, failed: failed, running: running, phase: phase)
            : Self.statusIcon
        button.toolTip =
            [
                failed > 0 ? Strings.failedJobs(failed) : nil, running > 0 ? Strings.runningJobs(running) : nil,
            ].compactMap { $0 }.joined(separator: "\n").nilIfEmpty ?? "Owler"
    }

    /// 輪は 15 fps で描き直す。Hawky と同じ速さで、0.8 秒で一周する
    private func animate() {
        let moves = running > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard moves != (animation != nil) else { return }
        guard moves else {
            animation?.invalidate()
            animation = nil
            phase = 0.5
            draw()
            return
        }
        let interval = 1.0 / 15
        animation = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase = (self.phase + CGFloat(interval / 0.8)).truncatingRemainder(dividingBy: 1)
                self.draw()
            }
        }
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
