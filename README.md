# WorkLogger

A lightweight macOS menu-bar app that silently tracks your work activity and generates weekly Excel timesheets — enriched with git commits, meetings, and browser tabs.

<img src="assets/imgv4.png" width="880" alt="Report Output">

## Install

```sh
# Prerequisites
xcode-select --install
pip3 install openpyxl

# Build & install
git clone https://github.com/Ralo93/tracker.git WorkLogger
cd WorkLogger
make app
```

On first launch grant **Accessibility**, **Screen Recording**, and **Safari Automation**, then relaunch.

## Features

- Automatic app & window tracking (VS Code project detection, Safari tabs & URLs)
- Teams meeting detection (`Kompakte Besprechungsansicht`)
- Git commit aggregation from configured repositories
- Idle / screen-lock / sleep detection for accurate work-time boundaries
- Quick manual entry from any app
- Weekly `.xlsx` report with grouped bullet-point descriptions
- Prefilled meeting slots (immovable tier-0 rows)
- Configurable noise filters, block grid, retention, and Safari privacy controls
- 113 automated tests gate every build
- Configurable via Preferences GUI (4 tabs)

## Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+L` | Quick manual log entry (from any app) |
| `Cmd+E` | Export weekly report (.xlsx) |
| `Cmd+,` | Preferences |
| `Cmd+Q` | Quit |

### Menu Bar

<img src="assets/menu.png" width="491" alt="Menu">

### Quick Log (`Cmd+Shift+L`)

<img src="assets/quicklog.png" width="589" alt="Quick Log">

### Preferences (`Cmd+,`)

<img src="assets/preferences.png" width="624" alt="Preferences">

## Example Logs

Each day produces a `YYYY-MM-DD.jsonl` file:

```jsonl
{"app":"Code","bundle_id":"com.microsoft.VSCode","detail":"WorkLogger","event":"app_switch","timestamp":"2026-04-15T09:33:51"}
{"detail":"GPT4Gov-Converter-App","event":"vscode_project_change","timestamp":"2026-04-15T09:34:07"}
{"app":"Safari","bundle_id":"com.apple.Safari","detail":"GitHub","event":"app_switch","timestamp":"2026-04-15T09:35:10","url":"https://github.com"}
{"event":"idle_start","idle_seconds":300,"timestamp":"2026-04-15T09:40:10"}
{"event":"idle_end","idle_duration_seconds":847,"timestamp":"2026-04-15T09:54:17"}
{"event":"screen_lock","timestamp":"2026-04-15T12:00:00"}
{"event":"screen_unlock","timestamp":"2026-04-15T13:00:00"}
{"description":"Sprint Planning Prep","duration_minutes":60,"event":"manual_entry","time":"17:45","timestamp":"2026-04-15T17:45:33"}
```


