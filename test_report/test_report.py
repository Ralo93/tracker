#!/usr/bin/env python3
"""
Tests for report.py — smart aggregation, Teams filtering, block helpers.

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

BM = report.BLOCK_MINUTES  # actual config-driven block size


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
    """Build a minimal aggregation dict for make_rows()."""
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


# ==============================================================================
# 1. Smart Aggregation — Multi-Block Manual Entry Distribution
# ==============================================================================

class TestSmartAggregation(unittest.TestCase):

    def test_single_block_no_split(self):
        """A manual entry that fits in one block should NOT be split."""
        entry = _make_manual("Task A | Task B", "2026-04-13", "10:00", BM)
        rows = report.make_rows([], [entry])
        manual = [r for r in rows if "Manual:" in r.get("Beschreibung", "")]
        self.assertEqual(len(manual), 1, "Single block should produce 1 row")
        self.assertIn("Task A", manual[0]["Beschreibung"])
        self.assertIn("Task B", manual[0]["Beschreibung"])

    def test_two_blocks_two_segments(self):
        """Two pipe-segments across two blocks → one segment per block."""
        entry = _make_manual("Task A | Task B", "2026-04-13", "10:00", BM * 2)
        rows = report.make_rows([], [entry])
        manual = [r for r in rows if r.get("Beschreibung", "") not in ("", "—")]
        self.assertEqual(len(manual), 2)
        self.assertIn("Task A", manual[0]["Beschreibung"])
        self.assertIn("Task B", manual[1]["Beschreibung"])

    def test_six_segments_three_blocks(self):
        """6 segments / 3 blocks → round-robin: 2 per block."""
        desc = "A | B | C | D | E | F"
        entry = _make_manual(desc, "2026-04-13", "10:00", BM * 3)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "—")],
            key=lambda r: r["Von"]
        )
        self.assertEqual(len(manual), 3)
        # Block 0: A, D  |  Block 1: B, E  |  Block 2: C, F
        self.assertIn("A", manual[0]["Beschreibung"])
        self.assertIn("D", manual[0]["Beschreibung"])
        self.assertIn("B", manual[1]["Beschreibung"])
        self.assertIn("E", manual[1]["Beschreibung"])
        self.assertIn("C", manual[2]["Beschreibung"])
        self.assertIn("F", manual[2]["Beschreibung"])

    def test_more_blocks_than_segments(self):
        """3 blocks but only 2 segments → 2 blocks get content, 1 gets dash."""
        entry = _make_manual("Task A | Task B", "2026-04-13", "10:00", BM * 3)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung") is not None],
            key=lambda r: r["Von"]
        )
        self.assertEqual(len(manual), 3)
        self.assertIn("Task A", manual[0]["Beschreibung"])
        self.assertIn("Task B", manual[1]["Beschreibung"])
        self.assertEqual(manual[2]["Beschreibung"], "—")

    def test_single_segment_multi_block_no_split(self):
        """A single topic spanning 2 blocks should NOT be split."""
        entry = _make_manual("Just one task", "2026-04-13", "10:00", BM * 2)
        rows = report.make_rows([], [entry])
        manual = [r for r in rows if "Manual:" in r.get("Beschreibung", "")]
        self.assertEqual(len(manual), 1, "Single segment → single row, no split")
        self.assertIn("Just one task", manual[0]["Beschreibung"])

    def test_block_times_are_correct(self):
        """Verify start/end times of split blocks are contiguous."""
        entry = _make_manual("A | B | C", "2026-04-13", "10:00", BM * 3)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "\u2014")],
            key=lambda r: r["Von"]
        )
        self.assertEqual(manual[0]["Von"], "10:00")
        self.assertEqual(manual[0]["Bis"], f"{10:02d}:{BM:02d}")
        self.assertEqual(manual[1]["Von"], f"{10:02d}:{BM:02d}")
        self.assertEqual(manual[1]["Bis"], f"{10 + (BM * 2) // 60:02d}:{(BM * 2) % 60:02d}")
        self.assertEqual(manual[2]["Von"], f"{10 + (BM * 2) // 60:02d}:{(BM * 2) % 60:02d}")
        self.assertEqual(manual[2]["Bis"], f"{10 + (BM * 3) // 60:02d}:{(BM * 3) % 60:02d}")

    def test_segments_with_whitespace_trimmed(self):
        """Pipe-separated segments should have whitespace trimmed."""
        entry = _make_manual("  Task A  |  Task B  ", "2026-04-13", "10:00", BM * 2)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "—")],
            key=lambda r: r["Von"]
        )
        self.assertEqual(len(manual), 2)
        self.assertEqual(manual[0]["Beschreibung"], "Task A")
        self.assertEqual(manual[1]["Beschreibung"], "Task B")

    def test_empty_pipe_segments_ignored(self):
        """Empty segments between pipes should be filtered out."""
        entry = _make_manual("A || B |  | C", "2026-04-13", "10:00", BM * 3)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "—")],
            key=lambda r: r["Von"]
        )
        # 3 real segments across 3 blocks
        self.assertEqual(len(manual), 3)
        self.assertIn("A", manual[0]["Beschreibung"])
        self.assertIn("B", manual[1]["Beschreibung"])
        self.assertIn("C", manual[2]["Beschreibung"])

    def test_snap_to_block_grid(self):
        """Entry at 10:17 should snap down to nearest block boundary."""
        entry = _make_manual("A | B", "2026-04-13", "10:17", BM * 2)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "\u2014")],
            key=lambda r: r["Von"]
        )
        # Should snap down to the block boundary at or before 10:17
        snapped = report.round_down(datetime(2026, 4, 13, 10, 17), BM)
        self.assertEqual(manual[0]["Von"], snapped.strftime("%H:%M"))

    def test_real_world_description(self):
        """The exact kind of description the user creates via Quick Log."""
        desc = (
            "PR Evaluation Pipeline DÜB | Teams: Florentin Rauscher (DE) | "
            "Teams: KI@BMF Dev | Teams: PM-Chatgruppe | Teams: Sven Metscher (DE) | "
            "COMMIT [GPT4Gov-Doc_Translation]: deleted redundant old testfiles | "
            "WorkLogger (57min) | GPT4Gov-Doc_Translation (23min) | "
            "Code (1h02m) | Safari (52min) | Microsoft Teams (6min) | "
            "Microsoft Word (5min) | Web: Confirmation request"
        )
        segments = [s.strip() for s in desc.split("|") if s.strip()]
        num_blocks = len(segments)  # enough blocks to hold all segments
        entry = _make_manual(desc, "2026-04-13", "10:00", BM * num_blocks)
        rows = report.make_rows([], [entry])
        manual = sorted(
            [r for r in rows if r.get("Beschreibung", "") not in ("", "—")],
            key=lambda r: r["Von"]
        )
        self.assertEqual(len(manual), num_blocks)
        # Every block should have content, not full description repeated
        for row in manual:
            self.assertNotEqual(row["Beschreibung"], desc,
                                "No block should contain the full original description")
        # Total segments across all blocks should equal original segment count
        all_segs = []
        for row in manual:
            all_segs.extend([s.strip() for s in row["Beschreibung"].split("|")])
        self.assertEqual(len(all_segs), len(segments))


# ==============================================================================
# 2. Teams Filtering — Only Calls/Meetings
# ==============================================================================

class TestTeamsFiltering(unittest.TestCase):

    def test_meeting_included(self):
        """Teams window with Kompakte Besprechungsansicht = actual call."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "Florentin Rauscher | Kompakte Besprechungsansicht | Microsoft Teams"
        ])
        desc = report.build_description(agg)
        self.assertIn("Meetings:", desc)
        self.assertIn("• Florentin Rauscher", desc)

    def test_chat_excluded(self):
        """Teams window that is just a chat should NOT appear individually."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "KI@BMF Dev | Chat | Microsoft Teams"
        ])
        desc = report.build_description(agg)
        self.assertNotIn("Teams: KI@BMF Dev", desc)
        self.assertNotIn("KI@BMF Dev", desc)

    def test_channel_excluded(self):
        """Teams channel window should NOT appear individually."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "PM-Chatgruppe | Microsoft Teams"
        ])
        desc = report.build_description(agg)
        self.assertNotIn("Teams: PM-Chatgruppe", desc)
        self.assertNotIn("PM-Chatgruppe", desc)

    def test_mixed_chat_and_meeting(self):
        """Only the meeting should appear, not the chat."""
        agg = _make_agg("2026-04-13", "09:00", "10:00", teams=[
            "KI@BMF Dev | Chat | Microsoft Teams",
            "Sven Metscher | Kompakte Besprechungsansicht | Microsoft Teams",
            "PM-Chatgruppe | Microsoft Teams",
        ])
        desc = report.build_description(agg)
        self.assertIn("• Sven Metscher", desc)
        self.assertNotIn("KI@BMF Dev", desc)
        self.assertNotIn("PM-Chatgruppe", desc)

    def test_teams_app_time_still_shown(self):
        """Teams should still appear in the app time summary if ≥5min."""
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        teams=["Chat stuff | Microsoft Teams"],
                        app_sec={"Microsoft Teams": 600})
        desc = report.build_description(agg)
        # Chat not listed individually, but app time IS shown
        self.assertIn("Microsoft Teams (10min)", desc)

    def test_no_teams_entries_produces_empty(self):
        """No teams windows → no teams in description."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[])
        desc = report.build_description(agg)
        self.assertNotIn("Meetings:", desc)
        self.assertNotIn("Teams:", desc)

    def test_meeting_with_only_noise_segments(self):
        """Meeting whose segments are all noise → should be skipped."""
        agg = _make_agg("2026-04-13", "09:00", "09:30", teams=[
            "Microsoft Teams | Kompakte Besprechungsansicht | Calendar"
        ])
        desc = report.build_description(agg)
        # All meaningful segments filtered → no Meetings group at all
        self.assertNotIn("Meetings:", desc)


# ==============================================================================
# 3. Round-to-Block Helpers
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
# 4. build_description Edge Cases
# ==============================================================================

class TestBuildDescription(unittest.TestCase):

    def test_empty_agg_returns_dash(self):
        agg = _make_agg("2026-04-13", "09:00", "09:30")
        desc = report.build_description(agg)
        self.assertEqual(desc, "—")

    def test_commits_shown(self):
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        commits=[{"repo": "MyApp", "msg": "fix bug", "sha": "abc123", "ts": datetime(2026, 4, 13, 9, 15)}])
        desc = report.build_description(agg)
        self.assertIn("Commits:", desc)
        self.assertIn("• [MyApp] fix bug", desc)

    def test_vscode_projects_shown(self):
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        proj_sec={"MyProject": 900})
        desc = report.build_description(agg)
        self.assertIn("VS Code:", desc)
        self.assertIn("• MyProject (15min)", desc)

    def test_vscode_projects_under_threshold_hidden(self):
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        proj_sec={"MyProject": 200})
        desc = report.build_description(agg)
        self.assertNotIn("MyProject", desc)

    def test_safari_tabs_shown(self):
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["GitHub Pull Request #42", "Jira Board"])
        desc = report.build_description(agg)
        self.assertIn("Web:", desc)
        self.assertIn("GitHub Pull Request #42", desc)

    def test_safari_max_five(self):
        tabs = [f"Tab {i}" for i in range(10)]
        agg = _make_agg("2026-04-13", "09:00", "10:00", safari=tabs)
        desc = report.build_description(agg)
        # Only first 5
        self.assertIn("Tab 4", desc)
        self.assertNotIn("Tab 5", desc)

    def test_manual_entry_in_agg(self):
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        manual_entries=[{"description": "Quick task"}])
        desc = report.build_description(agg)
        self.assertIn("Manual:", desc)
        self.assertIn("• Quick task", desc)


# ==============================================================================
# 5. extract_manual_entries
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
# 6. _fmt helper
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
# 7. Safari time accumulation
# ==============================================================================

class TestSafariTimeAccumulation(unittest.TestCase):

    def setUp(self):
        """Save original value and enable Safari time for these tests."""
        self._orig = report.SHOW_SAFARI_TIME

    def tearDown(self):
        report.SHOW_SAFARI_TIME = self._orig

    def test_time_shown_when_enabled(self):
        report.SHOW_SAFARI_TIME = True
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["Azure DevOps", "GitHub"],
                        safari_sec={"Azure DevOps": 720, "GitHub": 300})
        desc = report.build_description(agg)
        self.assertIn("• Azure DevOps (12min)", desc)
        self.assertIn("• GitHub (5min)", desc)

    def test_time_hidden_when_disabled(self):
        report.SHOW_SAFARI_TIME = False
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["Azure DevOps", "GitHub"],
                        safari_sec={"Azure DevOps": 720, "GitHub": 300})
        desc = report.build_description(agg)
        self.assertIn("Azure DevOps", desc)
        self.assertNotIn("12min", desc)

    def test_sorted_by_time_descending(self):
        report.SHOW_SAFARI_TIME = True
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["Low", "High", "Mid"],
                        safari_sec={"Low": 60, "High": 900, "Mid": 300})
        desc = report.build_description(agg)
        # Find the Web: group
        self.assertIn("Web:", desc)
        self.assertIn("• High (15min)", desc)
        # High should appear before Mid
        high_pos = desc.index("High")
        mid_pos = desc.index("Mid")
        self.assertLess(high_pos, mid_pos)

    def test_short_tabs_no_duration_label(self):
        """Tabs with <30s active time should show name only, no duration."""
        report.SHOW_SAFARI_TIME = True
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["QuickTab"],
                        safari_sec={"QuickTab": 15})
        desc = report.build_description(agg)
        self.assertIn("QuickTab", desc)
        self.assertNotIn("0min", desc)

    def test_max_five_tabs_with_time(self):
        report.SHOW_SAFARI_TIME = True
        tabs = [f"Tab{i}" for i in range(10)]
        secs = {f"Tab{i}": 600 - i * 50 for i in range(10)}
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=tabs, safari_sec=secs)
        desc = report.build_description(agg)
        self.assertIn("Tab0", desc)
        self.assertIn("Tab4", desc)
        self.assertNotIn("Tab5", desc)

    def test_skip_filters_still_apply(self):
        report.SHOW_SAFARI_TIME = True
        agg = _make_agg("2026-04-13", "09:00", "10:00",
                        safari=["Start Page", "Real Tab"],
                        safari_sec={"Start Page": 600, "Real Tab": 300})
        desc = report.build_description(agg)
        self.assertNotIn("Start Page", desc)
        self.assertIn("Real Tab", desc)

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


if __name__ == "__main__":
    unittest.main()
