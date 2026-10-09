import Foundation

/// 決まった時刻に動かす1本の仕事
struct Job: Codable, Identifiable, Equatable {
    /// launchd のラベルとファイル名に使う。英小文字・数字・`-` だけ
    var id: String
    /// 何をするジョブか。一覧に出す
    var summary: String
    /// 作業フォルダ。押したときにエディタで開く先でもある
    var folder: String
    /// 実行するコマンド。先頭が実行ファイル
    var command: [String]
    var schedule: [Slot]
    /// 実行の出力を、Owler の記録とは別にここへも足す。取り込む前のログを途切れさせないため
    var alsoLogTo: String?

    /// 動かす時刻。曜日が無ければ毎日。曜日は launchd と同じく 0 と 7 が日曜
    struct Slot: Codable, Equatable {
        var hour: Int
        var minute: Int
        var weekday: Int?
    }

    /// 画面に出す名前。説明があればそれ、無ければ ID
    var displayName: String { summary.isEmpty ? id : summary }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }

    /// launchd に渡す plist。Owler 自身を `run <id>` で呼ばせ、記録を取ってからコマンドを動かす
    func launchdPlist(owler: String) -> [String: Any] {
        var intervals: [[String: Int]] = []
        for slot in schedule {
            var entry = ["Hour": slot.hour, "Minute": slot.minute]
            if let weekday = slot.weekday { entry["Weekday"] = weekday }
            intervals.append(entry)
        }
        return [
            "Label": Paths.label(id),
            "ProgramArguments": [owler, "run", id],
            "StartCalendarInterval": intervals,
        ]
    }

    /// 次に動く時刻
    func nextFire(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        schedule.compactMap { slot -> Date? in
            var parts = DateComponents()
            parts.hour = slot.hour
            parts.minute = slot.minute
            // launchd の日曜は 0 と 7、Calendar は 1
            if let weekday = slot.weekday { parts.weekday = weekday % 7 + 1 }
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime)
        }.min()
    }

    /// いつ動くかの短い説明。時刻と曜日の書き方は地域に従う（アメリカの英語なら 3:33 AM）
    func scheduleText(locale: Locale = Strings.locale) -> String {
        let days = Set(schedule.map(\.weekday))
        let times = Array(Set(schedule.map { $0.hour * 60 + $0.minute })).sorted()
            .map { Format.timeOfDay(hour: $0 / 60, minute: $0 % 60, locale: locale) }
        let timeText = times.joined(separator: ", ")
        let ja = locale.language.languageCode?.identifier == "ja"
        if days == [nil] { return ja ? "毎日 \(timeText)" : "Daily at \(timeText)" }
        let names = days.compactMap { $0 }.map { $0 % 7 }.sorted().map { Format.weekday($0, locale: locale) }
        return ja ? "\(names.joined(separator: "・")) \(timeText)" : "\(names.joined(separator: ", ")) at \(timeText)"
    }

    var scheduleText: String { scheduleText() }
}

/// 時刻と曜日の書き方を読む。`--at 10:00` と `--weekdays 1-5` から Slot を作る
enum ScheduleParser {
    static func time(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
            (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return (h, m)
    }

    /// `1-5`、`1,3,5`、`0` のように書く。0 が日曜
    static func weekdays(_ text: String) -> [Int]? {
        var result: [Int] = []
        for piece in text.split(separator: ",") {
            let bounds = piece.split(separator: "-").map { Int($0) }
            if bounds.count == 1, let d = bounds[0] {
                result.append(d)
            } else if bounds.count == 2, let a = bounds[0], let b = bounds[1], a <= b {
                result.append(contentsOf: a...b)
            } else {
                return nil
            }
        }
        guard !result.isEmpty, result.allSatisfy({ (0...7).contains($0) }) else { return nil }
        return Array(Set(result.map { $0 % 7 })).sorted()
    }

    static func slots(times: [(Int, Int)], weekdays: [Int]?) -> [Job.Slot] {
        times.flatMap { h, m in
            weekdays.map { $0.map { Job.Slot(hour: h, minute: m, weekday: $0) } }
                ?? [Job.Slot(hour: h, minute: m, weekday: nil)]
        }
    }

    /// 既存の plist の StartCalendarInterval を読む。1件の辞書でも配列でもよい
    static func slots(fromLaunchd value: Any?) -> [Job.Slot]? {
        let entries: [[String: Any]]
        if let one = value as? [String: Any] {
            entries = [one]
        } else if let many = value as? [[String: Any]] {
            entries = many
        } else {
            return nil
        }
        var slots: [Job.Slot] = []
        for entry in entries {
            // 月や日を指定したものは Owler では表せない
            guard Set(entry.keys).isSubset(of: ["Hour", "Minute", "Weekday"]),
                let h = entry["Hour"] as? Int, let m = entry["Minute"] as? Int
            else { return nil }
            slots.append(Job.Slot(hour: h, minute: m, weekday: entry["Weekday"] as? Int))
        }
        return slots.isEmpty ? nil : slots
    }
}

/// ジョブの定義を読み書きし、launchd に登録する
enum JobStore {
    static func all() -> [Job] {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: Paths.jobsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Job.self, from: Data(contentsOf: $0)) }
            .sorted { $0.id < $1.id }
    }

    static func load(_ id: String) -> Job? {
        try? JSONDecoder().decode(Job.self, from: Data(contentsOf: Paths.job(id)))
    }

    /// 定義を書き、plist を書き、launchd に読み込ませ直す
    static func install(_ job: Job, owler: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.jobsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: Paths.launchAgents, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(job).write(to: Paths.job(job.id))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: job.launchdPlist(owler: owler), format: .xml, options: 0)
        try plist.write(to: Paths.plist(job.id))
        // 読み込み済みなら外してから入れ直す。外さずに入れると古い定義のまま残る
        Launchctl.bootout(Paths.label(job.id))
        try Launchctl.bootstrap(Paths.plist(job.id))
    }

    static func remove(_ id: String) {
        Launchctl.bootout(Paths.label(id))
        try? FileManager.default.removeItem(at: Paths.plist(id))
        try? FileManager.default.removeItem(at: Paths.job(id))
    }
}

/// launchctl を呼ぶ
enum Launchctl {
    static var domain: String { "gui/\(getuid())" }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @discardableResult
    static func call(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func bootstrap(_ plist: URL) throws {
        let result = call(["bootstrap", domain, plist.path])
        if result.status != 0 { throw Failure(description: "launchctl bootstrap: \(result.output)") }
    }

    /// 読み込まれていなくても失敗にしない
    static func bootout(_ label: String) { call(["bootout", "\(domain)/\(label)"]) }

    /// 時刻を待たずに今すぐ動かす
    static func kickstart(_ label: String) { call(["kickstart", "\(domain)/\(label)"]) }
}
