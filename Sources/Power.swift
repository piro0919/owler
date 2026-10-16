import Foundation

/// Mac が起きていた時刻。`pmset -g log` の眠った・起きた記録から読む。
/// 予定の時刻に記録の無い回のうち、起きていたのに動かなかった回だけを「記録なし」にするため。
/// 眠っていた時刻まで出すと、20分おきのジョブでは閉じていた夜の分で表が埋まる
@MainActor
final class PowerLog {
    static let shared = PowerLog()

    struct Event: Equatable {
        enum Kind { case wake, sleep, start }
        var time: Date
        var kind: Kind
    }

    private var events: [Event] = []
    /// 読んだ時刻。これより後のことはまだ分からない
    private var fetchedAt: Date?
    private var fetching = false

    /// その時刻に起きていたか。分からなければ nil。
    /// pmset は1回に2秒ほどかかるので、まだ読んでいない時刻を聞かれたときだけ裏で読み直す
    func awake(at date: Date) -> Bool? {
        guard let fetchedAt, date < fetchedAt else {
            refresh()
            return nil
        }
        return Self.awake(at: date, in: events)
    }

    private func refresh() {
        guard !fetching, (fetchedAt.map { Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        fetching = true
        Task.detached {
            let now = Date()
            let events = Self.parse(Self.read())
            await MainActor.run {
                self.events = events
                self.fetchedAt = now
                self.fetching = false
            }
        }
    }

    nonisolated private static func read() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// 「2026-10-16 07:03:08 +0900 Wake    \t…」の行から、起きた・眠った・powerd が起きた（起動）を拾う。
    /// 「Wake Requests」「WakeDetails」は予定や詳細なので拾わない。DarkWake は画面の消えたままの短い目覚めで、
    /// 定期実行が動く保証が無いので眠っている側に数える
    nonisolated static func parse(_ text: String) -> [Event] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var events: [Event] = []
        for line in text.split(separator: "\n") where line.count > 26 && line.first == "2" {
            let head = line.prefix(25)
            let kindText = line.dropFirst(26).prefix { $0 != "\t" }.trimmingCharacters(in: .whitespaces)
            let kind: Event.Kind? =
                switch kindText {
                case "Wake": .wake
                case "Sleep", "DarkWake": .sleep
                case "Start": .start
                default: nil
                }
            guard let kind, let time = formatter.date(from: String(head)) else { continue }
            events.append(Event(time: time, kind: kind))
        }
        return events.sorted { $0.time < $1.time }
    }

    /// 直前の出来事が目覚めか起動なら起きていた。記録より前の時刻は分からない。
    /// 次の出来事が起動なら、その間に電源が落ちていたので起きていなかったとみなす
    nonisolated static func awake(at date: Date, in events: [Event]) -> Bool? {
        guard let index = events.lastIndex(where: { $0.time <= date }) else { return nil }
        if index + 1 < events.count, events[index + 1].kind == .start { return false }
        return events[index].kind != .sleep
    }
}
