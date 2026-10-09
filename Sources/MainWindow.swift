import AppKit
import SwiftUI

/// 窓に出すものを集める。ファイルを見張らず、数秒ごとに読み直す
@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var lastRuns: [String: RunRecord] = [:]
    @Published var runs: [RunRecord] = []
    /// 切り替えたらその場で読み直す。3秒ごとの読み直しを待つと、前のジョブの一覧が残って見える
    @Published var selectedJob: String? {
        didSet {
            guard selectedJob != oldValue else { return }
            openedRunID = nil
            loadRuns()
        }
    }
    /// 開いている回。nil ならジョブのページ
    @Published var openedRunID: String?
    /// 実行中の回があるあいだ、読み直すたびに進める。回のページの出力を描き直させる
    @Published private(set) var tick = 0
    /// 終わった回の報告。記録は数 MB になるので、描くたびに読まない
    private var reports: [String: String?] = [:]

    private var timer: Timer?

    init() {
        reload()
        selectedJob = jobs.first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var job: Job? { jobs.first { $0.id == selectedJob } }
    var openedRun: RunRecord? { runs.first { $0.id == openedRunID } }
    /// Claude Code で開く回。開いている回が無ければ最新の回
    var run: RunRecord? { openedRun ?? runs.first }

    func reload() {
        let jobs = JobStore.all()
        if jobs != self.jobs { self.jobs = jobs }
        var last: [String: RunRecord] = [:]
        for job in jobs { last[job.id] = RunStore.all(job.id, limit: 1).first }
        if last != lastRuns { lastRuns = last }
        loadRuns()
    }

    private func loadRuns() {
        let runs = selectedJob.map { RunStore.all($0) } ?? []
        if runs != self.runs { self.runs = runs }
        if runs.contains(where: { $0.state == .running }) { tick += 1 }
    }

    /// その回の Claude の最後の発言。終わった回は一度読んだら覚えておく
    func report(job: Job, run: RunRecord) -> String? {
        guard let session = run.session else { return nil }
        if run.end != nil, let cached = reports[session] { return cached }
        let reply = Sessions.lastReply(in: Sessions.transcript(folder: Paths.expand(job.folder), session: session))
        if run.end != nil { reports[session] = reply }
        return reply
    }

    func runNow(_ id: String) {
        Launchctl.kickstart(Paths.label(id))
        // 記録は Owler run が書く。少し待ってから読み直す
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.reload() }
    }

    func openInEditor() {
        guard let job else { return }
        Editor.installed?.open(job: job, run: run)
    }

    func newJob() {
        Editor.installed?.open(folder: nil, session: nil, prompt: Strings.newJobPrompt(owler: CLI.executable))
    }
}

struct MainView: View {
    @ObservedObject var model: Model

    var body: some View {
        NavigationSplitView {
            List(model.jobs, selection: $model.selectedJob) { job in
                HStack(spacing: 10) {
                    StateDot(state: model.lastRuns[job.id]?.state)
                    Text(job.displayName).lineLimit(1)
                }
                .padding(.vertical, 4)
                .padding(.leading, 6)
                .contextMenu {
                    Button(Strings.runNow) { model.runNow(job.id) }
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 360)
            // 開閉のボタンを外すと、列の幅の指定だけでは細く畳まれる。一覧にも幅を持たせる
            .frame(minWidth: 240)
            // 一覧を畳む場面が無いので、開閉のボタンは出さない
            .toolbar(removing: .sidebarToggle)
            .overlay {
                if model.jobs.isEmpty {
                    VStack(spacing: 6) {
                        Text(Strings.noJobs).foregroundStyle(.secondary)
                        Text(Strings.noJobsHint).font(.caption).foregroundStyle(.tertiary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
            // 足すボタンは一覧の下に置く。リマインダーの「リストを追加」と同じ位置
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(action: model.newJob) {
                        Label(Strings.newJob, systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                if let job = model.job {
                    if let run = model.openedRun {
                        RunPage(model: model, job: job, run: run)
                    } else {
                        JobPage(model: model, job: job)
                    }
                } else {
                    Text(Strings.selectJob).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("")
        }
        .frame(minWidth: 860, minHeight: 520)
    }
}

/// ジョブのページ。手本は Vercel のデプロイ一覧。見出しと、枠に入った実行の表だけを置く
struct JobPage: View {
    @ObservedObject var model: Model
    let job: Job

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Header(title: job.displayName, subtitle: subtitle) {
                    OpenButton(model: model)
                }
                Card {
                    if model.runs.isEmpty {
                        Text(Strings.noRuns)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.runs.enumerated()), id: \.element.id) { index, run in
                                if index > 0 { Divider() }
                                RunRow(run: run) { model.openedRunID = run.id }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var subtitle: String {
        let next = job.nextFire().map { Strings.nextRun(Format.dateTime($0)) }
        return [job.scheduleText, next].compactMap { $0 }.joined(separator: " · ")
    }
}

/// 実行の表の1行。日時と状態だけ。押すとその回のページへ
struct RunRow: View {
    let run: RunRecord
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(Format.dateTime(run.start)).monospacedDigit()
                Spacer()
                StateDot(state: run.state)
                Text(Strings.stateName(run)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 1回の実行のページ。報告と出力を枠に入れて並べる
struct RunPage: View {
    @ObservedObject var model: Model
    let job: Job
    let run: RunRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    model.openedRunID = nil
                } label: {
                    Label(job.displayName, systemImage: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Header(title: Format.dateTime(run.start), subtitle: status, dot: run.state) {
                    OpenButton(model: model)
                }

                if let reply = model.report(job: job, run: run) {
                    Titled(Strings.report) {
                        Text(reply)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }

                let tail = RunStore.tail(job.id, run.stamp)
                Titled(Strings.output) {
                    Text(tail.isEmpty ? Strings.noOutput : tail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(tail.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .padding(28)
        }
    }

    private var status: String {
        let name = Strings.stateName(run)
        guard let end = run.end else { return name }
        return "\(name) · \(Format.duration(end.timeIntervalSince(run.start)))"
    }
}

/// 大きな見出しと、灰色の1行。右にボタンを置く
struct Header<Trailing: View>: View {
    let title: String
    let subtitle: String
    var dot: RunRecord.State? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let dot { StateDot(state: dot) }
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// 見出しを付けた枠
struct Titled<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Card { content }
        }
    }
}

struct OpenButton: View {
    @ObservedObject var model: Model

    var body: some View {
        Button(Strings.openInEditor, action: model.openInEditor)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(Editor.installed == nil)
            .help(Editor.installed == nil ? Strings.noEditor : "")
    }
}

/// 細い線で縁取った角丸の枠
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct StateDot: View {
    let state: RunRecord.State?

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        case .interrupted: .orange
        case nil: .gray.opacity(0.5)
        }
    }
}

/// 窓を1枚だけ持つ
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private let model = Model()

    /// 文字は描くときに読むので、言語を変えたら中身を作り直す
    func reloadLanguage() {
        window?.contentView = NSHostingView(rootView: MainView(model: model))
    }

    /// job を渡すと、そのジョブを選んだ状態で出す
    func show(job: String? = nil) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Owler"
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("Main")
            if !window.setFrameUsingName("Main") { window.center() }
            self.window = window
        }
        model.reload()
        if let job { model.selectedJob = job }
        Dock.show()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
