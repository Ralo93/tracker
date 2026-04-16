# WorkLogger

A lightweight macOS menu bar app that tracks your work activity and logs it as JSONL — one file per day. Includes a built-in report export that aggregates logs into a weekly Excel timesheet enriched with git commits.

## Installation

### Prerequisites

1. **Xcode Command Line Tools** (provides Swift compiler and `make`):
   ```sh
   xcode-select --install
   ```

2. **Python 3.10+** with **openpyxl** (required for Export Report):
   ```sh
   # via Homebrew
   brew install python@3.10
   pip3 install openpyxl

   # or via pyenv
   pyenv install 3.10.13
   pip install openpyxl
   ```

### Build the app

```sh
git clone <repo-url> WorkLogger
cd WorkLogger
make app
```

This will:
1. Run the full test suite (Swift + Python — build fails if any test fails)
2. Build a release binary via `swift build -c release`
3. Create `~/Desktop/WorkLogger.app` with a bundled icon, config, and report script
4. Code-sign the app (ad-hoc by default)
5. Reset Accessibility and Screen Recording TCC permissions
6. Print instructions to re-grant permissions

### First launch

1. Open `~/Desktop/WorkLogger.app`
2. macOS will prompt for **Accessibility**, **Screen Recording**, and **Safari Automation** permissions — grant all three
3. **Quit and relaunch** the app (Screen Recording requires a restart)
4. Open **Preferences…** from the menu bar to set your log directory and add git repositories

### Or install as a CLI

```sh
make install
```

Installs the binary to `/usr/local/bin/WorkLogger`.

## Features

### Activity Tracking

- **App switch tracking** — Logs every app you switch to, with window titles (truncated to 200 characters)
- **VS Code project detection** — Extracts the project name from the VS Code window title; detects project switches within VS Code
- **Safari tab & URL tracking** — Logs the current tab name and URL on switch, and monitors tab changes while Safari is active
- **Window titles for all apps** — Captures the focused window title for any app (e.g. document name in Word, sheet in Excel)
- **Idle detection** — Logs `idle_start` / `idle_end` events when no keyboard or mouse activity for a configurable threshold
- **Screen lock/unlock & sleep/wake** — Logs when you lock/unlock the screen or the system sleeps/wakes
- **Quick Manual Entry** (`Cmd+Shift+L`) — System-wide hotkey (Carbon `RegisterEventHotKey`) that opens a floating entry window from any app; logs a manual task with description, time, and duration
- **Export Report** (`Cmd+E`) — Generates a styled `.xlsx` report for the current week directly from the menu bar, with a save dialog
- **Start at Login** — Toggle from the menu bar to auto-launch on login (via LaunchAgent)
- **Preferences GUI** — Four-tab window to configure log directory, git repositories, prefilled meeting slots, and advanced settings (idle threshold, block minutes, skip lists)
- **JSONL output** — One `YYYY-MM-DD.jsonl` file per day, easy to parse and analyze

### Weekly Report

- Splits raw events into work slots bounded by gaps, idle periods, sleep, and screen locks
- Aggregates per-slot: app time (≥5 min), VS Code project time (≥5 min), Teams windows, Safari tabs
- Teams windows with `Kompakte Besprechungsansicht` are labeled `Meeting:`, others as `Teams:`
- Fetches git commits for every configured repository and attaches them to the nearest slot (labeled `COMMIT [repo]:`)
- Three-tier slot placement:
  - **Tier 0 — Prefilled meetings** (immovable, from config)
  - **Tier 1 — Manual entries** (labeled `MANUAL:`, placed at requested time, bumped past meetings if needed)
  - **Tier 2 — Auto-detected slots** (clipped around tiers 0 and 1, never pushed to future times; overlapping activity descriptions are merged into manual entries)
- Noise filtering: configurable skip lists for apps, Safari tab titles (exact and substring match), plus `Just a moment...` filtered by default
- Outputs a styled `.xlsx` file: blue header, alternating row fills, wrapped text, frozen header row

## Configuration

Configuration is stored at `~/Library/Application Support/WorkLogger/config.json`. On first launch, the bundled `config.json` is copied there with all `/Users/<bundled-user>/` paths automatically rewritten to the current user's home directory.

You can edit this file directly or use the Preferences window in the app.

```json
{
  "logDirectory": "/Users/you/Documents/WorkLogger/logs",
  "idleThresholdSeconds": 300,
  "report": {
    "repositories": [
      "/Users/you/repositories/MyProject"
    ],
    "gapMinutes": 10,
    "minSlotMinutes": 5,
    "blockMinutes": 15,
    "skipApps": ["Code", "Finder", "loginwindow", "WorkLogger", "Terminal"],
    "skipSafariExact": ["favorites://", "Start Page", "Just a moment..."],
    "skipSafariContains": ["access_token=", "?code="],
    "prefilledSlots": {
      "Monday": [],
      "Tuesday": ["09:00-09:15", "09:15-10:00"],
      "Wednesday": ["09:00-09:15", "13:30-14:00", "15:00-16:00"],
      "Thursday": ["09:00-09:15"],
      "Friday": ["09:00-09:15"]
    }
  }
}
```

### App keys

| Key | Default | Description |
|-----|---------|-------------|
| `logDirectory` | `~/Documents/WorkLogger/logs` | Where JSONL log files are written |
| `idleThresholdSeconds` | `300` | Seconds of inactivity before `idle_start` |
| `defaultDurationMinutes` | `60` | Default duration pre-filled in Quick Log entry |

### Report keys (`report` section)

| Key | Description |
|-----|-------------|
| `repositories` | List of git repo paths to pull commits from |
| `gapMinutes` | Gap between events that splits a slot (default 10) |
| `minSlotMinutes` | Slots shorter than this are discarded (default 5) |
| `blockMinutes` | Grid size for rounding slot start/end times (default 15) |
| `skipApps` | App names excluded from the description |
| `skipSafariExact` | Safari tab titles excluded exactly |
| `skipSafariContains` | Safari tab titles excluded if they contain these strings |
| `prefilledSlots` | Per-weekday list of immovable meeting ranges (`"HH:MM-HH:MM"`) |

## Permissions

On first launch, macOS will prompt for:

1. **Accessibility** — Required for reading VS Code window titles and the global `Cmd+Shift+L` hotkey
2. **Screen Recording** — Required for reading window titles of all apps via CGWindowList
3. **Automation (Safari)** — Required for reading Safari tab names and URLs

Grant all three, then **quit and relaunch** (Screen Recording requires a restart).

> `make app` automatically resets Accessibility and Screen Recording permissions so they can be re-granted cleanly after every rebuild.

## Menu Bar

The app shows **WL** in the menu bar with these options:

- **Quick Log Entry…** (`Cmd+Shift+L`) — Open the manual entry panel
- **Export Report…** (`Cmd+E`) — Generate a weekly `.xlsx` report with a save dialog
- **Preferences…** (`Cmd+,`) — Configure log directory, repositories, and prefilled meeting slots
- **Start at Login** — Toggle auto-launch on login
- **Quit** (`Cmd+Q`) — Stop WorkLogger

## Quick Manual Entry

Press **`Cmd+Shift+L`** from any app to open the entry panel. It has two tabs:

### Today

- **Description** — What you worked on
- **Time** — Start time (defaults to now, `HH:MM`)
- **Duration** — Minutes spent (default from config, fallback 60)

The entry is logged as a `manual_entry` event in today's JSONL file.

### Retroactive

Add an entry to a past day's log file:

- **Description** — What you worked on
- **Date** — Date picker (defaults to yesterday)
- **Time** — Start time (`HH:MM`, defaults to 09:00)
- **Duration** — Minutes spent

The entry is written to the selected date's JSONL file with the correct timestamp, so it appears in that day's report.

## Preferences

The Preferences window has four tabs:

- **General** — Set the log directory (with Browse button), data retention period, and Safari privacy toggles (tracking enabled, URL logging, domain-only mode)
- **Repositories** — Add/remove git repositories scanned for commits during report generation
- **Prefilled Slots** — Add/remove immovable meeting time ranges per weekday
- **Advanced** — Configure default quick entry duration, block minutes, idle threshold, and skip lists (apps, Safari exact titles, Safari substring matches)

Changes are saved to `~/Library/Application Support/WorkLogger/config.json` and take effect immediately.

## Event Types

| Event | Fields | Description |
|-------|--------|-------------|
| `started` | `config_path` | App launched |
| `permissions` | `screen_recording` | Permission status at startup |
| `app_switch` | `app`, `bundle_id`, `detail`, `url` (Safari only) | Switched to a different app |
| `safari_tab_change` | `detail`, `url` | Changed tabs within Safari |
| `vscode_project_change` | `detail` | Switched VS Code windows/projects |
| `idle_start` | `idle_seconds` | No input detected for threshold |
| `idle_end` | `idle_duration_seconds` | User returned from idle |
| `screen_lock` | — | Screen was locked |
| `screen_unlock` | — | Screen was unlocked |
| `system_sleep` | — | System going to sleep |
| `system_wake` | — | System woke up |
| `manual_entry` | `description`, `time`, `duration_minutes` | Manual task logged via quick entry |

All events include a `timestamp` field in ISO 8601 format. All string values are truncated to 200 characters.

## Example Log Output

```jsonl
{"config_path":"/Users/you/Desktop/WorkLogger.app/Contents/Resources/config.json","event":"started","timestamp":"2026-04-15T09:33:38"}
{"event":"permissions","screen_recording":true,"timestamp":"2026-04-15T09:33:38"}
{"app":"Code","bundle_id":"com.microsoft.VSCode","detail":"WorkLogger","event":"app_switch","timestamp":"2026-04-15T09:33:51"}
{"detail":"GPT4Gov-Converter-App","event":"vscode_project_change","timestamp":"2026-04-15T09:34:07"}
{"app":"Safari","bundle_id":"com.apple.Safari","detail":"GitHub","event":"app_switch","timestamp":"2026-04-15T09:35:10","url":"https://github.com"}
{"detail":"Stack Overflow","event":"safari_tab_change","timestamp":"2026-04-15T09:35:15","url":"https://stackoverflow.com"}
{"event":"idle_start","idle_seconds":300,"timestamp":"2026-04-15T09:40:10"}
{"event":"idle_end","idle_duration_seconds":847,"timestamp":"2026-04-15T09:54:17"}
{"event":"screen_lock","timestamp":"2026-04-15T12:00:00"}
{"event":"screen_unlock","timestamp":"2026-04-15T13:00:00"}
{"description":"Sprint Planning Prep","duration_minutes":60,"event":"manual_entry","time":"17:45","timestamp":"2026-04-15T17:45:33"}
```

## Export Report

Use **Export Report…** from the menu bar, or run from the command line:

```sh
# Print current week to terminal
python3 test_report/report.py

# Specific week
python3 test_report/report.py 2026 16

# Write Excel file
python3 test_report/report.py --xlsx

# Write to a specific path
python3 test_report/report.py 2026 16 --out ~/Downloads/report.xlsx
```

The description column for each slot follows this priority order:
1. Manual entries (`MANUAL: …`)
2. Teams calls/meetings (`Meeting:` — chats and channels are aggregated under general Teams app time)
3. Git commit messages (`COMMIT [repo]: …`)
4. VS Code projects (≥5 min)
5. Other apps (≥5 min, noise-filtered)
6. Safari tabs (top 5, noise-filtered)

Manual entries spanning multiple blocks are automatically split: pipe-separated topics in the description are distributed round-robin across blocks for a streamlined sequential layout.

## Development

```sh
# Run directly (uses config.json from repo root)
swift run --disable-sandbox

# Run all tests (required before build)
make test

# Build release .app (runs tests first, then builds)
make app

# Reset permissions only
make reset-permissions

# Clean build artifacts
make clean
```

### Test Suites

Both test suites must pass before the app can be built (`make app` → `make build` → `make test`).

**Swift (67 tests, 14 suites)** — `swift test`
- URL sanitization: `domainOnly`, `stripQuery`, sensitive token removal, IP/unicode/encoded URLs
- `sanitizeURL` integration with config toggles
- String truncation (200 chars): over, under, exact boundary, multi-field, non-string passthrough
- Log directory auto-creation (nested paths for `log()` and `logToDate()`)
- File permissions: `0600` on log files, retroactive entries, persistence across writes
- Auto-purge: retention periods, boundary, non-JSONL preservation, edge cases (zero, negative)
- Config privacy fields: encode/decode, round-trip, nil defaults
- Consent mechanism: default false, persistence, block logic
- Safari tracking toggles: defaults, disable, domain-only toggle
- `logToDate` retroactive entries: correct file, timestamp, truncation
- Privacy-by-default: most private defaults, sensitive data stripped

**Python (39 tests, 6 suites)** — `python3 -m pytest test_report/test_report.py -v`
- Smart aggregation: round-robin distribution, single block no-split, single segment no-split, contiguous block times, whitespace trimming, empty segments, snap-to-grid, real-world description
- Teams filtering: meetings included, chats/channels excluded, mixed, app time preserved, noise-only meetings
- Block helpers: `round_down`/`round_up` with various block sizes and boundaries
- `build_description`: empty agg, commits, VS Code projects, Safari tabs (max 5), manual entries
- `extract_manual_entries`: basic, empty desc, non-manual events, invalid time fallback
- `_fmt` helper: minutes, hours, mixed, zero
