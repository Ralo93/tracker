#!/usr/bin/env python3
"""Generiert ein .docx Compliance-Review-Dokument auf Deutsch für Manager/Legal."""

from docx import Document
from docx.shared import Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from pathlib import Path

ROOT = Path(__file__).parent.parent

def add_heading(doc, text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
    return h

def add_para(doc, text, bold=False, italic=False, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.bold = bold
    run.italic = italic
    return p

def add_bullet(doc, text, size=11):
    p = doc.add_paragraph(text, style="List Bullet")
    for run in p.runs:
        run.font.size = Pt(size)
    return p

def add_table(doc, headers, rows):
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = "Light Grid Accent 1"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, h in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = h
        for p in cell.paragraphs:
            for run in p.runs:
                run.bold = True
                run.font.size = Pt(10)
    for r_idx, row in enumerate(rows):
        for c_idx, val in enumerate(row):
            cell = table.rows[r_idx + 1].cells[c_idx]
            cell.text = str(val)
            for p in cell.paragraphs:
                for run in p.runs:
                    run.font.size = Pt(10)
    return table

def build_doc():
    doc = Document()
    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    # ══════════════════════════════════════════════════════════════════════
    # TITELSEITE
    # ══════════════════════════════════════════════════════════════════════
    doc.add_paragraph()
    title = doc.add_heading("WorkLogger", level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in title.runs:
        run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
        run.font.size = Pt(28)

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run("Datenschutz- & Compliance-Prüfung\nfür Legal / Compliance Assessment")
    run.font.size = Pt(16)
    run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    doc.add_paragraph()
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = meta.add_run("April 2026\nErstellt für PwC Compliance & Legal Team")
    run.font.size = Pt(12)
    run.italic = True

    doc.add_paragraph()
    add_para(doc,
        "Dieses Dokument bietet einen umfassenden Überblick über die WorkLogger-Anwendung, "
        "ihre Datenverarbeitungstätigkeiten, Datenschutzkontrollen, DSGVO-Konformitätsmaßnahmen "
        "und Risikobewertung — zur Prüfung durch das Legal- und Compliance-Team von PwC.",
        size=11)

    doc.add_page_break()

    # ══════════════════════════════════════════════════════════════════════
    # INHALTSVERZEICHNIS
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "Inhaltsverzeichnis", level=1)
    toc = [
        "1. Zusammenfassung",
        "2. Anwendungsübersicht",
        "3. Datenverarbeitungstätigkeiten",
        "4. Datenkategorien & Erhebung",
        "5. Datenschutzeinstellungen",
        "6. DSGVO-Konformitätsmaßnahmen",
        "7. Betroffenenrechte (Art. 15–22)",
        "8. Technische & organisatorische Maßnahmen (Art. 32)",
        "9. Risikobewertung & Mitigationen",
        "10. Testabdeckung & Qualitätssicherung",
        "11. Deployment & Verteilung",
        "12. Empfehlungen für Legal/Compliance",
        "Anhang A — Verzeichnis von Verarbeitungstätigkeiten (VVT)",
        "Anhang B — Datenschutz-Folgenabschätzung (DSFA)",
    ]
    for item in toc:
        add_para(doc, item, size=11)
    doc.add_page_break()

    # ══════════════════════════════════════════════════════════════════════
    # 1. ZUSAMMENFASSUNG
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "1. Zusammenfassung", level=1)
    add_para(doc,
        "WorkLogger ist eine leichtgewichtige macOS-Menüleisten-Anwendung zur persönlichen "
        "Arbeitszeiterfassung. Sie protokolliert Anwendungsnutzung, Fenstertitel, Safari-Tab-Wechsel, "
        "Leerlaufzeiten und manuelle Aufgabeneinträge als lokale JSONL-Dateien. Ein Python-basierter "
        "Reportgenerator erstellt wöchentliche Excel-Timesheets, angereichert mit Git-Commits aus "
        "konfigurierten Repositories.")
    add_para(doc, "Zentrale Compliance-Eigenschaften:")
    bullets = [
        "Alle Daten werden ausschließlich lokal auf dem Mac des Nutzers verarbeitet und gespeichert — kein Netzwerkverkehr, kein Cloud-Speicher, keine Drittanbieter-Dienste",
        "DSGVO-Konformität umgesetzt: Einwilligungsdialog beim ersten Start, automatische Löschung (Standard: 90 Tage), Domain-only URL-Logging, Dateiberechtigungen (chmod 600/700), Datenexport und -löschung über Menüleiste",
        "Privacy by Design und Default (Art. 25): restriktivste Einstellungen standardmäßig aktiviert",
        "Vollständige DSGVO-Dokumentation: Datenschutzhinweise (Art. 13), VVT (Art. 30), DSFA (Art. 35)",
        "Umfassende automatisierte Testabdeckung (113 Tests) als Build-Gate — kein ungetesteter Code wird ausgeliefert",
        "Open-Source-Quellcode zur Prüfung verfügbar unter https://github.com/Ralo93/tracker",
    ]
    for b in bullets:
        add_bullet(doc, b)

    # ══════════════════════════════════════════════════════════════════════
    # 2. ANWENDUNGSÜBERSICHT
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "2. Anwendungsübersicht", level=1)
    add_table(doc,
        ["Eigenschaft", "Wert"],
        [
            ["Anwendungsname", "WorkLogger"],
            ["Plattform", "macOS (13+ Ventura oder neuer)"],
            ["Sprache", "Swift (App) + Python (Reportgenerator)"],
            ["Verteilung", "Build aus Quellcode via Swift Package Manager"],
            ["Code-Signierung", "Ad-hoc (selbstsigniert) — kein Apple Developer ID"],
            ["Netzwerkzugriff", "Keiner — null Netzwerkaufrufe"],
            ["Quellcode", "https://github.com/Ralo93/tracker"],
            ["Lizenz", "Intern / noch festzulegen"],
        ])
    add_para(doc, "")
    add_heading(doc, "Funktionsweise", level=2)
    add_para(doc,
        "WorkLogger läuft als Menüleisten-Icon (\"WL\") und überwacht Anwendungswechsel, "
        "VS-Code-Projektwechsel, Safari-Tab-Änderungen sowie Leerlauf-/Sperr-/Schlafzustände. "
        "Jedes Ereignis wird an eine tägliche JSONL-Logdatei angehängt. Nutzer können manuelle "
        "Einträge über einen globalen Hotkey (Cmd+Shift+L) hinzufügen. Ein wöchentlicher "
        "Excel-Report kann über die Menüleiste oder Kommandozeile generiert werden.")

    # ══════════════════════════════════════════════════════════════════════
    # 3. DATENVERARBEITUNGSTÄTIGKEITEN
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "3. Datenverarbeitungstätigkeiten", level=1)
    add_table(doc,
        ["Tätigkeit", "Rechtsgrundlage", "Begründung"],
        [
            ["Aktive Anwendungen und Fenstertitel erfassen", "Berechtigtes Interesse (Art. 6(1)(f))", "Eigenes Interesse des Nutzers an genauer persönlicher Zeiterfassung"],
            ["Safari-Tab-Aktivität protokollieren", "Berechtigtes Interesse + Einwilligung", "Optionale Funktion, konfigurierbar über Schalter; explizite Einwilligung beim ersten Start"],
            ["Leerlaufzeiten, Bildschirmsperre, Schlaf/Wach erkennen", "Berechtigtes Interesse (Art. 6(1)(f))", "Genaue Abgrenzung von Arbeitssitzungen"],
            ["Manuelle Aufgabeneinträge speichern", "Einwilligung (Art. 6(1)(a))", "Nutzer erstellt Einträge freiwillig"],
            ["Git-Commit-Verlauf lesen", "Berechtigtes Interesse (Art. 6(1)(f))", "Wochenreport mit Arbeitsergebnissen anreichern"],
            ["Wöchentlichen Excel-Report erstellen", "Berechtigtes Interesse (Art. 6(1)(f))", "Zweck des Tools — Zeiterfassungsreport erstellen"],
        ])
    add_para(doc, "")
    add_para(doc,
        "Hinweis zum Einwilligungskontext im Arbeitsverhältnis: Wenn ein Arbeitgeber oder Vorgesetzter "
        "die Nutzung von WorkLogger anordnet, kann die Einwilligung möglicherweise nicht frei erteilt "
        "werden (DSGVO Erwägungsgrund 43). In diesem Fall ist das berechtigte Interesse des Arbeitnehmers "
        "(genaue Selbstdokumentation) die primäre Rechtsgrundlage. Eine Interessenabwägung (LIA) sollte "
        "von der Organisation dokumentiert werden.",
        italic=True, size=10)

    # ══════════════════════════════════════════════════════════════════════
    # 4. DATENKATEGORIEN
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "4. Datenkategorien & Erhebung", level=1)
    add_heading(doc, "Was wird erfasst", level=2)
    add_table(doc,
        ["Datentyp", "Quelle", "Zweck"],
        [
            ["Aktiver Anwendungsname", "macOS Workspace-Benachrichtigungen", "Erfassen, welche Apps wann genutzt werden"],
            ["Fenstertitel", "CGWindowListCopyWindowInfo", "Identifizieren, woran der Nutzer arbeitet"],
            ["VS-Code-Projektname", "Fenstertitel-Parsing", "Projektbasierte Zeiterfassung in VS Code"],
            ["Safari-Tab-Namen", "AppleScript-Automatisierung", "Webbasierte Arbeitstätigkeiten erfassen"],
            ["Safari-URLs", "AppleScript-Automatisierung", "Besuchte Seiten identifizieren (standardmäßig nur Domain)"],
            ["Leerlauf Start/Ende", "CGEventSource Idle-Time", "Pausen und inaktive Zeiträume erkennen"],
            ["Bildschirmsperre/-entsperrung", "Distributed Notifications", "Pausenzeiträume erkennen"],
            ["Schlaf/Aufwachen", "Workspace Notifications", "Systemschlafphasen erkennen"],
            ["Manuelle Einträge", "Nutzereingabe", "Vom Nutzer erstellte Aufgabenbeschreibungen mit Zeit und Dauer"],
            ["Git-Commits", "Lokale Git-Repos (nur Report)", "Report mit Commit-Details anreichern"],
        ])
    add_para(doc, "")
    add_heading(doc, "Was wird NICHT erfasst", level=2)
    for item in [
        "Bildschirminhalte, Screenshots oder Pixeldaten",
        "Tastatureingaben (außer Leerlauferkennung)",
        "Zwischenablage-Inhalte",
        "Netzwerkverkehr oder Browserverlauf über den aktiven Safari-Tab hinaus",
        "Audio, Video oder Mikrofondaten",
        "Daten anderer Nutzer auf geteilten Macs",
    ]:
        add_bullet(doc, item)

    # ══════════════════════════════════════════════════════════════════════
    # 5. DATENSCHUTZEINSTELLUNGEN
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "5. Datenschutzeinstellungen", level=1)
    add_para(doc,
        "Alle Datenschutzeinstellungen sind über Einstellungen → Allgemein zugänglich und werden "
        "in der Konfigurationsdatei gespeichert. Jede Einstellung hat einen Tooltip, der die genaue "
        "Funktion erklärt.")
    add_table(doc,
        ["Einstellung", "Standard", "Wirkung"],
        [
            ["safariTrackingEnabled", "true", "Auf false setzen, um Safari-Monitoring komplett zu deaktivieren"],
            ["logSafariURLs", "true", "Auf false setzen, um nur Tab-Namen, nicht URLs zu protokollieren"],
            ["logSafariDomainOnly", "true", "Nur Domain speichern (z.B. github.com statt vollem Pfad)"],
            ["retentionDays", "90", "Tage, die Logdateien aufbewahrt werden, bevor sie automatisch gelöscht werden"],
            ["skipApps", "(Liste)", "App-Namen, die aus Report-Beschreibungen ausgeschlossen werden"],
            ["skipSafariExact", "(Liste)", "Safari-Tab-Titel, die exakt gefiltert werden"],
            ["skipSafariContains", "(Liste)", "Safari-Tab-Titel, die per Substring-Match gefiltert werden"],
            ["showSafariTimeInReport", "false", "Akkumulierte Zeit pro Safari-Tab im Report anzeigen"],
        ])
    add_para(doc, "")
    add_heading(doc, "URL-Bereinigung", level=2)
    add_para(doc,
        "Standardmäßig (logSafariDomainOnly: true) werden URLs auf den Domainnamen reduziert:")
    add_para(doc,
        "https://portal.client.com/project/12345/docs?token=abc → portal.client.com",
        italic=True, size=10)
    add_para(doc,
        "OAuth-Tokens, Autorisierungscodes, Session-IDs und ähnliche sensible URL-Parameter werden "
        "niemals gespeichert. Query-Strings und Fragmente werden immer entfernt, auch wenn der "
        "Domain-only-Modus deaktiviert ist.")

    # ══════════════════════════════════════════════════════════════════════
    # 6. DSGVO-KONFORMITÄTSMAẞNAHMEN
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "6. DSGVO-Konformitätsmaßnahmen", level=1)
    measures = [
        ("Einwilligung beim ersten Start (Art. 7)",
         "Beim ersten Start zeigt WorkLogger einen Einwilligungsdialog an, der genau auflistet, "
         "welche Daten erfasst werden, und erfordert eine explizite Zustimmung (\"Ich stimme zu\") "
         "bevor jegliche Protokollierung beginnt. Bei Ablehnung beendet sich die App sofort."),
        ("Datenschutzhinweise (Art. 13/14)",
         "PRIVACY.md bietet einen vollständigen Art.-13-Datenschutzhinweis mit Rechtsgrundlage, "
         "Datenkategorien, Rechten, Aufbewahrungsfristen, Sicherheitsmaßnahmen und Verantwortlichen-Vorlage."),
        ("Automatische Löschung / Aufbewahrung (Art. 5(1)(e))",
         "Logdateien, die älter als die Aufbewahrungsfrist (Standard: 90 Tage) sind, werden bei "
         "jedem App-Start automatisch gelöscht."),
        ("Datenminimierung (Art. 5(1)(c))",
         "Domain-only URL-Logging, 200-Zeichen String-Trunkierung, konfigurierbare Feature-Schalter "
         "zur Deaktivierung unnötiger Erfassung."),
        ("Privacy by Design (Art. 25)",
         "Restriktivste Einstellungen standardmäßig aktiviert. Keine Daten verlassen das Gerät. "
         "Alle Dateiberechtigungen sind auf Eigentümer beschränkt."),
        ("Dokumentation (Art. 30, 35)",
         "Verzeichnis von Verarbeitungstätigkeiten (VVT/ROPA.md) und Datenschutz-Folgenabschätzung "
         "(DSFA/DPIA.md) sind beigefügt."),
        ("Kein Drittanbieter-Datenaustausch",
         "Null Netzwerkaufrufe. Keine Analyse, Telemetrie, Cloud-Speicherung oder Drittanbieter-Dienste."),
    ]
    for title, desc in measures:
        add_heading(doc, title, level=2)
        add_para(doc, desc)

    # ══════════════════════════════════════════════════════════════════════
    # 7. BETROFFENENRECHTE
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "7. Betroffenenrechte (Art. 15–22)", level=1)
    add_table(doc,
        ["Recht", "Artikel", "Umsetzung"],
        [
            ["Auskunftsrecht", "Art. 15", "\"Alle meine Daten exportieren…\" — Menüpunkt erstellt ZIP-Archiv aller JSONL-Logs und Konfiguration"],
            ["Recht auf Berichtigung", "Art. 16", "Retroaktiver Quick-Log-Tab ermöglicht Korrektureinträge; JSONL-Dateien in jedem Texteditor bearbeitbar"],
            ["Recht auf Löschung", "Art. 17", "\"Alle meine Daten löschen…\" — Menüpunkt mit doppelter Bestätigung; automatische Löschung alter Logs"],
            ["Recht auf Einschränkung", "Art. 18", "Safari-Schalter, skipApps-Konfiguration, App beenden zum Stoppen der Verarbeitung"],
            ["Recht auf Datenportabilität", "Art. 20", "JSONL ist ein offenes Format; ZIP-Export enthält alle Daten"],
            ["Widerspruchsrecht", "Art. 21", "App beenden, Einwilligung ablehnen oder alle Daten löschen"],
            ["Widerruf der Einwilligung", "Art. 7(3)", "Konfiguration löschen zum Zurücksetzen der Einwilligung; App jederzeit beenden"],
        ])

    # ══════════════════════════════════════════════════════════════════════
    # 8. TOM
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "8. Technische & organisatorische Maßnahmen (Art. 32)", level=1)
    add_table(doc,
        ["Maßnahme", "Umsetzung"],
        [
            ["Dateiberechtigungen", "Logdateien: 0600 (nur Eigentümer lesen/schreiben), Logverzeichnis: 0700, Konfiguration: 0600"],
            ["Verschlüsselung", "Basiert auf macOS FileVault (Vollverschlüsselung, Standard auf verwalteten Corporate-Macs)"],
            ["Datenminimierung", "URLs standardmäßig als Domain-only; alle Strings auf 200 Zeichen trunkiert"],
            ["Kein Netzwerkverkehr", "Null Netzwerkaufrufe — keine Analyse, Telemetrie oder Cloud-Sync"],
            ["Automatische Löschung", "Logs älter als Aufbewahrungsfrist werden bei jedem Start gelöscht"],
            ["Zugriffskontrolle", "Einzelnutzer-Tool; kein Mehrbenutzer-Zugriff, keine geteilten Konten"],
        ])

    # ══════════════════════════════════════════════════════════════════════
    # 9. RISIKOBEWERTUNG
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "9. Risikobewertung & Mitigationen", level=1)
    add_para(doc,
        "Die folgende Tabelle fasst alle identifizierten Datenschutz- und Sicherheitsbedenken, "
        "deren Risikostufen und den aktuellen Mitigationsstatus zusammen.")
    add_table(doc,
        ["#", "Bedenken", "Risiko", "Status"],
        [
            ["1", "Daten im Ruhezustand — keine Verschlüsselung", "Mittel", "Mitigiert (chmod 600, FileVault dokumentiert)"],
            ["2", "Sensible Daten in URLs", "Hoch", "Behoben (Domain-only Standard, Query-Stripping, Schalter)"],
            ["3", "Keine Datenaufbewahrung / Löschung", "Mittel", "Behoben (90-Tage Auto-Purge bei Start)"],
            ["4", "Keine Zugriffskontrollen", "Niedrig-Mittel", "Mitigiert (chmod 600/700)"],
            ["5", "Safari-Tracking — Datenschutz", "Mittel", "Behoben (Schalter, Domain-only Standard)"],
            ["6", "Fenstertitel-Leakage", "Mittel", "Mitigiert (dokumentiert, Einwilligung, skipApps)"],
            ["7", "Kein Einwilligungsmechanismus", "Hoch", "Behoben (Erststart-Dialog, Menüpunkt)"],
            ["8", "Ad-hoc Code-Signierung", "Mittel", "Dokumentiert"],
            ["9", "LaunchAgent Auto-Start", "Niedrig", "Dokumentiert"],
            ["10", "Screen Recording & Accessibility", "Mittel", "Dokumentiert"],
            ["11", "Git-Commit-Daten in Reports", "Niedrig", "Dokumentiert"],
            ["12", "Kein Audit Trail", "Niedrig", "Dokumentiert"],
            ["13", "Datenportabilität & Löschung", "Niedrig", "Behoben (Export-ZIP, Alle löschen, Auto-Purge)"],
            ["14", "DSGVO-Rechte-Umsetzung", "Mittel", "Behoben (Art. 15–22 alle implementiert)"],
            ["15", "DSGVO-Dokumentation", "Mittel", "Behoben (PRIVACY.md, ROPA.md, DPIA.md)"],
            ["16", "Automatisierte Testabdeckung", "Mittel", "Behoben (113 Tests, Build-gated)"],
        ])
    add_para(doc, "")
    add_heading(doc, "Restrisiken", level=2)
    for item in [
        "Daten im Ruhezustand nicht auf Anwendungsebene verschlüsselt — mitigiert durch FileVault-Empfehlung",
        "Fenstertitel können vertrauliche Dokumentnamen enthalten — mitigiert durch Einwilligung und skipApps-Filter",
        "Ad-hoc Code-Signierung kann durch Corporate MDM blockiert werden — erfordert IT-Freigabe oder Developer ID (99$/Jahr)",
        "Kein anwendungsseitiger Audit Trail — akzeptabel für Einzelnutzer-persönliches Tool",
    ]:
        add_bullet(doc, item)

    # ══════════════════════════════════════════════════════════════════════
    # 10. TESTABDECKUNG
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "10. Testabdeckung & Qualitätssicherung", level=1)
    add_para(doc,
        "Alle compliance-kritischen Kontrollen werden durch automatisierte Tests verifiziert, "
        "die bestanden werden müssen, bevor ein Build erstellt werden kann.")
    add_table(doc,
        ["Suite", "Tests", "Abdeckungsbereich"],
        [
            ["Swift — URL-Bereinigung", "12+", "Domain-only Extraktion, Query-Stripping, Token-Entfernung, IP/Unicode/kodierte URLs"],
            ["Swift — Dateiberechtigungen", "3", "chmod 600 auf Logdateien, retroaktive Einträge, Persistenz über Schreibvorgänge"],
            ["Swift — Auto-Purge", "7", "Aufbewahrungsfristen, Grenzwerte, Nicht-JSONL-Erhaltung, Randfälle"],
            ["Swift — Konfiguration & Einwilligung", "11", "Privacy-Feld Encoding/Decoding, Einwilligungsmechanismus, Safari-Schalter, Defaults"],
            ["Swift — Datenminimierung", "8+", "String-Trunkierung (200 Zeichen), Privacy-by-Default-Verifikation"],
            ["Python — Report-Pipeline", "46", "Smart-Aggregation, Teams-Filterung, Beschreibungs-Builder, manuelle Einträge"],
        ])
    add_para(doc, "")
    add_para(doc,
        "Build-Gate: make app → make build → make test. Beide Swift- und Python-Suiten müssen "
        "bestanden werden, bevor ein Binary erstellt wird. Gesamt: 113 Tests in 21 Suiten.",
        bold=True)

    # ══════════════════════════════════════════════════════════════════════
    # 11. DEPLOYMENT
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "11. Deployment & Verteilung", level=1)
    add_para(doc,
        "WorkLogger wird als Quellcode über GitHub verteilt. Nutzer erstellen das .app-Bundle lokal "
        "mit make app, wofür nur die Xcode Command Line Tools (kostenlos) und Python 3.10+ benötigt werden.")
    add_para(doc, "")
    add_heading(doc, "Voraussetzungen für Endnutzer", level=2)
    for item in [
        "macOS 13 (Ventura) oder neuer",
        "Xcode Command Line Tools (xcode-select --install)",
        "Python 3.10+ mit openpyxl (pip3 install openpyxl)",
        "Accessibility-, Screen-Recording- und Safari-Automatisierungsberechtigungen beim ersten Start gewähren",
    ]:
        add_bullet(doc, item)
    add_para(doc, "")
    add_heading(doc, "macOS-Berechtigungen erklärt", level=2)
    add_table(doc,
        ["Berechtigung", "Grund", "Umfang"],
        [
            ["Accessibility", "Fenstertitel über CGWindowList lesen; globaler Cmd+Shift+L Hotkey", "Liest nur Fensternamen, nicht Inhalte"],
            ["Screen Recording", "Von macOS für CGWindowListCopyWindowInfo benötigt", "Liest nur Fenstertitel, keine Bildschirmpixel"],
            ["Automation (Safari)", "Aktiven Tab-Namen und URL lesen", "Liest nur den aktuellen Tab, nicht den Verlauf"],
        ])

    # ══════════════════════════════════════════════════════════════════════
    # 12. EMPFEHLUNGEN
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "12. Empfehlungen für Legal/Compliance", level=1)

    recs = [
        ("Für sofortigen Einsatz (persönliche Nutzung)", [
            "Die Anwendung kann sofort für persönliche Zeiterfassung genutzt werden",
            "Alle hochriskanten Bedenken wurden behoben (Einwilligung, URL-Bereinigung, Datenaufbewahrung)",
            "Nutzer sollten sicherstellen, dass FileVault auf ihrem Mac aktiviert ist",
            "Der Quellcode ist zur Sicherheitsprüfung verfügbar unter https://github.com/Ralo93/tracker",
        ]),
        ("Für teamweiten Einsatz", [
            "Verantwortlichen-Details in PRIVACY.md und ROPA.md-Vorlagen ausfüllen",
            "Interessenabwägung (LIA) durchführen, falls Nutzung verpflichtend ist",
            "Mit IT abstimmen, um die App in MDM-Profilen freizuschalten (Accessibility, Screen Recording)",
            "Apple Developer ID (99$/Jahr) für ordentliche Code-Signierung erwägen",
            "Teammitglieder über erfasste Daten und ihre Rechte informieren",
        ]),
        ("Für formelle Compliance-Freigabe", [
            "Beigefügte DSFA (Anhang B) prüfen und Prüferfelder ausfüllen",
            "DPO zum VVT-Eintrag (Anhang A) konsultieren",
            "Prüfen, ob Betriebsrat-Beteiligung nach BetrVG §87 erforderlich ist",
            "Übereinstimmung mit internen Datenklassifizierungs- und Handhabungsrichtlinien von PwC verifizieren",
        ]),
    ]
    for title, items in recs:
        add_heading(doc, title, level=2)
        for item in items:
            add_bullet(doc, item)

    doc.add_page_break()

    # ══════════════════════════════════════════════════════════════════════
    # ANHANG A — VVT
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "Anhang A — Verzeichnis von Verarbeitungstätigkeiten (VVT)", level=1)
    add_para(doc, "DSGVO Artikel 30 — Verzeichnis von Verarbeitungstätigkeiten", italic=True)

    ropa = (ROOT / "ROPA.md").read_text()
    for line in ropa.split("\n"):
        line = line.strip()
        if not line or line.startswith("---") or line.startswith("# "):
            continue
        if line.startswith("## "):
            add_heading(doc, line.lstrip("# "), level=2)
        elif line.startswith("*"):
            add_para(doc, line.strip("*").strip(), italic=True, size=10)
        elif line.startswith("| ") and "---" not in line:
            add_para(doc, line.replace("|", "  ").strip(), size=10)
        else:
            add_para(doc, line, size=11)

    doc.add_page_break()

    # ══════════════════════════════════════════════════════════════════════
    # ANHANG B — DSFA
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "Anhang B — Datenschutz-Folgenabschätzung (DSFA)", level=1)
    add_para(doc, "DSGVO Artikel 35 — Datenschutz-Folgenabschätzung", italic=True)

    dpia = (ROOT / "DPIA.md").read_text()
    for line in dpia.split("\n"):
        line = line.strip()
        if not line or line.startswith("---") or line.startswith("# "):
            continue
        if line.startswith("## "):
            add_heading(doc, line.lstrip("# "), level=2)
        elif line.startswith("### "):
            add_heading(doc, line.lstrip("# "), level=3)
        elif line.startswith("*"):
            add_para(doc, line.strip("*").strip(), italic=True, size=10)
        elif line.startswith("- "):
            add_bullet(doc, line[2:])
        elif line.startswith("| ") and "---" not in line:
            add_para(doc, line.replace("|", "  ").strip(), size=10)
        else:
            add_para(doc, line, size=11)

    # ══════════════════════════════════════════════════════════════════════
    # SPEICHERN
    # ══════════════════════════════════════════════════════════════════════
    out = ROOT / "WorkLogger_Compliance_Review_DE.docx"
    doc.save(str(out))
    print(f"✓ Gespeichert: {out}")
    return out

if __name__ == "__main__":
    build_doc()
