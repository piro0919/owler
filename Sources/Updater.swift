import AppKit
import Sparkle

// 自動更新。
//
// Konechi と同じ挙動に揃える。確認は起動時に1回だけで、定期的には見に行かない。
// 見つかったときだけ画面を出し、入れるかどうかを毎回尋ねる。
//
// Sparkle は既定だと初回起動で「自動で確認していいか」を尋ねる画面を出すので、
// Info.plist の SUEnableAutomaticChecks を false にして止めてある。

final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    /// 起動時の確認で更新が見つかったか。画面を出すのは確認が終わってから
    private var foundUpdate = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

    /// 起動時の確認。何も無ければ黙って終わる。
    /// 手元のビルドは版数が 0.0.0 なので、公開中のどの版も「新しい」と判断され、
    /// 起動のたびに更新の画面が出る。その画面が前面を取り、窓を前に出す処理とぶつかって
    /// いた。手元のビルドでは確かめない。メニューからの確認はそのまま通す
    func checkQuietly() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version != "0.0.0" else { return }
        controller.updater.checkForUpdateInformation()
    }

    /// 設定画面の「更新を確認」。最新のときも結果を出す
    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    /// 黙って確認した結果、更新があった。
    /// ここで画面を出そうとしても、確認の最中なので Sparkle に捨てられる。
    /// 覚えておいて、確認が終わってから改めて頼む
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("更新が見つかりました: \(item.displayVersionString)")
        foundUpdate = true
    }

    /// 確認が終わった。見つからなかった場合や失敗した場合もここに来る
    func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        log("確認が終わりました: \(error.map { "\($0)" } ?? "問題なし")")
        // 後始末は黙った確認のときだけ。checkNow で出した画面を閉じたときもここに来て、
        // そこでも didFindValidUpdate が立っている。見分けずに出し直すと、閉じるたびに画面が出直す
        guard updateCheck == .updateInformation, foundUpdate else { return }
        foundUpdate = false

        DispatchQueue.main.async { [weak self] in
            self?.log("画面を出します")
            self?.checkNow()
        }
    }

    private func log(_ text: String) {
        guard CommandLine.arguments.contains("--diag") else { return }
        FileHandle.standardError.write("updater: \(text)\n".data(using: .utf8)!)
    }
}
