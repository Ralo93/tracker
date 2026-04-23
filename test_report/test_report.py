#!/usr/bin/env python3
"""
Tests for report.py — budget-fill pipeline, harvest, Teams filtering, helpers.

Run: python3 -m pytest test_report/test_report.py -v
  or: python3 test_report/test_report.py
"""

import sys, unittest
from datetime import datetime, timedelta
from pathlib import Path

# Ensure the test_report module is importable
sys.path.insert(0, str(Path(__file__).parent))
import report


# ── Helpers ────────────────────────────────────────────────────────────────────

MPM = report.MIN_PACKAGE_MIN  # minimum package minutes (15)


def _make_manual(desc: str, date_str: str, time_str: str, dur_min: int) -> dict:
    """Build a manual entry dict matching extract_manual_entries() output."""
    date = datetime.strptime(date_str, "%Y-%m-%d")
    h, m = map(int, time_str.split(":"))
    start = date.replace(hour=h, minute=m, second=0, microsecond=0)
    return {
        "date":        date_str,
        "start":       start,
        "end":         start + timedelta(minutes=dur_min),
        "dur_min":     dur_min,
        "description": desc,
        "_ts":         start,
    }


def _make_agg(date_str: str, t0_str: str, t1_str: str, **kwargs) -> dict:
    """Build a minimal aggregation dict."""
    date = datetime.strptime(date_str, "%Y-%m-%d")
    h0, m0 = map(int, t0_str.split(":"))
    h1, m1 = map(int, t1_str.split(":"))
    base = {
        "date":           date_str,
        "t0":             date.replace(hour=h0, minute=m0),
        "t1":             date.replace(hour=h1, minute=m1),
        "dur_min":        (h1 * 60 + m1) - (h0 * 60 + m0),
        "app_sec":        {},
        "proj_sec":       {},
        "safari_sec":     {},
        "teams":          [],
        "safari":         [],
        "commits":        [],
        "manual_entries": [],
    }
    base.update(kwargs)
    return base


def _make_pkg(desc: str, weight_min: float, date_str: str = "2026-04-13",
              t0: str = "09:00", t1: str = "10:00", ptype: str = "project") -> dict:
    """Build a work package dict."""
    date = datetime.strptime(date_str, "%Y-%m-%d")
    h0, m0 = map(int, t0.split(":"))
    h1, m1 = map(int, t1.split(":"))
    return {
        "type": ptype,
        "description": desc,
        "weight": weight_min * 60,
        "source_t0": date.replace(hour=h0, minute=m0),
        "source_t1": date.replace(hour=h1, minute=m1),
    }


# ==============================================================================
# 1. harvest_packages — Work Package Extraction
# ==============================================================================

class TestHarvestPackages(unittest.TestCase):

    def test_project_harvested(self):
        """VS Code project time → project package."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        proj_sec={"MyProject": 1800})
        pkgs = report.harvest_packages([agg], [])
        self.assertIn("2026-04-13", pkgs)
        descs = [p["description"] for p in pkgs["2026-04-13"]]
        self.assertIn("MyProject", descs)

    def test_commit_claims_project(self):
        """Commits for a repo should absorb its project time — no separate project pkg."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        proj_sec={"MyApp": 3600},
                        commits=[{"repo": "MyApp", "msg": "fix bug", "sha": "abc", "ts": datetime(2026, 4, 13, 9, 30)}])
        pkgs = report.harvest_packages([agg], [])
        descs = [p["description"] for p in pkgs["2026-04-13"]]
        # Should have "[MyApp] fix bug" but NOT a separate "MyApp"
        self.assertTrue(any("[MyApp]" in d for d in descs))
        self.assertNotIn("MyApp", descs)

    def test_manual_entry_becomes_package(self):
        """Manual entries → manual package with stated duration as weight."""
        manual = _make_manual("Sprint Planning", "2026-04-13", "14:00", 30)
        pkgs = report.harvest_packages([], [manual])
        self.assertIn("2026-04-13", pkgs)
        pkg = pkgs["2026-04-13"][0]
        self.assertEqual(pkg["description"], "Sprint Planning")
        self.assertEqual(pkg["weight"], 30 * 60)

    def test_teams_call_harvested(self):
        """Teams call window → call package."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        teams=["Florentin Rauscher | Kompakte Besprechungsansicht | Microsoft Teams"],
                        app_sec={"Microsoft Teams": 1800})
        pkgs = report.harvest_packages([agg], [])
        descs = [p["description"] for p in pkgs["2026-04-13"]]
        self.assertIn("Call: Florentin Rauscher", descs)

    def test_teams_chat_not_harvested(self):
        """Teams chat windows should not create packages."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        teams=["KI@BMF Dev | Chat | Microsoft Teams"])
        pkgs = report.harvest_packages([agg], [])
        # No packages or no call packages
        day_pkgs = pkgs.get("2026-04-13", [])
        call_pkgs = [p for p in day_pkgs if p["type"] == "call"]
        self.assertEqual(len(call_pkgs), 0)

    def test_dedup_same_project_across_slots(self):
        """Same project in multiple slots → merged into one package."""
        agg1 = _make_agg("2026-04-13", "09:00", "10:00", proj_sec={"MyProject": 1800})
        agg2 = _make_agg("2026-04-13", "14:00", "15:00", proj_sec={"MyProject": 900})
        pkgs = report.harvest_packages([agg1, agg2], [])
        proj_pkgs = [p for p in pkgs["2026-04-13"] if p["description"] == "MyProject"]
        self.assertEqual(len(proj_pkgs), 1, "Same project should be deduped")
        self.assertEqual(proj_pkgs[0]["weight"], 1800 + 900)

    def test_small_project_filtered(self):
        """Projects < 60s should be filtered out."""
        agg = _make_agg("2026-04-13", "09:00", "10:00", proj_sec={"Tiny": 30})
        pkgs = report.harvest_packages([agg], [])
        day_pkgs = pkgs.get("2026-04-13", [])
        descs = [p["description"] for p in day_pkgs]
        self.assertNotIn("Tiny", descs)

    def test_safari_web_research(self):
        """Non-noise Safari tabs → single web_research package."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["GitHub PR", "StackOverflow"],
                        safari_sec={"GitHub PR": 300, "StackOverflow": 200})
        pkgs = report.harvest_packages([agg], [])
        web_pkgs = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "web_research"]
        self.assertEqual(len(web_pkgs), 1)
        self.assertIn("GitHub PR", web_pkgs[0]["description"])

    def test_noise_safari_filtered(self):
        """Safari noise tabs should not produce packages."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["Start Page", "favorites://"],
                        safari_sec={"Start Page": 600})
        pkgs = report.harvest_packages([agg], [])
        web_pkgs = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "web_research"]
        self.assertEqual(len(web_pkgs), 0)

    def test_empty_input(self):
        """No aggs, no manual → empty packages."""
        pkgs = report.harvest_packages([], [])
        self.assertEqual(len(pkgs), 0)


# ==============================================================================
# 2. make_rows — Budget Fill Algorithm
# ==============================================================================

class TestBudgetFill(unittest.TestCase):

    def test_single_package_fills_day(self):
        """One package should expand to fill available time."""
        agg = _make_agg("2026-04-13", "09:00", "17:00")  # Sunday, no meetings
        pkgs = {"2026-04-13": [_make_pkg("MyProject", 60)]}
        rows = report.make_rows([agg], [], pkgs)
        proj_rows = [r for r in rows if r["Beschreibung"] == "MyProject"]
        self.assertGreaterEqual(len(proj_rows), 1)
        # Should fill substantial time, not just 60min
        total = sum(
            (datetime.strptime(r["Bis"], "%H:%M") - datetime.strptime(r["Von"], "%H:%M")).total_seconds() / 60
            for r in proj_rows
        )
        self.assertGreater(total, 60, "Single package should expand to fill available time")

    def test_no_duplicate_descriptions(self):
        """Each package should not have its description randomly duplicated.
        Splitting across lunch is acceptable (same desc, non-adjacent rows)."""
        agg = _make_agg("2026-04-13", "09:00", "17:00")
        pkgs = {"2026-04-13": [
            _make_pkg("ProjectA", 120, t0="09:00", t1="11:00"),
            _make_pkg("ProjectB", 60, t0="11:00", t1="12:00"),
            _make_pkg("ProjectC", 60, t0="14:00", t1="15:00"),
        ]}
        rows = report.make_rows([agg], [], pkgs)
        descs = [r["Beschreibung"] for r in rows]
        # All three packages should be present
        for desc in ["ProjectA", "ProjectB", "ProjectC"]:
            self.assertIn(desc, descs, f"{desc} missing from output")
        # No description should appear more than twice (at most a lunch split)
        for desc in set(descs):
            self.assertLessEqual(descs.count(desc), 2,
                                 f"{desc} duplicated too many times: {descs.count(desc)}")

    def test_manual_entry_gets_stated_duration(self):
        """Manual entry weight (30min) should be reflected proportionally."""
        agg = _make_agg("2026-04-13", "09:00", "17:00")
        manual = _make_manual("Quick task", "2026-04-13", "10:00", 30)
        pkgs = report.harvest_packages([agg], [manual])
        rows = report.make_rows([agg], [manual], pkgs)
        manual_rows = [r for r in rows if r["Beschreibung"] == "Quick task"]
        self.assertGreaterEqual(len(manual_rows), 1)
        total = sum(
            (datetime.strptime(r["Bis"], "%H:%M") - datetime.strptime(r["Von"], "%H:%M")).total_seconds() / 60
            for r in manual_rows
        )
        # Should get at least MIN_PACKAGE_MIN, not inflated to a full hour
        self.assertGreaterEqual(total, MPM)

    def test_rows_dont_overlap(self):
        """No two rows on the same date should overlap."""
        agg = _make_agg("2026-04-13", "08:00", "17:00")
        pkgs = {"2026-04-13": [
            _make_pkg("A", 120, t0="08:00", t1="10:00"),
            _make_pkg("B", 90, t0="10:00", t1="11:30"),
            _make_pkg("C", 60, t0="13:00", t1="14:00"),
            _make_pkg("D", 45, t0="14:00", t1="14:45"),
        ]}
        rows = report.make_rows([agg], [], pkgs)
        same_date = [r for r in rows if r["Datum"] == "13.04.2026"]
        for i in range(len(same_date) - 1):
            self.assertLessEqual(same_date[i]["Bis"], same_date[i + 1]["Von"],
                                 f"Overlap: {same_date[i]} vs {same_date[i+1]}")

    def test_rows_are_contiguous(self):
        """Work rows should fill continuously (no unexplained gaps outside lunch)."""
        agg = _make_agg("2026-04-13", "09:00", "17:00")  # Sunday, no meetings
        pkgs = {"2026-04-13": [
            _make_pkg("A", 120),
            _make_pkg("B", 120),
        ]}
        rows = report.make_rows([agg], [], pkgs)
        work_rows = [r for r in rows if r["Datum"] == "13.04.2026"]
        for i in range(len(work_rows) - 1):
            gap_start = work_rows[i]["Bis"]
            gap_end = work_rows[i + 1]["Von"]
            if gap_start != gap_end:
                # Only allowed gap is the lunch break
                self.assertEqual(gap_start, report.LUNCH_START,
                                 f"Unexpected gap from {gap_start} to {gap_end}")

    def test_planned_meetings_immovable(self):
        """Prefilled meetings should appear at their exact configured times."""
        # Use a Wednesday which has meetings in the test config
        agg = _make_agg("2026-04-15", "08:00", "17:00")  # Wednesday
        pkgs = {"2026-04-15": [_make_pkg("Work", 300, date_str="2026-04-15")]}
        rows = report.make_rows([agg], [], pkgs)
        # Check that work rows don't overlap meeting times
        work_rows = [r for r in rows if r["Beschreibung"] == "Work"]
        meeting_rows = [r for r in rows if r["Beschreibung"] != "Work"]
        for mr in meeting_rows:
            for wr in work_rows:
                # No overlap
                self.assertTrue(
                    wr["Bis"] <= mr["Von"] or wr["Von"] >= mr["Bis"],
                    f"Work row {wr['Von']}-{wr['Bis']} overlaps meeting {mr['Von']}-{mr['Bis']}"
                )

    def test_proportional_allocation(self):
        """Two packages with 2:1 weight ratio → ~2:1 time ratio."""
        agg = _make_agg("2026-04-13", "09:00", "17:00")  # Sunday, no meetings
        pkgs = {"2026-04-13": [
            _make_pkg("Heavy", 240),  # 4h of evidence
            _make_pkg("Light", 120),  # 2h of evidence
        ]}
        rows = report.make_rows([agg], [], pkgs)
        def _total_min(desc):
            return sum(
                (datetime.strptime(r["Bis"], "%H:%M") - datetime.strptime(r["Von"], "%H:%M")).total_seconds() / 60
                for r in rows if r["Beschreibung"] == desc
            )
        heavy = _total_min("Heavy")
        light = _total_min("Light")
        self.assertGreater(heavy, 0)
        self.assertGreater(light, 0)
        ratio = heavy / light
        # Should be roughly 2:1, allow tolerance for rounding to MIN_PACKAGE_MIN grid
        self.assertGreater(ratio, 1.3, f"Expected ~2:1 ratio, got {ratio:.1f}")
        self.assertLess(ratio, 3.0, f"Expected ~2:1 ratio, got {ratio:.1f}")

    def test_empty_packages_only_meetings(self):
        """If no work packages, only meeting rows should appear."""
        # Wednesday has meetings
        agg = _make_agg("2026-04-15", "08:00", "17:00")
        rows = report.make_rows([agg], [], {"2026-04-15": []})
        for r in rows:
            self.assertNotEqual(r["Beschreibung"], "—")


# ==============================================================================
# 3. Teams Filtering in harvest
# ==============================================================================

class TestTeamsFiltering(unittest.TestCase):

    def test_meeting_creates_call_package(self):
        """Teams window with Kompakte Besprechungsansicht → call package."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "Florentin Rauscher | Kompakte Besprechungsansicht | Microsoft Teams"
        ], app_sec={"Microsoft Teams": 1800})
        pkgs = report.harvest_packages([agg], [])
        calls = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "call"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["description"], "Call: Florentin Rauscher")

    def test_chat_no_package(self):
        """Teams chat → no call package."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "KI@BMF Dev | Chat | Microsoft Teams"
        ])
        pkgs = report.harvest_packages([agg], [])
        calls = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "call"]
        self.assertEqual(len(calls), 0)

    def test_mixed_chat_and_meeting(self):
        """Only the meeting creates a call package."""
        agg = _make_agg("2026-04-13", "09:00", "10:00", teams=[
            "KI@BMF Dev | Chat | Microsoft Teams",
            "Sven Metscher | Kompakte Besprechungsansicht | Microsoft Teams",
            "PM-Chatgruppe | Microsoft Teams",
        ], app_sec={"Microsoft Teams": 3600})
        pkgs = report.harvest_packages([agg], [])
        calls = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "call"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["description"], "Call: Sven Metscher")

    def test_noise_meeting_title_no_package(self):
        """Meeting with only noise segments → no call package."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "Microsoft Teams | Kompakte Besprechungsansicht | Calendar"
        ])
        pkgs = report.harvest_packages([agg], [])
        calls = [p for p in pkgs.get("2026-04-13", []) if p["type"] == "call"]
        self.assertEqual(len(calls), 0)


# ==============================================================================
# 4. Round-to-Block Helpers
# ==============================================================================

class TestBlockHelpers(unittest.TestCase):

    def test_round_down_on_boundary(self):
        dt = datetime(2026, 4, 13, 10, 0, 0)
        self.assertEqual(report.round_down(dt, 30), dt)

    def test_round_down_mid_block(self):
        dt = datetime(2026, 4, 13, 10, 17, 45)
        self.assertEqual(report.round_down(dt, 30), datetime(2026, 4, 13, 10, 0, 0))

    def test_round_down_just_before_boundary(self):
        dt = datetime(2026, 4, 13, 10, 29, 59)
        self.assertEqual(report.round_down(dt, 30), datetime(2026, 4, 13, 10, 0, 0))

    def test_round_up_on_boundary(self):
        dt = datetime(2026, 4, 13, 10, 0, 0)
        self.assertEqual(report.round_up(dt, 30), dt)

    def test_round_up_mid_block(self):
        dt = datetime(2026, 4, 13, 10, 1, 0)
        self.assertEqual(report.round_up(dt, 30), datetime(2026, 4, 13, 10, 30, 0))

    def test_round_up_15min_blocks(self):
        dt = datetime(2026, 4, 13, 10, 8, 0)
        self.assertEqual(report.round_up(dt, 15), datetime(2026, 4, 13, 10, 15, 0))

    def test_round_down_15min_blocks(self):
        dt = datetime(2026, 4, 13, 10, 22, 0)
        self.assertEqual(report.round_down(dt, 15), datetime(2026, 4, 13, 10, 15, 0))


# ==============================================================================
# 5. _compute_free_windows
# ==============================================================================

class TestFreeWindows(unittest.TestCase):

    def test_no_reserved(self):
        s = datetime(2026, 4, 13, 9, 0)
        e = datetime(2026, 4, 13, 17, 0)
        free = report._compute_free_windows(s, e, [])
        self.assertEqual(free, [(s, e)])

    def test_single_reserved_middle(self):
        s = datetime(2026, 4, 13, 9, 0)
        e = datetime(2026, 4, 13, 17, 0)
        reserved = [(datetime(2026, 4, 13, 12, 0), datetime(2026, 4, 13, 13, 0))]
        free = report._compute_free_windows(s, e, reserved)
        self.assertEqual(len(free), 2)
        self.assertEqual(free[0], (s, datetime(2026, 4, 13, 12, 0)))
        self.assertEqual(free[1], (datetime(2026, 4, 13, 13, 0), e))

    def test_adjacent_reserved(self):
        s = datetime(2026, 4, 13, 9, 0)
        e = datetime(2026, 4, 13, 17, 0)
        reserved = [
            (datetime(2026, 4, 13, 10, 0), datetime(2026, 4, 13, 11, 0)),
            (datetime(2026, 4, 13, 11, 0), datetime(2026, 4, 13, 12, 0)),
        ]
        free = report._compute_free_windows(s, e, reserved)
        self.assertEqual(len(free), 2)
        self.assertEqual(free[0][1], datetime(2026, 4, 13, 10, 0))
        self.assertEqual(free[1][0], datetime(2026, 4, 13, 12, 0))

    def test_reserved_at_edges(self):
        s = datetime(2026, 4, 13, 9, 0)
        e = datetime(2026, 4, 13, 17, 0)
        reserved = [
            (datetime(2026, 4, 13, 9, 0), datetime(2026, 4, 13, 10, 0)),
            (datetime(2026, 4, 13, 16, 0), datetime(2026, 4, 13, 17, 0)),
        ]
        free = report._compute_free_windows(s, e, reserved)
        self.assertEqual(len(free), 1)
        self.assertEqual(free[0], (datetime(2026, 4, 13, 10, 0), datetime(2026, 4, 13, 16, 0)))


# ==============================================================================
# 6. _dedup_packages
# ==============================================================================

class TestDedupPackages(unittest.TestCase):

    def test_no_dupes(self):
        pkgs = [
            _make_pkg("A", 60),
            _make_pkg("B", 30),
        ]
        result = report._dedup_packages(pkgs)
        self.assertEqual(len(result), 2)

    def test_merge_same_desc(self):
        pkgs = [
            _make_pkg("A", 60, t0="09:00", t1="10:00"),
            _make_pkg("A", 30, t0="14:00", t1="15:00"),
        ]
        result = report._dedup_packages(pkgs)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["weight"], 90 * 60)

    def test_sorted_by_source_t0(self):
        pkgs = [
            _make_pkg("B", 30, t0="14:00", t1="15:00"),
            _make_pkg("A", 60, t0="09:00", t1="10:00"),
        ]
        result = report._dedup_packages(pkgs)
        self.assertEqual(result[0]["description"], "A")
        self.assertEqual(result[1]["description"], "B")


# ==============================================================================
# 7. extract_manual_entries
# ==============================================================================

class TestExtractManualEntries(unittest.TestCase):

    def test_basic_extraction(self):
        events = [{
            "event": "manual_entry",
            "description": "Did stuff",
            "time": "10:30",
            "duration_minutes": 45,
            "timestamp": "2026-04-13T10:30:00",
            "_date": "2026-04-13",
            "_ts": datetime(2026, 4, 13, 10, 30),
        }]
        entries = report.extract_manual_entries(events)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["description"], "Did stuff")
        self.assertEqual(entries[0]["dur_min"], 45)
        self.assertEqual(entries[0]["start"], datetime(2026, 4, 13, 10, 30))

    def test_empty_description_skipped(self):
        events = [{
            "event": "manual_entry",
            "description": "  ",
            "time": "10:00",
            "duration_minutes": 30,
            "timestamp": "2026-04-13T10:00:00",
            "_date": "2026-04-13",
            "_ts": datetime(2026, 4, 13, 10, 0),
        }]
        entries = report.extract_manual_entries(events)
        self.assertEqual(len(entries), 0)

    def test_non_manual_events_ignored(self):
        events = [
            {"event": "app_switch", "description": "Chrome", "_date": "2026-04-13",
             "_ts": datetime(2026, 4, 13, 10, 0), "timestamp": "2026-04-13T10:00:00"},
            {"event": "idle_start", "_date": "2026-04-13",
             "_ts": datetime(2026, 4, 13, 10, 5), "timestamp": "2026-04-13T10:05:00"},
        ]
        entries = report.extract_manual_entries(events)
        self.assertEqual(len(entries), 0)

    def test_invalid_time_falls_back_to_ts(self):
        events = [{
            "event": "manual_entry",
            "description": "Stuff",
            "time": "invalid!!",
            "duration_minutes": 30,
            "timestamp": "2026-04-13T14:25:00",
            "_date": "2026-04-13",
            "_ts": datetime(2026, 4, 13, 14, 25),
        }]
        entries = report.extract_manual_entries(events)
        self.assertEqual(entries[0]["start"], datetime(2026, 4, 13, 14, 25))


# ==============================================================================
# 8. _fmt helper
# ==============================================================================

class TestFmt(unittest.TestCase):

    def test_minutes(self):
        self.assertEqual(report._fmt(300), "5min")

    def test_hours(self):
        self.assertEqual(report._fmt(3600), "1h00m")

    def test_hours_and_minutes(self):
        self.assertEqual(report._fmt(3720), "1h02m")

    def test_zero(self):
        self.assertEqual(report._fmt(0), "0min")


# ==============================================================================
# 9. Safari time accumulation in aggregate()
# ==============================================================================

class TestSafariTimeAccumulation(unittest.TestCase):

    def test_aggregate_tracks_safari_sec(self):
        """Integration: aggregate() should populate safari_sec from tab events."""
        base = datetime(2026, 4, 13, 9, 0)
        events = [
            {"event": "app_switch", "app": "Safari", "bundle_id": "com.apple.Safari",
             "detail": "Tab A", "timestamp": "2026-04-13T09:00:00",
             "_date": "2026-04-13", "_ts": base},
            {"event": "safari_tab_change", "detail": "Tab A",
             "timestamp": "2026-04-13T09:00:00",
             "_date": "2026-04-13", "_ts": base},
            {"event": "safari_tab_change", "detail": "Tab B",
             "timestamp": "2026-04-13T09:05:00",
             "_date": "2026-04-13", "_ts": base + timedelta(minutes=5)},
            {"event": "safari_tab_change", "detail": "Tab A",
             "timestamp": "2026-04-13T09:08:00",
             "_date": "2026-04-13", "_ts": base + timedelta(minutes=8)},
            {"event": "app_switch", "app": "Code", "bundle_id": "com.microsoft.VSCode",
             "detail": "MyProject", "timestamp": "2026-04-13T09:10:00",
             "_date": "2026-04-13", "_ts": base + timedelta(minutes=10)},
        ]
        agg = report.aggregate(events)
        self.assertIsNotNone(agg)
        # Tab A: 0-5min = 300s, then 8-10min = 120s → total 420s
        # Tab B: 5-8min = 180s
        self.assertAlmostEqual(agg["safari_sec"]["Tab A"], 420, delta=1)
        self.assertAlmostEqual(agg["safari_sec"]["Tab B"], 180, delta=1)


# ==============================================================================
# 10. _extract_meeting_name
# ==============================================================================

class TestExtractMeetingName(unittest.TestCase):

    def test_person_name(self):
        title = "Florentin Rauscher | Kompakte Besprechungsansicht | Microsoft Teams"
        self.assertEqual(report._extract_meeting_name(title), "Florentin Rauscher")

    def test_meeting_name(self):
        title = "Sprint Planning | Kompakte Besprechungsansicht | Microsoft Teams"
        self.assertEqual(report._extract_meeting_name(title), "Sprint Planning")

    def test_no_call_indicator(self):
        title = "Chat | Microsoft Teams"
        self.assertIsNone(report._extract_meeting_name(title))

    def test_all_noise(self):
        title = "Microsoft Teams | Kompakte Besprechungsansicht | Calendar"
        self.assertIsNone(report._extract_meeting_name(title))


if __name__ == "__main__":
    unittest.main()
