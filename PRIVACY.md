# WorkLogger — Privacy Notice

*Last updated: April 2026*

This privacy notice is provided in accordance with the EU General Data Protection Regulation (GDPR), specifically Articles 13 and 14, to inform data subjects about the processing of their personal data.

---

## 1. Identity and Contact Details of the Controller

WorkLogger is a personal productivity tool operated by the individual user who installs and runs it. The user is both the **data controller** and the **data subject**.

When deployed within an organization, the deploying entity (e.g. the team lead or the organization itself) should be identified as the controller. Contact details should be provided by the deploying organization.

> **Template:** \
> Controller: [Your name / Organization name] \
> Contact: [Email address] \
> Data Protection Officer (if applicable): [DPO contact]

---

## 2. Purpose and Lawful Basis (Art. 6)

| Purpose | Lawful Basis | Justification |
|---------|-------------|---------------|
| Track active applications and window titles | Legitimate interest (Art. 6(1)(f)) | User's own interest in accurate personal time tracking |
| Log Safari tab activity | Legitimate interest + Consent | Optional feature, disabled via config toggle; explicit consent on first launch |
| Detect idle periods, screen lock, sleep/wake | Legitimate interest (Art. 6(1)(f)) | Accurately delimit work sessions |
| Store manual task entries | Consent (Art. 6(1)(a)) | User voluntarily creates entries |
| Read git commit history | Legitimate interest (Art. 6(1)(f)) | Enrich weekly time report with work output |
| Generate weekly Excel report | Legitimate interest (Art. 6(1)(f)) | Purpose of the tool — produce a time tracking report |

**Note on consent in employment context:** If an employer or manager requires team members to use WorkLogger, consent may not be freely given (Recital 43). In such cases, legitimate interest of the employee (accurate self-reporting) is the primary lawful basis. A Legitimate Interest Assessment (LIA) should be documented by the organization.

---

## 3. What Data Is Collected

| Data Type | Source | Purpose |
|-----------|--------|---------|
| Active application name | macOS workspace notifications | Track which apps you use and when |
| Window titles | CGWindowListCopyWindowInfo | Identify what you're working on (document names, email subjects, etc.) |
| VS Code project name | Window title parsing | Track project-level time in VS Code |
| Safari tab names | AppleScript automation | Track web-based work activities |
| Safari URLs | AppleScript automation | Identify visited sites (domain only by default) |
| Idle start/end | CGEventSource idle time | Detect breaks and inactive periods |
| Screen lock/unlock | Distributed notifications | Detect breaks and away-from-desk periods |
| Sleep/wake | Workspace notifications | Detect system sleep periods |
| Manual entries | User input | User-created task descriptions with time and duration |
| Git commits | Local git repositories | Enrich weekly report with commit details (report generation only) |

### What Is NOT Collected

- Screen content, screenshots, or pixel data
- Keystrokes or keyboard input (beyond idle detection)
- Clipboard contents
- Network traffic or browsing history beyond the active Safari tab
- Audio, video, or microphone data
- Data from other users on shared Macs

---

## 4. Recipients and Third-Party Sharing

**None.** WorkLogger does not transmit data over the network. There are no third-party recipients, no analytics services, no telemetry, and no cloud storage. All data remains exclusively on the local file system.

The exported `.xlsx` report is created locally and saved to a user-chosen location. The user controls any subsequent sharing of this file.

---

## 5. Data Transfers Outside the EU/EEA

**None.** All processing occurs locally on the user's Mac. No data is transferred to any server, domestic or international.

---

## 6. Where Data Is Stored

| File | Location | Permissions |
|------|----------|-------------|
| Daily log files | `~/Documents/WorkLogger/logs/YYYY-MM-DD.jsonl` (configurable) | `0600` (owner read/write only) |
| Configuration | `~/Library/Application Support/WorkLogger/config.json` | `0600` (owner read/write only) |
| Log directory | `~/Documents/WorkLogger/logs/` (configurable) | `0700` (owner only) |
| Exported reports | User-chosen location via Save dialog | Inherits user's default permissions |

Log files are in JSONL format (one JSON object per line), an open standard that can be read by any text editor.

---

## 7. Data Retention (Art. 5(1)(e))

- Logs are automatically deleted after **90 days** (configurable via `retentionDays` in config)
- Purging runs on every app launch
- You can manually delete any log file at any time — they are plain files on your disk
- Set `retentionDays` to a lower value for stricter retention
- The "Delete All My Data…" menu item erases all logs, configuration, and launch agent in one action

---

## 8. Your Rights (Art. 15–22)

As the data subject, you have the following rights under GDPR:

| Right | Article | How to Exercise |
|-------|---------|-----------------|
| **Right of access** | Art. 15 | Menu bar → "Export All My Data…" creates a zip of all JSONL log files and configuration |
| **Right to rectification** | Art. 16 | Use the "Retroactive" tab in Quick Log to add corrected entries; edit JSONL files directly in any text editor |
| **Right to erasure** | Art. 17 | Menu bar → "Delete All My Data…" permanently erases all logs, config, and launch agent. Individual files can also be deleted from the log directory |
| **Right to restriction** | Art. 18 | Disable Safari tracking, reduce `skipApps`, or quit the application to stop processing |
| **Right to data portability** | Art. 20 | JSONL is an open, portable format readable by Python, JavaScript, Excel, and any text editor. "Export All My Data…" provides a complete archive |
| **Right to object** | Art. 21 | Quit the application. Decline consent on first launch. Use "Delete All My Data…" to erase and stop |
| **Right to withdraw consent** | Art. 7(3) | Quit the application at any time. Delete config to reset consent status |

**Supervisory authority:** If you believe your data protection rights have been violated, you have the right to lodge a complaint with your national supervisory authority. In Germany: [Bundesbeauftragter für den Datenschutz (BfDI)](https://www.bfdi.bund.de/).

---

## 9. Privacy Controls

The following settings in `config.json` (or Settings → Advanced) control data collection:

| Setting | Default | Effect |
|---------|---------|--------|
| `safariTrackingEnabled` | `true` | Set to `false` to completely disable Safari tab and URL monitoring |
| `logSafariURLs` | `true` | Set to `false` to log tab names but not URLs |
| `logSafariDomainOnly` | `true` | When `true`, only the domain is logged (e.g. `github.com` instead of the full URL). Query strings and fragments are always stripped |
| `retentionDays` | `90` | Number of days to keep log files before automatic deletion |
| `skipApps` | (list) | App names excluded from activity descriptions in reports |

---

## 10. URL Sanitization

By default (`logSafariDomainOnly: true`), Safari URLs are reduced to the domain name only:
- `https://portal.client.com/project/12345/docs?token=abc` → `portal.client.com`

If `logSafariDomainOnly` is set to `false` but `logSafariURLs` is `true`, queries and fragments are still stripped:
- `https://github.com/org/repo/pull/42?diff=split#discussion` → `https://github.com/org/repo/pull/42`

OAuth tokens, authorization codes, session IDs, and similar sensitive URL parameters are never persisted.

---

## 11. User Consent (Art. 7)

On first launch, WorkLogger displays a consent dialog explaining what data is collected and requires explicit agreement ("I Agree") before any logging begins. The consent status is stored in the configuration file (`consentGiven: true`). If consent is declined, the app exits immediately without writing any data.

Consent can be withdrawn at any time by:
1. Quitting the application
2. Deleting the configuration file (resets consent)
3. Using "Delete All My Data…" from the menu bar

A "About WorkLogger Data…" menu item is always accessible from the menu bar, showing current data collection settings and storage locations.

---

## 12. Security Measures (Art. 32)

| Measure | Implementation |
|---------|---------------|
| File permissions | Log files: `0600`, log directory: `0700`, config: `0600` (owner-only) |
| Encryption at rest | Relies on macOS FileVault (full-disk encryption, standard on managed corporate Macs) |
| Data minimization | URLs logged as domain-only by default; all strings truncated to 200 characters |
| No network transmission | Zero network calls — no analytics, telemetry, or cloud sync |
| Automatic purging | Logs older than retention period deleted on every launch |
| Access control | Single-user tool; no multi-user access, no shared accounts |

---

## 13. macOS Permissions

WorkLogger requests these system permissions:

| Permission | Why It's Needed | What It Does |
|------------|-----------------|-------------|
| **Accessibility** | Read window titles via CGWindowList; global Cmd+Shift+L hotkey | Only reads window *names*, not content |
| **Screen Recording** | macOS requires this for CGWindowListCopyWindowInfo | Only reads window *titles*, not screen pixels |
| **Automation (Safari)** | Read the active tab name and URL | Only reads the current tab, not history |

---

## 14. Privacy by Design and Default (Art. 25)

WorkLogger implements privacy by design through:

- **Domain-only URL logging** enabled by default (not full URLs)
- **Query/fragment stripping** on all URLs (prevents token leakage)
- **Configurable Safari opt-out** (can disable all Safari tracking)
- **First-launch consent** required before any data is written
- **Auto-purge** of old logs (90-day default retention)
- **Owner-only file permissions** (chmod 600/700)
- **No network communication** whatsoever
- **200-character truncation** on all logged string values
- **Complete data export and deletion** accessible from the menu bar
