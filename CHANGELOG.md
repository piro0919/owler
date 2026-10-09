# Changelog

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
