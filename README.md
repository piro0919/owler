# Owler

A macOS app that keeps an eye on your scheduled jobs, and opens any run in
Claude Code inside Cursor, VS Code or the Claude desktop app.

Put a few jobs on launchd — a nightly `claude -p` that goes through your inbox,
a script that fetches something every evening — and you soon lose track of how
many there are, when they run, and whether last night's run worked. The output
ends up in log files you never open.

Owler lists the jobs it runs, with the result of every run. Pick a run and
**Open in Claude Code**: Owler brings the job's folder to the front in your
editor and starts a Claude Code conversation that already knows where that run's
transcript and output are. You read what happened, and ask about it, without
leaving the editor.

Claude Code's desktop app has scheduled tasks of its own. Owler is for people
who would rather stay in Cursor or VS Code. Jobs run on launchd, so they fire
whether Owler is open or not.

There is a page for it at [owler.kkweb.io](https://owler.kkweb.io).

macOS 14+. No Xcode needed: `./build.sh` compiles with the Swift that ships with
the Command Line Tools.

## Installing

With Homebrew:

```bash
brew install --cask piro0919/tap/owler
```

Or download the DMG from [Releases](https://github.com/piro0919/owler/releases/latest)
and drag Owler into Applications.

The first launch will be blocked: Owler is signed with a self-signed certificate,
not an Apple Developer ID, so macOS cannot verify who made it. To let it through,
open **System Settings → Privacy & Security**, scroll to the bottom, and click
**Open Anyway** next to the message about Owler. You only do this once.

Grant Accessibility access when Owler asks — it needs it to bring the right
editor window to the front. The first time Owler hands a link to the Claude Code
extension, the editor asks whether the extension may open it.

Updates arrive through Sparkle. Owler looks once at launch and only says
something when there is one.

## Adding a job

Click **+** (New Job). Owler opens a Claude Code conversation in your editor
asking for help to set up a job. Talk it through; when you agree, Claude
registers the job with Owler's command line:

```bash
/Applications/Owler.app/Contents/MacOS/Owler add daily-inbox \
  --folder ~/work/inbox --at 9:00 --weekdays 1-5 \
  --summary "Sort the inbox" -- /bin/zsh ~/work/inbox/run.sh
```

`--name` gives the job a short name for the job list, the menu bar and the title
of its page; the summary then shows under the title. `rename` changes it later.

Run `Owler help` for the rest: `import` takes over a launchd job you already
have, `remove`, `start` (run now), `pause`, `resume`, `rename`, `list`, and
`open` (open the last run in Claude Code).

A job can also run just once: `--on 2026-11-27 --at 12:00` instead of a repeating
schedule. After it runs, Owler takes it out of launchd and lists it under
**Done**, where its runs stay readable until you remove it. If the Mac was asleep
or off and the time passed more than 10 minutes ago, it does not run late by
itself; its page shows "No record" and you decide whether to run it now.

**Pause** on a job's page stops it until you click **Resume**. A paused job is
greyed out in the window and the menu bar, and its scheduled times do not count
as "No record". A job taken out of launchd outside Owler (a plist marked
`Disabled`, or `launchctl bootout`) is shown as paused too, and **Resume** loads
it again.

Jobs live in `~/Library/Application Support/Owler/`. Each one is a launchd agent
labelled `io.kkweb.owler.job.<id>` that calls `Owler run <id>`, which records the
start, end, exit code and output of every run before handing over to your
command.

If a scheduled time passes while the Mac was awake and no run was recorded, a
job's page shows that time as "No record". This catches runs that never started,
for example when macOS stopped Owler before it could write anything. Owler
reads the sleep and wake history from `pmset -g log`, so times when the Mac was
asleep or off are left out.

## How a run is linked to Claude Code

When a job starts `claude -p` in its folder, Owler finds the Claude Code
transcript of that process and links it to the run. Only Claude Code started by
the job itself counts, so two jobs sharing a folder don't pick up each other's
conversations. The window shows
Claude's last message as the run's report, along with what the run cost as
Claude Code counts it. A job's page shows the average per run and what that
comes to over a month on its schedule. On a run's page, the arrow buttons
next to the title, or the ↑ and ↓ keys, step to the newer or older run.

The Claude Code extension does not reopen sessions created by `claude -p`, so
**Open in Claude Code** starts a new conversation and puts the transcript and
log paths in its first message. The message is not sent; you read it, edit it if
you like, and send it.

**Open Claude Code In** in Settings picks where that conversation opens: Cursor,
VS Code, or the Claude desktop app, among the ones installed. With the desktop
app, the conversation opens in its Code tab with the job's folder; the app
shows its folder list so you can check the folder before you send.

## Menu bar

Owler also sits in the menu bar, listing each job with the result of its last
run and when it runs next, in the order the jobs run next. A number next to the owl
counts the jobs whose last run failed, or whose last scheduled time has no
record. A failed run drops out of the count once you open it. Turn it off
in the settings (the gear at the bottom of the job list, or ⌘,) if you only want
the window.

Some jobs are there for you to read, such as a morning digest written by
`claude -p`. Add them with `--review`, and after each successful run a dot
appears next to the owl until you open that run. A newer run doesn't clear it,
but opening one run also clears the older ones, so a few missed days take one
click. Jobs with an unread run are listed together at the top of the menu, and
clicking one takes you to its newest unread run. It makes no sound and shows no
notification; it only tells you something is waiting.

A job can also ask for the dot on a single run. Owler passes a file path in
`OWLER_REVIEW_FILE`; write anything to it, and if the run succeeds, it gets the
dot, with or without `--review`. What the job wrote shows next to that run in
the job's page, so you can tell which run to open. A job that only needs you now
and then can stay quiet the rest of the time. Add it with
`--review-when "<when>"` so its page in the window says when to expect it; if
the job writes only a mark such as `1`, the run's row shows that sentence.

Opening a run also clears the dots of the job's older runs. If each run asks
about something different, such as drafts of replies for you to approve, add
`--review-each`, and each run that asked keeps its dot until you open it.

## Building

```bash
./build.sh
./Owler.app/Contents/MacOS/Owler --selftest
open ./Owler.app
```

## License

MIT
