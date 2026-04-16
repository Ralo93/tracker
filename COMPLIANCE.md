# WorkLogger — Compliance & Data Protection Review

This document lists all identified data protection, security, and corporate compliance concerns for WorkLogger, along with the mitigation status for each.

---

## 1. Data at Rest — No Encryption

**Concern:** JSONL log files and the configuration file are stored as plain text on disk. They contain window titles, URLs, app usage patterns, git commit messages, and manually entered task descriptions. If the device is lost, stolen, or accessed by another user, this data is exposed.

**Risk level:** Medium (mitigated by macOS FileVault if enabled)

**Mitigation:**
- [x] Restrict file permissions to owner-only (`chmod 600`) on all JSONL files and the config file
- [x] Document that FileVault full-disk encryption should be enabled (standard on managed corporate Macs)
- [ ] Future: Offer optional application-level encryption using a Keychain-derived key

---

## 2. Sensitive Data in URLs

**Concern:** Full URLs are logged in `app_switch` (Safari) and `safari_tab_change` events. These can contain:
- OAuth tokens and authorization codes (`?code=`, `access_token=`, `session_state=`)
- Client-specific portal paths (`/client/12345/documents/`)
- Internal application routes with identifiers
- SSO callback URLs with credentials

The existing `skipSafariContains` filter only suppresses the event *title* — the full URL is still written to the log.

**Risk level:** High

**Mitigation:**
- [x] Strip query strings and fragments from all logged URLs (remove everything after `?` or `#`)
- [x] Truncate URLs to domain-only by default (e.g. `https://portal.client.com/path` → `portal.client.com`)
- [x] Add a `logSafariURLs` config toggle (default `true`) to allow complete opt-out of URL logging
- [x] Add a `logSafariDomainOnly` config toggle (default `true`) to log only the domain portion

---

## 3. No Data Retention / Automatic Purge

**Concern:** Log files accumulate indefinitely with no automatic cleanup. Under GDPR Article 5(1)(e) (storage limitation), personal data should be kept only as long as necessary. Months or years of detailed activity logs exceed any reasonable retention period for time tracking purposes.

**Risk level:** Medium

**Mitigation:**
- [x] Add `retentionDays` config key (default: 90 days)
- [x] On every app launch, delete JSONL files older than the retention period
- [x] Document the retention policy in the privacy notice

---

## 4. No Access Controls

**Concern:** Log files are readable by any process running as the current user. There is no authentication to view, export, or modify logged data. Any other application on the system can read the JSONL files.

**Risk level:** Low-Medium (single-user context)

**Mitigation:**
- [x] Set file permissions to `0600` (owner read/write only) on JSONL files and config
- [x] Set directory permissions to `0700` on the log directory
- [x] Document that this is a single-user tool with no multi-user access model

---

## 5. Safari Tracking — Privacy Implications

**Concern:** Logging every Safari tab change with URL constitutes browser history monitoring. Even for self-tracking, this may conflict with corporate acceptable use policies if the data is stored unencrypted and could be subpoenaed or accessed during investigations.

**Risk level:** Medium

**Mitigation:**
- [x] Add `safariTrackingEnabled` config toggle (default `true`) to disable all Safari monitoring
- [x] Add `logSafariURLs` config toggle (default `true`) to log tab titles without URLs
- [x] Document the scope of Safari monitoring in the privacy notice
- [x] Apply domain-only URL logging by default

---

## 6. Window Title Capture — Potential Information Leakage

**Concern:** Window titles are captured for all applications via `CGWindowListCopyWindowInfo`. These titles may contain:
- Confidential document names (Word, Excel, PDF viewers)
- Email subject lines (Outlook)
- Chat message previews (Teams, Slack)
- Client names and project identifiers

All strings are truncated to 200 characters, but that is still sufficient to expose sensitive content.

**Risk level:** Medium

**Mitigation:**
- [x] Document which data is captured and why in the privacy notice
- [x] The existing `skipApps` filter allows excluding specific applications
- [x] The 200-character truncation limits exposure but does not eliminate it
- [x] First-launch consent dialog informs users exactly what is captured

---

## 7. No User Consent Mechanism

**Concern:** The app begins logging immediately on first launch with no explicit user consent. GDPR Article 7 and corporate data protection policies typically require informed, specific consent before processing personal data.

**Risk level:** High (for GDPR compliance)

**Mitigation:**
- [x] Add a first-launch consent dialog listing exactly what is tracked
- [x] Require explicit "I agree" before any logging begins
- [x] Provide a "What data does WorkLogger collect?" menu item accessible at any time
- [x] Create a PRIVACY.md documenting all data processing

---

## 8. Ad-hoc Code Signing

**Concern:** The app is signed with `--sign -` (ad-hoc, no developer identity). On managed corporate Macs:
- Gatekeeper may block execution
- MDM profiles (e.g. Jamf, Intune) may prevent unsigned apps from running
- PPPC (Privacy Preferences Policy Control) profiles may deny Accessibility/Screen Recording

**Risk level:** Medium (depends on MDM configuration)

**Mitigation:**
- [x] Document that a Developer ID certificate resolves this ($99/year Apple Developer Program)
- [x] Provide `make setup-cert` target for self-signed certificate as intermediate step
- [x] Document the Gatekeeper bypass for ad-hoc builds: `xattr -d com.apple.quarantine`
- [x] Note: If MDM blocks the app, it cannot be used without IT approval regardless

---

## 9. LaunchAgent for Auto-Start

**Concern:** The "Start at Login" feature writes a LaunchAgent plist to `~/Library/LaunchAgents/`. Corporate endpoint detection tools (CrowdStrike, Carbon Black, SentinelOne) may:
- Flag the creation of a new LaunchAgent as suspicious
- Alert the SOC (Security Operations Center)
- Quarantine or remove the plist

**Risk level:** Low

**Mitigation:**
- [x] Document the LaunchAgent behavior
- [x] The feature is opt-in (toggled by the user, not enabled by default)
- [x] The plist only calls `open WorkLogger.app` — no hidden scripts or elevated privileges

---

## 10. Screen Recording & Accessibility Permissions

**Concern:** The app requests two of the most sensitive macOS permissions:
- **Screen Recording** (`CGWindowListCopyWindowInfo`) — Allows reading all visible window content
- **Accessibility** — Allows reading and controlling UI elements system-wide

These permissions trigger alerts in corporate endpoint management systems and may require IT pre-approval via MDM profiles.

**Risk level:** Medium

**Mitigation:**
- [x] Document exactly why each permission is needed and what it is used for
- [x] The app only reads window *titles*, not screen content or pixel data
- [x] Accessibility is used solely for `CGWindowListCopyWindowInfo` and the global hotkey
- [ ] Provide a mode that works without Screen Recording (reduced functionality)

---

## 11. Git Commit Data in Reports

**Concern:** The report pipeline reads git commit messages and author information from configured repositories. Commit messages may reference:
- Client names or project codes
- JIRA/ticket identifiers
- Code review comments
- Co-author names

This data is included in the exported `.xlsx` file.

**Risk level:** Low (user controls which repos are configured)

**Mitigation:**
- [x] Repositories are explicitly configured by the user (not auto-discovered)
- [x] Commit messages are truncated in the report
- [x] Document that the report file should be treated as confidential

---

## 12. No Audit Trail

**Concern:** There is no log of who accessed, exported, or modified the data. If the app is used in a regulated environment, an audit trail may be required.

**Risk level:** Low (single-user tool)

**Mitigation:**
- [x] Document that this is a personal productivity tool, not a corporate monitoring system
- [x] The JSONL format is append-only by design (though files can be edited externally)
- [ ] The export action could optionally log an event to create a minimal audit trail

---

## 13. Data Portability & Deletion

**Concern:** GDPR Articles 17 (right to erasure) and 20 (right to data portability) require that users can delete their data and export it in a portable format.

**Risk level:** Low (user has direct file access)

**Mitigation:**
- [x] JSONL is an open, portable format — fully satisfies data portability
- [x] Users can delete their own log files at any time (file system access)
- [x] Automatic purge (retention policy) provides systematic deletion
- [x] Document the data location and deletion procedure
- [x] "Export All My Data…" menu item creates a zip archive of all JSONL files and config (Art. 15/20)
- [x] "Delete All My Data…" menu item with double confirmation erases all logs, config, and launch agent (Art. 17)

---

## 14. GDPR Rights Implementation

**Concern:** GDPR Articles 15–22 require specific data subject rights to be exercisable.

**Risk level:** Medium (if deployed in EU corporate context)

**Mitigation:**
- [x] **Art. 15 — Right of access:** "Export All My Data…" menu item creates zip of all JSONL + config
- [x] **Art. 16 — Right to rectification:** Retroactive Quick Log tab allows adding corrected entries; JSONL files editable in any text editor
- [x] **Art. 17 — Right to erasure:** "Delete All My Data…" with double confirmation; auto-purge of old logs
- [x] **Art. 18 — Right to restriction:** Safari toggle, skipApps config, quit app to stop all processing
- [x] **Art. 20 — Right to portability:** JSONL open format; zip export includes all data
- [x] **Art. 21 — Right to object:** Quit app, decline consent, or delete all data
- [x] **Art. 7(3) — Withdraw consent:** Delete config to reset consent; quit app at any time

---

## 15. GDPR Documentation

**Concern:** GDPR requires formal documentation: privacy notice (Art. 13/14), record of processing (Art. 30), and DPIA (Art. 35).

**Risk level:** Medium

**Mitigation:**
- [x] `PRIVACY.md` — Full Art. 13 privacy notice with lawful basis, rights, controller template, security measures
- [x] `ROPA.md` — Record of Processing Activities (Art. 30)
- [x] `DPIA.md` — Data Protection Impact Assessment (Art. 35) with risk assessment and mitigation
- [x] `COMPLIANCE.md` — This document, tracking all concerns and implementation status

---

## 16. Automated Test Coverage for Compliance Measures

**Concern:** Compliance controls (URL sanitization, file permissions, auto-purge, consent defaults, privacy-by-default) are only effective if they are verified continuously. Without automated testing, regressions could silently re-introduce data protection vulnerabilities.

**Risk level:** Medium

**Mitigation:**
- [x] **Swift test suite** (67 tests, 14 suites) validates all compliance controls: URL sanitization (domain-only, query stripping, token removal), file permissions (0600), auto-purge (retention boundary, edge cases), string truncation (200 chars), config privacy fields, consent mechanism, Safari toggles, log directory creation, privacy-by-default verification
- [x] **Python test suite** (39 tests, 6 suites) validates report pipeline: smart block aggregation, Teams chat/channel filtering (only calls logged individually), block grid helpers, description builder, manual entry extraction
- [x] **Build gate:** `make app` depends on `make test` — both suites must pass before a binary can be produced. No untested code ships.
- [x] Tests cover edge cases: exact retention boundary, zero/negative retention, empty directories, multi-field truncation, non-string field passthrough, encoded URLs, IP addresses, unicode domains

---

## Summary Matrix

| # | Concern | Risk | Status |
|---|---------|------|--------|
| 1 | Data at rest — no encryption | Medium | **Mitigated** (chmod 600, FileVault documented) |
| 2 | Sensitive data in URLs | High | **Resolved** (domain-only default, query stripping, toggles) |
| 3 | No data retention / purge | Medium | **Resolved** (90-day auto-purge on launch) |
| 4 | No access controls | Low-Med | **Mitigated** (chmod 600/700) |
| 5 | Safari tracking — privacy | Medium | **Resolved** (toggles, domain-only default) |
| 6 | Window title leakage | Medium | **Mitigated** (documented, consent, skipApps) |
| 7 | No user consent mechanism | High | **Resolved** (first-launch dialog, menu item) |
| 8 | Ad-hoc code signing | Medium | **Documented** |
| 9 | LaunchAgent auto-start | Low | **Documented** |
| 10 | Screen Recording & Accessibility | Medium | **Documented** |
| 11 | Git commit data in reports | Low | **Documented** |
| 12 | No audit trail | Low | **Documented** |
| 13 | Data portability & deletion | Low | **Resolved** (export zip, delete all, auto-purge) |
| 14 | GDPR rights implementation | Medium | **Resolved** (Art. 15–22 all implemented) |
| 15 | GDPR documentation | Medium | **Resolved** (PRIVACY.md, ROPA.md, DPIA.md) || 16 | Automated test coverage | Medium | **Resolved** (106 tests, build-gated) |