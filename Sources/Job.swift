import Foundation
import Security

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
    /// 足す環境変数。取り込んだ plist の EnvironmentVariables を引き継ぐ
    var environment: [String: String]?
    /// 終わった回を利用者に見に来てほしいジョブ。成功した回をまだ開いていなければ、メニューバーに印を出す。
    /// 裏で動いて成功すれば見なくてよいジョブにまで印を出すと、印の意味が薄れるので、ジョブごとに選ぶ
    var review: Bool?
    /// ジョブが `OWLER_REVIEW_FILE` に書いて未読にするのは、どんなときか。Owler には中身が分からないので、
    /// 足すときに一文で書いてもらい、窓に出す。「返信の下書きを作ったとき」など
    var reviewWhen: String?
    /// 1回だけ動かすジョブの日。時刻は schedule の1枠。launchd の StartCalendarInterval には年が無いので、
    /// 月・日・時・分で登録し、動いたら Owler が launchd から外す。外さないと翌年の同じ日にまた動く
    var on: Day?
    /// 利用者が止めたジョブ。launchd からは外し、plist は残す。再開で入れ直す。再開の日は持たない
    var paused: Bool?

    /// 動かす時刻。曜日が無ければ毎日。曜日は launchd と同じく 0 と 7 が日曜
    struct Slot: Codable, Equatable, Hashable {
        var hour: Int
        var minute: Int
        var weekday: Int?
    }

    /// 年月日。定義には「2026-11-27」の形で書く
    struct Day: Codable, Equatable, Hashable {
        var year: Int
        var month: Int
        var day: Int

        init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        /// `2026-11-27` を読む。2月30日のような無い日は読まない
        init?(_ text: String, calendar: Calendar = .current) {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
            guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2] else { return nil }
            let date = calendar.date(from: DateComponents(year: y, month: m, day: d))
            guard let date, calendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: y, month: m, day: d)
            else { return nil }
            self.init(year: y, month: m, day: d)
        }

        var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

        init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let day = Day(text, calendar: Calendar(identifier: .gregorian)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            self = day
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(text)
        }
    }

    /// 1回だけのジョブが動く日時。繰り返すジョブは nil
    func oneOffFire(calendar: Calendar = .current) -> Date? {
        guard let on, let slot = schedule.first else { return nil }
        return calendar.date(
            from: DateComponents(year: on.year, month: on.month, day: on.day, hour: slot.hour, minute: slot.minute))
    }

    /// 1回だけのジョブで、その時刻を過ぎたもの。動いたか、記録なしかは問わない。消すのは利用者
    func isDone(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        oneOffFire(calendar: calendar).map { $0 <= now } ?? false
    }

    /// 止まっているジョブ。止めたもの（paused）と、Owler の外の理由で launchd に入っていないもの
    /// （plist の Disabled や、手で bootout したもの）を同じに扱う。`loaded` が分からなければ（nil）入っているとみなす。
    /// 済んだ1回だけのジョブは、動いたあとに外すので、入っていなくても止まっているとはしない
    func isStopped(loaded: Bool?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !isDone(now: now, calendar: calendar) && (paused == true || loaded == false)
    }

    /// 1回だけのジョブを、遅れて起こされても動かす幅。missedFires が動いたとみなす幅（10分後まで）と揃える。
    /// これより遅れた回（眠っていて過ぎ、起きたときに launchd が起こした回）は動かさず、「記録なし」にして
    /// 人が今すぐ実行で決める（2026-11-26、遅れて動かしてよいかは仕事によるので勝手に動かさないと決めた）
    static let oneOffLateness: TimeInterval = 600

    /// launchd に起こされたのに、動かさない回か。止めたジョブ（外す前に時刻が来た）と、1回だけのジョブが
    /// 時刻の1分前から10分後まで以外に起こされたとき（眠っていて過ぎた回と、年が無いので翌年の同じ日に
    /// 起こされた回）。手で動かした回は除く
    func skipsFire(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if paused == true { return true }
        guard on != nil else { return false }
        guard let fire = oneOffFire(calendar: calendar) else { return true }
        return !(-60...Self.oneOffLateness).contains(now.timeIntervalSince(fire))
    }

    /// 回のあとに launchd から外すか。止めたジョブ（動いている最中に止めた）と、済んだ1回だけのジョブ
    func unloadsAfterRun(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        paused == true || isDone(now: now, calendar: calendar)
    }

    /// 窓を開いたときの念のための片付けで外すか。済んだ1回だけのジョブが、まだ launchd に入っていて動いていないとき。
    /// 遅れても動かす幅（oneOffLateness）を過ぎたか、時刻のあとに始まって終わった回があれば外す。
    /// 幅の中はまだ外さない（launchd が起こすのと競らない）
    func leftLoaded(lastRun: RunRecord?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let fire = oneOffFire(calendar: calendar), fire <= now, lastRun?.state != .running else { return false }
        let late = now.timeIntervalSince(fire) > Self.oneOffLateness
        let ran = lastRun.map { $0.settled && $0.start >= fire.addingTimeInterval(-60) } ?? false
        return late || ran
    }

    /// まだ見に来ていない回か。`--review` のジョブの回と、ジョブが自分で見に来てほしいと伝えた回（RunRecord.asked）。
    /// 失敗は「!」で数えるので、ここでは成功した回だけを見る
    func awaitsReview(_ run: RunRecord?) -> Bool {
        guard let run, review == true || run.asked == true else { return false }
        return run.state == .succeeded && run.seen == nil
    }

    /// 失敗か中断で、まだ開いていない回。メニューバーの「!」に数える。開けば外す。次の回まで消えないと、
    /// 夜の最後の回の失敗が朝まで残り、中身を見たあとも消す手段が無かった（2026-10-20）
    func awaitsAcknowledgement(_ run: RunRecord?) -> Bool {
        guard let run else { return false }
        return [.failed, .interrupted].contains(run.state) && run.seen == nil
    }

    /// まだ見に来ていない回すべて。新しい順のまま返す。最新の回だけを見ると、次の回が来たところで印が黙って消える
    func unseenRuns(_ runs: [RunRecord]) -> [RunRecord] {
        runs.filter { awaitsReview($0) }
    }

    /// その回を開いたときに、見たことにする回。`--review` のジョブは、それより古い未読の回もまとめて。
    /// 毎日の報告は新しい回で置き換わるので、溜まった古い回まで一つずつ開かせない。
    /// ジョブが頼んだ回（asked）は回ごとに中身が違う（返信の下書きなど）ので、開いた回だけ
    func seenByOpening(_ run: RunRecord, among runs: [RunRecord]) -> [RunRecord] {
        let older = review == true ? unseenRuns(runs).filter { $0.stamp < run.stamp && $0.asked != true } : []
        return (awaitsReview(run) || awaitsAcknowledgement(run) ? [run] : []) + older
    }

    /// 30日に動く回数の見込み。曜日の決まった時刻は週に1回。1回だけのジョブは繰り返さないので 0
    var runsPerMonth: Double {
        if on != nil { return 0 }
        return schedule.reduce(0) { $0 + ($1.weekday == nil ? 30 : 30.0 / 7) }
    }

    struct CostEstimate: Equatable {
        var perRun: Double
        var month: Double
    }

    /// 終わった回の料金（Claude が動かなかった回は nil）から、1回あたりと月の見込みを出す。
    /// 1回あたりは Claude が動いた回の平均。月は、予定の回数に Claude が動いた回の割合を掛ける。
    /// 割合を掛けないと、土日は抜けるジョブ（Spatto）で、動かない日まで数えて8割増しに見込んでいた（2026-10-14）
    func costEstimate(_ costs: [Double?]) -> CostEstimate? {
        let known = costs.compactMap { $0 }
        guard !known.isEmpty else { return nil }
        let perRun = known.reduce(0, +) / Double(known.count)
        let share = Double(known.count) / Double(costs.count)
        return CostEstimate(perRun: perRun, month: perRun * runsPerMonth * share)
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
            // 年は書けない。動いたあとに Owler が外す（unloadsAfterRun）
            if let on {
                entry["Month"] = on.month
                entry["Day"] = on.day
            }
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
        fires(from: date, direction: .forward, calendar: calendar).min()
    }

    /// 直前に動くはずだった時刻
    func previousFire(before date: Date = Date(), calendar: Calendar = .current) -> Date? {
        fires(from: date, direction: .backward, calendar: calendar).max()
    }

    /// 予定の時刻を過ぎたのに記録の無い回。新しい順。起きていた時刻（`awake` が true）に限る。
    /// 2026-10-16、更新直後の 9:00 に `Owler run` が起動前に macOS に殺され、記録が何も残らず、窓では前の日の成功が
    /// 最新のまま普通に見えていた。原因が何でも気付けるように、予定と記録を突き合わせる。
    /// 予定の1分前から10分後までに始まった回か、その時刻に動いていた回があれば、動いたとみなす。
    /// `since` より前は見ない。ジョブを足す前の時刻や、残っている記録より古い時刻まで「記録なし」にしないため
    func missedFires(
        runs: [RunRecord], since: Date, now: Date = Date(), calendar: Calendar = .current,
        awake: (Date) -> Bool?
    ) -> [Date] {
        // 止めているあいだの予定は動かないのが正しいので数えない。再開すると定義を書き直すので、
        // 止めていたあいだの時刻は `since`（定義を書いた時刻）より前になり、再開のあとも数えない
        if paused == true { return [] }
        var missed: [Date] = []
        // 始まったばかりの回は記録を書く途中かもしれないので、2分待ってから数える
        var cursor = now.addingTimeInterval(-120)
        while let fire = previousFire(before: cursor, calendar: calendar), fire < cursor, fire >= since {
            cursor = fire
            let ran = runs.contains { run in
                let end = run.end ?? (run.state == .running ? now : run.start)
                let lag = run.start.timeIntervalSince(fire)
                return (-60...600).contains(lag) || (run.start <= fire && end >= fire)
            }
            if !ran, awake(fire) == true { missed.append(fire) }
        }
        return missed
    }

    private func fires(from date: Date, direction: Calendar.SearchDirection, calendar: Calendar) -> [Date] {
        // 1回だけのジョブは、その日時だけ。launchd は翌年も起こすが、Owler run が動かさない
        if on != nil {
            guard let fire = oneOffFire(calendar: calendar) else { return [] }
            return (direction == .forward ? fire > date : fire < date) ? [fire] : []
        }
        return schedule.compactMap { slot -> Date? in
            var parts = DateComponents()
            parts.hour = slot.hour
            parts.minute = slot.minute
            // launchd の日曜は 0 と 7、Calendar は 1
            if let weekday = slot.weekday { parts.weekday = weekday % 7 + 1 }
            return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime, direction: direction)
        }
    }

    /// いつ動くかの短い説明。時刻と曜日の書き方は地域に従う（アメリカの英語なら 3:33 AM）。
    /// 時刻×曜日の組み合わせが揃っていれば「月・金 9:00」とまとめ、揃っていなければ枠ごとに並べる
    func scheduleText(locale: Locale = Strings.locale, now: Date = Date(), calendar: Calendar = .current) -> String {
        if let fire = oneOffFire(calendar: calendar) {
            return Format.once(fire, now: now, calendar: calendar, locale: locale)
        }
        let ja = locale.language.languageCode?.identifier == "ja"
        let slots = Set(schedule.map { Slot(hour: $0.hour, minute: $0.minute, weekday: $0.weekday.map { $0 % 7 }) })
        let minutes = Set(slots.map { $0.hour * 60 + $0.minute }).sorted()
        let days = Set(slots.map(\.weekday))
        let time = { (m: Int) in Format.timeOfDay(hour: m / 60, minute: m % 60, locale: locale) }
        let dayNames = { (ds: [Int]) in
            ds.map { Format.weekday($0, locale: locale) }.joined(separator: ja ? "・" : ", ")
        }
        let isGrid = slots.count == minutes.count * days.count && (days == [nil] || !days.contains(nil))
        if isGrid {
            let interval = Self.interval(minutes, ja: ja, time: time)
            let times = interval ?? minutes.map(time).joined(separator: ", ")
            // 英語は「Daily at 9:00」と「Daily, every 20 min …」で前置きの形が変わる
            let at = interval == nil ? " at " : ", "
            if days == [nil] { return ja ? "毎日 \(times)" : "Daily\(at)\(times)" }
            let names = dayNames(days.compactMap { $0 }.sorted())
            return ja ? "\(names) \(times)" : "\(names)\(at)\(times)"
        }
        return slots.sorted { ($0.weekday ?? -1, $0.hour, $0.minute) < ($1.weekday ?? -1, $1.hour, $1.minute) }
            .map { slot in
                let t = time(slot.hour * 60 + slot.minute)
                guard let day = slot.weekday else { return ja ? "毎日 \(t)" : "Daily \(t)" }
                return "\(dayNames([day])) \(t)"
            }
            .joined(separator: ", ")
    }

    var scheduleText: String { scheduleText() }

    /// 等間隔の時刻を「9:00〜0:40 の20分おき」とまとめる。日をまたいでもよい（円の上で、間が1か所だけ空いている）。
    /// 予約投稿のジョブで48個の時刻を並べ、見出しの下が5行に埋まっていた（2026-10-14）。4個より少なければまとめない
    static func interval(_ minutes: [Int], ja: Bool, time: (Int) -> String) -> String? {
        guard minutes.count >= 4 else { return nil }
        let gaps = minutes.indices.map { i in
            i + 1 < minutes.count ? minutes[i + 1] - minutes[i] : minutes[0] + 24 * 60 - minutes[i]
        }
        let step = gaps.min() ?? 0
        let wide = gaps.indices.filter { gaps[$0] != step }
        let every =
            step % 60 == 0
            ? (ja ? "\(step / 60)時間おき" : "every \(step / 60) h") : (ja ? "\(step)分おき" : "every \(step) min")
        // 一日じゅう等間隔なら、始まりも終わりも無い
        if wide.isEmpty { return every }
        guard wide.count == 1 else { return nil }
        let first = minutes[(wide[0] + 1) % minutes.count]
        let last = minutes[wide[0]]
        return ja ? "\(time(first))〜\(time(last)) の\(every)" : "\(every) from \(time(first)) to \(time(last))"
    }
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

    /// 定義を書いた時刻。予定が今の形になったのはこれ以降
    static func written(_ id: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.job(id).path))?[.modificationDate] as? Date
    }

    static func load(_ id: String) -> Job? {
        try? JSONDecoder().decode(Job.self, from: Data(contentsOf: Paths.job(id)))
    }

    /// 定義を書き、plist を書き、launchd に読み込ませ直す
    static func install(_ job: Job, owler: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.jobsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: Paths.launchAgents, withIntermediateDirectories: true)
        let previous = load(job.id)
        try write(plistFor: job, owler: owler)
        // 読み込み済みなら外してから入れ直す。外さずに入れると古い定義のまま残る。
        // bootout はすぐには終わらないので、外れたのを確かめてから入れる
        Launchctl.bootoutAndWait(Paths.label(job.id))
        do {
            try Launchctl.bootstrap(Paths.plist(job.id))
        } catch {
            // 入れ損ねたら前の定義に戻す。定義だけ新しくなって launchd に何も無い、という半端を残さない
            if let previous {
                try? write(plistFor: previous, owler: owler)
                try? Launchctl.bootstrap(Paths.plist(job.id))
            } else {
                try? FileManager.default.removeItem(at: Paths.plist(job.id))
            }
            throw error
        }
        Reload.remember(job.id, program: owler)
        try save(job)
    }

    /// 定義だけを書く。launchd には触らない
    static func save(_ job: Job) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(job).write(to: Paths.job(job.id))
    }

    struct Missing: Error, CustomStringConvertible {
        let id: String
        var description: String { "No such job: \(id)" }
    }

    /// 止める。先に定義に paused を書いてから launchd から外す。plist は残し、再開で入れ直す。
    /// 動いている回があれば今は外さず、false を返す。bootout は動いているジョブのプロセスに SIGTERM を送って止める
    /// （2026-11-26 に実測。Reload が動いている回の終わりを待つのも同じ理由）。その回は最後まで動かし、
    /// 終わったところで Owler run が定義の paused を見て自分で外す（Runner）。
    /// 先に paused を書くので、外すまでのあいだに時刻が来ても、Owler run は動かさずに外す
    @discardableResult
    static func pause(_ id: String) throws -> Bool {
        guard var job = load(id) else { throw Missing(id: id) }
        job.paused = true
        try save(job)
        if isRunning(id) { return false }
        Launchctl.bootoutAndWait(Paths.label(id))
        return true
    }

    /// 再開する。launchd に入っていなければ、plist を定義から書き直して入れる。Owler の外で Disabled を
    /// 書かれた plist は入れられない（bootstrap が断る）ので、書き直して消す。`launchctl disable` の印も外す。
    /// 呼ぶ実行ファイルは今の plist のものを引き継ぐ。手元のビルドで再開しても、ジョブの呼び先を変えない。
    /// 動いている最中に止めて、まだ外れていない（その回が終わっていない）ときは、入れ直すと回が止まるので印を消すだけ。
    /// 済んだ1回だけのジョブは入れない。入れると翌年の同じ日に起こされる
    static func resume(_ id: String, owler fallback: String) throws {
        guard var job = load(id) else { throw Missing(id: id) }
        job.paused = nil
        let label = Paths.label(id)
        if !job.isDone(), !Launchctl.isLoaded(label) {
            let owler = Reload.program(id) ?? fallback
            try FileManager.default.createDirectory(at: Paths.launchAgents, withIntermediateDirectories: true)
            try write(plistFor: job, owler: owler)
            Launchctl.enable(label)
            try Launchctl.bootstrap(Paths.plist(id))
            Reload.remember(id, program: owler)
        }
        try save(job)
    }

    /// 今すぐ動かす。止めたジョブや済んだ1回だけのジョブは launchd に入っていないので、入れてから起こす。
    /// 起こした回は、手で動かした印（RunStore.manualRequest）を見て Owler run が動かし、終わったら外し直す。
    /// Owler の外で止められたジョブは、止めた（paused）扱いにしてから入れる。そうしないと回のあとも入ったままで、
    /// 黙って再開してしまう。plist は定義から書き直す。外で Disabled を書かれた plist は bootstrap が断るため
    static func runNow(_ id: String) throws {
        let label = Paths.label(id)
        if !Launchctl.isLoaded(label), var job = load(id) {
            if !job.isDone(), job.paused != true {
                job.paused = true
                try save(job)
            }
            try write(plistFor: job, owler: Reload.program(id) ?? CLI.executable)
            try Launchctl.bootstrap(Paths.plist(id))
        }
        RunStore.requestManual(id)
        let result = Launchctl.kickstart(label)
        if result.status != 0 {
            RunStore.cancelManual(id)
            throw Launchctl.Failure(description: "launchctl kickstart: \(result.output)")
        }
    }

    /// その回がまだ動いているか。launchd が起こした直後（記録を書く前）も含む
    static func isRunning(_ id: String) -> Bool {
        Launchctl.isRunning(Paths.label(id)) || RunStore.all(id, limit: 1).first?.state == .running
    }

    private static func write(plistFor job: Job, owler: String) throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: job.launchdPlist(owler: owler), format: .xml, options: 0)
        try plist.write(to: Paths.plist(job.id))
    }

    static func remove(_ id: String) {
        Launchctl.bootoutAndWait(Paths.label(id))
        try? FileManager.default.removeItem(at: Paths.plist(id))
        try? FileManager.default.removeItem(at: Paths.job(id))
    }
}

/// 更新で Owler の署名が変わったら、ジョブを launchd に入れ直す。
/// macOS はジョブごとに、起こしてよいプログラムの署名を覚えている（launchctl print の「managed LWCR」）。
/// 自己署名なので更新のたびに食い違い、入れ直すまで起動の段階で殺されるか、起こされもしなかった。
/// 0.1.14 と 0.1.16 に上げた直後の 9:00 に、どちらも起きた（2026-10-16・10-21）。入れ直せば通る（実測）。
/// 見るのは各ジョブの plist が呼ぶ実行ファイルの署名で、入れたときの値をジョブごとに覚える。
/// 動いている Owler の署名で決めると、手元のビルドを開いただけで全部を入れ直してしまう
enum Reload {
    private static let key = "loadedCodeHashes"

    /// その実行ファイルの署名の値（cdhash）
    static func codeHash(at path: String) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
            let hash = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// plist が呼ぶ実行ファイル
    static func program(_ id: String) -> String? {
        guard let data = try? Data(contentsOf: Paths.plist(id)),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    static func needed(loaded: String?, current: String?) -> Bool {
        guard let current else { return false }
        return loaded != current
    }

    private static var loaded: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 入れた時点の署名を覚える。`owler add` のたびに、次の起動で入れ直さずに済む
    static func remember(_ id: String, program: String) {
        guard let hash = codeHash(at: program) else { return }
        loaded[id] = hash
    }

    /// アプリの起動時に呼ぶ。動いているジョブは入れ直すと止まるので、終わるまで1分おきに待つ。
    /// 入れ損ねたジョブも覚えずに次の巡で試す。1時間で諦め、残りは次に起動したときにやる
    /// 入れ直すジョブか。止めたジョブと済んだ1回だけのジョブは、launchd に戻すと止めた意味が無くなる（1回だけのジョブは
    /// 翌年の同じ日に起こされる）。Owler の外で外されたジョブ（loaded が false）も、入れ直すと利用者の操作を覆すので触らない。
    /// ただし自分で外して入れ損ねたジョブ（retrying）は、外れているのが自分のせいなので入れ直す
    static func reloads(_ job: Job, loaded: Bool, retrying: Bool, now: Date = Date()) -> Bool {
        job.paused != true && !job.isDone(now: now) && (loaded || retrying)
    }

    static func ifUpdated() {
        Thread.detachNewThread {
            // 外したあと入れ損ねたジョブ。次の巡で、launchd に入っていなくても入れ直す
            var retrying: Set<String> = []
            for _ in 0..<60 {
                var waiting = false
                // 巡ごとに読み直す。待っているあいだに消されたジョブ・止めたジョブを入れ直さない
                for job in JobStore.all() {
                    guard let program = program(job.id),
                        needed(loaded: loaded[job.id], current: codeHash(at: program)),
                        reloads(
                            job, loaded: Launchctl.isLoaded(Paths.label(job.id)), retrying: retrying.contains(job.id))
                    else {
                        retrying.remove(job.id)
                        continue
                    }
                    if JobStore.isRunning(job.id) {
                        waiting = true
                        continue
                    }
                    Launchctl.bootoutAndWait(Paths.label(job.id))
                    do {
                        try Launchctl.bootstrap(Paths.plist(job.id))
                        remember(job.id, program: program)
                        retrying.remove(job.id)
                    } catch {
                        retrying.insert(job.id)
                        waiting = true
                    }
                }
                if !waiting { return }
                sleep(60)
            }
        }
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

    /// 外した直後は「入出力エラー」で断られることがあるので、少し間を置いて数回試す
    static func bootstrap(_ plist: URL) throws {
        var result = call(["bootstrap", domain, plist.path])
        for _ in 0..<5 where result.status != 0 {
            usleep(500_000)
            result = call(["bootstrap", domain, plist.path])
        }
        if result.status != 0 { throw Failure(description: "launchctl bootstrap: \(result.output)") }
    }

    static func isLoaded(_ label: String) -> Bool { call(["print", "\(domain)/\(label)"]).status == 0 }

    /// launchd がそのジョブのプロセスを起こしている最中か。回の記録を書く前の、起きた直後も含む
    static func isRunning(_ label: String) -> Bool {
        call(["print", "\(domain)/\(label)"]).output.contains("\n\tstate = running")
    }

    /// 外して、外れたのを確かめる。読み込まれていなくても失敗にしない
    static func bootoutAndWait(_ label: String) {
        call(["bootout", "\(domain)/\(label)"])
        for _ in 0..<50 where isLoaded(label) { usleep(100_000) }
    }

    static func bootout(_ label: String) { call(["bootout", "\(domain)/\(label)"]) }

    /// 時刻を待たずに今すぐ動かす。launchd に入っていなければ断られる
    @discardableResult
    static func kickstart(_ label: String) -> (status: Int32, output: String) {
        call(["kickstart", "\(domain)/\(label)"])
    }

    /// `launchctl disable` の印を外す。印があると、plist を直しても bootstrap が断る
    static func enable(_ label: String) { call(["enable", "\(domain)/\(label)"]) }

    /// 入っているジョブのラベルと、動いていればそのプロセスの番号。`launchctl list` を1回だけ呼ぶ。
    /// ジョブごとに `print` を呼ぶと、3秒ごとの読み直しのたびにジョブの数だけ launchctl を起こすことになる
    static func list() -> [String: Int32?]? {
        let result = call(["list"])
        return result.status == 0 ? parseList(result.output) : nil
    }

    /// `PID\tStatus\tLabel` の行を読む。動いていなければ PID は `-`
    static func parseList(_ output: String) -> [String: Int32?] {
        var jobs: [String: Int32?] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            // 添字で nil を入れると鍵ごと消えるので updateValue で入れる
            jobs.updateValue(Int32(columns[0]), forKey: String(columns[2]))
        }
        return jobs
    }
}

/// launchd に入っているジョブ。窓とメニューバーが3秒ごとに読み直すたびに launchctl を起こさないよう、
/// `launchctl list` を1回だけ呼び、10秒は覚えておく。読むのは裏で行い、まだ読めていなければ分からない（nil）
@MainActor
final class LoadedJobs {
    static let shared = LoadedJobs()

    /// ラベルと、動いていればそのプロセスの番号
    private var labels: [String: Int32?]?
    private var fetchedAt: Date?
    private var fetching = false
    /// 読んでいる最中に古くなった。読み終えても覚えずに、次に聞かれたときに読み直す
    private var staleWhileFetching = false

    /// 入っているか。分からなければ nil
    func isLoaded(_ id: String) -> Bool? {
        refreshIfStale()
        return labels.map { $0[Paths.label(id)] != nil }
    }

    /// 止める・再開する・今すぐ実行したあとに呼ぶ。次に聞かれたときに読み直す
    func invalidate() {
        fetchedAt = nil
        if fetching { staleWhileFetching = true }
        refreshIfStale()
    }

    private func refreshIfStale() {
        guard !fetching, (fetchedAt.map { Date().timeIntervalSince($0) > 10 }) ?? true else { return }
        fetching = true
        Task.detached {
            let now = Date()
            let labels = Launchctl.list()
            if let labels { Self.unloadFinishedOneOffs(labels, now: now) }
            await MainActor.run {
                // 読めなかったときは前の値を残す
                if let labels { self.labels = labels }
                self.fetchedAt = self.staleWhileFetching ? nil : now
                self.staleWhileFetching = false
                self.fetching = false
            }
        }
    }

    /// 念のための片付け。済んだ1回だけのジョブがまだ入っていれば外す。ふつうは動いた回の Owler run が外すが、
    /// 外す前に止められた・記録なしで過ぎた、といったときに残る。残すと翌年の同じ日に起こされる
    /// （そのときも Owler run は動かさないが、外しておく）
    nonisolated private static func unloadFinishedOneOffs(_ labels: [String: Int32?], now: Date) {
        for job in JobStore.all() where job.on != nil {
            let label = Paths.label(job.id)
            guard let pid = labels[label], pid == nil,
                job.leftLoaded(lastRun: RunStore.all(job.id, limit: 1).first, now: now)
            else { continue }
            Launchctl.bootout(label)
        }
    }
}
