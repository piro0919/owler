# Changelog

## [Unreleased]

- A run you haven't opened keeps its dot even after newer runs come in, or a newer run fails. Before, only the latest run counted, so the dot could disappear before you saw it
- For jobs added with `--review`, opening a run also clears the older unread runs, since a newer report replaces them. Runs a job asked you to read through `OWLER_REVIEW_FILE` still each wait for you
- Picking a job in the window no longer counts as reading it. The dot goes away when you open the run itself, or open the job in Claude Code
- Clicking a job in the menu bar opens its newest unread run directly
- Unread runs are shown in bold in the window's list of runs
- Adding `--review` to an existing job no longer marks all its past runs as unread

## [0.1.7]

- A job can now ask you to come and read a single run. Owler passes a file path in `OWLER_REVIEW_FILE`, and if the job writes anything to it, that run gets the dot in the menu bar when it succeeds
- This works for any job, with or without `--review`. Jobs added with `--review` still get the dot after every successful run

## [0.1.6]

- Jobs can now ask you to come and read their results. Add a job with `--review`, and after each successful run a dot appears next to the owl in the menu bar
- The dot stays until you open that run from the menu bar, the window, or Claude Code. It makes no sound and shows no notification
- In the menu, such a job says "New" before its next run, and its name is shown in bold in the window

## [0.1.5]

- The menu bar now shows when each job runs next, such as "Next Tomorrow 9:00". Today and tomorrow are written as words, later days as dates
- A successful last run is no longer written out, since the dot already shows it. Failed, interrupted and running jobs still say so before the next run
- If a job missed its last scheduled run, for example because the Mac was asleep, the menu shows when it last ran so the gap is easy to spot

## [0.1.4]

- The update window now follows the Mac's language, so it appears in Japanese on a Japanese Mac. It was always in English before. The release notes themselves are still in English

## [0.1.3]

- When the menu bar item is shown, closing every window now removes Owler from the Dock. It comes back to the Dock when a window is opened again

## [0.1.2]

- The menu bar shows a spinning ring and a count while jobs are running, the same way Hawky shows working sessions. It stops when nothing is running, and stays still when Reduce Motion is on
- Jobs whose last run failed are now counted next to a "!" mark. When both are present, they are stacked in two rows, with the running row drawn darker so the ring stays readable at menu bar size

## [0.1.1]

- Jobs no longer inherit Owler's permissions. Once Owler had been granted Accessibility (or any other privacy permission), a job's commands could use it too, for example to control other apps. They now run with only the permissions they would have on launchd by themselves
- Open in Claude Code no longer waits 10 seconds when Accessibility access has not been granted

## [0.1.0]

- First release
- Lists jobs registered with Owler and records every run: start, end, exit code and output
- Links runs that start `claude -p` to their Claude Code transcript, and shows Claude's last message as the report
- Open in Claude Code: brings the job's folder to the front in Cursor or VS Code and starts a conversation that points at the run's transcript and output
- Command line for registering jobs (`add`, `import`, `remove`, `start`, `list`, `open`)
- Menu bar item with the last result of each job, which can be turned off in Settings
