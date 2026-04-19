# Respect

A macOS SwiftUI app that helps enforce work time boundaries. Built with Swift Package Manager.

## Architecture

- **Package.swift** — SPM manifest, targets macOS 13+
- **Sources/Respect/RespectApp.swift** — App entry point, AppDelegate (lock window management, screen unlock/user switch detection)
- **Sources/Respect/SessionManager.swift** — State machine, timers, Claude API calls, spacebar monitor, sleep prevention
- **Sources/Respect/SpeechService.swift** — Hold-spacebar-to-talk using SFSpeechRecognizer + AVAudioEngine
- **Sources/Respect/Views.swift** — All SwiftUI views (chat, working, lock screen, API key input)
- **Scripts/build.sh** — Builds, creates .app bundle, code signs with developer cert
- **Scripts/install.sh** — Builds, copies to /Applications, sets up LaunchAgent

## Build & Run

```bash
bash Scripts/build.sh        # Build Respect.app in project root
open Respect.app             # Run locally

bash Scripts/install.sh      # Install to /Applications + LaunchAgent
```

## Logging

- Uses `os.Logger` (subsystem `com.respect.timer`) for system console logs
- Also writes to `~/.config/respect/respect.log` with timestamps for easy sharing
- `log` (Logger) and `logToFile()` are defined in SessionManager.swift and available project-wide
- Key events logged: state transitions, lock/unlock, window management, API calls, errors
- To read logs: `cat ~/.config/respect/respect.log`
- To tail live: `tail -f ~/.config/respect/respect.log`
- To clear: `rm ~/.config/respect/respect.log`

## Key Details

- API key stored at `~/.config/respect/api_key` (not in repo)
- Code signed with "Apple Development: Chris Grim (BWCAXMSGPQ)"
- LaunchAgent at `~/Library/LaunchAgents/com.respect.timer.plist`
- Bundle ID: `com.respect.timer`
- Uses Claude Sonnet API for natural language time parsing
- Uses private `SACLockScreenImmediate` API to lock the Mac screen
- Screen sleep is prevented via IOPMAssertion during active work sessions
