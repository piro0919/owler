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

/// メニューバーの入口。各ジョブの前回の成否と次回を並べ、押すと窓でそのジョブを開く。
/// アイコンの横には、前回が失敗のジョブの数と、実行中のジョブの数を印つきで出す（StatusTitle）。
/// 見に来てほしいジョブ（Job.review）にまだ開いていない回があれば、影絵の右上に点を打つ
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    /// 実行中の輪を回す。実行中が無いときと「視差効果を減らす」のときは止める
    private var animation: Timer?
    private var phase: CGFloat = 0.5
    private var failed = 0
    private var running = 0
    private var unseen = 0
    private let open: (String?) -> Void

    init(open: @escaping (String?) -> Void) {
        self.open = open
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
            timer = Self.schedule(every: 3) { [weak self] in self?.refresh() }
            // 「視差効果を減らす」を切り替えたら、次の読み直しを待たずに輪を止める・回す
            NotificationCenter.default.addObserver(
                self, selector: #selector(displayOptionsChanged),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        } else {
            timer?.invalidate()
            timer = nil
            animation?.invalidate()
            animation = nil
            // 出すたびに登録するので、消すときに外す。外さないと出し入れのたびに重なる
            NotificationCenter.default.removeObserver(
                self, name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    /// 1件のジョブの前回と、まだ見に来ていない回があるか、前回より後に記録の無い予定があるか
    private struct Entry {
        var job: Job
        var run: RunRecord?
        var unseen: Bool
        var missed: Bool
    }

    /// メニューの並び（次に動く順）で返す
    private func lastRuns() -> [Entry] {
        Self.ordered(JobStore.all()).map { job in
            let run = RunStore.all(job.id, limit: 1).first
            return Entry(
                job: job, run: run, unseen: !RunStore.unseen(job).isEmpty,
                missed: !RunStore.missed(job, runs: run.map { [$0] } ?? [], limit: 1).isEmpty)
        }
    }

    private func refresh() {
        guard item != nil else { return }
        let runs = lastRuns()
        // 記録の無い予定は失敗と同じく「!」で数える。次の回が動けば消える
        failed = runs.filter { $0.missed || [.failed, .interrupted].contains($0.run?.state) }.count
        running = runs.filter { $0.run?.state == .running }.count
        unseen = runs.filter(\.unseen).count
        draw()
        animate()
    }

    private func draw() {
        guard let button = item?.button else { return }
        button.title = ""
        button.image =
            failed + running + unseen > 0
            ? StatusTitle.image(
                icon: Self.statusIcon, failed: failed, running: running, unseen: unseen > 0, phase: phase)
            : Self.statusIcon
        // 吹き出しは付け直すたびに消える。輪を描き直すたびに付け直すと読めなくなるので、変わったときだけ
        let parts = [
            unseen > 0 ? Strings.unseenJobs(unseen) : nil,
            failed > 0 ? Strings.failedJobs(failed) : nil, running > 0 ? Strings.runningJobs(running) : nil,
        ].compactMap { $0 }
        let tip = parts.isEmpty ? "Owler" : parts.joined(separator: "\n")
        if button.toolTip != tip {
            button.toolTip = tip
            // 件数は絵の中にしかないので、VoiceOver には同じ文を読ませる
            button.setAccessibilityLabel(tip)
        }
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
        animation = Self.schedule(every: interval) { [weak self] in
            guard let self else { return }
            self.phase = (self.phase + CGFloat(interval / 0.8)).truncatingRemainder(dividingBy: 1)
            self.draw()
        }
    }

    @objc private func displayOptionsChanged() { animate() }

    /// メニューを開いている間も止まらないよう、common モードで回す。scheduledTimer は default モードだけで、
    /// メニューの操作中（eventTracking）は止まる
    private static func schedule(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let runs = lastRuns()
        if runs.isEmpty {
            let empty = NSMenuItem(title: Strings.noJobs, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        // 未読の回のあるジョブを上にまとめる（Hawky の許可待ちと同じ）。2行目に「未読」と添えるだけでは埋もれた。
        // 未読が無ければ見出しは出さない。あれば両方に付ける。片方だけだと、見出しの無い側が何の行なのか分からない
        let sections = [
            (Strings.unseenHeader, runs.filter(\.unseen)),
            (Strings.otherJobsHeader, runs.filter { !$0.unseen }),
        ].filter { !$0.1.isEmpty }
        for (index, (header, rows)) in sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            if sections.count > 1 || header == Strings.unseenHeader { menu.addItem(.sectionHeader(title: header)) }
            for entry in rows { menu.addItem(row(entry)) }
        }
        menu.addItem(.separator())
        menu.addItem(action(Strings.openOwler, #selector(openWindow)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.quit, action: #selector(NSApp.terminate), keyEquivalent: "q"))
        refresh()
    }

    private func row(_ entry: Entry) -> NSMenuItem {
        let job = entry.job
        let item = NSMenuItem(title: job.displayName, action: #selector(openJob(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = job.id
        item.image = Self.dot(entry.run?.state, missed: entry.missed)
        item.toolTip = job.summary.isEmpty ? nil : job.summary
        // 2行目に次回を出す。subtitle の無い版では1行に並べる
        let line = Self.line(job, entry.run, missed: entry.missed)
        if #available(macOS 14.4, *) {
            item.subtitle = line
        } else {
            item.title = "\(job.displayName)  —  \(line)"
        }
        return item
    }

    /// メニューの並び。次に動く順。2行目に次回を出すので、上から時刻が並ぶ。
    /// ID の順だった頃は、画面に出るのが日本語の説明なので規則が見えず、ランダムに見えると言われた（2026-10-14）。
    /// 窓の一覧は選んだ行が時刻のたびに動くと使いにくいので、ID の順のまま
    nonisolated static func ordered(_ jobs: [Job], now: Date = Date(), calendar: Calendar = .current) -> [Job] {
        let next = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0.nextFire(after: now, calendar: calendar)) })
        return jobs.sorted {
            switch (next[$0.id] ?? nil, next[$1.id] ?? nil) {
            case (let a?, let b?) where a != b: a < b
            case (_?, nil): true
            case (nil, _?): false
            default: $0.id < $1.id
            }
        }
    }

    /// 各ジョブの2行目。前回の成功は丸の色で分かるので書かず、失敗・中断・実行中だけを言葉で添える。
    /// ただし直前の予定の回が記録に無いときは、成功でも前回の日時を出す。スリープで飛ばした回などに気付けるように。
    /// 起きていたのに記録の無い予定が前回より後にあれば（`missed`）、失敗と同じく「記録なし」と添える
    nonisolated static func line(
        _ job: Job, _ run: RunRecord?, missed: Bool = false, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        var parts: [String] = []
        if missed {
            parts.append(Strings.missed)
        } else if let run {
            if run.state != .succeeded {
                parts.append(Strings.stateText(run))
            } else if let previous = job.previousFire(before: now, calendar: calendar),
                run.start < previous.addingTimeInterval(-60)
            {
                parts.append(Strings.lastRun(Format.near(run.start, now: now, calendar: calendar)))
            }
        } else {
            parts.append(Strings.noRuns)
        }
        if let next = job.nextFire(after: now, calendar: calendar) {
            parts.append(Strings.nextRun(Format.near(next, now: now, calendar: calendar)))
        }
        return parts.joined(separator: " · ")
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openJob(_ sender: NSMenuItem) { open(sender.representedObject as? String) }
    @objc private func openWindow() { open(nil) }

    /// フクロウの影絵。テンプレート画像にして、明暗の色付けは macOS に任せる
    private static let statusIcon: NSImage? = {
        guard let image = NSImage(named: "StatusIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    /// 状態の丸。窓の一覧と同じ色。記録の無い予定があれば灰の白抜き
    static func dot(_ state: RunRecord.State?, missed: Bool = false) -> NSImage {
        if missed {
            return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                NSColor.systemGray.setStroke()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.75, dy: 1.75))
                path.lineWidth = 1.5
                path.stroke()
                return true
            }
        }
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
