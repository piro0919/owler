import ServiceManagement
import SwiftUI

/// 設定のページ。本体の窓の右側に、ジョブのページと同じ作り（見出しと枠）で出す。
/// 初めは別の窓（Gocci を写した作り）だったが、窓が2枚あって邪魔だと言われ、本体に入れた（2026-10-14）
struct SettingsPage: View {
    @State private var showsMenuBar = Preferences.showsMenuBar
    @State private var language = Language.chosen
    // ログイン項目はこのページの外でも変えられるので、開くたびに OS から読む
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchFailed = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Header(title: Strings.settingsTitle, subtitle: "Owler \(version)") { EmptyView() }
                Card {
                    VStack(spacing: 0) {
                        SettingRow(Strings.showInMenuBar) {
                            Toggle("", isOn: $showsMenuBar).labelsHidden().toggleStyle(.switch)
                        }
                        Divider()
                        SettingRow(Strings.language) {
                            Picker("", selection: $language) {
                                ForEach(Language.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Divider()
                        SettingRow(Strings.launchAtLogin, note: launchFailed ? Strings.launchFailed : nil) {
                            Toggle("", isOn: $launchesAtLogin).labelsHidden().toggleStyle(.switch)
                        }
                        Divider()
                        SettingRow(Strings.updates) {
                            Button(Strings.checkForUpdates) { Updater.shared.checkNow() }
                        }
                    }
                }
            }
            .padding(28)
        }
        .onChange(of: showsMenuBar) { _, on in Preferences.showsMenuBar = on }
        // 言語を変えると窓の中身ごと作り直される（AppDelegate）
        .onChange(of: language) { _, chosen in Language.chosen = chosen }
        .onChange(of: launchesAtLogin) { _, on in setLaunchAtLogin(on) }
    }

    /// メニューバーに居るにはアプリが動いている必要がある。ジョブ自体は Owler が閉じていても launchd が動かす
    private func setLaunchAtLogin(_ on: Bool) {
        let enabled = SMAppService.mainApp.status == .enabled
        // 失敗して見た目を戻したときも呼ばれる。OS 側と同じなら何もしない
        guard on != enabled else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchFailed = false
        } catch {
            launchFailed = true
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// 設定の1行。左に項目名、右に操作。注意があれば下に赤で添える
struct SettingRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let control: Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                control
            }
            if let note { Text(note).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}
