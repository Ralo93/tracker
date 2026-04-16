# WorkLogger — Data Protection Impact Assessment (DPIA)

*GDPR Article 35 — Data Protection Impact Assessment*

*Last updated: April 2026*

---

## 1. Overview

| Field | Value |
|-------|-------|
| **Processing activity** | WorkLogger — Personal Work Activity Tracking |
| **Controller** | [To be filled by deploying organization] |
| **DPO consulted** | [Yes/No — to be filled] |
| **Date of assessment** | [To be filled] |
| **Assessor** | [To be filled] |

---

## 2. Description of the Processing

### 2.1 Nature of Processing

WorkLogger is a macOS menu bar application that monitors the user's active application, window title, and optionally Safari tab/URL to generate a personal weekly timesheet. It logs events as JSONL files on the local file system.

### 2.2 Scope

| Dimension | Scope |
|-----------|-------|
| **Data subjects** | Individual user who installs and operates the application |
| **Volume** | ~500–2,000 events per working day per user |
| **Geography** | Local to user's Mac — no network transmission |
| **Duration** | Continuous during work hours; retention: 90 days (configurable) |

### 2.3 Context

- The tool is used for **personal time tracking** and **weekly timesheet generation**
- The user initiates and controls all processing
- No manager, employer, or third party has access to the data unless the user shares it
- If deployed by an organization, the employer–employee power dynamic must be considered (see Section 5)

### 2.4 Purpose

1. Accurately track which applications, projects, and tasks the user works on throughout the day
2. Generate a weekly Excel report with time slots, descriptions, and git commits
3. Provide manual entry capability for meetings and tasks not automatically detected

---

## 3. Necessity and Proportionality (Art. 35(7)(b))

### 3.1 Necessity

| Question | Assessment |
|----------|------------|
| Is this processing necessary for the stated purpose? | **Yes** — Automated activity tracking is the only practical way to produce accurate time reports without constant manual logging |
| Could the purpose be achieved with less data? | Partially — Window titles could be omitted, but this would significantly reduce report accuracy. Safari URLs are already minimized to domain-only |
| Is there a less intrusive alternative? | Manual-only time tracking exists but is far less accurate and imposes a greater burden on the user |

### 3.2 Proportionality

| Measure | Justification |
|---------|---------------|
| **Domain-only URLs** | Full URLs are unnecessary; domain identifies the web application used |
| **Query/fragment stripping** | Prevents accidental capture of tokens, session IDs, OAuth codes |
| **200-char truncation** | Limits exposure of long window titles |
| **Configurable skip lists** | Users can exclude specific apps and Safari patterns |
| **Safari opt-out** | Entire Safari monitoring can be disabled |
| **90-day auto-purge** | Data is not kept longer than necessary |
| **Consent before processing** | No data is written until explicit consent |

---

## 4. Risk Assessment (Art. 35(7)(c))

### 4.1 Risk Identification

| # | Risk | Likelihood | Severity | Overall |
|---|------|------------|----------|---------|
| R1 | Unauthorized access to log files by other local processes | Low | Medium | **Low** |
| R2 | Sensitive window titles captured (client names, email subjects) | Medium | Medium | **Medium** |
| R3 | Safari URLs leak OAuth tokens or client-specific paths | Low (mitigated) | High | **Low** |
| R4 | Device theft/loss exposes log data | Low | Medium | **Low** |
| R5 | Employer uses data for performance monitoring without consent | Low | High | **Medium** |
| R6 | Excessive data retention | Low (mitigated) | Low | **Low** |
| R7 | User unaware of what is being tracked | Low (mitigated) | Medium | **Low** |

### 4.2 Risk Assessment Detail

**R1 — Unauthorized local access**
- File permissions set to `0600` (owner-only read/write)
- Directory permissions set to `0700` (owner-only)
- Residual risk: root/sudo access can bypass file permissions → acceptable given single-user context

**R2 — Sensitive window titles**
- Window titles may contain document names, email subjects, or chat previews
- Mitigation: 200-character truncation, configurable `skipApps` filter
- Residual risk: Some sensitive titles will be captured → acceptable given data stays local and is auto-purged

**R3 — URL token leakage**
- Default: domain-only logging (`logSafariDomainOnly: true`)
- Even when full paths are logged, query strings and fragments are stripped
- `skipSafariContains` filter blocks known OAuth/SSO URL patterns
- Residual risk: negligible with default settings

**R4 — Device theft/loss**
- Relies on macOS FileVault for encryption at rest
- On managed corporate Macs, FileVault is typically enforced via MDM
- Residual risk: if FileVault is disabled, files are readable → document FileVault as a prerequisite

**R5 — Employer misuse for performance monitoring**
- Data is stored locally; employer cannot access without physical/remote access to the device
- If deployed organizationally, a clear policy must state this is for self-reporting only
- Residual risk: organizational measure, not technical → document in deployment guidelines

**R6 — Excessive retention**
- Auto-purge deletes logs older than `retentionDays` (default 90) on every launch
- "Delete All My Data…" menu item provides immediate complete erasure
- Residual risk: negligible

**R7 — Lack of transparency**
- First-launch consent dialog lists all tracked data categories
- "About WorkLogger Data…" menu item accessible at any time
- PRIVACY.md documents all processing in detail
- Residual risk: negligible

---

## 5. Measures to Mitigate Risks (Art. 35(7)(d))

| Risk | Measure | Type | Status |
|------|---------|------|--------|
| R1 | chmod 600/700 on all files and directories | Technical | ✅ Implemented |
| R2 | 200-char truncation, skipApps filter, consent dialog | Technical + Organizational | ✅ Implemented |
| R3 | Domain-only URL default, query stripping, Safari toggle | Technical | ✅ Implemented |
| R4 | Document FileVault requirement | Organizational | ✅ Documented |
| R5 | Document "self-reporting only" policy for org deployments | Organizational | ✅ Documented |
| R6 | Auto-purge, configurable retention, "Delete All My Data…" | Technical | ✅ Implemented |
| R7 | Consent dialog, "About" menu item, PRIVACY.md | Technical + Organizational | ✅ Implemented |

---

## 6. Consultation (Art. 35(9))

| Stakeholder | Consulted | Outcome |
|-------------|-----------|---------|
| Data subjects (users) | Yes — consent dialog on first launch | Consent required before processing |
| DPO | [To be filled by deploying organization] | — |
| Supervisory authority (Art. 36) | Not required — residual risks are acceptable after mitigation | — |

---

## 7. Decision

| Question | Answer |
|----------|--------|
| Are residual risks acceptable after mitigation? | **Yes** |
| Is prior consultation with supervisory authority required (Art. 36)? | **No** — No high residual risks remain |
| Should processing proceed? | **Yes**, with all documented measures in place |

---

## 8. Review Schedule

This DPIA should be reviewed:
- When new data categories are added to logging
- When the tool is deployed to users beyond the original scope
- When macOS permission models change significantly
- Annually as part of regular data protection review

---

## Appendix A: Related Documents

| Document | Purpose |
|----------|---------|
| `PRIVACY.md` | Full privacy notice (Art. 13/14) |
| `ROPA.md` | Record of Processing Activities (Art. 30) |
| `COMPLIANCE.md` | Technical compliance checklist with implementation status |
| `README.md` | User documentation and installation guide |
