# WorkLogger Report Pipeline

## How to run

```bash
python3 test_report/report.py           # print table for current ISO week
python3 test_report/report.py 2026 16   # specific year + week
python3 test_report/report.py --csv     # also write report_KW16_2026.csv
```

---

## Configuration (`config.json` → `report` section)

All tuneable values live in `config.json`. The app config and report config share the same file.

| Key | Default | Meaning |
|---|---|---|
| `repositories` | `[]` | Absolute paths to git repos to scan for commits |
| `gapMinutes` | `10` | Idle gap (minutes) between events that splits a new slot |
| `minSlotMinutes` | `5` | Slots shorter than this are discarded |
| `blockMinutes` | `30` | Start/end times are rounded to this grid for Excel |
| `skipApps` | see below | Apps excluded from the description (background noise) |
| `skipSafariExact` | see below | Safari tab titles excluded exactly |
| `skipSafariContains` | see below | Safari tab titles excluded if they contain any of these strings |

To add a new repo:
```json
"report": {
  "repositories": [
    "/Users/you/repositories/MyRepo",
    "/Users/you/repositories/AnotherRepo"
  ]
}
```

---

## Pipeline steps

### Step 1 — Load events

Reads all `YYYY-MM-DD.jsonl` files from `logDirectory` for the requested ISO week.
Each line is a JSON object. Every event gets two internal fields added:

- `_date` — the filename date string (`2026-04-15`)
- `_ts`  — a naive local `datetime` parsed from the `timestamp` field

Timestamp formats handled:
- `2026-04-15T11:48:01` — naive local (current app format)
- `2026-04-15T11:48:01Z` — UTC with Z suffix (older app format, converted to local)
- `2026-04-15 12:00:00 +0200` — git log format (converted to local)

Events are sorted by `_ts` before further processing.

---

### Step 2 — Slot detection

A **slot** is a continuous block of activity. Events are grouped into slots by these rules, in order:

| Trigger | Action |
|---|---|
| `started` event (app relaunch) | Close current slot, start new one |
| `system_sleep` / `screen_lock` / `idle_start` | Close current slot |
| `system_wake` / `screen_unlock` / `idle_end` | End break, next event starts a new slot |
| Gap > `gapMinutes` between consecutive events | Close current slot |

`permissions` events are treated as noise and never split a slot.

Slots shorter than `minSlotMinutes` are discarded.

---

### Step 3 — Aggregation per slot

For each slot, the following are measured:

#### App time (`app_sec`)
Each `app_switch` event starts a timer for the new app. The timer for the previous app is closed. Duration = time from `app_switch` to the next event.

#### VS Code project time (`proj_sec`)
Tracked via two signals (whichever fires first wins):
1. `vscode_project_change` events (explicit project switch inside VS Code)
2. The `detail` field of `app_switch` events for `Code` (window title shows current project)

Intervals are accumulated per project name.

#### Teams meetings (`teams`)
Every `app_switch` to Microsoft Teams with a non-empty `detail` field is recorded. The window title format is:
```
Kompakte Besprechungsansicht | MeetingName | Microsoft Teams
```
The middle segment is extracted as the meeting name.

#### Safari tabs (`safari`)
Every `safari_tab_change` event's `detail` (page title) is recorded in order of first appearance. No duplicates. Filtered later in the description step.

---

### Step 4 — Commit fetching

For each calendar day that has log data, **all** commits from all configured repos are fetched — not just during the WorkLogger window. This ensures commits made before WorkLogger started are still captured.

```
git log --after="YYYY-MM-DD 00:00:00" --before="YYYY-MM-DD 23:59:59" --format="%H|%ai|%s" --all
```

---

### Step 5 — Attach commits to slots

Each commit is matched to the slot whose `[t0, t1]` window contains the commit timestamp.
If no slot contains it (e.g. commit made during a break or before WorkLogger started), it goes to the **nearest slot** by midpoint distance.

---

### Step 6 — Build description

Each slot's description is built in priority order:

1. **Teams meetings** — meaningful name extracted from window title
2. **Commits** — prefixed with `COMMIT [repo]:` as a strong signal
3. **VS Code projects** — only those with ≥ 60s, excluded: `Save As`, `unknown`
4. **Other apps** — all apps with ≥ 30s, excluded via `skipApps` config (Finder, Terminal, etc.)
5. **Safari tabs** — top 5 after filtering noise via `skipSafariExact` / `skipSafariContains`

---

### Step 7 — Produce rows

Start/end times are rounded to the `blockMinutes` grid (default 30min).
After rounding, adjacent slots are checked for overlap and clipped so no two rows ever overlap.
Zero-duration rows are dropped.

Output columns: `Wochentag | Datum | Von | Bis | Beschreibung`

---

## Debugging

Run the individual step scripts to inspect the pipeline at each stage:

```bash
python3 test_report/step1_parse.py      # raw events
python3 test_report/step2_slots.py      # slot boundaries
python3 test_report/step3_aggregate.py  # aggregated app/project/teams/safari per slot
python3 test_report/step4_commits.py    # commits matched to slots
```
