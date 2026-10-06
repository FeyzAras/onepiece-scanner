# One Piece TCG Scanner

Kamera auf eine One-Piece-Karte halten — sie wird **automatisch erkannt** und landet mit echtem
Cardmarket-Preis in deiner Sammlung. Kein Knopfdruck pro Karte.

---

## 📲 App herunterladen

**[→ Neueste Version für Android herunterladen (APK)](https://github.com/FeyzAras/onepiece-scanner/releases/latest)**

Den Link **auf dem Handy** öffnen und die Datei `onepiece-scanner-arm64.apk` antippen.

<details>
<summary><b>Installation Schritt für Schritt</b> (aufklappen)</summary>

1. Link oben auf dem Handy öffnen → unter **Assets** auf `onepiece-scanner-arm64.apk` tippen
2. Chrome fragt, ob die Datei heruntergeladen werden darf → **Herunterladen** bestätigen
3. Heruntergeladene Datei öffnen (Benachrichtigung antippen oder in „Downloads")
4. Android meldet *„Aus dieser Quelle dürfen keine unbekannten Apps installiert werden"* →
   **Einstellungen** → **„Aus dieser Quelle zulassen"** → zurück → **Installieren**
5. Play Protect warnt eventuell vor unbekanntem Entwickler → **Trotzdem installieren**
6. Beim ersten Start: **Kamera-Berechtigung zulassen**

Schritt 4 und 5 sind normal bei Apps, die nicht über den Play Store kommen.

Es gibt drei APK-Varianten. Für aktuelle Handys (auch Samsung S24) ist **`arm64`** die richtige;
`armeabi-v7a` ist für ältere Geräte, `x86_64` für Emulatoren.
</details>

**Ausführliche Bedienungsanleitung: [ANLEITUNG.md](ANLEITUNG.md)**

Es gibt die App auch als **Web-Version** zum Ausprobieren ohne Installation:
**[feyzaras.github.io/onepiece-scanner](https://feyzaras.github.io/onepiece-scanner/)** —
funktioniert in jedem Browser, hat aber eine langsamere Texterkennung und nicht alle Funktionen.

---

## Was die App kann

**Scannen ohne Knopfdruck** — Kamera läuft dauerhaft, Karte in den Rahmen halten genügt.

**Erkennung über die Kartennummer** statt über den Namen. Der Name reicht nicht: Viele Karten
heißen gleich, und Namen anderer Karten stehen im Effekttext — beim Scannen von „Snake Dance"
wurden früher reihum „Gina" und „Portgas.D.Ace" erkannt. Die aufgedruckte Nummer (`OP07-055`) ist
dagegen eindeutig. Dieselbe Nummer muss zweimal gelesen werden, bevor die Karte übernommen wird.

**Richtiges Artwork** — Zu 1.083 Kartennummern gibt es zwei Versionen: normal und Alt-Art, bei
identischer Nummer und identischem Namen. Welche vor der Kamera liegt, entscheidet ein
Bild-Fingerabdruck: für alle 2.166 betroffenen Karten vorab berechnet, zur Laufzeit mit dem
Kamerabild verglichen.

**Echte Cardmarket-Preise** — 3.865 von 3.868 Karten (99,9 %) mit Trendpreis, und zwar für die
**richtige Druckvariante**. Cardmarket führt pro Kartennummer im Schnitt 4,2 Produkte (Originaldruck,
Alt-Art, Nachdrucke, Promos), deren Preise weit auseinanderliegen — bei OP01-001 zwischen 1,87 € und
610 €. Die Zuordnung erkennt die Originaledition des Sets und unterscheidet darin normales Artwork
von Alt-Art. Wie sicher das war, steht in den Kartendetails; dort lässt sich auch jede andere
Version antippen, falls die Automatik danebenliegt.

**Sammlung** — Ordner, Dubletten-Zähler (×3), Suche über Name/Nummer/Set, Sortierung nach zuletzt
gescannt, Name, Set oder Preis. Karten lassen sich im Vollbild vergrößern. Bleibt dauerhaft
gespeichert.

**Decks** — Aktuelle Turnierdecks, dazu für jedes ein Balken: wie viele Karten davon du besitzt.
In der Deckliste steht je Karte „2/4" — was du hast und was das Deck braucht.

---

## Aufbau des Projekts

| Ordner | Inhalt |
| --- | --- |
| `android_app/` | Die Android-App (Flutter). Hauptvariante. |
| `docs/` | Die Web-Version (PWA), wird von GitHub Pages ausgeliefert |
| `scripts/` | Datenpflege: Kartenkatalog, Preise, Bild-Fingerabdrücke, Decklisten |
| `data/` | Zwischenstände der Datenpipeline (nicht versioniert) |
| `.github/workflows/` | Tägliche Aktualisierung von Preisen und Decklisten |

### Technik

Flutter + `camera` (Live-Bildstrom) + **Google ML Kit Text Recognition** — Texterkennung läuft
direkt auf dem Gerät, ohne Cloud und ohne Internetverbindung. Kartenkatalog und Preise liegen als
Asset in der App; nachgeladen werden nur die Kartenbilder (und die werden zwischengespeichert).

---

## Selbst bauen

```bash
cd android_app
flutter pub get
flutter test                        # 31 Tests der Erkennungslogik
flutter build apk --release --split-per-abi
# Ergebnis: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Die APK wird mit dem Flutter-Debug-Schlüssel signiert — ausreichend zum Selbstinstallieren, für
den Play Store bräuchte es einen eigenen Signaturschlüssel.

### Daten aktualisieren

```bash
npm install
npm run data:all     # Katalog, Preise, Bild-Fingerabdrücke, Decks, verteilen
npm test             # Erkennungslogik und Preise prüfen
```

Einzelne Schritte: `data:catalog`, `data:prices`, `data:hashes`, `data:decks`, `data:sync`.
Ein erneuter `data:catalog`-Lauf übernimmt vorhandene Preise und Fingerabdrücke, statt sie zu
verwerfen.

---

## Datenquellen

| Was | Quelle |
| --- | --- |
| Kartenkatalog | [`one-piece-card-game-json`](https://www.npmjs.com/package/one-piece-card-game-json) (npm) |
| Kartenbilder | [en.onepiece-cardgame.com](https://en.onepiece-cardgame.com) (offizielle Bandai-Seite) |
| Preise | [Cardmarket](https://www.cardmarket.com) — die täglichen Export-Dateien, die Cardmarket selbst veröffentlicht und ausdrücklich zur Nutzung in eigenen Anwendungen freigibt |
| Turnierdecks | [onepiecetopdecks.com](https://onepiecetopdecks.com) — automatisierte Zugriffe laut `robots.txt` erlaubt, eine Seite pro Tag |

Dieses Projekt ist ein privates Hilfsmittel und steht in keiner Verbindung zu Bandai, Cardmarket
oder onepiecetopdecks.com. One Piece und alle Kartenbilder gehören ihren jeweiligen Rechteinhabern.

---

## Bekannte Grenzen

- **Preise sind tagesaktuell, aber nicht in Echtzeit.** Eine GitHub Action holt sie einmal täglich,
  die App lädt sie beim Start. Innerhalb eines Tages ändern sie sich nicht — Cardmarkets
  Trendpreis tut das ohnehin nicht stündlich.
- **Druckvarianten-Zuordnung beruht auf zwei Annahmen.** Cardmarket liefert keine Editionsnamen,
  nur Nummern; welche Edition das Originalset ist, wird aus den enthaltenen Kartennummern
  abgeleitet (die zuerst angelegte „reine" Edition eines Sets). Und wo zwei Produkte in einer
  Edition stehen, gilt die teurere als Alt-Art — Cardmarket benennt sie nicht unterschiedlich.
  Rund 80 % der Karten sind dadurch eindeutig oder als Paar zugeordnet, der Rest ist in der App
  als unsicher gekennzeichnet und manuell korrigierbar.
- **Keine Länder- oder Sprachfilterung.** Die Export-Dateien enthalten nur europaweite Aggregate
  (Trend, Durchschnitt, Tiefstpreis). Verkäuferland, Kartensprache und Zustand gibt es bei
  Cardmarket nur auf Angebotsebene, und dorthin führt nur die API — die ist für neue Anträge
  geschlossen.
- **Artwork-Erkennung unter Kamerabedingungen ungetestet** — die Logik ist an 150 echten
  Alt-Art-Karten geprüft, aber mit Katalogbildern, nicht mit Fotos bei Zimmerlicht.
- Die Web-Version hat die neuen Tabs (Sammlung, Decks) nicht; sie ist die ältere, einfachere Fassung.
