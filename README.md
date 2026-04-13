# Respect

A macOS menu bar app that helps you set work time boundaries. When you log in or unlock your Mac, Respect asks how long you're working — then holds you to it.

## How It Works

1. **Login/unlock** — Full-screen prompt asks how long you're working
2. **Set your time** — Type or hold spacebar to dictate (e.g. "2 hours", "until 10:30 PM")
3. **Work** — App hides, keeps your screen awake, shows a countdown in the menu bar
4. **10-min warning** — Notification pops up, menu bar switches to a live countdown
5. **Time's up** — Lock screen overlay with a 2-minute countdown
6. **Done** — Mac locks automatically

You can unlock early to set a new timer, or hit "Lock Out Now" to end immediately.

## Features

- Natural language time parsing via Claude API
- Hold-spacebar voice input (like Claude Code)
- Airbnb-inspired UI
- Menu bar countdown in the final 10 minutes
- Prevents screen sleep during work sessions
- Covers all monitors when locked
- Starts automatically on login via LaunchAgent
- No Dock icon — lives in the menu bar

## Requirements

- macOS 13+
- [Anthropic API key](https://console.anthropic.com/settings/keys)

## Install

```bash
git clone https://github.com/chrisgrim/respect.git
cd respect
bash Scripts/install.sh
```

This builds the app, copies it to `/Applications`, and sets up a LaunchAgent so it starts on every login. You'll be prompted for your API key on first launch.

## Build Only

```bash
bash Scripts/build.sh
open Respect.app
```

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.respect.timer.plist
rm ~/Library/LaunchAgents/com.respect.timer.plist
rm -rf /Applications/Respect.app
```

## Built With

- SwiftUI + AppKit
- Claude Sonnet API
- Apple Speech framework
- Built entirely with [Claude Code](https://claude.ai/claude-code)
