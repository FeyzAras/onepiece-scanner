# One Piece TCG Scanner

Kamera auf eine One-Piece-Karte halten — die Karte wird **automatisch** erkannt und mit Preis in eine
Liste eingetragen. Kein Knopfdruck pro Karte.

Das Projekt enthält zwei Varianten:

| Variante | Ordner | Zustand |
| --- | --- | --- |
| **Android-App** (Flutter, native) | `android_app/` | Hauptvariante. APK zum Installieren auf dem Handy. |
| Web-App (PWA) | `docs/` | Läuft im Browser, installierbar über "Zum Startbildschirm hinzufügen". |

Projektkontext: `2.7.Pythagoras/Projekte/P-001_TCG_Marktplatz_DE/02_Konzeption_Kartenscanner_OnePiece.md`
im Obsidian-Vault.

---

## Android-App

**Technik:** Flutter + `camera` (Live-Bildstrom) + Google **ML Kit Text Recognition** (On-Device-OCR,
funktioniert offline, keine Cloud). Kartenkatalog liegt als Asset in der App.

**So funktioniert das Erkennen:**
1. Die Kamera liefert laufend Bilder (ca. alle 450 ms wird eins ausgewertet).
2. ML Kit liest den Text auf der Karte.
3. Abgleich in zwei Stufen:
   - **Kartennummer** (z. B. `OP01-001`) — eindeutig, trennt auch gleichnamige Karten sauber.
     Typische OCR-Fehler werden ausgeglichen (`oo01.001` → `OP01-001`), akzeptiert wird nur,
     was einer real existierenden Karten-ID entspricht.
   - **Kartenname** — Fallback, wenn die Nummer nicht lesbar war.
4. Treffer landet in der Session-Liste (Bild, Name, Set-Nummer, Preis). Dieselbe Karte wird
   innerhalb von 4 Sekunden nicht doppelt eingetragen.

**Bauen:**
```
cd android_app
flutter pub get
flutter test          # Erkennungslogik gegen den echten Katalog pruefen
flutter build apk --release
# Ergebnis: build/app/outputs/flutter-apk/app-release.apk
```

**Installieren:** APK auf das Handy laden, öffnen, "Installation aus unbekannten Quellen" für den
Browser/Dateimanager erlauben. Die APK ist mit dem Flutter-Debug-Schlüssel signiert — für den
Eigengebrauch völlig in Ordnung, für den Play Store bräuchte es einen eigenen Signaturschlüssel.

---

## Web-App (PWA)

```
npm install
npm run build-db   # Kartendaten neu aufbauen + nach docs/data/cards.json kopieren
npm run dev        # Vorschau unter http://localhost:3000
```

Komplett client-seitig, kein Server nötig. OCR läuft per `tesseract.js` im Browser (langsamer als
ML Kit, ca. 2–4 s pro Versuch). Liegt in `docs/`, damit GitHub Pages es direkt ausliefern kann.

---

## Was ist echt, was ist Platzhalter?

| Teil | Status |
| --- | --- |
| Dauer-Scan, Erkennung, Session-Liste, Gesamtwert (beide Varianten) | **echt**, gebaut und auf Logik-Ebene getestet |
| OCR | **echt** — ML Kit (App) bzw. tesseract.js (Web) |
| Kartennummer- und Namensabgleich | **echt**, durch automatische Tests abgedeckt (`flutter test`, `node scripts/verify-match.mjs`) |
| Kartenkatalog | **echt, aktuell** — npm-Paket [`one-piece-card-game-json`](https://www.npmjs.com/package/one-piece-card-game-json), Stand 09/2026, 3.868 Karten, OP01–OP17 + EB + Promos + ST01–36 |
| **Preise** | **Platzhalter (Mock)** — siehe unten |

## Preise: Stand und was fehlt

Cardmarket veröffentlicht offizielle, frei nutzbare tägliche Preis-Export-Dateien (seit 07/2025,
One Piece ausdrücklich abgedeckt, kein API-Antrag nötig). **Der Download war aus der
Entwicklungsumgebung, in der das hier gebaut wurde, durch Cloudflare blockiert (HTTP 403)** —
getestet, nicht vermutet. Deshalb steht in beiden Varianten ein klar gekennzeichneter
Platzhalterpreis (`price_mock.dart` / `price-mock.js`).

Nächster Schritt: `https://www.cardmarket.com/OnePiece/Data/Price-Guide` von einem normalen
Rechner/Netz aus testen. Klappt das, importiert ein kleines Skript die echten Preise in
`assets/cards.json` bzw. `docs/data/cards.json`.

## Grenzen (ehrlich)

1. **Nicht auf einem echten Gerät getestet.** In der Entwicklungsumgebung war kein Android-Gerät
   angeschlossen und kein Emulator verfügbar. Getestet wurden: Kompilierung (`flutter analyze`,
   `flutter build`) und die komplette Erkennungslogik (`flutter test`, 9 Tests). **Nicht** getestet:
   Kamerabild, ML-Kit-Erkennung auf echten Karten, Bildrotation, Performance, Akkuverbrauch.
2. Die Bildrotation beim Kamerastream (`_toInputImage` in `main.dart`) ist auf Hochformat und
   Rückkamera ausgelegt. Falls Karten nicht erkannt werden, ist das der erste Verdächtige.
3. Preise sind Platzhalter.
4. Kartendaten werden nicht automatisch aktualisiert — bei einem neuen Set `npm run build-db`
   ausführen und `assets/cards.json` neu kopieren.
5. Web-Variante: Der Zuschnitt auf den Kartenrahmen (`captureGuideFrameToCanvas`) ist nur
   durchgerechnet, nicht an einer echten Kamera verifiziert.

## Nächste sinnvolle Schritte
- APK auf dem S24 installieren und melden, was passiert (erkennt er Karten? wie schnell?).
- Cardmarket-Preisimport, sobald der Download von außerhalb der Sandbox klappt.
- Sammlung dauerhaft speichern (aktuell lebt die Liste nur während der Sitzung).
- Export (CSV) für die gescannte Liste.
