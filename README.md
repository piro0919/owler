# Owler

A macOS app that keeps an eye on your scheduled jobs, and opens any run in
Claude Code inside Cursor or VS Code.

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

Run `Owler help` for the rest: `import` takes over a launchd job you already
have, `remove`, `start` (run now), `list`, and `open` (open the last run in
Claude Code).

Jobs live in `~/Library/Application Support/Owler/`. Each one is a launchd agent
labelled `io.kkweb.owler.job.<id>` that calls `Owler run <id>`, which records the
start, end, exit code and output of every run before handing over to your
command.

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

## Menu bar

Owler also sits in the menu bar, listing each job with the result of its last
run and when it runs next, in the order the jobs run next. A number next to the owl
counts the jobs whose last run failed. Turn it off
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
dot, with or without `--review`. Each of these runs keeps its dot until you
open that run itself. A job that only needs you now and then, such as
one that drafts replies for you to approve, can stay quiet the rest of the time.
Add it with `--review-when "<when>"` so its page in the window says when to
expect it.

## Building

```bash
./build.sh
./Owler.app/Contents/MacOS/Owler --selftest
open ./Owler.app
```

## License

MIT
