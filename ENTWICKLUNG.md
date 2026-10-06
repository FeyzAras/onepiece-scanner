# Entwicklerhandbuch

Dieses Dokument richtet sich an jemanden, der das Projekt übernimmt — Mensch oder KI. Es erklärt
nicht nur *was* gebaut wurde, sondern *warum es so gebaut wurde*, welche Wege nicht funktionieren,
und wo die Fallstricke liegen. Die Bedienung steht in [ANLEITUNG.md](ANLEITUNG.md), der Überblick
in [README.md](README.md).

---

## 1. In zwei Minuten startklar

```bash
# Android-App bauen
cd android_app
flutter pub get
flutter test                                  # 53 Tests, laufen ohne Gerät
flutter build apk --release --split-per-abi   # -> build/app/outputs/flutter-apk/

# Daten aktualisieren
npm install
npm run data:all     # Katalog, Preise, Bild-Fingerabdrücke, Decks, verteilen
npm test             # prüft Erkennungslogik und Preise
```

### Werkzeugkette auf dem ursprünglichen Rechner

Auf dem Entwicklungsrechner war **nichts** installiert — kein Node, kein Git, kein Java, kein
Flutter. Alles liegt portabel unter `C:\Users\<Benutzer>\Dev\.toolchain\`:

| Werkzeug | Pfad | Version |
| --- | --- | --- |
| Node + npm | `.toolchain/node/` | 24.21 |
| Git | `.toolchain/git/cmd/git.exe` | 2.56 |
| GitHub CLI | `.toolchain/gh/bin/gh.exe` | 2.102 |
| JDK | `.toolchain/jdk17/` | Temurin 17 |
| Android SDK | `.toolchain/android-sdk/` | API 36, build-tools 36 |
| Flutter | `.toolchain/flutter/` | 3.47.6 |

`.toolchain/env.ps1` setzt alle Pfade. In jeder PowerShell-Sitzung einmal:

```powershell
. C:\Users\<Benutzer>\Dev\.toolchain\env.ps1
```

Nichts davon liegt in der Systemumgebung — ohne dieses Skript findet die Shell die Werkzeuge nicht.

---

## 2. Aufbau

```
android_app/          Die Android-App (Flutter) — das eigentliche Produkt
  lib/
    main.dart           Navigation, Zustand, Zusammenspiel der Teile
    scanner_view.dart   Kamera, Texterkennung, Mehrfachbestätigung
    card_matcher.dart   Erkennung: Kartennummer -> Karte, Artwork-Auswahl
    image_hash.dart     Bild-Fingerabdruck (dHash) aus dem Kamerabild
    card_model.dart     Kartendaten und Preis-Datenmodell
    collection_view.dart Sammlung: Raster, Suche, Sortierung, Kartendetails
    collection_store.dart Dauerhafte Speicherung (Ordner, Scans, Preiswahl)
    collection_export.dart CSV-Export
    decks_view.dart     Deck-Tab mit Sammlungsabgleich
    deck_model.dart     Decklisten einlesen und nachladen
    price_store.dart    Tagesaktuelle Preise nachladen
    widgets.dart        Gemeinsame Bausteine und Farben
  assets/             cards.json, decks.json (in die App eingebacken)
  test/               53 Tests, laufen ohne Gerät

scripts/              Datenpflege (Node, läuft nur beim Entwickeln/in CI)
docs/                 Web-Version (PWA) + die Datendateien, die die App nachlädt
data/                 Zwischenstände (nicht versioniert)
.github/workflows/    Tägliche Aktualisierung von Preisen und Decks
```

---

## 3. Die Datenpipeline

Vier Schritte, **die Reihenfolge ist wichtig**:

```
1. scripts/build-db.js              npm-Paket -> data/cards.normalized.json
2. scripts/fetch-cardmarket.js      Cardmarket-Exporte -> data/cm_*.json
   scripts/import-cardmarket-prices.js  ordnet Preise den Karten zu
3. scripts/build-image-hashes.js    lädt ~2.200 Bilder, berechnet Fingerabdrücke
4. scripts/fetch-decks.js           Turnierdecks -> docs/data/decks.json
   scripts/build-price-file.js      schlanke Preisdatei -> docs/data/prices.json
   scripts/sync-cards.js            verteilt alles an App und Web
```

`npm run data:all` macht das in der richtigen Reihenfolge.

**Fallstrick:** `build-db.js` baut den Katalog von Grund auf neu. Ohne Gegenmaßnahme würde das
die Preise und Bild-Fingerabdrücke löschen, die Schritt 2 und 3 hinzugefügt haben. Das Skript
übernimmt sie deshalb aus der vorhandenen Datei (`carryOver`). Wenn du dort etwas änderst, achte
darauf, dass das erhalten bleibt — sonst sind nach einem Lauf still alle Preise weg.

### Datenquellen

| Was | Woher | Besonderheit |
| --- | --- | --- |
| Kartenkatalog | npm `one-piece-card-game-json` | englischer + japanischer Katalog |
| Kartenbilder | `en.onepiece-cardgame.com` | direkt verlinkt, nicht mitgeliefert |
| Preise | `downloads.s3.cardmarket.com` | Spiel-ID **18** = One Piece |
| Turnierdecks | `onepiecetopdecks.com` | Seitenliste aus deren Sitemap |

---

## 4. Wie die Erkennung funktioniert

```
Kamerabild (NV21)
   │
   ├─► ML Kit Texterkennung (auf dem Gerät, lateinische Schrift)
   │      └─► Rohtext
   │             └─► card_matcher: Kartennummer suchen (OP07-055)
   │                    └─► tolerant gegen OCR-Fehler, nur real existierende IDs
   │
   └─► image_hash: Fingerabdruck des Rahmeninhalts
          └─► entscheidet bei mehreren Artworks zur selben Nummer

   Beides zusammen -> Kandidat
          └─► muss 2× hintereinander bestätigt werden
                 └─► wandert in die Sammlung
```

### Warum die Kartennummer und nicht der Name

Der Name allein führt zu Fehltreffern: Viele Karten heißen gleich, und Namen anderer Karten stehen
im Effekttext. Beim Scannen von „Snake Dance" wurden reihum „Gina" und „Portgas.D.Ace" erkannt,
weil deren Namen auf der Karte stehen.

**Deshalb: Ohne gelesene Kartennummer wird nichts übernommen.** Der Name dient nur noch als
Gegenprobe (`how == 'number+name'`) und als Hinweis an den Nutzer, wenn die Nummer unlesbar war.

Die Nummernerkennung ist bewusst tolerant (`_candidateRe` in `card_matcher.dart`): OCR liest oft
`oo01.001` statt `OP01-001`. Es werden Varianten gebildet und **nur akzeptiert, was einer real
existierenden Karten-ID entspricht** — dadurch sind Falschtreffer praktisch ausgeschlossen.

### Warum zweimal bestätigen

Ein einzelner Fehlgriff landete sonst sofort in der Sammlung. `kConfirmationsNeeded = 2` in
`scanner_view.dart`. Falls die Erkennung zu träge wirkt, ist das die erste Stellschraube.

### Artwork-Unterscheidung

Zu **1.083 Kartennummern gibt es zwei Karten**: normales Artwork und Alt-Art, bei identischer
Nummer und identischem Namen. Am Text sind sie nicht unterscheidbar.

Lösung: `scripts/build-image-hashes.js` lädt alle 2.166 betroffenen Bilder und berechnet je einen
dHash (9×8 Graustufen, waagerechte Nachbarvergleiche, 64 Bit). Die App berechnet denselben Hash
aus dem Kamerabild (`image_hash.dart`) und nimmt die ähnlichere Version.

**Beide Berechnungen müssen identisch bleiben** — die in JavaScript (`build-image-hashes.js`) und
die in Dart (`image_hash.dart`). Ändert man eine, passen die Werte nicht mehr zusammen und die
Zuordnung wird zufällig.

Liegt der Abstand zwischen den Kandidaten unter `kArtworkDecisionMargin` (4 Bit), gilt die
Entscheidung als unsicher und es wird die Standardversion genommen. Der Nutzer kann in den
Kartendetails umschalten.

---

## 5. Preise: das kniffligste Thema

### Das Problem

Cardmarket führt **pro Kartennummer im Schnitt 4,2 Produkte**, teils über 20: Originaldruck,
Alt-Art, Nachdrucke in späteren Sets, Promos, Turnierpreise. Die Preise liegen weit auseinander —
bei OP01-001 zwischen 1,87 € und 610 €. Bei rund 80 % der Nummern beträgt die Spanne mindestens
Faktor 5.

Eine frühere Fassung nahm einfach das älteste Produkt. Dadurch bekamen normales Artwork und
Alt-Art denselben, viel zu niedrigen Preis.

### Die Lösung

Cardmarket liefert **keine Editionsnamen**, nur Nummern (`idExpansion`). Welche Edition das
Originalset ist, wird aus den enthaltenen Kartennummern abgeleitet: Enthält eine Edition zu über
90 % Karten mit der Vorsilbe `OP01`, ist es das OP01-Set. Pro Set gilt die **zuerst angelegte**
solche Edition als Originaldruck.

Innerhalb dieser Edition bleiben meist ein oder zwei Produkte:

| Fall | Behandlung | Anzahl |
| --- | --- | --- |
| 1 Produkt | eindeutig | 1.898 |
| 2 Produkte | günstigere = normal, teurere = Alt-Art | 630 |
| mehr / keine Edition | unsicher, günstigste als Normalversion | 285 |

### Zwei Annahmen, die man kennen muss

1. **„Originaledition" = zuerst angelegte reine Edition.** Ohne Editionsnamen nicht beweisbar.
   Besitzt jemand einen Nachdruck, bekommt er den Preis des Originals.
2. **Bei zwei Produkten ist die teurere die Alt-Art.** Cardmarket benennt sie nicht
   unterschiedlich. Wo beide ähnlich teuer sind, ist die Wahl folgenlos; wo sie weit
   auseinanderliegen, trifft die Annahme zu.

Beides ist in der App sichtbar (`PriceConfidence`) und pro Karte korrigierbar.

### Tagesaktualität

Die Preise stecken **nicht** fest in der App. `docs/data/prices.json` (159 KB) wird täglich per
GitHub Action aktualisiert, die App lädt sie beim Start (`price_store.dart`). Ohne Netz gelten
die zuletzt geladenen, davor die mitgelieferten.

**Wichtig:** Die Preiswahl des Nutzers wird als **Platz in der Versionsliste** gespeichert, nicht
als Betrag. Sonst würde ausgerechnet die vom Nutzer korrigierte Karte als einzige auf einem alten
Preis einfrieren, während sich alle anderen aktualisieren.

---

## 6. Was nicht funktioniert — bitte nicht erneut versuchen

Diese Wege wurden untersucht und sind Sackgassen. Die Begründung steht dabei, damit man sie bei
geänderter Lage neu bewerten kann.

### Cardmarket-API

Geschlossen. Cardmarkets eigene Hilfeseite: *„Currently, we are not accepting applications for
access to the Cardmarket API."* Im Juli 2025 wurde erklärt, die öffentlichen Export-Dateien
**ersetzen** die Pläne zur Ausweitung des API-Zugangs. Es gibt ein Partnerprogramm (TCG PowerTools,
Scryfall), aber keinen veröffentlichten Bewerbungsweg.

### Preise nach Verkäuferland oder Kartensprache

Nicht möglich. Die Export-Dateien enthalten nur europaweite Aggregate (`avg`, `low`, `trend`,
`avg1`, `avg7`, `avg30`, jeweils auch für Foil). Verkäuferland, Sprache und Zustand existieren bei
Cardmarket nur auf **Angebotsebene** — erreichbar nur über die API oder die Website.

### cardmarket.com auslesen

Die Website steckt vollständig hinter einer Cloudflare-Prüfung. Selbst `robots.txt` kommt nur als
JavaScript-Challenge zurück. Das ist ein klares „automatisierte Zugriffe unerwünscht" — wurde
deshalb nicht weiterverfolgt. Der **Datei-Server** `downloads.s3.cardmarket.com` ist davon nicht
betroffen und ausdrücklich zur Nutzung freigegeben.

### Englischen vom japanischen Druck unterscheiden

Nicht zuverlässig möglich. Beide tragen dieselbe Kartennummer in lateinischer Schrift. Das Artwork
ist meist identisch, nur der Kartentext unterscheidet sich — zu wenig für einen 64-Bit-Bildhash.
Eine Spracherkennung bräuchte ein zusätzliches japanisches ML-Kit-Modell in der App, und selbst
dann ließen sich die Preise nicht trennen, weil Cardmarket ohne Editionsnamen nicht verrät, welches
Produkt der japanische Druck ist.

**Hinweis:** Der „japanische" Katalog des npm-Pakets enthält trotz des Namens dieselben lateinischen
Namen und englischen Effekttexte — nur die Bildadressen unterscheiden sich. Japanische Karten
werden deshalb ohnehin erkannt. Aufgenommen wurden lediglich die 115 Karten, die nie auf Englisch
erschienen sind (`jpOnly`).

---

## 7. Stolpersteine, die Zeit gekostet haben

**R8 zerlegt ML Kit.** Der Release-Build lief, aber jede Bilderkennung scheiterte zur Laufzeit mit
`InputImageConverterError … NullPointerException`. Ursache: R8 entfernt Teile, die ML Kit erst zur
Laufzeit über Reflection lädt. Deshalb ist `isMinifyEnabled = false` in `android/app/build.gradle.kts`.
Wer die Optimierung wieder einschalten will, braucht die Keep-Regeln aus `proguard-rules.pro` —
und muss es auf einem echten Gerät testen, nicht nur bauen.

**Gradle-Speicher.** Die Flutter-Vorlage setzt `-Xmx8G -XX:MaxMetaspaceSize=4G`. Auf einem Rechner
mit 16 GB RAM reichte das, um den Build abstürzen zu lassen. Steht jetzt auf 2 GB
(`android/gradle.properties`) — für dieses Projekt völlig ausreichend.

**PowerShell und UTF-8.** `Get-Content … | Set-Content` in Windows PowerShell 5.1 liest Dateien
ohne BOM als Windows-1252 und schreibt sie als UTF-8 zurück — dabei werden alle Umlaute zerstört.
Für Textersetzungen in Quelldateien `[System.IO.File]::ReadAllText` / `WriteAllText` mit
`UTF8Encoding($false)` verwenden.

**PowerShell-Pfade und .NET.** `Set-Location` ändert **nicht** das Arbeitsverzeichnis für
.NET-Methoden wie `[System.IO.File]::ReadAllBytes`. Dort absolute Pfade verwenden.

**onepiecetopdecks.com ist wählerisch.** Node-eigene `fetch`-Anfragen bekommen HTTP 403, `curl`
funktioniert. Und kurioserweise: eine kurze Plattform-Kennung (`Mozilla/5.0 (Windows NT 10.0;
Win64; x64)`) kommt durch, eine ausführliche Chrome-Kennung wird blockiert. Außerdem drosselt die
Seite bei schnell aufeinanderfolgenden Abrufen — daher 2,5 Sekunden Pause zwischen den Seiten.

**Deckmenge.** Die Seiten enthalten 12.635 Decks, aber nur 1.864 Archetypen. Ungefiltert wären das
7,9 MB — zu viel fürs Handy. Je Archetyp werden die fünf neuesten behalten (`MAX_JE_ARCHETYP`),
das ergibt 1,55 MB bei 96 % Kartenabdeckung.

---

## 8. Veröffentlichen

```powershell
. C:\Users\<Benutzer>\Dev\.toolchain\env.ps1
cd android_app
flutter build apk --release --split-per-abi

cd ..
gh release create v0.8.0 `
  "<Pfad>\app-arm64-v8a-release.apk" `
  --title "v0.8.0 – …" --notes-file <datei.md>
```

Hochgeladen wird nur die **arm64**-Variante (aktuelle Handys). Die APK ist mit dem
Flutter-Debug-Schlüssel signiert — ausreichend zum Selbstinstallieren, für den Play Store bräuchte
es einen eigenen Signaturschlüssel.

### Automatik auf GitHub

| Workflow | Wann | Was |
| --- | --- | --- |
| `update-prices.yml` | täglich 04:41 UTC | Cardmarket-Preise -> `docs/data/prices.json` |
| `update-decks.yml` | täglich 04:17 UTC | Turnierdecks -> `docs/data/decks.json` |

Beide committen nur bei echten Änderungen. Beide brauchen den `workflow`-Zugriff am GitHub-Token —
ohne den lassen sich die Dateien unter `.github/workflows/` nicht hochladen
(`gh auth refresh -h github.com -s workflow`).

Die App lädt beide Dateien direkt von `raw.githubusercontent.com`. Ändert sich der Repository-Pfad,
müssen die Adressen in `price_store.dart` und `deck_model.dart` angepasst werden.

---

## 9. Was als Nächstes anstünde

**Offen, weil nur am echten Gerät prüfbar:**
- Trifft die Artwork-Erkennung unter Zimmerlicht? Getestet ist sie an 150 Karten, aber mit
  Katalogbildern statt Kamerafotos.
- Ist die Erkennung im Alltag schnell genug, oder nervt die doppelte Bestätigung?
- Stimmen die Preise gegen den echten Markt?

**Naheliegende Erweiterungen:**
- Sammlungswert über die Zeit verfolgen (Preisdaten kommen ja täglich)
- Deckbau: eigene Listen anlegen statt nur fremde ansehen
- Mehrere Karten gleichzeitig scannen (Binderseite)
- Die Web-Version nachziehen — sie steht auf dem Stand vor den Tabs

**Bewusst nicht gemacht:**
- Web-Version aktuell halten (vom Nutzer als nicht benötigt eingestuft)
- Play-Store-Veröffentlichung (bräuchte Signaturschlüssel, Datenschutzerklärung, Bildrechte-Klärung)
