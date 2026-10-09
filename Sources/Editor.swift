import AppKit

/// Claude Code の拡張が入ったエディタで開く。
/// 拡張は `<scheme>://anthropic.claude-code/open?session=…&prompt=…` を受け付ける。
/// prompt は送らずに入力欄へ入るだけなので、利用者が読んでから送れる
enum Editor: String, CaseIterable {
    case cursor = "com.todesktop.230313mzl4w4u92"
    case vscode = "com.microsoft.VSCode"

    var scheme: String { self == .cursor ? "cursor" : "vscode" }

    /// 入っているもの。両方あれば Cursor
    static var installed: Editor? {
        allCases.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil }
    }

    /// 拡張に渡す URL
    func claudeURL(session: String?, prompt: String?) -> URL? {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = "anthropic.claude-code"
        parts.path = "/open"
        var items: [URLQueryItem] = []
        if let session { items.append(URLQueryItem(name: "session", value: session)) }
        if let prompt { items.append(URLQueryItem(name: "prompt", value: prompt)) }
        parts.queryItems = items.isEmpty ? nil : items
        return parts.url
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

    /// フォルダの窓を前に出してから、Claude Code を開く。
    /// URL は前面の窓で開かれるので、そのフォルダの窓が前に来たことを確かめてから渡す
    @MainActor
    func open(folder: String?, session: String?, prompt: String?, done: (@MainActor () -> Void)? = nil) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue),
            let url = claudeURL(session: session, prompt: prompt)
        else {
            done?()
            return
        }
        guard let folder else {
            NSWorkspace.shared.open(url)
            done?()
            return
        }
        Focus.ensureTrusted()
        let path = Paths.expand(folder)
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
