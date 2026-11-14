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
flutter test                                  # 182 Tests, laufen ohne Gerät
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
    collection_store.dart Dauerhafte Speicherung (Ordner, Scans, Preiswahl, Sicherung)
    collection_export.dart CSV-Export und JSON-Sicherung
    collection_import.dart Listen einlesen — Formaterkennung und Zuordnung, ohne UI
    import_view.dart    Import-Blatt: Quelle, Vorschau, Zielordner, Einfügemodus
    csv_reader.dart     CSV zerlegen (Quoting, Trennzeichen, Kodierung)
    update_service.dart Neue Version finden, herunterladen, prüfen
    update_view.dart    Update-Hinweis, Update-Blatt, Warnung bei abgelehntem Update
    app_installer.dart  Brücke zum Android-Installer (MethodChannel)
    decks_view.dart     Deck-Tab mit Sammlungsabgleich
    deck_model.dart     Decklisten einlesen und nachladen
    price_store.dart    Tagesaktuelle Preise nachladen
    widgets.dart        Gemeinsame Bausteine und Farben
  assets/             cards.json, decks.json (in die App eingebacken)
  test/               182 Tests, laufen ohne Gerät
  android/app/src/main/kotlin/…/InstallChannel.kt, InstallStatusReceiver.kt
                      PackageInstaller-Sitzung für die Aktualisierung aus der App

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

### Der Import benutzt dieselbe Nummernerkennung

`collection_import.dart` löst Nummern in zwei Stufen auf: erst normalisiert (`OP1-1` → `OP01-001`),
dann über `CardMatcher.findNumber` — dieselbe Funktion, die auch die Kamera benutzt. Sie fängt
`OPO1-001` ab, weil sie Präfixe mit Hamming-Abstand 1 prüft und `O`/`0` sowie `I`/`1` tauscht.

**Wichtig und leicht zu übersehen:** Die Toleranz greift nur im **Präfix**. Der dreistellige
Zahlenteil muss stimmen — `OPO1-OO1` wird *nicht* gefunden. Grund ist `_candidateRe`, das dort
`\d{3}` verlangt. Das ist bewusst so: Akzeptiert wird ausschließlich, was einer real existierenden
Karten-ID entspricht, und je mehr Toleranz im Zahlenteil, desto eher trifft man die falsche Karte.

Drei Entscheidungen, die beim Import bewusst so getroffen wurden:

| Entscheidung | Begründung |
| --- | --- |
| **Eigener CSV-Leser** statt eines Pakets | Rund hundert Zeilen, vollständig testbar. Das Projekt kommt auch sonst ohne Zusatzpakete aus, wo es sich vermeiden lässt (Netzzugriffe über nacktes `HttpClient` statt `http`) |
| **`file_selector` statt `file_picker`** | Von flutter.dev gepflegt, macht nur „eine Datei öffnen". R8 ist in diesem Projekt abgeschaltet, weil ML Kit sonst stirbt — jede weitere native Abhängigkeit ist in dieser Lage ein Risiko, das sich erst auf dem Gerät zeigt |
| **Datei-Auswahl ohne Typfilter** | Android graut Dateien aus, deren MIME-Typ nicht im Filter steht. Eine über Chrome geladene CSV kommt oft als `application/octet-stream` an, eine aus WhatsApp als `application/vnd.ms-excel`. Geprüft wird deshalb der **Inhalt**, nicht der angebliche Typ |

`Deck.parseCardList` (`deck_model.dart`) wird **nicht** wiederverwendet. Sie ist für ein maschinell
erzeugtes Format gebaut (`indexOf('x')`, Trennung nur am Leerzeichen) und scheitert an
`4x OP01-001`, `OP01-001 x3` und am Unicode-`×`. Sie hat eigene Tests und bedient die Deck-Pipeline —
anfassen bringt Risiko ohne Gewinn. Ein Test sichert ab, dass beide Parser auf der strengen Form
`NxID` dasselbe liefern.

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

### Preis-APIs anderer Anbieter (Marktüberblick, geprüft am 2026-11-13)

Die Frage „gibt es statt der Export-Dateien eine API?" wurde einmal gründlich durchgesehen. Ergebnis
in Kurzform: **Für den europäischen Markt in Euro gibt es nichts Besseres als die Cardmarket-Exporte.**
Jeder Anbieter, der EUR-Preise verspricht, gibt genau diese Daten weiter — gegen Geld und mit
ungeklärter Lizenz.

| Anbieter | Markt / Währung | Urteil |
| --- | --- | --- |
| **CardTrader** (`api.cardtrader.com/api/v2`) | EU / **EUR** | **Einziger echter Kandidat**, siehe unten |
| **tcgcsv.com** | USA / USD | Brauchbar als kostenlose Zweitmeinung, siehe unten |
| Scrydex | USA / USD | Ab 29 $/Monat. One Piece ist *Beta*, Preisquelle für One Piece nicht genannt. AGB verbieten „mirror, or commercially exploit" — unser Pipeline-Prinzip (Daten ins öffentliche Repo spiegeln) wäre damit ausgeschlossen |
| BerryWallet / PokéWallet | USD **und EUR** | Liefert erklärtermaßen Cardmarket-Werte (`avg`, `low`, `trend`, `avg1/7/30` — dieselben Felder wie unsere Exporte) für 20 €/Monat. Nirgends steht, woher diese Cardmarket-Daten stammen oder ob die Weitergabe lizenziert ist. Bezahlen für Daten, die wir offiziell und kostenlos bekommen |
| apitcg.com | USD | Doku-Route liefert 404, kein Betreiber erkennbar, One-Piece-Preise nicht belegt. Nicht verwertbar |
| optcgapi.com | nicht angegeben | Kostenloses Ein-Personen-Hobbyprojekt, keine Auth. Währung, Preisquelle und Feldnamen sind nirgends dokumentiert, letzter Update-Eintrag März 2026. Höchstens als Kartendaten-Reserve |

**CardTrader** ist deshalb interessant, weil die API **Angebotsebene** liefert und damit genau das
aufmacht, was bei Cardmarket verschlossen ist (siehe nächster Abschnitt):
`GET /marketplace/products?expansion_id=…` gibt je Blueprint die 25 günstigsten Angebote mit
`price.cents` + `price.currency` (EUR), `properties_hash.condition`, Sprache, `quantity` und
`user.country_code`. Auth per `Authorization: Bearer <token>`, Limits 200 Anfragen/10 s allgemein,
10/s auf den Marktplatz.

Drei Dinge vor einem Einbau klären:
1. **Kommt man überhaupt an einen Token?** Die offizielle Doku (`cardtrader.com/en/docs/api/full`)
   antwortet automatisierten Abrufen mit HTTP 403 und war nicht lesbar. Sie sagt laut Suchtreffern
   „obtain the auth token inside the settings page on your CardTrader profile"; mehrere
   Drittanbieter-Integrationen behaupten dagegen, es brauche ein aktives Verkäuferkonto mit
   bestimmtem Plan. **Ungeklärt — im eingeloggten Profil nachsehen.**
2. **Anderer Markt.** CardTrader ist deutlich kleiner als Cardmarket. Bei Nischenkarten können ein,
   zwei Angebote den „Preis" bestimmen. Es ersetzt Cardmarket nicht, es ergänzt es.
3. **Nur günstigste Angebote, keine Historie.** Aus 25 Angeboten lässt sich ein „ab X €" bilden,
   kein Trend und kein Durchschnitt. `price_cents` taucht nur beim CSV-Import auf, in der
   Marktplatz-Antwort ist der Preis ein Objekt.

**tcgcsv.com** ist geprüft und passt technisch perfekt zu unserer Pipeline (täglicher Abruf per
Action, App lädt fertige JSON): Kategorie **68** = One Piece Card Game, Abruf über
`https://tcgcsv.com/tcgplayer/68/{groupId}/prices`, Felder `lowPrice`, `midPrice`, `highPrice`,
`marketPrice`, `directLowPrice`, `subTypeName`, Aktualisierung täglich gegen 20:00 UTC, Archiv
zurück bis 2024-02-08. Zur Erlaubnis sagt die FAQ wörtlich: *„How do I get permission to use
TCGCSV? You don't. Permission is implicit."* Auflagen: höchstens ein Sync pro Tag, vorher
`last-updated.txt` prüfen, eigener `User-Agent`, keine Abrufe direkt aus der App heraus, unter
10.000 Anfragen/24 h. **Aber: US-Markt in Dollar.** Für einen deutschen Sammler ist das eine
Zweitmeinung, kein Ersatz.

### Preise nach Verkäuferland oder Kartensprache

Nicht möglich. Die Export-Dateien enthalten nur europaweite Aggregate (`avg`, `low`, `trend`,
`avg1`, `avg7`, `avg30`, jeweils auch für Foil). Verkäuferland, Sprache und Zustand existieren bei
Cardmarket nur auf **Angebotsebene** — erreichbar nur über die API oder die Website.

> Teilweise entschärft: Über die CardTrader-API (oben) wären Zustand, Sprache und Verkäuferland
> erreichbar — allerdings für CardTrader-Angebote, nicht für Cardmarket-Angebote.

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

**PowerShell und stderr.** Windows PowerShell 5.1 macht aus jeder stderr-Zeile eines externen
Programms einen Fehlerdatensatz, sobald stderr umgeleitet wird. Mit `$ErrorActionPreference = 'Stop'`
bricht ein Skript dann mitten im Build ab, obwohl Flutter nur eine harmlose SDK-Warnung ausgab —
so beim ersten Release-Versuch von v0.9.0. `scripts/release.ps1` führt externe Programme deshalb
über `Nativ { … }` mit `'Continue'` aus und bewertet nur den Exitcode.

**Commit-Nachrichten mit Anführungszeichen.** `git commit -m @'…'@` zerlegt die Nachricht in
mehrere Argumente, sobald sie doppelte Anführungszeichen enthält (wieder PowerShell 5.1 beim
Übergeben an externe Programme). Längere Nachrichten in eine Datei schreiben und `git commit -F`
benutzen.

**Speicher beim Bauen.** Ein Release-Build im Hintergrund wurde einmal von Claude Code beendet, weil
der Rechner kaum noch freien Arbeitsspeicher hatte. Der Build braucht rund 2 GB. Vorher den freien
Speicher prüfen und lange Builds im Vordergrund laufen lassen. Nach `flutter clean` dauert ein Build
rund 7½ Minuten, ein Folgebuild gut eine Minute.

**onepiecetopdecks.com ist wählerisch.** Node-eigene `fetch`-Anfragen bekommen HTTP 403, `curl`
funktioniert. Und kurioserweise: eine kurze Plattform-Kennung (`Mozilla/5.0 (Windows NT 10.0;
Win64; x64)`) kommt durch, eine ausführliche Chrome-Kennung wird blockiert. Außerdem drosselt die
Seite bei schnell aufeinanderfolgenden Abrufen — daher 2,5 Sekunden Pause zwischen den Seiten.

**Deckmenge.** Die Seiten enthalten 12.635 Decks, aber nur 1.864 Archetypen. Ungefiltert wären das
7,9 MB — zu viel fürs Handy. Je Archetyp werden die fünf neuesten behalten (`MAX_JE_ARCHETYP`),
das ergibt 1,55 MB bei 96 % Kartenabdeckung.

### Drei stille Datenverluste (gefunden und behoben am 2026-11-13)

Alle drei verschwiegen ihren Schaden — das ist das Gemeinsame und der Grund, warum sie hier stehen.

**Der Export sicherte nur das Sichtbare.** `collection_view.dart` übergab dem Export-Knopf die
**gefilterte** Anzeigeliste. Wer einen Suchbegriff stehen hatte oder einen Ordner-Chip gesetzt hatte
und dann sicherte, bekam ohne Hinweis eine Teilsicherung. Zusätzlich gruppierte die Anzeige nur nach
Karten-ID — dieselbe Karte in zwei Ordnern wurde zu *einer* Zeile, der zweite Ordner fiel weg.
Jetzt: `CollectionExport.buildCsv` bekommt die vollständige Sammlung und gruppiert nach
`(Karten-ID, Ordner, Erkennungsart)`. Ist ein Filter aktiv, sagt eine Meldung ausdrücklich, dass
trotzdem alles gesichert wurde.

**Unbekannte Karten-IDs wurden beim Start gelöscht.** `main.dart` löste jeden gespeicherten Scan
über den Katalog auf und ließ fallen, was er nicht fand; der nächste Speichervorgang schrieb die
gekürzte Liste zurück. Ein App-Update, das eine ID ändert, hätte die betroffenen Karten unbemerkt
entfernt. Jetzt wandern sie nach `_unresolvedScans` und werden unverändert mitgeschrieben.

**Beschädigte Daten führten zum stillen Leerstart.** `CollectionStore.load()` fing jeden Lesefehler
ab und startete leer — der nächste Klick überschrieb die noch vorhandenen Rohdaten endgültig. Jetzt
wird der Rohtext unter `collection_v2_broken_<Zeitstempel>` gesichert (höchstens drei), und die
Sammlung zeigt einen unübersehbaren Hinweis.

**Dazu, gleicher Anlass:** `assets/decks.json` stand nicht in `pubspec.yaml` und landete deshalb nie
im APK. `DeckStore.loadBundled()` scheiterte immer still, der Deck-Tab funktionierte nur mit Netz.

---

## 8. Veröffentlichen

### Der Signaturschlüssel — vor allem anderen lesen

Android lässt ein Update nur zu, wenn es mit **demselben Schlüssel** signiert ist wie die
installierte App. Passt er nicht, bleibt nur Deinstallieren — und damit wäre die Sammlung des
Nutzers weg. Dieser Schlüssel ist das unersetzlichste Stück des Projekts.

| | |
| --- | --- |
| Arbeitskopie | `C:\Users\ArasFeyzullah\Dev\.secrets\onepiece-release.jks` |
| Herkunft | ursprünglich der Flutter-Debug-Schlüssel, erzeugt am 05.10.2026 |
| Gültig bis | **27.09.2056** |
| Alias / Passwort | `androiddebugkey` / `android` |
| **Soll-Fingerabdruck** | `CC:BD:78:F9:5F:9D:ED:20:8A:B9:6D:CC:DF:ED:50:A3:BE:70:95:E1:D6:CD:30:55:23:43:9C:F6:83:CB:04:BB` |

Der Fingerabdruck ist gegen die veröffentlichte v0.7.0 geprüft (`apksigner verify --print-certs`)
und stimmt überein — es ist nachweislich der Schlüssel aller bisherigen Releases.

Eingebunden über `android/key.properties` (nicht versioniert). **Fehlt die Keystore-Datei, bricht
der Build ab.** Das ist Absicht: Vorher stand hier `signingConfigs.getByName("debug")`, und wenn
`~/.android/debug.keystore` fehlt, erzeugt das Android-Werkzeug stillschweigend einen *neuen*
Schlüssel. Der Build läuft durch, die APK ist signiert — nur mit fremder Identität. Aufgefallen
wäre das erst auf dem Handy mit „App nicht installiert", und dann wäre es nicht mehr zu reparieren.

> ⚠️ **Geht diese Datei verloren, lässt sich die installierte App nie wieder aktualisieren.**
> Mindestens drei Kopien halten, davon eine außerhalb des Rechners (Passwortmanager als Anhang,
> verschlüsseltes Archiv auf einem Stick). Ein Backup gilt erst als bewiesen, wenn damit gebaut
> wurde und `apksigner verify --print-certs` denselben Fingerabdruck liefert.

### Versionsnummern

`android_app/pubspec.yaml` ist die einzige Quelle der Wahrheit. Build-Nummer nach der Regel
`major*10000 + minor*100 + patch` — 0.8.0 wird also `0.8.0+800`. Beim Bauen mit `--split-per-abi`
addiert Flutter `1000 × ABI`, arm64 ergibt `2800`.

**Pflicht: immer `--split-per-abi`, nie `-P force-version-code-ignoring-abi=true`.** Ein
universeller Build hätte `versionCode 800` — kleiner als die veröffentlichte `2001`, und Android
lehnt die Installation als Downgrade ab. Der Git-Tag `vX.Y.Z` muss zur pubspec-Version passen.

`package.json` trägt eine eigene Version für die Node-Datenpipeline. Die hat mit der App nichts zu
tun und wird bewusst nicht mitgezogen.

### Ablauf

```powershell
. C:\Users\<Benutzer>\Dev\.toolchain\env.ps1
cd android_app
flutter build apk --release --split-per-abi

# Signatur prüfen, BEVOR das Release entsteht
& "<toolchain>\android-sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs `
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk

cd ..
gh release create v0.8.0 `
  "android_app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk#onepiece-scanner-arm64.apk" `
  --title "v0.8.0 – …" --notes-file <datei.md>
```

Hochgeladen wird nur die **arm64**-Variante (aktuelle Handys). Der Anhang `#onepiece-scanner-arm64.apk`
benennt die Datei beim Hochladen um — `README.md` und `ANLEITUNG.md` nennen diesen Namen, und ab
der In-App-Aktualisierung sucht die App ihn.

**Reihenfolge beachten, sobald `docs/data/version.json` existiert:** erst das Release samt APK
anlegen und prüfen, dass die Adresse wirklich antwortet — **danach** die `version.json` schreiben.
Andersherum bieten alle Geräte innerhalb von Minuten ein Update an, dessen Datei es noch nicht gibt.

**Releases ausschließlich über `scripts/release.ps1`.** Das Skript prüft Version gegen pubspec,
Schlüssel, Signatur-Fingerabdruck, benennt die APK **vor** dem Hochladen um und schreibt
`version.json` erst, wenn die APK nachweislich erreichbar ist. Die `#name`-Angabe von `gh` setzt
übrigens nur das Anzeige-Etikett, nicht den Dateinamen — daran ist v0.8.0 zuerst gescheitert.

### Aktualisierung aus der App (seit v0.9.0)

```
docs/data/version.json  ──►  UpdateService.pruefen()      höchstens 1×/Tag, still bei Fehlern
                              UpdateService.anbieten()     reine Entscheidung, testbar
                              UpdateService.herunterladen() .part → Länge → SHA-256 → .apk
                              AppInstaller.installieren()  ──►  InstallChannel.kt (PackageInstaller)
                                                               ◄──  InstallStatusReceiver.kt
```

| Entscheidung | Begründung |
| --- | --- |
| Versionsvergleich über **versionName** | `--split-per-abi` addiert `1000 × ABI` auf den versionCode. Ein einziger Build ohne den Schalter, und jeder Vergleich über den Code kippt |
| `version.json` im Repo statt GitHub-API | Dasselbe Muster wie Preise und Decks; die API hat 60 Anfragen/Stunde je IP, hinter Mobilfunk-NAT teilen sich viele Geräte eine IP |
| **PackageInstaller-Sitzung** statt `ACTION_VIEW` | Kein FileProvider nötig — und vor allem erfährt die App, *warum* eine Installation scheitert. `ACTION_VIEW` meldet nur „App nicht installiert", und die naheliegende Reaktion darauf ist Deinstallieren. Genau das löscht die Sammlung |
| Eigener Dialog bei `STATUS_FAILURE_CONFLICT` | Signatur oder Version passen nicht. Der Dialog sagt ausdrücklich **„nicht deinstallieren"** und bietet sofort die Sicherung an |
| Download in `.part`-Datei | Erst nach Längen- und Prüfsummenprüfung bekommt sie ihren Namen. Eine halbe APK kann nie an den Installer gehen |
| Vor der Installation `await _persist()` | Android beendet die App während der Installation; ein laufender Speichervorgang ginge verloren |
| Keine Prozessorprüfung | Es gibt nur die arm64-Fassung. Läuft die App, kann das Gerät auch die nächste ausführen |
| `mandatory` in `version.json` | Notausgang: Eine Pflicht-Aktualisierung lässt sich nicht überspringen — für den Fall, dass eine veröffentlichte Fassung Daten gefährdet |

Die Download-Tests laufen gegen einen **echten lokalen Server** (`test/update_service_test.dart`):
Umleitung wie bei GitHub, fehlende Längenangabe, Verbindungsabriss über einen rohen Socket,
falsche Prüfsumme, Abbruch. Was sich nur am Gerät prüfen lässt: der Installationsdialog, die
Berechtigung „Unbekannte Apps", der Neustart nach dem Update.

**Wichtig für den Übergang:** v0.9.0 selbst musste noch von Hand installiert werden — v0.8.0 kennt
den Updater nicht. Erst ab der darauffolgenden Version greift der Weg aus der App.

**Ende-zu-Ende geprüft am 2026-11-14** (aus Sicht des Handys): `version.json` über
`raw.githubusercontent.com` abgerufen, die darin genannte APK heruntergeladen — Größe und SHA-256
stimmen exakt mit `version.json` überein, Signatur-Fingerabdruck wie alle bisherigen Releases.
Was noch aussteht, ist nur am Gerät prüfbar: der erste echte Update-Vorgang von v0.9.0 auf v0.10.0.

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

**In Arbeit (Stand 2026-11-13):**
- Kartenlisten importieren — eigene Sicherung, Deckliste, Nummernliste, Cardmarket-Export
- Aktualisierung aus der App heraus statt manuell über die Releases-Seite

**Naheliegende Erweiterungen:**
- Sammlungswert über die Zeit verfolgen (Preisdaten kommen ja täglich)
- Deckbau: eigene Listen anlegen statt nur fremde ansehen
- Mehrere Karten gleichzeitig scannen (Binderseite)
- Die Web-Version nachziehen — sie steht auf dem Stand vor den Tabs

**Bewusst nicht gemacht:**
- Web-Version aktuell halten (vom Nutzer als nicht benötigt eingestuft)
- Play-Store-Veröffentlichung (bräuchte Signaturschlüssel, Datenschutzerklärung, Bildrechte-Klärung)
