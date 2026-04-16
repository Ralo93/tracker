# WorkLogger — Record of Processing Activities (ROPA)

*GDPR Article 30 — Record of Processing Activities*

*Last updated: April 2026*

---

## 1. Controller Information

| Field | Value |
|-------|-------|
| **Name of controller** | [To be filled by deploying organization] |
| **Contact details** | [To be filled by deploying organization] |
| **Data Protection Officer** | [If applicable — to be filled by deploying organization] |
| **EU Representative (Art. 27)** | Not applicable (local-only processing, no EU establishment issues) |

---

## 2. Processing Activity: Work Activity Tracking

| Field | Description |
|-------|-------------|
| **Name of processing activity** | WorkLogger — Personal Work Activity Tracking |
| **Purpose of processing** | Record daily work activities (application usage, project time, meetings, manual entries) for personal time tracking and weekly timesheet generation |
| **Categories of data subjects** | Individual users who install and operate the software on their own Mac |
| **Categories of personal data** | Application names, window titles, Safari tab names, Safari domains (URLs sanitized), idle/lock/sleep events, manual task descriptions, git commit messages |
| **Special categories (Art. 9)** | None processed |
| **Lawful basis** | Legitimate interest of the data subject (Art. 6(1)(f)) — accurate personal time tracking; Consent (Art. 6(1)(a)) — explicit first-launch consent dialog |

---

## 3. Data Recipients

| Recipient | Purpose | Safeguards |
|-----------|---------|------------|
| **None** | No data is transmitted to any third party, server, or cloud service | N/A |

The exported `.xlsx` report file is created locally. Any further sharing of that file is at the user's discretion and outside the scope of this processing activity.

---

## 4. International Transfers

| Transfer | Destination | Mechanism |
|----------|-------------|-----------|
| **None** | All processing is local to the user's Mac | N/A |

---

## 5. Retention Periods

| Data Category | Retention Period | Mechanism |
|---------------|------------------|-----------|
| Daily JSONL log files | **90 days** (configurable via `retentionDays`) | Automatic purge on every app launch |
| Configuration file | Indefinite (until user deletes or resets) | Manual deletion or "Delete All My Data…" |
| Exported reports (.xlsx) | At user's discretion | Not managed by WorkLogger |

---

## 6. Technical and Organizational Security Measures (Art. 32)

| Measure | Description |
|---------|-------------|
| **File permissions** | Log files: `0600` (owner read/write only); log directory: `0700` (owner only); config: `0600` |
| **Encryption at rest** | Relies on macOS FileVault full-disk encryption (standard on managed corporate Macs) |
| **Data minimization** | URLs logged as domain-only by default; all string values truncated to 200 characters; configurable skip lists for apps and Safari titles |
| **No network transmission** | Application makes zero network calls — no analytics, telemetry, cloud sync, or phone-home functionality |
| **Access control** | Single-user application; data accessible only to the macOS user account running the app |
| **Consent mechanism** | First-launch consent dialog with explicit "I Agree" required before any logging begins |
| **Automatic purging** | Logs exceeding retention period are deleted on every application launch |
| **User rights implementation** | "Export All My Data…" (Art. 15), "Delete All My Data…" (Art. 17), retroactive entry editing (Art. 16), configurable tracking toggles (Art. 18/21) |
| **Privacy by default** | Domain-only URL logging, Safari opt-out toggle, query/fragment stripping — all enabled by default |

---

## 7. Data Protection Impact Assessment

A separate DPIA document is maintained. See `DPIA.md`.

The processing is considered **low risk** because:
- The data subject is also the controller (self-monitoring)
- No special categories of data are processed
- No automated decision-making or profiling occurs
- No data leaves the local device
- Data is automatically purged after a defined retention period

---

## 8. Changes to This Record

This record should be reviewed and updated when:
- New categories of personal data are collected
- The purpose of processing changes
- The tool is deployed to additional users within an organization
- Security measures are modified
