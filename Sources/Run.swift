import Foundation

/// 1回の実行の記録。`runs/<id>/<stamp>.json` に置き、出力は同じ名前の .log に置く
struct RunRecord: Codable, Equatable, Identifiable {
    var stamp: String
    var start: Date
    var end: Date?
    var exitCode: Int32?
    /// この実行の間に作られた Claude Code のセッション
    var session: String?
    /// 記録を取っている `Owler run` のプロセス。終わりを書けずに止まった回を見分ける
    var pid: Int32?

    var id: String { stamp }

    /// interrupted は、終わりを書く前に `Owler run` ごと止められた回（登録し直し・ログアウト・電源断など）
    enum State { case running, succeeded, failed, interrupted }

    var state: State {
        if let exitCode { return exitCode == 0 ? .succeeded : .failed }
        guard let pid, kill(pid, 0) == 0 || errno == EPERM else { return .interrupted }
        return .running
    }
}

enum RunStore {
    static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    static func record(_ id: String, _ stamp: String) -> URL {
        Paths.runs(id).appendingPathComponent("\(stamp).json")
    }

    static func log(_ id: String, _ stamp: String) -> URL {
        Paths.runs(id).appendingPathComponent("\(stamp).log")
    }

    /// 新しい順
    static func all(_ id: String, limit: Int = 50) -> [RunRecord] {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: Paths.runs(id), includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
            .compactMap { try? decoder.decode(RunRecord.self, from: Data(contentsOf: $0)) }
    }

    /// 残す回数。これより古い回は記録も出力も消す
    static let keep = 100

    static func prune(_ id: String) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.runs(id), includingPropertiesForKeys: nil)) ?? []
        let stamps = files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted(by: >)
        for stamp in stamps.dropFirst(keep) {
            try? fm.removeItem(at: record(id, stamp))
            try? fm.removeItem(at: log(id, stamp))
        }
    }

    static func save(_ record: RunRecord, for id: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: Self.record(id, record.stamp))
    }

    /// 出力の末尾
    static func tail(_ id: String, _ stamp: String, bytes: Int = 16_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: log(id, stamp)) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }
}

/// launchd から `Owler run <id>` で呼ばれ、記録を取りながらコマンドを動かす
enum Runner {
    static func run(_ id: String) -> Int32 {
        guard let job = JobStore.load(id), let executable = job.command.first else {
            FileHandle.standardError.write(Data("Owler: no such job: \(id)\n".utf8))
            return 2
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.runs(id), withIntermediateDirectories: true)
        let start = Date()
        var record = RunRecord(stamp: RunStore.stampFormat.string(from: start), start: start, pid: getpid())
        try? RunStore.save(record, for: id)

        fm.createFile(atPath: RunStore.log(id, record.stamp).path, contents: nil)
        let outputs = [RunStore.log(id, record.stamp).path, job.alsoLogTo.map(Paths.expand)]
            .compactMap { $0 }
            .compactMap { path -> FileHandle? in
                if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
                let handle = FileHandle(forWritingAtPath: path)
                _ = try? handle?.seekToEnd()
                return handle
            }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Paths.expand(executable))
        process.arguments = Array(job.command.dropFirst())
        process.currentDirectoryURL = URL(fileURLWithPath: Paths.expand(job.folder))
        if let extra = job.environment {
            process.environment = ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                done.signal()
                return
            }
            for output in outputs { output.write(data) }
        }

        let status: Int32
        do {
            try process.run()
            process.waitUntilExit()
            // 裏で起こした子が出力をつかんだまま残ると、終わりの印が来ない。少しだけ待って読むのをやめる
            if done.wait(timeout: .now() + 2) == .timedOut {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            status = process.terminationStatus
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            for output in outputs { output.write(Data("Owler: \(error)\n".utf8)) }
            status = 127
        }
        for output in outputs { try? output.close() }

        record.end = Date()
        record.exitCode = status
        record.session = Sessions.find(folder: Paths.expand(job.folder), from: start, to: record.end!)
        try? RunStore.save(record, for: id)
        RunStore.prune(id)
        return status
    }
}

/// Claude Code のセッションの記録を読む
enum Sessions {
    /// Claude Code は実体のパスで置き場を決める。`/tmp` なら `/private/tmp`。
    /// Foundation の resolvingSymlinksInPath は逆に `/private` を剥がすので、realpath を使う
    static func folder(for workdir: String) -> URL {
        let real = realpath(workdir, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        return Paths.claudeProjects.appendingPathComponent(Paths.claudeProjectName(real ?? workdir))
    }

    /// その実行の間に作られた、`claude -p` のセッション。複数あれば最後に書かれたもの。
    /// 同じフォルダで利用者が対話で使ったセッションは、記録の entrypoint が `sdk-` で始まらないので外す。
    /// スクリプトの中で別のフォルダへ移ってから claude を呼んだ場合は見つからない
    static func find(folder workdir: String, from start: Date, to end: Date) -> String? {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder(for: workdir), includingPropertiesForKeys: keys)) ?? []
        return
            files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> (String, Date)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                    let created = values.creationDate,
                    created >= start.addingTimeInterval(-1), created <= end.addingTimeInterval(1),
                    isNonInteractive(url)
                else { return nil }
                return (url.deletingPathExtension().lastPathComponent, values.contentModificationDate ?? created)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// 記録の頭に `"entrypoint":"sdk-cli"` のような印があるか
    static func isNonInteractive(_ transcript: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 64 * 1024)) ?? Data(), as: UTF8.self)
        return isNonInteractive(head: head)
    }

    static func isNonInteractive(head: String) -> Bool {
        head.contains("\"entrypoint\":\"sdk-")
    }

    static func transcript(folder workdir: String, session: String) -> URL {
        folder(for: workdir).appendingPathComponent("\(session).jsonl")
    }

    /// セッションの最後の Claude の発言。`claude -p` ならこれがその回の報告になる
    static func lastReply(in transcript: URL) -> String? {
        guard let data = try? Data(contentsOf: transcript) else { return nil }
        return lastReply(jsonl: String(decoding: data, as: UTF8.self))
    }

    static func lastReply(jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n").reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "assistant",
                let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { continue }
            let text = content.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }
}
