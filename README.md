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
transcript written during the run and links it to the run. The window shows
Claude's last message as the run's report.

The Claude Code extension does not reopen sessions created by `claude -p`, so
**Open in Claude Code** starts a new conversation and puts the transcript and
log paths in its first message. The message is not sent; you read it, edit it if
you like, and send it.

## Menu bar

Owler also sits in the menu bar, listing each job with the result of its last
run. A number next to the owl counts the jobs whose last run failed. Turn it off
in **Settings…** if you only want the window.

## Building

```bash
./build.sh
./Owler.app/Contents/MacOS/Owler --selftest
open ./Owler.app
```

## License

MIT
