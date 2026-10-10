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
    static var selectJob: String { t("定期実行を選んでください", "Select a job") }
    static var newJob: String { t("新しい定期実行", "New Job") }
    static var runNow: String { t("今すぐ実行", "Run Now") }
    static var openInEditor: String { t("Claude Code で開く", "Open in Claude Code") }
    static var noEditor: String { t("Cursor も VS Code も見つかりません", "Neither Cursor nor VS Code is installed") }
    static var schedule: String { t("時刻", "Schedule") }
    static var next: String { t("次回", "Next") }
    static var folder: String { t("フォルダ", "Folder") }
    static var command: String { t("コマンド", "Command") }
    static var runs: String { t("実行の記録", "Runs") }
    static var noRuns: String { t("まだ動いていません", "Not run yet") }
    static var running: String { t("実行中", "Running") }
    static var succeeded: String { t("成功", "Succeeded") }
    static func failed(_ code: Int32) -> String { t("失敗（終了コード \(code)）", "Failed (exit \(code))") }
    static var openOwler: String { t("Owler を開く", "Open Owler") }
    static var settings: String { t("設定…", "Settings…") }
    static var settingsTitle: String { t("設定", "Settings") }
    static var quit: String { t("Owler を終了", "Quit Owler") }
    static var language: String { t("言語", "Language") }
    static var launchAtLogin: String { t("ログイン時に起動", "Launch at Login") }
    static var launchFailed: String { t("ログイン時の起動を切り替えられませんでした", "Could not change Launch at Login") }
    static var checkForUpdates: String { t("アップデートを確認", "Check for Updates") }
    static var showInMenuBar: String { t("メニューバーに表示", "Show in Menu Bar") }
    static func runningJobs(_ n: Int) -> String { t("実行中の定期実行 \(n) 件", "\(n) job(s) running") }
    static func failedJobs(_ n: Int) -> String { t("前回が失敗の定期実行 \(n) 件", "\(n) job(s) failed last time") }
    static func stateText(_ run: RunRecord) -> String {
        switch run.state {
        case .running: running
        case .succeeded: succeeded
        case .failed: failed(run.exitCode ?? 0)
        case .interrupted: interrupted
        }
    }
    static func nextRun(_ when: String) -> String { t("次回 \(when)", "Next \(when)") }
    static func lastRun(_ when: String) -> String { t("前回 \(when)", "Last \(when)") }
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
    static var noOutput: String { t("出力はありません", "No output") }

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
