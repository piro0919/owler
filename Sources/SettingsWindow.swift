import AppKit
import ServiceManagement

/// 設定の窓。作りは Gocci（を写した Hawky）に揃えてある。左に項目名を右寄せで置き、右に操作を並べる
@MainActor
final class SettingsWindowController: NSWindowController {
    private let menuBarCheckbox = NSButton(checkboxWithTitle: Strings.showInMenuBar, target: nil, action: nil)
    private let languagePopUp = NSPopUpButton()
    private let launchCheckbox = NSButton(checkboxWithTitle: Strings.launchAtLogin, target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")
    private lazy var messageRow: NSView = aligned(messageLabel)
    private var dividers: [NSView] = []

    /// 見出しの幅。操作の左端を一列に揃えるための基準
    private static let labelWidth: CGFloat = 110
    private static let width: CGFloat = 420

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = Strings.settingsTitle
        window.isReleasedWhenClosed = false
        self.init(window: window)
        build()
    }

    private func build() {
        guard let window else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"

        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(toggleMenuBar)

        languagePopUp.target = self
        languagePopUp.action = #selector(changeLanguage)
        for language in Language.allCases {
            languagePopUp.addItem(withTitle: language.label)
        }

        launchCheckbox.target = self
        launchCheckbox.action = #selector(toggleLaunch)

        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.preferredMaxLayoutWidth = Self.width - 24 * 2 - Self.labelWidth - 10
        // 文字が無いときは畳む。空のまま置くと、その行のぶんだけ間延びする
        messageLabel.isHidden = true
        messageRow.isHidden = true

        let updateButton = NSButton(title: Strings.checkForUpdates, target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded

        let about = NSTextField(labelWithString: "Owler \(version)")
        about.textColor = .secondaryLabelColor
        about.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [
            aligned(menuBarCheckbox),
            divider(),
            row(Strings.language, languagePopUp),
            aligned(launchCheckbox),
            messageRow,
            aligned(updateButton),
            aligned(about),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false

        let margin: CGFloat = 24
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
        ])
        for line in dividers {
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: Self.width, height: content.fittingSize.height))
    }

    func show() {
        // 開くたびに読み直す。ログイン項目は、この窓の外でも変えられる
        menuBarCheckbox.state = Preferences.showsMenuBar ? .on : .off
        languagePopUp.selectItem(at: Language.allCases.firstIndex(of: Language.chosen) ?? 0)
        launchCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        report("")

        Dock.show()
        NSApp.activate()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 操作

    @objc private func toggleMenuBar() { Preferences.showsMenuBar = menuBarCheckbox.state == .on }

    @objc private func changeLanguage() {
        let index = languagePopUp.indexOfSelectedItem
        guard Language.allCases.indices.contains(index) else { return }
        Language.chosen = Language.allCases[index]
    }

    /// メニューバーに居るにはアプリが動いている必要がある。ジョブ自体は Owler が閉じていても launchd が動かす
    @objc private func toggleLaunch() {
        do {
            if launchCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            report("")
        } catch {
            report(Strings.launchFailed, failed: true)
        }
        // OS 側の状態に見た目を合わせる。失敗したときは元に戻る
        launchCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func checkForUpdates() { Updater.shared.checkNow() }

    // MARK: - 組み立て

    private func row(_ title: String, _ controls: NSView...) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        label.alignment = .right

        let stack = NSStackView(views: [label] + controls)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        return stack
    }

    /// 見出しの無い行。操作の左端を見出しのある行に揃える
    private func aligned(_ views: NSView...) -> NSView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true

        let stack = NSStackView(views: [spacer] + views)
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        dividers.append(line)
        return line
    }

    private func report(_ text: String, failed: Bool = false) {
        messageLabel.textColor = failed ? .systemRed : .secondaryLabelColor
        messageLabel.stringValue = text
        messageLabel.isHidden = text.isEmpty
        messageRow.isHidden = text.isEmpty
    }
}
