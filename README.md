# One Piece TCG Scanner

Kamera auf eine One-Piece-Karte halten — sie wird **automatisch erkannt** und landet mit echtem
Cardmarket-Preis in deiner Sammlung. Kein Knopfdruck pro Karte.

---

## 📲 Aufs Handy laden

### ⬇️ [**onepiece-scanner-arm64.apk herunterladen**](https://github.com/FeyzAras/onepiece-scanner/releases/latest/download/onepiece-scanner-arm64.apk)

Diesen Link am **Handy** antippen — er zeigt immer auf die neueste Fassung, ohne Umweg über
die Release-Seite. Eine Datei für aktuelle Android-Geräte (arm64, auch Samsung S24), rund 37 MB.

Beim allerersten Mal fragt Android nach der Erlaubnis, Apps aus dieser Quelle zu installieren
→ erlauben, zurück, installieren. Play Protect meldet „unbekannter Entwickler"
→ *Trotzdem installieren*. Danach genügt Antippen.

> **Updates legen sich über die alte Fassung — die Sammlung bleibt erhalten.**
> Nicht vorher deinstallieren, das würde sie löschen.
>
> Ab Version 0.9.0 meldet die App neue Versionen selbst und installiert sie auf Antippen.
> Der Link oben ist dann nur noch für die Erstinstallation nötig.

Alle Fassungen: [Releases](https://github.com/FeyzAras/onepiece-scanner/releases) ·
Bedienung: [ANLEITUNG.md](ANLEITUNG.md) ·
Für Entwickler: [ENTWICKLUNG.md](ENTWICKLUNG.md)

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

**Richtiges Artwork** — Zu über 1.000 Kartennummern gibt es mehrere Motive: Normalversion,
Parallelen, Nachdrucke, bei identischer Nummer und identischem Namen. Der Katalog kennt alle 4.958
Motive. Ob Normalversion oder Alt-Art vor der Kamera liegt, entscheidet ein Bild-Fingerabdruck,
vorab berechnet und zur Laufzeit mit dem Kamerabild verglichen; weitere Motive wählt man in den
Kartendetails per Bild.

**Echte Cardmarket-Preise** — Trendpreis, täglich aktualisiert, wie bei Scryfall. Cardmarket
führt pro Kartennummer oft mehrere Versionen (Booster-Druck, Parallele, Nachdrucke, Promos,
asiatische und japanische Auflage) mit weit auseinanderliegenden Preisen — OP17-040 etwa viermal
zwischen 0,06 € und 74 €. In den Kartendetails steht **jede Version mit dem Namen ihrer
Cardmarket-Ausgabe und ihrem Preis**; man tippt die eigene an. Von sich aus wählt die App die
englische Ausgabe, aus der das Motiv stammt, und sagt, wie sicher das war.

**Sammlung** — Ordner, Dubletten-Zähler (×3), Suche über Name/Nummer/Set, Sortierung nach zuletzt
gescannt, Name, Set oder Preis. Karten lassen sich im Vollbild vergrößern. Bleibt dauerhaft
gespeichert und lässt sich **sichern**: eine CSV für Excel und eine JSON-Datei, die sich
verlustfrei wieder einlesen lässt.

**Übersicht** — der Wert deiner Sammlung als Kurve, zurück bis Oktober 2026, mit Veränderung
seit 7 und 30 Tagen. Je Set der Fortschritt („OP01 · Romance Dawn — 87 von 175"), Alt-Arts
getrennt gezählt, mit den fehlenden Karten und was sie kosten. In den Kartendetails die
Preiskurve jeder einzelnen Karte.

**Wunschliste** — Karten vormerken, mit den Kosten zum heutigen Preis. Fehlende Karten eines
Sets oder Turnierdecks mit einem Tipp übernehmen, als Deckliste an Händler schicken. Scannst du
eine gesuchte Karte, wird sie automatisch abgehakt.

**Listen einlesen** — Sicherungsdatei, eigener CSV-Export, Deckliste (`4xOP01-001 …`), eine
Nummer je Zeile oder ein Cardmarket-Bestandsexport. Das Format wird selbst erkannt, schief
geschriebene Nummern (`OP1-1`, `OPO1-001`) werden korrigiert, und vor dem Übernehmen zeigt eine
Vorschau, was erkannt wurde und was nicht. Ein Fehlgriff lässt sich rückgängig machen.

**Decks** — Turnierdecks aus allen Sets (OP01–OP17), englisches und japanisches Format: rund 4.900
Listen aus 1.864 Archetypen. Für jedes Deck ein Balken, wie viele Karten davon du besitzt; in der
Deckliste steht je Karte „2/4" — was du hast und was das Deck braucht.

**Eigene Decks** — Leader wählen, Karten hinzufügen (nur was zum Leader passt), laufende Prüfung
nach den offiziellen Regeln: 50 Karten, höchstens 4 je Nummer samt Alt-Arts, Farben des Leaders,
Sonderregeln einzelner Leader. Dazu Kostenkurve, Abgleich mit der Sammlung, fehlende Karten auf
die Wunschliste, Teilen und Einfügen als Deckliste. Ein Turnierdeck lässt sich als Vorlage
übernehmen. Die Prüfung ist an 4.918 echten Turnierdecks getestet.

**Japanische Karten** — funktionieren ohne Zusatzschritt, weil die Kartennummer auch dort
lateinisch aufgedruckt ist. 115 Karten, die nie auf Englisch erschienen sind, sind zusätzlich im
Katalog und entsprechend gekennzeichnet.

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
flutter test                        # 291 Tests, laufen ohne Gerät
npm run test:data                   # 23 Tests der Datenaufbereitung (aus dem Hauptordner)
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
| Turnierdecks | [onepiecetopdecks.com](https://onepiecetopdecks.com) — automatisierte Zugriffe laut `robots.txt` erlaubt. Die Seitenliste kommt aus der Sitemap, gelesen wird einmal täglich mit Pause zwischen den Seiten |

Dieses Projekt ist ein privates Hilfsmittel und steht in keiner Verbindung zu Bandai, Cardmarket
oder onepiecetopdecks.com. One Piece und alle Kartenbilder gehören ihren jeweiligen Rechteinhabern.

---

## Bekannte Grenzen

- **Preise sind tagesaktuell, aber nicht in Echtzeit.** Eine GitHub Action holt sie einmal täglich,
  die App lädt sie beim Start. Innerhalb eines Tages ändern sie sich nicht — Cardmarkets
  Trendpreis tut das ohnehin nicht stündlich.
- **Die automatische Version ist ein Vorschlag.** Innerhalb einer Cardmarket-Ausgabe heißen alle
  Versionen einer Nummer gleich; welche Normalversion und welche Parallele ist, wird über den Preis
  abgeleitet (die teurere ist die Parallele). 85 % der Motive sind so eindeutig oder als Paar
  zugeordnet, der Rest ist als unsicher gekennzeichnet — und jede Version ist mit Namen wählbar.
  Für einige Turnier- und Sammelmotive findet sich keine passende Version; dort wählt man selbst.
- **Bis Version 0.12 waren die Preise von OP05 bis OP16 und EB01 bis EB03 japanisch bzw.
  asiatisch** (Cardmarket legt diese Ausgaben zuerst an). Seit 0.13.0 englisch; der Preisverlauf
  vor dem 24.11.2026 lässt sich nicht nachträglich korrigieren.
- **Kein Länderfilter.** Die Export-Dateien enthalten europaweite Aggregate (Trend, Durchschnitt,
  Tiefstpreis). Japanische und asiatische Auflagen führt Cardmarket als eigene Ausgaben — die sind
  wählbar. Verkäuferland und Zustand gibt es nur auf Angebotsebene, und dorthin führt nur die API,
  die für neue Anträge geschlossen ist.
- **Deckprüfung ohne Sperrliste.** Verbotene oder begrenzte Karten stehen nicht in den Daten;
  vor einem Turnier die offizielle Liste ansehen.
- **Artwork-Erkennung unter Kamerabedingungen ungetestet** — die Logik ist an 150 echten
  Alt-Art-Karten geprüft, aber mit Katalogbildern, nicht mit Fotos bei Zimmerlicht.
- Die Web-Version hat die neuen Tabs (Sammlung, Decks) nicht; sie ist die ältere, einfachere Fassung.
