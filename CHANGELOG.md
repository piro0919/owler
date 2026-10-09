# Changelog

## [0.1.1]

- Jobs no longer inherit Owler's Accessibility access. A job's commands used to be able to control other apps once Owler had been granted Accessibility; they are now started detached from Owler's permissions
- Open in Claude Code no longer waits 10 seconds when Accessibility access has not been granted

## [0.1.0]

- First release
- Lists jobs registered with Owler and records every run: start, end, exit code and output
- Links runs that start `claude -p` to their Claude Code transcript, and shows Claude's last message as the report
- Open in Claude Code: brings the job's folder to the front in Cursor or VS Code and starts a conversation that points at the run's transcript and output
- Command line for registering jobs (`add`, `import`, `remove`, `start`, `list`, `open`)
- Menu bar item with the last result of each job, which can be turned off in Settings
