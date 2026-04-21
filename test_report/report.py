#!/usr/bin/env python3
"""
WorkLogger weekly report generator.

Pipeline:
  1. Load all JSONL events for the week
  2. Split into work slots (idle/sleep/lock/gap boundaries)
  3. Aggregate app + project time per slot
  4. Fetch ALL git commits for each calendar day (full day, not just WorkLogger window)
  5. Attach commits to slots by timestamp proximity
  6. Output CSV rows: Weekday | Date | Start | End | Description

Usage:
  python3 test_report/report.py              # current ISO week
  python3 test_report/report.py 2026 16      # specific year + week number
  python3 test_report/report.py --csv        # write report.xlsx instead of printing
"""

import json, subprocess, sys
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── Load config ───────────────────────────────────────────────────────────────

def _find_config() -> Path:
    candidates = [
        # User config written by the app's Settings (highest priority)
        Path.home() / "Library/Application Support/WorkLogger/config.json",
        # Repo root (dev workflow)
        Path(__file__).parent.parent / "config.json",
        # App bundle fallback
        Path.home() / "Desktop/WorkLogger.app/Contents/Resources/config.json",
    ]
    for p in candidates:
        if p.exists():
            return p
    raise FileNotFoundError("config.json not found")

_cfg     = json.loads(_find_config().read_text())
_rep     = _cfg.get("report", {})

LOG_DIR          = Path(_cfg["logDirectory"])
REPOS            = [Path(p) for p in _rep.get("repositories", [])]
GAP_MINUTES      = _rep.get("gapMinutes",      10)
MIN_SLOT_MINUTES = _rep.get("minSlotMinutes",    5)
BLOCK_MINUTES    = _rep.get("blockMinutes",     30)
SKIP_APPS        = {
    "Code", "Finder", "loginwindow", "universalAccessAuthWarn",
    "UserNotificationCenter", "WorkLogger", "Terminal",
    "Safari", "Microsoft Teams",
} | set(_rep.get("skipApps", []))
# Hardcoded noise that is always filtered regardless of user config
_BUILTIN_SAFARI_EXACT = {
    "favorites://", "Personal Desktop", "Start Page", "502 Bad Gateway", "Untitled",
    "Just a moment...", "Failed to open page", "reading-list://",
}
_BUILTIN_SAFARI_CONTAINS = {
    "#code=", "spa-signin-oidc", "access_token=", "?code=", "session_state=",
    "#loginHint=", "windows.cloud.microsoft", "Sign in to your account", "Windows App",
    "_MsalRedirect", "/_msal/", "vssps.visualstudio.com",
}
SKIP_SAFARI_EXACT    = _BUILTIN_SAFARI_EXACT | set(_rep.get("skipSafariExact", []))
SKIP_SAFARI_CONTAINS = _BUILTIN_SAFARI_CONTAINS | set(_rep.get("skipSafariContains", []))
SHOW_SAFARI_TIME = _cfg.get("showSafariTimeInReport", False)

# Planned meeting slots per weekday: list of (start_time, end_time, description)
_raw_prefilled = _rep.get("prefilledSlots", {})
PREFILLED_SLOTS: dict[str, list[tuple[str, str, str]]] = {}
for _dow, _ranges in _raw_prefilled.items():
    if _dow == "comment":
        continue
    parsed = []
    for _r in _ranges:
        if isinstance(_r, dict):
            _time = _r.get("time", "")
            _desc = _r.get("description", "")
        else:
            _time = _r
            _desc = ""
        _s, _e = _time.split("-")
        parsed.append((_s.strip(), _e.strip(), _desc))
    PREFILLED_SLOTS[_dow] = parsed

BREAK_START = {"system_sleep", "screen_lock", "idle_start"}
BREAK_END   = {"system_wake",  "screen_unlock", "idle_end"}
NOISE       = {"permissions"}

# ── Timestamp parsing ─────────────────────────────────────────────────────────

def parse_ts(s: str) -> datetime:
    """Parse timestamps from any format WorkLogger emits, return naive local time."""
    s = s.strip()
    if s.endswith("Z"):
        dt = datetime.fromisoformat(s[:-1]).replace(tzinfo=timezone.utc)
        return dt.astimezone().replace(tzinfo=None)
    # git: "2026-04-15 12:00:00 +0200"  (space, no colon in offset)
    if " " in s and (s[-5] in "+-") and (":" not in s[-5:]):
        s = s[:-2] + ":" + s[-2:]
    s = s.replace(" ", "T", 1)
    dt = datetime.fromisoformat(s)
    if dt.tzinfo:
        dt = dt.astimezone().replace(tzinfo=None)
    return dt

# ── Load events ───────────────────────────────────────────────────────────────

def load_week(year: int, week: int) -> list[dict]:
    events = []
    for path in sorted(LOG_DIR.glob("*.jsonl")):
        try:
            date = datetime.strptime(path.stem, "%Y-%m-%d").date()
        except ValueError:
            continue
        if date.isocalendar()[:2] == (year, week):
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        ev = json.loads(line)
                        ev["_date"] = path.stem
                        ev["_ts"]   = parse_ts(ev["timestamp"])
                        events.append(ev)
                    except Exception:
                        pass
    events.sort(key=lambda e: e["_ts"])
    return events

# ── Manual entries ───────────────────────────────────────────────────────────

def extract_manual_entries(events: list[dict]) -> list[dict]:
    """Pull all manual_entry events out of the event list.
    Each entry has description, time (HH:MM), duration_minutes, _date, _ts.
    """
    entries = []
    for ev in events:
        if ev.get("event") != "manual_entry":
            continue
        desc = ev.get("description", "").strip()
        if not desc:
            continue
        time_str  = ev.get("time", "")       # "HH:MM" as user entered
        dur_min   = int(ev.get("duration_minutes", 60))
        date_str  = ev["_date"]               # YYYY-MM-DD
        date      = datetime.strptime(date_str, "%Y-%m-%d")

        # Resolve start time: use user-supplied time field if valid, else use _ts
        try:
            h, m = map(int, time_str.split(":"))
            start = date.replace(hour=h, minute=m, second=0, microsecond=0)
        except Exception:
            start = ev["_ts"].replace(second=0, microsecond=0)

        end = start + timedelta(minutes=dur_min)
        entries.append({
            "date":     date_str,
            "start":    start,
            "end":      end,
            "dur_min":  dur_min,
            "description": desc,
            "_ts":      ev["_ts"],
        })
    return entries

# ── Slot detection ────────────────────────────────────────────────────────────

def split_slots(events: list[dict]) -> list[list[dict]]:
    slots, current, in_break = [], [], False
    for ev in events:
        evt = ev.get("event", "")
        if evt in NOISE:
            current.append(ev); continue
        if evt == "started" and current:
            slots.append(current); current = [ev]; in_break = False; continue
        if evt in BREAK_START:
            if current: current.append(ev); slots.append(current)
            current = []; in_break = True; continue
        if evt in BREAK_END:
            in_break = False; continue
        if current and not in_break:
            if (ev["_ts"] - current[-1]["_ts"]).total_seconds() / 60 > GAP_MINUTES:
                slots.append(current); current = [ev]; continue
        current.append(ev)
    if current:
        slots.append(current)
    return slots

# ── Aggregation per slot ──────────────────────────────────────────────────────

def aggregate(slot: list[dict]) -> dict | None:
    real = [e for e in slot if e.get("event") not in NOISE]
    if not real:
        return None
    t0, t1 = real[0]["_ts"], real[-1]["_ts"]
    dur = (t1 - t0).total_seconds() / 60
    if dur < MIN_SLOT_MINUTES:
        return None

    app_sec:     dict[str, float] = defaultdict(float)
    proj_sec:    dict[str, float] = defaultdict(float)
    safari_sec:  dict[str, float] = defaultdict(float)
    teams_seen:  list[str] = []
    safari_seen: list[str] = []
    manual_entries: list[dict] = []

    cur_app = cur_app_ts = None
    cur_proj = cur_proj_ts = None
    cur_safari = cur_safari_ts = None

    for i, ev in enumerate(real):
        evt = ev.get("event", "")
        ts  = ev["_ts"]

        if evt == "app_switch":
            if cur_app and cur_app_ts:
                app_sec[cur_app] += (ts - cur_app_ts).total_seconds()
            # close vscode project if leaving VS Code
            if cur_app not in ("Code", None) and cur_proj and cur_proj_ts:
                proj_sec[cur_proj] += (ts - cur_proj_ts).total_seconds()
                cur_proj = cur_proj_ts = None
            cur_app, cur_app_ts = ev.get("app", "?"), ts

            app = cur_app
            detail = ev.get("detail", "")

            # Use app_switch detail as project hint when VS Code is activated
            # and no explicit vscode_project_change has been seen yet
            if app == "Code" and detail and detail not in ("unknown window", ""):
                if cur_proj != detail:
                    # close previous project interval
                    if cur_proj and cur_proj_ts:
                        proj_sec[cur_proj] += (ts - cur_proj_ts).total_seconds()
                    cur_proj, cur_proj_ts = detail, ts

            if app == "Microsoft Teams" and detail:
                if detail not in teams_seen:
                    teams_seen.append(detail)

        elif evt == "vscode_project_change":
            if cur_proj and cur_proj_ts:
                proj_sec[cur_proj] += (ts - cur_proj_ts).total_seconds()
            cur_proj, cur_proj_ts = ev.get("detail", "?"), ts

        elif evt == "manual_entry":
            manual_entries.append({
                "description":      ev.get("description", ""),
                "time":             ev.get("time", ""),
                "duration_minutes": ev.get("duration_minutes", 60),
            })

        elif evt == "safari_tab_change":
            label = ev.get("detail") or ev.get("url", "")
            if label and label not in safari_seen:
                safari_seen.append(label)
            # Accumulate time per Safari tab
            if cur_safari and cur_safari_ts:
                safari_sec[cur_safari] += (ts - cur_safari_ts).total_seconds()
            cur_safari, cur_safari_ts = label, ts

    # close final intervals
    if cur_app and cur_app_ts:
        app_sec[cur_app] += (t1 - cur_app_ts).total_seconds()
    if cur_proj and cur_proj_ts:
        proj_sec[cur_proj] += (t1 - cur_proj_ts).total_seconds()
    if cur_safari and cur_safari_ts:
        safari_sec[cur_safari] += (t1 - cur_safari_ts).total_seconds()

    return {
        "date":          real[0]["_date"],
        "t0":            t0,
        "t1":            t1,
        "dur_min":       dur,
        "app_sec":       dict(sorted(app_sec.items(),  key=lambda x: -x[1])),
        "proj_sec":      dict(sorted(proj_sec.items(), key=lambda x: -x[1])),
        "safari_sec":    dict(sorted(safari_sec.items(), key=lambda x: -x[1])),
        "teams":         teams_seen,
        "safari":        safari_seen,
        "manual_entries": manual_entries,
    }

# ── Git commits ───────────────────────────────────────────────────────────────

def commits_for_day(repo: Path, date_str: str) -> list[dict]:
    day     = datetime.strptime(date_str, "%Y-%m-%d")
    after   = day.strftime("%Y-%m-%d 00:00:00")
    before  = day.strftime("%Y-%m-%d 23:59:59")
    try:
        r = subprocess.run(
            ["git", "-C", str(repo), "log",
             f"--after={after}", f"--before={before}",
             "--format=%H|%ai|%s", "--all"],
            capture_output=True, text=True, timeout=10
        )
    except Exception:
        return []
    out = []
    for line in r.stdout.strip().splitlines():
        parts = line.split("|", 2)
        if len(parts) != 3:
            continue
        sha, ts_raw, msg = parts
        try:
            ts = parse_ts(ts_raw)
        except Exception:
            continue
        out.append({"sha": sha[:8], "ts": ts, "msg": msg, "repo": repo.name})
    return out

def all_commits_for_dates(dates: list[str]) -> list[dict]:
    commits = []
    for date in dates:
        for repo in REPOS:
            commits.extend(commits_for_day(repo, date))
    commits.sort(key=lambda c: c["ts"])
    return commits

# ── Attach commits to slots ───────────────────────────────────────────────────

def attach_commits(aggs: list[dict], all_commits: list[dict]) -> None:
    """Add 'commits' key to each agg. Unmatched commits go to nearest slot."""
    for agg in aggs:
        agg["commits"] = []

    # also carry over manual entries to matched slots
    for agg in aggs:
        agg.setdefault("manual_entries", [])

    for commit in all_commits:
        ct = commit["ts"]
        # find slot whose window contains the commit timestamp
        matched = next(
            (a for a in aggs if a["t0"] <= ct <= a["t1"]),
            None
        )
        if matched is None:
            # assign to closest slot by midpoint distance
            matched = min(
                aggs,
                key=lambda a: abs(((a["t0"] + (a["t1"] - a["t0"]) / 2) - ct).total_seconds())
            )
        matched["commits"].append(commit)

# ── Round to block grid ───────────────────────────────────────────────────────

def round_down(dt: datetime, minutes: int) -> datetime:
    return dt - timedelta(minutes=dt.minute % minutes, seconds=dt.second, microseconds=dt.microsecond)

def round_up(dt: datetime, minutes: int) -> datetime:
    excess = timedelta(minutes=dt.minute % minutes, seconds=dt.second, microseconds=dt.microsecond)
    return (dt - excess + timedelta(minutes=minutes)) if excess else dt

# ── Description builder ───────────────────────────────────────────────────────

def build_description(agg: dict) -> str:
    """Build a grouped, bullet-pointed description for an xlsx cell.

    Groups:
      • Manual entries
      • Meetings
      • Commits (grouped by repo)
      • VS Code projects
      • Apps
      • Web / Safari
    Each group gets a header line; items within are bulleted with "• ".
    Groups are separated by newlines for readability in wrapped Excel cells.
    """
    B = "• "                       # bullet prefix
    groups: list[str] = []         # each element = one group block

    # ── 0. Manual entries ─────────────────────────────────────────────────
    manual_lines = [f"{B}{m['description']}" for m in agg.get("manual_entries", [])]
    if manual_lines:
        groups.append("Manual:\n" + "\n".join(manual_lines))

    # ── 1. Meetings ──────────────────────────────────────────────────────
    meeting_lines: list[str] = []
    for w in agg["teams"]:
        if "Kompakte Besprechungsansicht" not in w:
            continue
        segments = [s.strip() for s in w.split("|")]
        meaningful = [s for s in segments if s and s not in
                      ("Microsoft Teams", "Calendar", "Kompakte Besprechungsansicht",
                       "Chat", "Calendar | Calendar")]
        if not meaningful:
            continue
        label = f"{B}{meaningful[0]}"
        if label not in meeting_lines:
            meeting_lines.append(label)
    if meeting_lines:
        groups.append("Meetings:\n" + "\n".join(meeting_lines))

    # ── 2. Commits (grouped by repo) ────────────────────────────────────
    commits_by_repo: dict[str, list[str]] = {}
    for c in agg.get("commits", []):
        commits_by_repo.setdefault(c["repo"], []).append(c["msg"])
    if commits_by_repo:
        commit_lines = [f"{B}[{repo}] {', '.join(msgs)}" for repo, msgs in commits_by_repo.items()]
        groups.append("Commits:\n" + "\n".join(commit_lines))

    # ── 3. VS Code projects ─────────────────────────────────────────────
    proj_lines = [
        f"{B}{proj} ({_fmt(sec)})"
        for proj, sec in agg["proj_sec"].items()
        if sec >= 300 and proj not in ("Save As", "unknown")
    ]
    if proj_lines:
        groups.append("VS Code:\n" + "\n".join(proj_lines))

    # ── 4. Apps ──────────────────────────────────────────────────────────
    app_lines = [
        f"{B}{app} ({_fmt(sec)})"
        for app, sec in agg["app_sec"].items()
        if app not in SKIP_APPS and sec >= 300
    ]
    if app_lines:
        groups.append("Apps:\n" + "\n".join(app_lines))

    # ── 5. Safari / Web ─────────────────────────────────────────────────
    if SHOW_SAFARI_TIME:
        safari_time = agg.get("safari_sec", {})
        safari_with_time = [
            (tab, safari_time.get(tab, 0))
            for tab in agg["safari"]
            if tab
            and tab not in SKIP_SAFARI_EXACT
            and not any(s in tab for s in SKIP_SAFARI_CONTAINS)
        ]
        safari_with_time.sort(key=lambda x: -x[1])
        web_lines: list[str] = []
        for tab, sec in safari_with_time[:5]:
            if sec >= 30:
                web_lines.append(f"{B}{tab} ({_fmt(sec)})")
            else:
                web_lines.append(f"{B}{tab}")
        if web_lines:
            groups.append("Web:\n" + "\n".join(web_lines))
    else:
        safari_filtered = [
            t for t in agg["safari"]
            if t
            and t not in SKIP_SAFARI_EXACT
            and not any(s in t for s in SKIP_SAFARI_CONTAINS)
        ]
        if safari_filtered:
            web_lines = [f"{B}{t}" for t in safari_filtered[:5]]
            groups.append("Web:\n" + "\n".join(web_lines))

    return "\n\n".join(groups) if groups else "—"

def _fmt(sec: float) -> str:
    m = int(sec / 60)
    return f"{m//60}h{m%60:02d}m" if m >= 60 else f"{m}min"

# ── Report rows ───────────────────────────────────────────────────────────────

WEEKDAYS_DE = ["Montag","Dienstag","Mittwoch","Donnerstag","Freitag","Samstag","Sonntag"]
WEEKDAYS_EN = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

def _prefilled_blocks(date: datetime) -> list[tuple[datetime, datetime, str]]:
    """Return planned meeting windows for a given date as (start, end, description)."""
    dow_en = WEEKDAYS_EN[date.weekday()]
    blocks = []
    for start_str, end_str, desc in PREFILLED_SLOTS.get(dow_en, []):
        sh, sm = map(int, start_str.split(":"))
        eh, em = map(int, end_str.split(":"))
        blocks.append((
            date.replace(hour=sh, minute=sm, second=0, microsecond=0),
            date.replace(hour=eh, minute=em, second=0, microsecond=0),
            desc,
        ))
    return blocks


def make_rows(aggs: list[dict], manual_entries: list[dict] = []) -> list[dict]:
    """
    Three-tier placement:
      Tier 0 (immovable): prefilled meeting slots from config
      Tier 1 (high prio): manual_entries — placed at user-requested time,
                          bumped past meetings if needed, never overlapping tier-0
      Tier 2 (fill):      auto-detected activity slots — fill remaining space
    """
    rows: list[dict] = []

    # Collect all occupied windows: prefilled meetings + placed manual entries
    # so auto-slots can avoid them
    occupied: list[tuple[datetime, datetime]] = []

    # ── Tier 0: emit prefilled meeting slots as filled rows ──────────────────
    # Gather all active dates from aggs + manual entries
    active_dates: set[str] = set()
    for agg in aggs:
        active_dates.add(agg["date"])
    for entry in manual_entries:
        active_dates.add(entry["date"])

    for date_str in sorted(active_dates):
        date = datetime.strptime(date_str, "%Y-%m-%d")
        dow_de = WEEKDAYS_DE[date.weekday()]
        for ps, pe, desc in _prefilled_blocks(date):
            occupied.append((ps, pe))
            rows.append({
                "Wochentag":    dow_de,
                "Datum":        date.strftime("%d.%m.%Y"),
                "Von":          ps.strftime("%H:%M"),
                "Bis":          pe.strftime("%H:%M"),
                "Beschreibung": desc if desc else "Meeting",
                "_priority":    0,
                "_start":       ps,
            })

    def overlaps_any(start: datetime, end: datetime,
                     blocks: list[tuple[datetime, datetime]]) -> bool:
        return any(start < be and end > bs for bs, be in blocks)

    def push_past(start: datetime, end: datetime,
                  blocks: list[tuple[datetime, datetime]]) -> tuple[datetime, datetime]:
        duration = end - start
        for _ in range(len(blocks) + 1):
            moved = False
            for bs, be in blocks:
                if start < be and end > bs:
                    start = be
                    end   = start + duration
                    moved = True
                    break
            if not moved:
                break
        return start, end

    for entry in sorted(manual_entries, key=lambda e: e["start"]):
        date     = datetime.strptime(entry["date"], "%Y-%m-%d")
        prefilled = [(s, e) for s, e, _ in _prefilled_blocks(date)]
        start, end = entry["start"], entry["end"]

        # Snap to block grid
        start = round_down(start, BLOCK_MINUTES)
        end   = start + timedelta(minutes=round(entry["dur_min"] / BLOCK_MINUTES) * BLOCK_MINUTES
                                   or BLOCK_MINUTES)

        # Push past any prefilled meetings
        if overlaps_any(start, end, prefilled):
            start, end = push_past(start, end, prefilled)

        occupied.append((start, end))
        dow_de = WEEKDAYS_DE[date.weekday()]

        # Smart split: distribute description topics across blocks
        total_blocks = max(1, int((end - start).total_seconds() / 60) // BLOCK_MINUTES)
        desc = entry["description"]
        # Parse pipe-separated segments from the manual description
        segments = [s.strip() for s in desc.split("|") if s.strip()]

        if total_blocks <= 1 or len(segments) <= 1:
            # Single block or no segments to distribute — emit as-is
            rows.append({
                "Wochentag":    dow_de,
                "Datum":        date.strftime("%d.%m.%Y"),
                "Von":          start.strftime("%H:%M"),
                "Bis":          end.strftime("%H:%M"),
                "Beschreibung": f"Manual:\n• {desc}",
                "_priority":    1,
                "_start":       start,
            })
        else:
            # Distribute segments across blocks round-robin
            block_segments: list[list[str]] = [[] for _ in range(total_blocks)]
            for i, seg in enumerate(segments):
                block_segments[i % total_blocks].append(seg)

            for b in range(total_blocks):
                b_start = start + timedelta(minutes=b * BLOCK_MINUTES)
                b_end   = b_start + timedelta(minutes=BLOCK_MINUTES)
                block_desc = " | ".join(block_segments[b]) if block_segments[b] else "—"
                rows.append({
                    "Wochentag":    dow_de,
                    "Datum":        date.strftime("%d.%m.%Y"),
                    "Von":          b_start.strftime("%H:%M"),
                    "Bis":          b_end.strftime("%H:%M"),
                    "Beschreibung": block_desc,
                    "_priority":    1,
                    "_start":       b_start,
                })

    # ── Tier 2: place auto-detected slots ────────────────────────────────────────────────
    # Auto-slots stay at their real event times; if they overlap a protected window
    # (prefilled meeting or manual entry), they get clipped — never pushed forward.

    for agg in aggs:
        date      = datetime.strptime(agg["date"], "%Y-%m-%d")
        prefilled = [(s, e) for s, e, _ in _prefilled_blocks(date)]
        start     = round_down(agg["t0"], BLOCK_MINUTES)
        end       = round_up(agg["t1"],   BLOCK_MINUTES)

        desc = build_description(agg)

        # Build protected windows: prefilled meetings + placed manual entries
        protected = sorted(
            prefilled + [(s, e) for s, e in occupied if s.date() == date.date()],
            key=lambda b: b[0]
        )

        # Clip/split: keep only the parts of [start, end) that don't overlap any protected window
        fragments = [(start, end)]
        for bs, be in protected:
            new_fragments = []
            for fs, fe in fragments:
                if fe <= bs or fs >= be:
                    new_fragments.append((fs, fe))      # no overlap
                else:
                    if fs < bs:
                        new_fragments.append((fs, bs))  # part before protected
                    if fe > be:
                        new_fragments.append((be, fe))  # part after protected
            fragments = new_fragments

        # Emit a row for each surviving fragment
        dow_de = WEEKDAYS_DE[date.weekday()]
        for fs, fe in fragments:
            if fe - fs < timedelta(minutes=MIN_SLOT_MINUTES):
                continue
            if not desc:
                continue
            rows.append({
                "Wochentag":    dow_de,
                "Datum":        date.strftime("%d.%m.%Y"),
                "Von":          fs.strftime("%H:%M"),
                "Bis":          fe.strftime("%H:%M"),
                "Beschreibung": desc,
                "_priority":    2,
                "_start":       fs,
            })

    # Sort all rows by date + start time, then strip internal keys
    rows.sort(key=lambda r: (r["Datum"], r["_start"]))

    # Merge consecutive rows with identical descriptions on the same date
    merged: list[dict] = []
    for r in rows:
        if (merged
            and merged[-1]["Datum"] == r["Datum"]
            and merged[-1]["Beschreibung"] == r["Beschreibung"]
            and merged[-1]["Bis"] == r["Von"]):
            merged[-1]["Bis"] = r["Bis"]
        else:
            merged.append(r)
    rows = merged

    # Eliminate any remaining overlaps between same-tier rows (clip end)
    for i in range(len(rows) - 1):
        cur, nxt = rows[i], rows[i + 1]
        if cur["Datum"] == nxt["Datum"] and cur["Bis"] > nxt["Von"]:
            cur["Bis"] = nxt["Von"]

    # Remove zero-duration rows and internal keys
    clean = []
    for r in rows:
        r.pop("_priority", None)
        r.pop("_start", None)
        if r["Von"] < r["Bis"]:
            clean.append(r)

    return clean

# ── Output ────────────────────────────────────────────────────────────────────

def print_table(rows: list[dict]) -> None:
    header = ["Wochentag", "Datum", "Von", "Bis", "Beschreibung"]
    widths = [12, 12, 6, 6, 80]
    sep = "─" * (sum(widths) + len(widths) * 3 + 1)

    print(sep)
    print("  ".join(h.ljust(w) for h, w in zip(header, widths)))
    print(sep)
    for row in rows:
        desc = row["Beschreibung"]
        # wrap description
        first = True
        while desc:
            chunk, desc = desc[:widths[-1]], desc[widths[-1]:]
            if first:
                line = "  ".join([
                    row["Wochentag"].ljust(widths[0]),
                    row["Datum"].ljust(widths[1]),
                    row["Von"].ljust(widths[2]),
                    row["Bis"].ljust(widths[3]),
                    chunk.ljust(widths[4]),
                ])
                first = False
            else:
                line = "  ".join([" " * w for w in widths[:4]] + [chunk])
            print(line)
    print(sep)

def write_xlsx(rows: list[dict], path: Path) -> None:
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Report"

    headers = ["Wochentag", "Datum", "Von", "Bis", "Beschreibung"]
    col_widths = [14, 14, 7, 7, 80]

    header_fill = PatternFill("solid", fgColor="2F5597")
    header_font = Font(bold=True, color="FFFFFF")

    for col, (h, w) in enumerate(zip(headers, col_widths), start=1):
        cell = ws.cell(row=1, column=col, value=h)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(vertical="center")
        ws.column_dimensions[cell.column_letter].width = w
    ws.row_dimensions[1].height = 18

    alt_fill = PatternFill("solid", fgColor="D9E1F2")
    for row_idx, row in enumerate(rows, start=2):
        fill = alt_fill if row_idx % 2 == 0 else None
        for col, key in enumerate(headers, start=1):
            cell = ws.cell(row=row_idx, column=col, value=row.get(key, ""))
            cell.alignment = Alignment(wrap_text=True, vertical="top")
            if fill:
                cell.fill = fill
        # auto height: 15pt per line in description col
        desc = row.get("Beschreibung", "")
        lines = max(1, desc.count("\n") + 1)
        ws.row_dimensions[row_idx].height = max(15, lines * 15)

    ws.freeze_panes = "A2"
    wb.save(path)
    print(f"✅  Written to {path}")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    args  = [a for a in sys.argv[1:] if not a.startswith("--")]
    to_xlsx = "--csv" in flags or "--xlsx" in flags

    # Optional explicit output path: --out /path/to/file.xlsx
    out_path_arg: str | None = None
    for i, a in enumerate(sys.argv):
        if a == "--out" and i + 1 < len(sys.argv):
            out_path_arg = sys.argv[i + 1]
            to_xlsx = True
            break

    now  = datetime.now()
    year = int(args[0]) if len(args) > 0 else now.isocalendar().year
    week = int(args[1]) if len(args) > 1 else now.isocalendar().week

    print(f"\nLoading week {week}/{year}…")
    events = load_week(year, week)
    print(f"  {len(events)} events loaded")

    # ── Tier 1: extract manual entries (highest priority) ─────────────────────
    manual_entries = extract_manual_entries(events)
    print(f"  {len(manual_entries)} manual entries")

    # ── Tier 2: auto-detected slots from activity ─────────────────────────────
    slots = split_slots(events)
    print(f"  {len(slots)} raw slots")
    aggs  = [a for a in (aggregate(s) for s in slots) if a]
    print(f"  {len(aggs)} meaningful slots (≥{MIN_SLOT_MINUTES}min)")

    dates = sorted({a["date"] for a in aggs} | {e["date"] for e in manual_entries})
    all_commits = all_commits_for_dates(dates)
    print(f"  {len(all_commits)} commits across {len(dates)} day(s)")
    if all_commits:
        attach_commits(aggs, all_commits)

    rows = make_rows(aggs, manual_entries)

    print()
    print_table(rows)

    if to_xlsx:
        out = Path(out_path_arg) if out_path_arg else Path(__file__).parent / f"report_KW{week:02d}_{year}.xlsx"
        write_xlsx(rows, out)
