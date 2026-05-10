#!/usr/bin/env python3
"""Generiert eine Management-Zusammenfassung (5-6 Seiten) auf Deutsch."""

from docx import Document
from docx.shared import Pt, RGBColor, Cm
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

def add_bullet(doc, text, size=11, bold=False):
    p = doc.add_paragraph(text, style="List Bullet")
    for run in p.runs:
        run.font.size = Pt(size)
        run.bold = bold
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
    doc.add_paragraph()
    title = doc.add_heading("WorkLogger", level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in title.runs:
        run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
        run.font.size = Pt(32)

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run("Management-Zusammenfassung")
    run.font.size = Pt(20)
    run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    doc.add_paragraph()

    tagline = doc.add_paragraph()
    tagline.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = tagline.add_run("Automatisierte Arbeitszeiterfassung für macOS\nDatenschutzkonform • Lokal • Open Source")
    run.font.size = Pt(13)
    run.italic = True
    run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)

    doc.add_paragraph()
    doc.add_paragraph()

    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = meta.add_run("April 2026\nPwC Deutschland — Zur Freigabe durch Management, Compliance & Legal")
    run.font.size = Pt(11)

    doc.add_page_break()

    # ══════════════════════════════════════════════════════════════════════
    # 1. AUF EINEN BLICK
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "1. Auf einen Blick", level=1)

    add_table(doc,
        ["", ""],
        [
            ["Was ist WorkLogger?", "macOS-Menüleisten-App zur automatischen Arbeitszeiterfassung"],
            ["Zweck", "Wöchentliche Excel-Timesheets automatisch erstellen statt manuell pflegen"],
            ["Datenverarbeitung", "100% lokal — kein Internet, kein Cloud, keine Drittanbieter"],
            ["DSGVO-Status", "Alle Hochrisiko-Bedenken behoben; vollständige Dokumentation vorhanden"],
            ["Quellcode", "Open Source: https://github.com/Ralo93/tracker"],
            ["Testabdeckung", "113 automatisierte Tests, Build-gated (kein ungetesteter Code)"],
        ])

    # ══════════════════════════════════════════════════════════════════════
    # 2. PROBLEM & LÖSUNG
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "2. Problem & Lösung", level=1)

    add_heading(doc, "Das Problem", level=2)
    add_para(doc,
        "Berater erfassen ihre Arbeitszeiten typischerweise manuell in Excel-Timesheets — oft am "
        "Ende des Tages oder der Woche aus dem Gedächtnis. Dies führt zu:")
    for item in [
        "Ungenauen Zeiteinträgen (Schätzungen statt tatsächlicher Zeiten)",
        "Erheblichem Zeitaufwand für die manuelle Pflege (~45 Minuten/Woche)",
        "Fehlenden Details (Projektwechsel, Meeting-Zeiten, Web-Recherche)",
        "Frustration bei der Rekonstruktion vergangener Arbeitstage",
    ]:
        add_bullet(doc, item)

    add_heading(doc, "Die Lösung", level=2)
    add_para(doc,
        "WorkLogger läuft unsichtbar in der macOS-Menüleiste und erfasst automatisch:")
    for item in [
        "Welche Anwendungen wann genutzt werden (mit Zeitdauer)",
        "An welchen VS-Code-Projekten gearbeitet wird",
        "Welche Webseiten besucht werden (nur Domain, keine Pfade)",
        "Wann Meetings stattfinden (Teams-Erkennung)",
        "Git-Commits aus konfigurierten Repositories",
        "Leerlauf-, Sperr- und Schlafphasen (für genaue Arbeitszeitabgrenzung)",
    ]:
        add_bullet(doc, item)

    add_para(doc,
        "Per Tastenkürzel (Cmd+Shift+L) können jederzeit manuelle Einträge ergänzt werden. "
        "Der wöchentliche Excel-Report wird per Knopfdruck aus der Menüleiste generiert.")

    # ══════════════════════════════════════════════════════════════════════
    # 3. ZEITERSPARNIS / ROI
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "3. Zeitersparnis & ROI", level=1)

    add_table(doc,
        ["Kennzahl", "Wert"],
        [
            ["Geschätzte Zeitersparnis pro Mitarbeiter", "~45 Minuten / Woche (konservativ)"],
            ["Jährliche Ersparnis pro Mitarbeiter", "~39 Stunden / Jahr"],
            ["Bei 10 Mitarbeitern", "~390 Stunden / Jahr"],
            ["Bei 50 Mitarbeitern", "~1.950 Stunden / Jahr"],
            ["Qualitätsverbesserung", "Exakte Zeiten statt Schätzungen, lückenlose Dokumentation"],
        ])

    add_para(doc, "")
    add_heading(doc, "Woher kommen die 45 Minuten?", level=2)
    add_table(doc,
        ["Tätigkeit (manuell)", "Geschätzter Aufwand", "Mit WorkLogger"],
        [
            ["Tägliches Zeiterfassen (5×5 min)", "25 min/Woche", "Entfällt (automatisch)"],
            ["Wochenreport erstellen & formatieren", "10 min/Woche", "1 Klick (< 1 min)"],
            ["Vergangene Tage rekonstruieren", "5–10 min/Woche", "Entfällt (lückenlose Logs)"],
            ["Meetings & Projektwechsel nachschlagen", "5 min/Woche", "Automatisch erfasst"],
            ["GESAMT", "~45 min/Woche", "< 5 min/Woche"],
        ])

    add_para(doc, "")
    add_para(doc,
        "Zusätzlicher Nutzen: Höhere Genauigkeit der Timesheets, bessere Projektkalkulation "
        "durch reale Zeitdaten, und reduzierte Frustration bei der nachträglichen Dokumentation.",
        italic=True)

    # ══════════════════════════════════════════════════════════════════════
    # 4. DATENSCHUTZ
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "4. Datenschutz & DSGVO-Konformität", level=1)

    add_para(doc,
        "WorkLogger wurde von Anfang an mit Datenschutz als Kernprinzip entwickelt. "
        "Die wichtigsten Punkte auf einen Blick:")

    add_heading(doc, "Keine Daten verlassen den Rechner", level=2)
    add_para(doc,
        "WorkLogger macht null Netzwerkaufrufe. Keine Cloud, kein Server, keine Telemetrie. "
        "Alle Daten bleiben ausschließlich lokal auf dem Mac des Nutzers.")

    add_heading(doc, "DSGVO-Konformität", level=2)
    add_table(doc,
        ["Anforderung", "Status", "Umsetzung"],
        [
            ["Einwilligung (Art. 7)", "✓ Umgesetzt", "Einwilligungsdialog beim ersten Start"],
            ["Datenschutzhinweise (Art. 13)", "✓ Vorhanden", "Vollständige Datenschutzerklärung (PRIVACY.md)"],
            ["Datenminimierung (Art. 5)", "✓ Umgesetzt", "Domain-only URLs, 200-Zeichen-Trunkierung"],
            ["Speicherbegrenzung (Art. 5)", "✓ Umgesetzt", "Automatische Löschung nach 90 Tagen"],
            ["Betroffenenrechte (Art. 15–22)", "✓ Umgesetzt", "Export, Löschung, Einschränkung über Menü"],
            ["TOM (Art. 32)", "✓ Umgesetzt", "chmod 600/700, FileVault-Empfehlung"],
            ["Privacy by Design (Art. 25)", "✓ Umgesetzt", "Restriktivste Einstellungen als Standard"],
            ["VVT (Art. 30)", "✓ Vorhanden", "ROPA.md beigefügt"],
            ["DSFA (Art. 35)", "✓ Vorhanden", "DPIA.md beigefügt"],
        ])

    add_para(doc, "")
    add_heading(doc, "Was wird NICHT erfasst", level=2)
    for item in [
        "Keine Bildschirminhalte, Screenshots oder Pixeldaten",
        "Keine Tastatureingaben",
        "Keine Zwischenablage-Inhalte",
        "Kein Netzwerkverkehr oder Browserverlauf",
        "Kein Audio, Video oder Mikrofon",
    ]:
        add_bullet(doc, item)

    # ══════════════════════════════════════════════════════════════════════
    # 5. RISIKOBEWERTUNG
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "5. Risikobewertung (Kurzfassung)", level=1)

    add_para(doc,
        "16 Risiken wurden identifiziert und bewertet. Alle hochriskanten Themen sind behoben:")

    add_table(doc,
        ["Risiko", "Stufe", "Status"],
        [
            ["Sensible Daten in URLs", "Hoch", "✓ Behoben — Domain-only Standard"],
            ["Fehlende Einwilligung", "Hoch", "✓ Behoben — Erststart-Dialog"],
            ["Keine automatische Löschung", "Mittel", "✓ Behoben — 90-Tage Auto-Purge"],
            ["Safari-Tracking-Datenschutz", "Mittel", "✓ Behoben — konfigurierbare Schalter"],
            ["Fenstertitel können vertraulich sein", "Mittel", "Mitigiert — Einwilligung + Filter"],
            ["Ad-hoc Code-Signierung", "Mittel", "Dokumentiert — Developer ID möglich"],
        ])

    add_para(doc, "")
    add_para(doc,
        "Vollständige Risikobewertung mit 16 Punkten im Detail-Dokument "
        "(WorkLogger_Compliance_Review_DE.docx) verfügbar.",
        italic=True, size=10)

    # ══════════════════════════════════════════════════════════════════════
    # 6. NÄCHSTE SCHRITTE
    # ══════════════════════════════════════════════════════════════════════
    add_heading(doc, "6. Nächste Schritte & Empfehlungen", level=1)

    add_heading(doc, "Sofort möglich (persönliche Nutzung)", level=2)
    for item in [
        "WorkLogger kann sofort für die persönliche Zeiterfassung eingesetzt werden",
        "Voraussetzung: macOS 13+, Xcode Command Line Tools, Python 3.10+",
        "Installation: git clone + make app (< 5 Minuten)",
        "FileVault sollte auf dem Mac aktiviert sein",
    ]:
        add_bullet(doc, item)

    add_heading(doc, "Für teamweiten Rollout", level=2)
    for item in [
        "Verantwortlichen-Details in Datenschutzdokumentation eintragen",
        "Prüfen, ob Betriebsrat-Beteiligung nach BetrVG §87 erforderlich ist",
        "Mit IT abstimmen: App in MDM-Profilen freischalten (Accessibility, Screen Recording)",
        "Optional: Apple Developer ID für Code-Signierung (99$/Jahr)",
        "Teammitglieder über Funktionsumfang und Datenschutz informieren",
    ]:
        add_bullet(doc, item)

    add_heading(doc, "Für formelle Compliance-Freigabe", level=2)
    for item in [
        "Detail-Dokument (Compliance Review) und DSFA durch Legal/DPO prüfen lassen",
        "Interessenabwägung (LIA) dokumentieren, falls Nutzung angeordnet wird",
        "Abgleich mit PwC-internen Datenklassifizierungsrichtlinien",
    ]:
        add_bullet(doc, item)

    doc.add_paragraph()
    doc.add_paragraph()

    # Abschluss
    closing = doc.add_paragraph()
    closing.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = closing.add_run("— Ende der Management-Zusammenfassung —")
    run.font.size = Pt(10)
    run.italic = True
    run.font.color.rgb = RGBColor(0x99, 0x99, 0x99)

    add_para(doc, "")
    contact = doc.add_paragraph()
    contact.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = contact.add_run(
        "Detail-Dokument: WorkLogger_Compliance_Review_DE.docx\n"
        "Quellcode: https://github.com/Ralo93/tracker\n"
        "Fragen: [Kontakt einfügen]"
    )
    run.font.size = Pt(10)
    run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)

    # ══════════════════════════════════════════════════════════════════════
    out = ROOT / "WorkLogger_Executive_Summary_DE.docx"
    doc.save(str(out))
    print(f"✓ Gespeichert: {out}")
    return out

if __name__ == "__main__":
    build_doc()
