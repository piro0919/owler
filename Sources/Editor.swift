import AppKit

/// Claude Code を開くアプリ。Claude Code の拡張が入ったエディタか、Claude のデスクトップアプリ。
/// 拡張は `<scheme>://anthropic.claude-code/open?session=…&prompt=…` を受け付ける。
/// デスクトップアプリは `claude://code/new?folder=…&q=…` で、Code のタブに新しい会話を開く
/// （https://support.claude.com/en/articles/14729294）。folder は開くたびにフォルダの一覧が出て確かめられる。
/// どちらも一言目は送らずに入力欄へ入るだけなので、利用者が読んでから送れる
enum Editor: String, CaseIterable {
    case cursor = "com.todesktop.230313mzl4w4u92"
    case vscode = "com.microsoft.VSCode"
    case claudeDesktop = "com.anthropic.claudefordesktop"

    var label: String {
        switch self {
        case .cursor: return "Cursor"
        case .vscode: return "VS Code"
        case .claudeDesktop: return Strings.claudeDesktop
        }
    }

    private static let key = "editor"

    /// このパソコンに入っているもの。並びは設定に出す順で、選んでいなければ先頭を使う
    static var available: [Editor] {
        allCases.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil }
    }

    /// 設定で選んだもの。選んでいないか、選んだものが消えていれば、入っているものの先頭（両方あれば Cursor）
    static var preferred: Editor? {
        get {
            let installed = available
            let chosen = UserDefaults.standard.string(forKey: key).flatMap(Editor.init(rawValue:))
            return chosen.flatMap { installed.contains($0) ? $0 : nil } ?? installed.first
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }

    /// 渡す URL
    func claudeURL(folder: String?, session: String?, prompt: String?) -> URL? {
        switch self {
        case .cursor, .vscode:
            // 拡張には前から URLComponents の符号化で渡していて、それで開けている
            var parts = URLComponents()
            parts.scheme = self == .cursor ? "cursor" : "vscode"
            parts.host = "anthropic.claude-code"
            parts.path = "/open"
            var items: [URLQueryItem] = []
            if let session { items.append(URLQueryItem(name: "session", value: session)) }
            if let prompt { items.append(URLQueryItem(name: "prompt", value: prompt)) }
            parts.queryItems = items.isEmpty ? nil : items
            return parts.url
        case .claudeDesktop:
            var items: [(String, String)] = []
            if let folder { items.append(("folder", folder)) }
            if let prompt { items.append(("q", prompt)) }
            return Self.strictURL("claude://code/new", items)
        }
    }

    /// 値は英数字と `-._~` 以外をすべて符号にする。URLComponents に任せると `+` がそのまま残り、
    /// 受け取る側によっては空白に読まれる。デスクトップアプリにはこの形で開けることを確かめた（2026-11-26）
    private static func strictURL(_ head: String, _ items: [(String, String)]) -> URL? {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        let query = items.compactMap { name, value in
            value.addingPercentEncoding(withAllowedCharacters: allowed).map { "\(name)=\($0)" }
        }
        return URL(string: query.isEmpty ? head : head + "?" + query.joined(separator: "&"))
    }

    /// その回を調べる会話を始める。拡張は `claude -p` で作られたセッション（記録の entrypoint が
    /// `sdk-cli`）を一覧から外していて、session を渡しても開けない。代わりに記録の置き場を一言目に入れて渡す
    @MainActor
    func open(job: Job, run: RunRecord?, done: (@MainActor () -> Void)? = nil) {
        let transcript = run?.session.map {
            Sessions.transcript(folder: Paths.expand(job.folder), session: $0).path
        }
        let log = run.map { RunStore.log(job.id, $0.stamp).path }
        let prompt = Strings.inspectPrompt(
            job: job.id, when: run.map { Format.dateTime($0.start) }, transcript: transcript, log: log)
        open(folder: job.folder, session: nil, prompt: prompt, done: done)
    }

    /// Claude Code を開く。エディタでは、URL が前面の窓で開かれるので、フォルダの窓が前に来たことを
    /// 確かめてから渡す。デスクトップアプリはフォルダを URL で受け取るので、そのまま渡す
    @MainActor
    func open(folder: String?, session: String?, prompt: String?, done: (@MainActor () -> Void)? = nil) {
        let path = folder.map(Paths.expand)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue),
            let url = claudeURL(folder: path, session: session, prompt: prompt)
        else {
            done?()
            return
        }
        guard let path, self != .claudeDesktop else {
            NSWorkspace.shared.open(url)
            done?()
            return
        }
        Focus.ensureTrusted()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: config)
        let bundleID = rawValue
        Task { @MainActor in
            // 許可が無いと窓を確かめられない。来なくても、最後は URL を渡す
            _ = await Focus.bringForward(bundleID: bundleID, folder: path)
            try? await Task.sleep(for: .milliseconds(400))
            NSWorkspace.shared.open(url)
            done?()
        }
    }
}
