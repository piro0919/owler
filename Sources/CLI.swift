import Foundation

/// `Owler <command>` で呼ばれたときの入口。Claude Code がジョブを足すときもここを通る
enum CLI {
    static let usage = """
        Usage:
          owler add <id> --folder <dir> --at <HH:MM> [--at <HH:MM>...] [--weekdays <days>]
                    [--summary <text>] [--also-log <file>] -- <command> [args...]
              Register a job and load it into launchd. <id> is lowercase letters, digits and '-'.
              <days> is like 1-5 or 0,6 (0 = Sunday). Omit it to run every day.
              Re-running add with the same <id> replaces the job.
          owler import <plist> --id <id> [--folder <dir>] [--summary <text>]
              Take over an existing launchd job. The old job is unloaded and its plist is moved to
              ~/Library/Application Support/Owler/imported/. Its StandardOutPath keeps receiving output.
          owler remove <id>       Unload a job and delete it.
          owler start <id>        Run a job now.
          owler list              Show jobs and their last run.
          owler open <id>         Open the last run in Claude Code (Cursor or VS Code).
          owler run <id>          Used by launchd. Runs the job and records it.

        A run that starts `claude -p` in the job's folder is linked to that Claude Code session,
        so it can be reopened from the Owler window.
        """

    /// アプリの中の実行ファイル。plist はここを呼ぶ
    static var executable: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    static func main(_ args: [String]) -> Int32 {
        guard let command = args.first else { return fail(usage) }
        let rest = Array(args.dropFirst())
        switch command {
        case "add": return add(rest)
        case "import": return importJob(rest)
        case "remove": return withID(rest) { JobStore.remove($0) }
        case "start": return withID(rest) { Launchctl.kickstart(Paths.label($0)) }
        case "list": return list()
        case "open": return open(rest)
        case "run":
            guard let id = rest.first else { return fail(usage) }
            return Runner.run(id)
        case "help", "--help", "-h":
            print(usage)
            return 0
        default: return fail(usage)
        }
    }

    // MARK: - 引数

    struct Options {
        var positional: [String] = []
        var values: [String: [String]] = [:]
        var tail: [String] = []

        func one(_ key: String) -> String? { values[key]?.last }
    }

    /// `--key value` を集め、`--` より後ろはそのまま残す
    static func parse(_ args: [String]) -> Options? {
        var options = Options()
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--" {
                options.tail = Array(args[(i + 1)...])
                break
            }
            if arg.hasPrefix("--") {
                guard i + 1 < args.count else { return nil }
                options.values[String(arg.dropFirst(2)), default: []].append(args[i + 1])
                i += 2
            } else {
                options.positional.append(arg)
                i += 1
            }
        }
        return options
    }

    // MARK: - コマンド

    static func add(_ args: [String]) -> Int32 {
        guard let o = parse(args), let id = o.positional.first, let folder = o.one("folder"), !o.tail.isEmpty
        else { return fail(usage) }
        guard Job.isValidID(id) else { return fail("Invalid id: \(id)") }
        let times = (o.values["at"] ?? []).map(ScheduleParser.time)
        guard !times.isEmpty, !times.contains(where: { $0 == nil }) else { return fail("Give --at as HH:MM") }
        var weekdays: [Int]?
        if let text = o.one("weekdays") {
            guard let days = ScheduleParser.weekdays(text) else { return fail("Invalid --weekdays: \(text)") }
            weekdays = days
        }
        let job = Job(
            id: id,
            summary: o.one("summary") ?? "",
            folder: absolute(folder),
            command: o.tail,
            schedule: ScheduleParser.slots(times: times.compactMap { $0 }, weekdays: weekdays),
            alsoLogTo: o.one("also-log").map(absolute))
        return install(job)
    }

    static func importJob(_ args: [String]) -> Int32 {
        guard let o = parse(args), let path = o.positional.first, let id = o.one("id") else { return fail(usage) }
        guard Job.isValidID(id) else { return fail("Invalid id: \(id)") }
        let source = URL(fileURLWithPath: absolute(path))
        guard let data = try? Data(contentsOf: source),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let label = plist["Label"] as? String
        else { return fail("Cannot read \(source.path)") }
        if label.hasPrefix(Paths.labelPrefix) { return fail("\(label) is already an Owler job") }
        let command =
            plist["ProgramArguments"] as? [String] ?? (plist["Program"] as? String).map { [$0] } ?? []
        guard !command.isEmpty else { return fail("\(label) has no ProgramArguments") }
        guard let schedule = ScheduleParser.slots(fromLaunchd: plist["StartCalendarInterval"]) else {
            return fail("\(label) has no StartCalendarInterval that Owler can express (Hour, Minute, Weekday)")
        }
        guard let folder = o.one("folder").map(absolute) ?? plist["WorkingDirectory"] as? String else {
            return fail("\(label) has no WorkingDirectory. Give --folder")
        }
        let job = Job(
            id: id,
            summary: o.one("summary") ?? "",
            folder: folder,
            command: command,
            schedule: schedule,
            alsoLogTo: plist["StandardOutPath"] as? String)

        // 新しいほうを入れてから古いほうを外す。両方が入っている間に時刻が来ると2回動くが、
        // 先に外して入れ損ねると1回も動かなくなる。こちらのほうが害が大きい
        let status = install(job)
        guard status == 0 else { return status }
        Launchctl.bootout(label)
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.importedDir, withIntermediateDirectories: true)
        let backup = Paths.importedDir.appendingPathComponent(source.lastPathComponent)
        try? fm.removeItem(at: backup)
        do {
            try fm.moveItem(at: source, to: backup)
        } catch {
            return fail("Imported, but could not move \(source.path): \(error)")
        }
        print("Moved \(source.lastPathComponent) to \(backup.path)")
        return 0
    }

    static func list() -> Int32 {
        let jobs = JobStore.all()
        if jobs.isEmpty { print("No jobs") }
        for job in jobs {
            let last = RunStore.all(job.id, limit: 1).first
            let state =
                switch last?.state {
                case .running: "running"
                case .succeeded: "ok"
                case .failed: "failed (\(last?.exitCode ?? 0))"
                case nil: "never run"
                }
            print("\(job.id)\t\(job.scheduleText)\t\(state)\t\(job.summary)")
        }
        return 0
    }

    static func open(_ args: [String]) -> Int32 {
        guard let id = args.first, let job = JobStore.load(id) else { return fail("No such job: \(args.first ?? "")") }
        guard let editor = Editor.installed else { return fail("Neither Cursor nor VS Code is installed") }
        // 窓が前に来るのを待ってから URL を渡すので、渡し終えるまで終わらずに待つ
        nonisolated(unsafe) var finished = false
        MainActor.assumeIsolated {
            editor.open(job: job, run: RunStore.all(id, limit: 1).first) { finished = true }
        }
        let deadline = Date().addingTimeInterval(15)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        return 0
    }

    // MARK: - 下請け

    static func install(_ job: Job) -> Int32 {
        do {
            try JobStore.install(job, owler: executable)
        } catch {
            return fail("\(error)")
        }
        print("Registered \(Paths.label(job.id)): \(job.scheduleText)")
        return 0
    }

    static func withID(_ args: [String], _ action: (String) -> Void) -> Int32 {
        guard let id = args.first, JobStore.load(id) != nil else { return fail("No such job: \(args.first ?? "")") }
        action(id)
        return 0
    }

    static func absolute(_ path: String) -> String {
        let expanded = Paths.expand(path)
        if expanded.hasPrefix("/") { return expanded }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).standardizedFileURL.path
    }

    @discardableResult
    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}
