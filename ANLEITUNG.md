# Anleitung — One Piece Scanner

> **Hinweis zu den Abbildungen:** Die Bilder unten sind **maßstabsgetreue Nachbildungen aus dem
> UI-Code**, keine echten Screenshots. In der Entwicklungsumgebung war kein Android-Gerät und kein
> Emulator verfügbar. Sobald die App auf dem Handy läuft, werden sie durch echte Screenshots ersetzt.

---

## 1. App installieren (Android)

1. Auf dem Handy die **Releases-Seite** öffnen:
   https://github.com/FeyzAras/onepiece-scanner/releases
2. Unter dem neuesten Eintrag die Datei **`onepiece-scanner.apk`** antippen → wird heruntergeladen.
3. Die heruntergeladene Datei öffnen (Benachrichtigung antippen oder in „Downloads").
4. Android fragt: *„Aus dieser Quelle dürfen keine unbekannten Apps installiert werden"* →
   **Einstellungen** antippen → **„Aus dieser Quelle zulassen"** aktivieren → zurück → **Installieren**.
5. Beim ersten Start fragt die App nach der **Kamera-Berechtigung** → **Zulassen**.

> Die App ist mit einem Entwickler-Schlüssel signiert, nicht über den Play Store verteilt. Deshalb
> die Rückfrage von Android — das ist normal bei selbst gebauten Apps.

**Es gibt keine Internetpflicht:** Erkennung und Kartendaten liegen komplett in der App. Internet
wird nur benutzt, um die Kartenbilder in der Liste nachzuladen.

---

## 2. Scannen

<img src="docs/images/ui-scan.svg" width="300" alt="Scan-Ansicht: Kamerabild mit Kartenrahmen, Statusanzeige und eingeklappter Liste">

So läuft es ab:

1. App öffnen — die Kamera startet und **scannt sofort von allein**. Kein Knopfdruck nötig.
2. Karte so halten, dass sie **im goldenen Rahmen** liegt.
3. Sobald die App die Karte erkennt:
   - kurzes **Vibrieren**
   - grüne Bestätigung oben: **✓ Kartenname**
   - Eintrag wandert unten in die Liste
4. Nächste Karte davor halten. Dieselbe Karte wird innerhalb von 4 Sekunden **nicht doppelt**
   eingetragen — du kannst sie also ruhig im Bild lassen.

**Der runde Knopf unten ist kein Auslöser**, sondern Pause/Weiter. Nützlich, wenn du kurz etwas
anderes machst und nicht willst, dass die App im Hintergrund weiter Karten einsammelt.

### Damit die Erkennung gut funktioniert
- **Licht**: gleichmäßig, nicht direkt von oben — Spiegelungen auf Folienkarten sind der häufigste Grund für Fehlversuche.
- **Abstand**: Karte den Rahmen gut ausfüllen lassen.
- **Ruhig halten**: ca. eine halbe Sekunde, die App wertet mehrmals pro Sekunde aus.
- **Gerade halten**: stark schräge Winkel erschweren das Lesen der Kartennummer.

---

## 3. Die Liste

<img src="docs/images/ui-liste.svg" width="300" alt="Liste der gescannten Karten mit Namen, Set-Nummer, Erkennungsart und Preis">

Die Liste am unteren Rand **nach oben ziehen**, um alle gescannten Karten zu sehen.

| Element | Bedeutung |
| --- | --- |
| **Gesamt** oben rechts | Summe aller Preise in der aktuellen Sitzung |
| 🟩 **über Kartennummer** | Die App hat die aufgedruckte Nummer (z. B. `OP01-001`) gelesen — **eindeutig**, auch bei mehreren Karten mit demselben Namen |
| ⬜ **über Name** | Nur der Name war lesbar — bei gleichnamigen Karten (z. B. den vielen „Roronoa Zoro"-Versionen) kann die falsche Variante getroffen sein; kurz prüfen |
| **MOCK** am Preis | Platzhalterpreis, **keine echte Cardmarket-Zahl** — siehe unten |
| **✕** | Einzelnen Eintrag entfernen |
| **Liste leeren** | Alles entfernen (mit Rückfrage) |

> **Achtung:** Die Liste lebt nur, solange die App offen ist. Beim Schließen ist sie weg —
> dauerhaftes Speichern ist noch nicht eingebaut.

---

## 4. Zu den Preisen

Die angezeigten Preise sind **Platzhalter**, berechnet aus der Seltenheitsstufe. Sie sind klar mit
`MOCK` markiert, damit sie nicht versehentlich für echte Marktpreise gehalten werden.

Der Weg zu echten Preisen ist geklärt, aber noch nicht umgesetzt: Cardmarket veröffentlicht seit
Juli 2025 **offizielle tägliche Preis-Export-Dateien** zur freien Nutzung, One Piece ist abgedeckt.
Der Download war aus der Entwicklungsumgebung heraus durch Cloudflare blockiert (HTTP 403) — von
einem normalen Anschluss aus sollte er funktionieren. Dann kann ein kleines Importskript die echten
Preise einspielen.

---

## 5. Wenn etwas nicht klappt

| Problem | Was tun |
| --- | --- |
| Kamera bleibt schwarz | Berechtigung prüfen: Einstellungen → Apps → One Piece Scanner → Berechtigungen → Kamera |
| Es wird gar nichts erkannt | Mehr Licht, Karte näher ran, ruhiger halten. Hilft das nicht, melde dich — dann ist vermutlich die Bilddrehung auf deinem Gerät anders als angenommen |
| Falsche Variante erkannt | Prüfe das Etikett: steht „über Name" dran, war die Kartennummer nicht lesbar. Karte leicht kippen, damit die Nummer unten besser ins Bild kommt |
| Kartenbilder bleiben leer | Internetverbindung — die Bilder werden von der offiziellen Bandai-Seite nachgeladen |
| App ruckelt / Akku heiß | Über den runden Knopf pausieren, wenn du gerade nicht scannst |

---

## 6. Web-Variante

Es gibt dieselbe Funktion zusätzlich als Web-App unter
https://feyzaras.github.io/onepiece-scanner/ (im Browser öffnen, über das Menü
„Zum Startbildschirm hinzufügen" installierbar).

Sie ist bewusst die Zweitlösung: Die Texterkennung im Browser ist deutlich langsamer
(ca. 2–4 Sekunden pro Versuch statt mehrmals pro Sekunde). Nützlich zum schnellen Ausprobieren
auf einem beliebigen Gerät, inklusive iPhone oder Rechner mit Webcam.
