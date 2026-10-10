import AppKit

/// 画面も launchd も触らずに、規則だけを確かめる。`./Owler --selftest` で走る
@MainActor
enum SelfTest {
    private static var failures = 0

    static func run() -> Int32 {
        failures = 0

        // Claude Code のセッションの置き場の名前
        do {
            check(
                Paths.claudeProjectName("/Users/piro/.config/spatto-promo") == "-Users-piro--config-spatto-promo",
                "`/` と `.` は `-` になる")
            check(Paths.claudeProjectName("/Users/a/日本") == "-Users-a---", "英数字以外は `-` になる")
        }

        // 時刻と曜日
        do {
            check(ScheduleParser.time("10:00")! == (10, 0), "時刻を読む")
            check(ScheduleParser.time("24:00") == nil, "24時は無い")
            check(ScheduleParser.time("9") == nil, "分が無ければ読まない")
            check(ScheduleParser.weekdays("1-5") == [1, 2, 3, 4, 5], "範囲を読む")
            check(ScheduleParser.weekdays("0,7,6") == [0, 6], "7 は日曜として 0 にまとめる")
            check(ScheduleParser.weekdays("5-1") == nil, "逆向きの範囲は読まない")
            check(ScheduleParser.weekdays("8") == nil, "8 は曜日ではない")
            let slots = ScheduleParser.slots(times: [(10, 0)], weekdays: [1, 2])
            check(slots.count == 2 && slots.allSatisfy { $0.hour == 10 }, "曜日ごとに枠を作る")
        }

        // 既存の plist の読み込み
        do {
            let one = ScheduleParser.slots(fromLaunchd: ["Hour": 17, "Minute": 30])
            check(one == [Job.Slot(hour: 17, minute: 30, weekday: nil)], "1件の辞書を読む")
            let many = ScheduleParser.slots(fromLaunchd: [["Hour": 9, "Minute": 0, "Weekday": 1]])
            check(many == [Job.Slot(hour: 9, minute: 0, weekday: 1)], "配列を読む")
            check(ScheduleParser.slots(fromLaunchd: ["Hour": 9, "Minute": 0, "Day": 1]) == nil, "日付の指定は表せない")
            check(ScheduleParser.slots(fromLaunchd: nil) == nil, "時刻の無いジョブは取り込まない")
        }

        // launchd に渡す plist
        do {
            let job = Job(
                id: "daily", summary: "", folder: "/tmp", command: ["/bin/echo"],
                schedule: [Job.Slot(hour: 10, minute: 0, weekday: 1)], alsoLogTo: nil)
            let plist = job.launchdPlist(owler: "/Applications/Owler.app/Contents/MacOS/Owler")
            check(plist["Label"] as? String == "io.kkweb.owler.job.daily", "ラベルに頭を付ける")
            check(
                plist["ProgramArguments"] as? [String] == [
                    "/Applications/Owler.app/Contents/MacOS/Owler", "run", "daily",
                ],
                "Owler を経由して動かす")
            let intervals = plist["StartCalendarInterval"] as? [[String: Int]]
            check(intervals == [["Hour": 10, "Minute": 0, "Weekday": 1]], "曜日つきの枠を書く")
        }

        // 次に動く時刻
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let job = Job(
                id: "a", summary: "", folder: "/tmp", command: ["/bin/echo"],
                schedule: [Job.Slot(hour: 10, minute: 0, weekday: 1)], alsoLogTo: nil)
            // 2026-10-09 は金曜。次の月曜は 10-12
            let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))!
            let next = job.nextFire(after: friday, calendar: calendar)
            let parts = next.map { calendar.dateComponents([.month, .day, .hour], from: $0) }
            check(parts?.month == 10 && parts?.day == 12 && parts?.hour == 10, "launchd の曜日で次を求める")
            let previous = job.previousFire(before: friday, calendar: calendar)
            let back = previous.map { calendar.dateComponents([.month, .day, .hour], from: $0) }
            check(back?.month == 10 && back?.day == 5 && back?.hour == 10, "直前の予定の回を求める")
        }

        // 近い日時とメニューの2行目
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let ja = Locale(identifier: "ja_JP")
            let us = Locale(identifier: "en_US")
            func at(_ day: Int, _ hour: Int) -> Date {
                calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
            }
            let now = at(10, 12)
            check(Format.near(at(10, 15), now: now, calendar: calendar, locale: ja) == "今日 15:00", "今日は言葉にする")
            check(Format.near(at(11, 9), now: now, calendar: calendar, locale: ja) == "明日 9:00", "明日は言葉にする")
            check(
                Format.near(at(11, 9), now: now, calendar: calendar, locale: us).hasPrefix("Tomorrow "),
                "英語の明日")
            check(Format.near(at(12, 9), now: now, calendar: calendar, locale: ja).contains("12"), "明後日からは日付")

            let daily = Job(
                id: "a", summary: "", folder: "/tmp", command: ["/bin/echo"],
                schedule: [Job.Slot(hour: 9, minute: 0, weekday: nil)], alsoLogTo: nil)
            func run(_ start: Date, _ code: Int32) -> RunRecord {
                RunRecord(stamp: "s", start: start, end: start, exitCode: code, session: nil, pid: nil)
            }
            let line = { (r: RunRecord?) in MenuBar.line(daily, r, now: now, calendar: calendar) }
            check(
                line(run(at(10, 9), 0)) == Strings.nextRun(Format.near(at(11, 9), now: now, calendar: calendar)),
                "成功なら次回だけ")
            check(line(run(at(10, 9), 1)).hasPrefix(Strings.failed(1) + " · "), "失敗は言葉で添える")
            check(line(run(at(8, 9), 0)).hasPrefix(Strings.lastRun("")), "予定の回が無ければ前回を出す")
            check(line(nil).hasPrefix(Strings.noRuns + " · "), "まだ動いていないことも出す")
        }

        // 日時の書き方は地域に従う
        do {
            let ja = Locale(identifier: "ja_JP")
            let us = Locale(identifier: "en_US")
            let gb = Locale(identifier: "en_GB")
            check(Format.timeOfDay(hour: 3, minute: 33, locale: ja) == "3:33", "日本語の時刻は24時間制")
            check(Format.timeOfDay(hour: 15, minute: 5, locale: ja) == "15:05", "日本語の午後も24時間制")
            check(
                Format.timeOfDay(hour: 15, minute: 5, locale: us).replacingOccurrences(of: "\u{202F}", with: " ")
                    == "3:05 PM", "アメリカの英語は12時間制")
            check(Format.timeOfDay(hour: 15, minute: 5, locale: gb) == "15:05", "イギリスの英語は24時間制")
            check(Format.weekday(1, locale: ja) == "月", "日本語の曜日")
            check(Format.weekday(0, locale: us) == "Sun", "英語の曜日。0 が日曜")
            check(Format.duration(6, locale: ja) == "6秒", "日本語のかかった時間")
            check(Format.duration(65, locale: us) == "1m 5s", "英語のかかった時間")
            let job = Job(
                id: "a", summary: "", folder: "/tmp", command: ["/bin/echo"],
                schedule: [Job.Slot(hour: 9, minute: 0, weekday: 1), Job.Slot(hour: 9, minute: 0, weekday: 5)],
                alsoLogTo: nil)
            check(job.scheduleText(locale: ja) == "月・金 9:00", "日本語の時刻の説明")
            check(
                job.scheduleText(locale: us).replacingOccurrences(of: "\u{202F}", with: " ") == "Mon, Fri at 9:00 AM",
                "英語の時刻の説明")
        }

        // 時刻×曜日が揃っていない枠は、まとめずに並べる
        do {
            let ja = Locale(identifier: "ja_JP")
            func job(_ slots: [Job.Slot]) -> Job {
                Job(id: "a", summary: "", folder: "/tmp", command: ["/bin/echo"], schedule: slots, alsoLogTo: nil)
            }
            check(
                job([Job.Slot(hour: 9, minute: 0, weekday: 1), Job.Slot(hour: 17, minute: 0, weekday: 5)])
                    .scheduleText(locale: ja) == "月 9:00, 金 17:00", "曜日ごとに時刻が違えば枠ごとに並べる")
            check(
                job([Job.Slot(hour: 9, minute: 0, weekday: nil), Job.Slot(hour: 18, minute: 0, weekday: 1)])
                    .scheduleText(locale: ja) == "毎日 9:00, 月 18:00", "毎日の枠を落とさない")
            check(
                job([Job.Slot(hour: 9, minute: 0, weekday: 0), Job.Slot(hour: 9, minute: 0, weekday: 7)])
                    .scheduleText(locale: ja) == "日 9:00", "0 と 7 は同じ日曜")
        }

        // メニューバーの絵
        do {
            let icon = NSImage(size: NSSize(width: 18, height: 18))
            let single = StatusTitle.image(icon: icon, failed: 1, running: 0, phase: 0)
            let both = StatusTitle.image(icon: icon, failed: 1, running: 12, phase: 0.5)
            check(single.size.height == 22, "メニューバーの厚みに収める")
            check(single.size.width > 18 && single.isTemplate, "影絵の右に印と数を足し、テンプレート画像にする")
            check(both.size.width >= single.size.width, "桁が増えれば幅も増える")
        }

        // 子の終わり方
        do {
            check(Spawn.exitCode(fromWaitStatus: 0) == 0, "正常に終われば 0")
            check(Spawn.exitCode(fromWaitStatus: 3 << 8) == 3, "終了コードを読む")
            check(Spawn.exitCode(fromWaitStatus: 15) == 143, "シグナルで止まれば 128 + 番号")
            check(Spawn.canDisclaim, "ジョブを Owler の許可から切り離せる")
        }

        // 中断した回
        do {
            var run = RunRecord(stamp: "x", start: Date(), pid: getpid())
            check(run.state == .running, "記録を取っているプロセスが生きていれば実行中")
            run.pid = 999_999
            check(run.state == .interrupted, "プロセスがいなければ中断")
            run.exitCode = 0
            check(run.state == .succeeded, "終わりが書かれていればその結果")
        }

        // 紐づけるのは claude -p のセッションだけ
        do {
            check(Sessions.isNonInteractive(head: #"{"entrypoint":"sdk-cli","type":"user"}"#), "sdk-cli は紐づける")
            check(!Sessions.isNonInteractive(head: #"{"entrypoint":"claude-vscode"}"#), "エディタの対話は紐づけない")
            check(!Sessions.isNonInteractive(head: #"{"entrypoint":"cli"}"#), "ターミナルの対話は紐づけない")
        }

        // コマンドの名前を絶対パスにする
        do {
            check(CLI.resolve("sh", environment: ["PATH": "/nowhere:/bin"]) == "/bin/sh", "PATH から探す")
            check(CLI.resolve("no-such-command-xyz", environment: ["PATH": "/bin"]) == nil, "無ければ断る")
            check(CLI.resolve("/bin/sh") == "/bin/sh", "絶対パスはそのまま")
        }

        // 知らないオプション
        do {
            let o = CLI.parse(["a", "--weekday", "1-5", "--at", "9:00"])
            check(o?.unknown(allowed: ["at", "weekdays"]) == "weekday", "綴りを間違えたオプションを拾う")
            check(o?.unknown(allowed: ["at", "weekday"]) == nil, "知っている名前だけなら無い")
        }

        // ジョブの名前
        do {
            check(Job.isValidID("spatto-promo"), "英小文字と `-` は使える")
            check(!Job.isValidID("Spatto"), "大文字は使えない")
            check(!Job.isValidID("a/b"), "`/` は使えない")
            check(!Job.isValidID(""), "空は使えない")
        }

        // セッションの最後の発言
        do {
            let jsonl = """
                {"type":"user","message":{"role":"user","content":"始めて"}}
                {"type":"assistant","message":{"content":[{"type":"text","text":"報告です"}]}}
                {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}
                {"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
                """
            check(Sessions.lastReply(jsonl: jsonl) == "報告です", "ツールの呼び出しを飛ばして最後の文を拾う")
            check(Sessions.lastReply(jsonl: "") == nil, "空なら無い")
        }

        // 引数
        do {
            let o = CLI.parse(["daily", "--at", "10:00", "--at", "18:00", "--", "/bin/zsh", "--at", "x"])
            check(o?.positional == ["daily"], "位置の引数を拾う")
            check(o?.values["at"] == ["10:00", "18:00"], "同じ名前を重ねられる")
            check(o?.tail == ["/bin/zsh", "--at", "x"], "`--` より後ろはそのまま")
            check(CLI.parse(["--at"]) == nil, "値の無い名前は誤り")
        }

        // エディタに渡す URL
        do {
            let url = Editor.cursor.claudeURL(session: "abc", prompt: "見て & 直して")?.absoluteString
            check(
                url
                    == "cursor://anthropic.claude-code/open?session=abc&prompt=%E8%A6%8B%E3%81%A6%20%26%20%E7%9B%B4%E3%81%97%E3%81%A6",
                "セッションと最初の一言を渡す")
        }

        print(failures == 0 ? "selftest: ok" : "selftest: \(failures) failed")
        return failures == 0 ? 0 : 1
    }

    private static func check(_ condition: Bool, _ name: String) {
        if !condition {
            failures += 1
            print("NG: \(name)")
        }
    }
}
