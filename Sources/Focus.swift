import AppKit
import ApplicationServices

/// エディタの、目当てのフォルダの窓を前に出す。Hawky の Focus から、フォルダで探す部分だけを持ってきた。
/// Claude Code の拡張は URL を前面の窓で開くので、窓が前に来たことを確かめてから URL を渡す
@MainActor
enum Focus {
    /// 待つ間隔と回数。新しく窓を開くと、前に出るまで2〜3秒かかる。10秒で諦める
    private static let interval = Duration.milliseconds(250)
    private static let attempts = 40

    /// アクセシビリティの許可。無ければ設定を開くよう促す（初回だけ出る）
    @discardableResult
    static func ensureTrusted() -> Bool {
        // kAXTrustedCheckOptionPrompt は C から来る var なので Swift 6 では触れない
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// フォルダの窓が前面に来るまで待つ。来なければ前に出す。来たら true
    static func bringForward(bundleID: String, folder: String) async -> Bool {
        let name = URL(fileURLWithPath: folder).lastPathComponent
        for _ in 0..<attempts {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                if let front = focusedWindow(of: axApp), let title = string(front, kAXTitleAttribute as String),
                    holdsFolder(title, name), app.isActive
                {
                    return true
                }
                raise(folderNamed: name, in: axApp)
                // macOS 14 以降は、前面化の権利を明け渡さないと他のアプリを前に出せない
                if let me = NSApp { me.yieldActivation(to: app) }
                app.activate()
            }
            try? await Task.sleep(for: interval)
        }
        return false
    }

    /// 窓の名前がそのフォルダのものか。Cursor は `<タブ> — <フォルダ>` かフォルダ名だけ、
    /// VS Code は `<タブ> - <フォルダ> - Visual Studio Code`。部分一致だと `tmp` が何にでも当たる
    static func holdsFolder(_ title: String, _ folder: String) -> Bool {
        guard !folder.isEmpty else { return false }
        return title == folder || title.hasSuffix(" — \(folder)") || title.hasPrefix("\(folder) — ")
            || title.contains(" - \(folder) - ") || title.hasPrefix("\(folder) - ")
    }

    /// 窓の一覧にあれば前に出す。macOS のタブで束ねた背面の窓は、タブバーのボタンにだけ出るので押す
    private static func raise(folderNamed name: String, in axApp: AXUIElement) {
        let open = windows(of: axApp)
        if let window = open.first(where: {
            string($0, kAXTitleAttribute as String).map { holdsFolder($0, name) } ?? false
        }) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
            return
        }
        for window in open {
            for tab in windowTabs(of: window)
            where string(tab, kAXTitleAttribute as String).map({ holdsFolder($0, name) }) ?? false {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementPerformAction(tab, kAXPressAction as CFString)
                return
            }
        }
    }

    // MARK: - AX の細かい取り回し

    private static func windowTabs(of window: AXUIElement) -> [AXUIElement] {
        children(window)
            .filter { string($0, kAXRoleAttribute as String) == (kAXTabGroupRole as String) }
            .flatMap { children($0) }
            .filter { string($0, kAXRoleAttribute as String) == (kAXRadioButtonRole as String) }
    }

    private static func focusedWindow(of axApp: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &raw) == .success,
            let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return (raw as! AXUIElement)
    }

    private static func windows(of axApp: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &raw) == .success,
            let windows = raw as? [AXUIElement]
        else { return [] }
        return windows
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
            let kids = raw as? [AXUIElement]
        else { return [] }
        return kids
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}
