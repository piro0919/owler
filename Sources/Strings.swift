import Foundation

/// 画面の言語。既定はシステムに従い、日本語の環境なら日本語、それ以外は英語にする
enum Language: String, CaseIterable {
    case system, ja, en

    private static let key = "language"

    static var chosen: Language {
        get { UserDefaults.standard.string(forKey: key).flatMap(Language.init(rawValue:)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    static var resolved: Language {
        switch chosen {
        case .ja: return .ja
        case .en: return .en
        case .system: return (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? .ja : .en
        }
    }

    var label: String {
        switch self {
        case .system: return Strings.t("システムに従う", "Follow system")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("owler.languageChanged")
}

/// 画面に出す文言。言語は設定で切り替えられるので、読むたびに選び直す
enum Strings {
    static var isJapanese: Bool { Language.resolved == .ja }

    static func t(_ ja: String, _ en: String) -> String { isJapanese ? ja : en }

    /// 日時の書式に使う地域。言語がシステムに従うなら OS の設定そのもの（地域ごとの12時間制・24時間制も含む）。
    /// 言語を選んでいて OS と食い違うときは、その言語の代表の地域にする
    static var locale: Locale {
        let current = Locale.current
        let code = current.language.languageCode?.identifier
        switch Language.chosen {
        case .system: return current
        case .ja: return code == "ja" ? current : Locale(identifier: "ja_JP")
        case .en: return code == "en" ? current : Locale(identifier: "en_US")
        }
    }

    static var jobs: String { t("定期実行", "Jobs") }
    static var noJobs: String { t("定期実行はまだありません", "No jobs yet") }
    static var noJobsHint: String {
        t("「新しい定期実行」から Claude Code に相談して足せます", "Use New Job to set one up with Claude Code")
    }
    static var newJob: String { t("新しい定期実行", "New Job") }
    static var runNow: String { t("今すぐ実行", "Run Now") }
    static var pause: String { t("止める", "Pause") }
    static var resume: String { t("再開", "Resume") }
    /// 止めたジョブと、Owler の外で launchd から外されたジョブ。次回の代わりに出す
    static var paused: String { t("停止中", "Paused") }
    /// 時刻を過ぎた1回だけのジョブ。窓の一覧の見出しと、メニューの2行目
    static var done: String { t("済み", "Done") }
    static var pauseFailed: String { t("止められませんでした", "Could not pause the job") }
    static var resumeFailed: String { t("再開できませんでした", "Could not resume the job") }
    static var runNowFailed: String { t("実行できませんでした", "Could not run the job") }
    static var openInEditor: String { t("Claude Code で開く", "Open in Claude Code") }
    static var noEditor: String {
        t("Cursor も VS Code も Claude デスクトップアプリも見つかりません", "None of Cursor, VS Code or the Claude desktop app is installed")
    }
    /// 設定の項目名。窓のボタンが「Claude Code で開く」なので、それを押したときの話だと分かる名前にする
    static var openWith: String { t("Claude Code を開くアプリ", "Open Claude Code In") }
    static var claudeDesktop: String { t("Claude デスクトップアプリ", "Claude desktop app") }
    static var schedule: String { t("時刻", "Schedule") }
    static var next: String { t("次回", "Next") }
    static var folder: String { t("フォルダ", "Folder") }
    static var command: String { t("コマンド", "Command") }
    static var runs: String { t("実行の記録", "Runs") }
    static var missed: String { t("記録なし", "No record") }
    static var running: String { t("実行中", "Running") }
    static var succeeded: String { t("成功", "Succeeded") }
    /// 回のページの状態の行に添える終了コード。メニューと実行の表は「失敗」だけにする。赤い丸と「失敗」で伝わり、
    /// ほとんどのジョブは 1 を返すので、括弧で添えても足すものが無かった（2026-11-26）
    static func exitCode(_ code: Int32) -> String { t("終了コード \(code)", "exit \(code)") }
    static var openOwler: String { t("Owler を開く", "Open Owler") }
    static var settings: String { t("設定…", "Settings…") }
    static var settingsTitle: String { t("設定", "Settings") }
    static var quit: String { t("Owler を終了", "Quit Owler") }
    static func cost(_ value: Double) -> String { t("約 \(Format.usd(value))", "about \(Format.usd(value))") }
    static func costPerRun(_ perRun: Double, month: Double) -> String {
        t(
            "1回 約 \(Format.usd(perRun)) · 月 約 \(Format.usd(month))",
            "About \(Format.usd(perRun)) a run · \(Format.usd(month)) a month")
    }
    static var updates: String { t("アップデート", "Updates") }
    static var language: String { t("言語", "Language") }
    static var launchAtLogin: String { t("ログイン時に起動", "Launch at Login") }
    static var launchFailed: String { t("ログイン時の起動を切り替えられませんでした", "Could not change Launch at Login") }
    /// 項目名が「アップデート」なので、ボタンは「確認」だけにする。並べると同じ言葉が2回出た
    static var checkForUpdates: String { t("確認", "Check") }
    static var showInMenuBar: String { t("メニューバーに表示", "Show in Menu Bar") }
    static func runningJobs(_ n: Int) -> String { t("実行中の定期実行 \(n) 件", "\(n) job(s) running") }
    static func unseenJobs(_ n: Int) -> String { t("まだ見ていない回のある定期実行 \(n) 件", "\(n) job(s) with a run to review") }
    /// ジョブのページの「未読」の項目。どんなときに未読にするか。--review なら毎回なので、書いた一文より先に見る
    static func reviewCondition(_ job: Job) -> String {
        if job.review == true { return t("うまく終わるたび", "After every successful run") }
        if let when = job.reviewWhen, !when.isEmpty { return when }
        return t("なし", "Never")
    }
    static var scheduleLabel: String { t("予定", "Schedule") }
    static var nextLabel: String { t("次回", "Next") }
    static var costLabel: String { t("料金", "Cost") }
    static var unseenLabel: String { t("未読", "Unread") }
    static var newerRun: String { t("新しい回", "Newer Run") }
    static var olderRun: String { t("古い回", "Older Run") }
    static var unseenHeader: String { t("未読", "Unread") }
    static var otherJobsHeader: String { t("ほかの定期実行", "Other Jobs") }
    static func failedJobs(_ n: Int) -> String { t("前回が失敗の定期実行 \(n) 件", "\(n) job(s) failed last time") }
    static func stateText(_ run: RunRecord) -> String {
        switch run.state {
        case .running: running
        case .succeeded: succeeded
        case .failed: t("失敗", "Failed")
        case .interrupted: interrupted
        }
    }
    static func nextRun(_ when: String) -> String { t("次回 \(when)", "Next \(when)") }
    static func lastRun(_ when: String) -> String { t("前回 \(when)", "Last \(when)") }
    /// 1回だけのジョブのメニューの2行目。「次回」と書くと、次の次もあるように読める
    static func onceRun(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        t(
            "\(Format.near(date, now: now, calendar: calendar)) の1回",
            "Once, \(Format.near(date, now: now, calendar: calendar, midSentence: true))")
    }
    static func stateName(_ run: RunRecord) -> String {
        switch run.state {
        case .running: running
        case .succeeded: succeeded
        case .failed: t("失敗", "Failed")
        case .interrupted: interrupted
        }
    }
    static var interrupted: String { t("中断", "Interrupted") }
    static var report: String { t("Claude の報告", "Claude's report") }
    static var output: String { t("出力", "Output") }

    /// 新しい定期実行を相談するときの最初の一言
    static func newJobPrompt(owler: String) -> String {
        t(
            """
            定期実行を1本足したいです。何をさせるか、いつ動かすかを一緒に決めてください。
            決まったら Owler に登録してください。使い方は `\(owler) help` で読めます。
            """,
            """
            I want to add a scheduled job. Help me decide what it should do and when it should run.
            Once we agree, register it with Owler. Run `\(owler) help` for usage.
            """)
    }

    /// その回を調べるときの最初の一言。記録の置き場を渡して、Claude に読ませる
    static func inspectPrompt(job: String, when: String?, transcript: String?, log: String?) -> String {
        var ja =
            when.map { "Owler の定期実行「\(job)」の \($0) の回に何が起きたかを調べて、要約してください。" }
            ?? "Owler の定期実行「\(job)」はまだ動いていません。何をするジョブか確かめてください。"
        var en =
            when.map { "Look into what happened in the \($0) run of the Owler job \"\(job)\" and summarize it." }
            ?? "The Owler job \"\(job)\" has not run yet. Check what it does."
        if let transcript {
            ja += "\nこの回の Claude Code のセッションの記録: \(transcript)"
            en += "\nClaude Code transcript of this run: \(transcript)"
        }
        if let log {
            ja += "\nこの回の出力: \(log)"
            en += "\nOutput of this run: \(log)"
        }
        return t(ja, en)
    }
}
