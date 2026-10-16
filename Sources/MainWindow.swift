import AppKit
import SwiftUI

/// 窓に出すものを集める。ファイルを見張らず、数秒ごとに読み直す
@MainActor
final class Model: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var lastRuns: [String: RunRecord] = [:]
    /// まだ見に来ていない回のあるジョブ
    @Published var unseenJobs: Set<String> = []
    @Published var runs: [RunRecord] = []
    /// 選んだジョブの、予定の時刻に記録の無い回。新しい順
    @Published var missed: [Date] = []
    /// 最後の回より後に、記録の無い予定があるジョブ。一覧の丸を白抜きにする
    @Published var missedJobs: Set<String> = []
    /// 切り替えたらその場で読み直す。3秒ごとの読み直しを待つと、前のジョブの一覧が残って見える
    @Published var selectedJob: String? {
        didSet {
            guard selectedJob != oldValue else { return }
            if selectedJob != nil { showsSettings = false }
            openedRunID = nil
            loadRuns()
        }
    }
    /// 右側に設定のページを出しているか。出すときはジョブの選択を外す。一覧の選択と右側が食い違わないように
    @Published var showsSettings = false
    /// 開いている回。nil ならジョブのページ
    @Published var openedRunID: String? {
        didSet { if openedRunID != nil { markSeen() } }
    }
    /// 実行中の回があるあいだ、読み直すたびに進める。回のページの出力を描き直させる
    @Published private(set) var tick = 0
    /// 終わった回の報告。記録は数 MB になるので、描くたびに読まない
    private var reports: [String: String?] = [:]
    /// 終わった回の料金。報告と同じく一度読んだら覚えておく
    private var costs: [String: Double?] = [:]

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
        let unseen = Set(jobs.filter { !RunStore.unseen($0).isEmpty }.map(\.id))
        if unseen != unseenJobs { unseenJobs = unseen }
        let missed = Set(
            jobs.filter { !RunStore.missed($0, runs: last[$0.id].map { [$0] } ?? [], limit: 1).isEmpty }.map(\.id))
        if missed != missedJobs { missedJobs = missed }
        loadRuns()
    }

    private func loadRuns() {
        let runs = selectedJob.map { RunStore.all($0) } ?? []
        if runs != self.runs { self.runs = runs }
        let missed = job.map { RunStore.missed($0, runs: runs, limit: RunStore.listed) } ?? []
        if missed != self.missed { self.missed = missed }
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

    /// その回の料金。Claude Code の会話が紐づいていなければ nil
    func cost(job: Job, run: RunRecord) -> Double? {
        guard let session = run.session, run.end != nil else { return nil }
        if let cached = costs[session] { return cached }
        let cost = Sessions.cost(in: Sessions.transcript(folder: Paths.expand(job.folder), session: session))
        costs[session] = cost
        return cost
    }

    /// 1回あたりの料金と月の見込み。表に出している回のうち、終わった回で数える
    func costEstimate(job: Job) -> Job.CostEstimate? {
        job.costEstimate(runs.filter { $0.end != nil }.map { cost(job: job, run: $0) })
    }

    /// 見に来てほしいジョブの、開いた回を見たことにする。ジョブのページでは最新の回。
    /// ジョブを選んだだけでは見たことにしない。ジョブのページには報告が出ないので、読まずに印が消える
    func markSeen() {
        guard let job, let run, !job.seenByOpening(run, among: runs).isEmpty else { return }
        RunStore.markSeen(job, opening: run)
        reload()
    }

    /// 開いている回の隣の回。runs は新しい順なので、-1 が新しい回、+1 が古い回。端なら nil
    func adjacentRun(_ offset: Int) -> RunRecord? {
        guard let index = runs.firstIndex(where: { $0.id == openedRunID }), runs.indices.contains(index + offset)
        else { return nil }
        return runs[index + offset]
    }

    func openAdjacentRun(_ offset: Int) {
        if let run = adjacentRun(offset) { openedRunID = run.id }
    }

    func runNow(_ id: String) {
        Launchctl.kickstart(Paths.label(id))
        // 記録は Owler run が書く。少し待ってから読み直す
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.reload() }
    }

    func openInEditor() {
        guard let job else { return }
        markSeen()
        Editor.installed?.open(job: job, run: run)
    }

    func openSettings() {
        selectedJob = nil
        showsSettings = true
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
                    StateDot(state: model.lastRuns[job.id]?.state, missed: model.missedJobs.contains(job.id))
                    Text(job.displayName).lineLimit(1)
                        .fontWeight(model.unseenJobs.contains(job.id) ? .bold : nil)
                }
                .padding(.vertical, 4)
                .padding(.leading, 6)
                .contextMenu {
                    Button(Strings.runNow) { model.runNow(job.id) }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 290, max: 360)
            // 開閉のボタンを外すと、列の幅の指定だけでは細く畳まれる。一覧にも幅を持たせる
            .frame(minWidth: 280)
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
                    // 設定は本体の窓の中に出す。別の窓だった頃は、窓が2枚あって邪魔だと言われた
                    Button(action: model.openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.showsSettings ? .primary : .secondary)
                    .help(Strings.settingsTitle)
                    .accessibilityLabel(Strings.settingsTitle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                if model.showsSettings {
                    SettingsPage()
                } else if let job = model.job {
                    if let run = model.openedRun {
                        RunPage(model: model, job: job, run: run)
                    } else {
                        JobPage(model: model, job: job)
                    }
                } else {
                    // ジョブを選んでいないときは何も出さない。「定期実行を選んでください」は要らないと言われた（2026-10-14）。
                    // 中身が空だと下の背景や題が効かないので、透明な色を置く
                    Color.clear
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
                Header(title: job.displayName, details: details) {
                    OpenButton(model: model)
                }
                Card {
                    if rows.isEmpty {
                        Text(Strings.noRuns)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Divider() }
                                switch row {
                                case .run(let run):
                                    RunRow(run: run, unseen: job.awaitsReview(run)) { model.openedRunID = run.id }
                                case .missed(let fire):
                                    MissedRow(fire: fire)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    /// 実行の表の行。記録の無い予定の回を、その時刻の位置に差す
    private enum Row: Identifiable {
        case run(RunRecord)
        case missed(Date)

        var id: String {
            switch self {
            case .run(let run): run.id
            case .missed(let fire): "missed-\(fire.timeIntervalSince1970)"
            }
        }

        var time: Date {
            switch self {
            case .run(let run): run.start
            case .missed(let fire): fire
            }
        }
    }

    private var rows: [Row] {
        (model.runs.map(Row.run) + model.missed.map(Row.missed)).sorted { $0.time > $1.time }
    }

    /// 見出しの下の項目。予定・次回・料金を「·」で1行につないでいた頃は、折り返して「月 約 $14」が割れ、
    /// ごちゃついて見えると言われた（2026-10-14）。項目名を左に揃え、1項目1行にした
    private var details: [(String, String)] {
        var rows = [(Strings.scheduleLabel, job.scheduleText)]
        if let next = job.nextFire() { rows.append((Strings.nextLabel, Format.dateTime(next))) }
        // 記録は100回で消えるので、頻繁なジョブでは月の合計を数えられない。1回の平均と予定の回数から見込む
        if let cost = model.costEstimate(job: job) {
            rows.append((Strings.costLabel, Strings.costPerRun(cost.perRun, month: cost.month)))
        }
        rows.append((Strings.unseenLabel, Strings.reviewCondition(job)))
        return rows
    }
}

/// 実行の表の1行。日時と状態だけ。押すとその回のページへ
struct RunRow: View {
    let run: RunRecord
    /// まだ見に来ていない回は日時を太字にする。一覧の名前と同じ
    var unseen = false
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(Format.dateTime(run.start)).monospacedDigit()
                    .fontWeight(unseen ? .bold : nil)
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

/// 予定の時刻に記録の無い回の行。開く中身が無いので押せない。原因（殺された・登録が外れていた）は
/// Owler には分からないので、起きたことだけを書く
struct MissedRow: View {
    let fire: Date

    var body: some View {
        HStack(spacing: 12) {
            Text(Format.dateTime(fire)).monospacedDigit()
            Spacer()
            StateDot(state: nil, missed: true)
            Text(Strings.missed).foregroundStyle(.secondary)
            // 押せる行と文言の位置を揃える
            Image(systemName: "chevron.right").font(.caption).hidden()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
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
                    HStack(spacing: 8) {
                        RunStepper(model: model)
                        OpenButton(model: model)
                    }
                }

                if let reply = model.report(job: job, run: run) {
                    Titled(Strings.report) {
                        MarkdownView(reply).padding(16)
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
        let cost = model.cost(job: job, run: run).map(Strings.cost)
        return [name, Format.duration(end.timeIntervalSince(run.start)), cost].compactMap { $0 }.joined(
            separator: " · ")
    }
}

/// 大きな見出しと、灰色の1行。右にボタンを置く
struct Header<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    /// 項目名つきの行。ジョブのページで、予定・次回・料金・未読にするときを並べる
    var details: [(String, String)] = []
    var dot: RunRecord.State? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    HStack(spacing: 6) {
                        if let dot { StateDot(state: dot) }
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                }
                if !details.isEmpty {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(details, id: \.0) { label, value in
                            GridRow {
                                Text(label).foregroundStyle(.tertiary)
                                Text(value).foregroundStyle(.secondary)
                            }
                        }
                    }
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

/// 回のページで前後の回へ移る。並びは実行の表と同じで、∧ が新しい回、∨ が古い回。
/// 毎回一覧に戻らないと隣の回を見られず不便だと言われた（2026-10-14）。↑↓ のキーでも移れる
struct RunStepper: View {
    @ObservedObject var model: Model

    var body: some View {
        HStack(spacing: 4) {
            step("chevron.up", -1, .upArrow, Strings.newerRun)
            step("chevron.down", 1, .downArrow, Strings.olderRun)
        }
        .controlSize(.large)
    }

    private func step(_ symbol: String, _ offset: Int, _ key: KeyEquivalent, _ label: String) -> some View {
        Button {
            model.openAdjacentRun(offset)
        } label: {
            Image(systemName: symbol).frame(width: 14)
        }
        .keyboardShortcut(key, modifiers: [])
        .disabled(model.adjacentRun(offset) == nil)
        .help(label)
        .accessibilityLabel(label)
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
    /// 予定の時刻に記録が無い。灰の白抜きにする
    var missed = false

    var body: some View {
        if missed {
            Circle().strokeBorder(Color.gray, lineWidth: 1.5).frame(width: 8, height: 8)
        } else {
            Circle().fill(color).frame(width: 8, height: 8)
        }
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

    /// job を渡すと、そのジョブを選んだ状態で出す。settings なら設定のページを出す
    func show(job: String? = nil, settings: Bool = false) {
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
        if settings { model.openSettings() }
        if let job {
            model.selectedJob = job
            // メニューバーから開いたとき、まだ見に来ていない回があれば、いちばん新しいその回を開く（開けば見たことになる）
            if let definition = model.job, let run = RunStore.unseen(definition).first {
                model.openedRunID = run.id
            }
        }
        Dock.show()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
