# One Piece TCG Scanner

Kamera auf eine One-Piece-Karte halten — die Karte wird **automatisch** erkannt und mit Preis in eine
Liste eingetragen. Kein Knopfdruck pro Karte.

👉 **[Anleitung: Installieren und benutzen](ANLEITUNG.md)**

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
| **Preise** | **echte Cardmarket-Preise**, 3.865 von 3.868 Karten (99,9 %) — siehe unten |

## Preise: echte Cardmarket-Daten

Cardmarket veröffentlicht seit 07/2025 selbst tägliche Export-Dateien und erlaubt deren Nutzung in
eigenen Anwendungen ausdrücklich — kein API-Antrag, kein Scraping. Die Website `www.cardmarket.com`
ist zwar durch Cloudflare geschützt (liefert 403), der Datei-Server dahinter aber nicht:

```
https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_18.json
https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_18.json
```

`18` ist Cardmarkets Spiel-ID für One Piece. Die Produktnamen tragen die Kartennummer im Format
`Roronoa Zoro (OP01-001)`, darüber läuft die Zuordnung zu unserem Katalog.

**Aktualisieren:**
```
node scripts/fetch-cardmarket.js          # lädt beide Dateien neu
node scripts/import-cardmarket-prices.js  # spielt sie in data/cards.normalized.json ein
npm run build-db                          # verteilt in docs/ und android_app/assets/
```

Angezeigt wird Cardmarkets **Trendpreis**; fehlt der, wird auf Durchschnitt bzw. niedrigsten Preis
zurückgegriffen (steht jeweils unter dem Betrag).

**Bekannte Ungenauigkeit:** Alternative Artworks teilen sich derzeit den Preis der Normalversion.
Cardmarket führt sie als eigene Produkte, aber ohne unterscheidbaren Namen — eine saubere Trennung
bräuchte den Abgleich über die Edition.

## Grenzen (ehrlich)

1. **Nicht auf einem echten Gerät getestet.** In der Entwicklungsumgebung war kein Android-Gerät
   angeschlossen und kein Emulator verfügbar. Getestet wurden: Kompilierung (`flutter analyze`,
   `flutter build`) und die komplette Erkennungslogik (`flutter test`, 9 Tests). **Nicht** getestet:
   Kamerabild, ML-Kit-Erkennung auf echten Karten, Bildrotation, Performance, Akkuverbrauch.
2. Die Bildrotation beim Kamerastream (`_toInputImage` in `main.dart`) ist auf Hochformat und
   Rückkamera ausgelegt. Falls Karten nicht erkannt werden, ist das der erste Verdächtige.
3. Preise werden nicht automatisch aktualisiert — die Import-Skripte müssen manuell laufen
   (Stand der eingespielten Daten steht in der App unter jedem Betrag).
4. Kartendaten werden ebenfalls nicht automatisch aktualisiert — bei einem neuen Set
   `npm run build-db` ausführen.
5. Web-Variante: Der Zuschnitt auf den Kartenrahmen (`captureGuideFrameToCanvas`) ist nur
   durchgerechnet, nicht an einer echten Kamera verifiziert.

## Nächste sinnvolle Schritte
- APK auf dem S24 installieren und melden, was passiert (erkennt er Karten? wie schnell?).
- Cardmarket-Preisimport, sobald der Download von außerhalb der Sandbox klappt.
- Sammlung dauerhaft speichern (aktuell lebt die Liste nur während der Sitzung).
- Export (CSV) für die gescannte Liste.
