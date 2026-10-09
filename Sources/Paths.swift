import Foundation

/// Owler が読み書きする場所
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// ジョブの定義と実行の記録の置き場。OWLER_SUPPORT_DIR で差し替えられる（LP の写真を見本のジョブで撮るため）
    static let support =
        ProcessInfo.processInfo.environment["OWLER_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
        ?? home.appendingPathComponent("Library/Application Support/Owler")
    static let jobsDir = support.appendingPathComponent("jobs")
    static let runsDir = support.appendingPathComponent("runs")
    /// 取り込んだ元の plist の控え
    static let importedDir = support.appendingPathComponent("imported")

    static let launchAgents = home.appendingPathComponent("Library/LaunchAgents")

    /// launchd のラベルの頭。これで始まるものを Owler のジョブとみなす
    static let labelPrefix = "io.kkweb.owler.job."

    static func job(_ id: String) -> URL { jobsDir.appendingPathComponent("\(id).json") }
    static func runs(_ id: String) -> URL { runsDir.appendingPathComponent(id) }
    static func label(_ id: String) -> String { labelPrefix + id }
    static func plist(_ id: String) -> URL { launchAgents.appendingPathComponent("\(label(id)).plist") }

    /// Claude Code がセッションを置くフォルダ。設定フォルダを変えている人は CLAUDE_CONFIG_DIR に従う
    static var claudeProjects: URL {
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let base = env.map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        return base.appendingPathComponent("projects")
    }

    /// 作業フォルダから、Claude Code のセッションの置き場の名前を作る。
    /// 英数字以外はすべて `-` になる。`/Users/piro/.config/spatto-promo` → `-Users-piro--config-spatto-promo`
    static func claudeProjectName(_ folder: String) -> String {
        String(folder.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// `~` で始まるパスを開く
    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }
}
