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
flutter test                                  # 291 Tests, laufen ohne Gerät
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
    card_model.dart     Kartendaten und Preis-Datenmodell, Motiv-Platz (-ALT, -ALTk)
    card_versions.dart  Cardmarket-Versionen je Nummer: Modell, Datei, Speicher, Gruppierung
    collection_view.dart Sammlung: Raster, Suche, Sortierung, Kartendetails
    collection_store.dart Dauerhafte Speicherung (Ordner, Scans, Versionswahl, Sicherung)
    collection_export.dart CSV-Export und JSON-Sicherung
    collection_import.dart Listen einlesen — Formaterkennung und Zuordnung, ohne UI
    import_view.dart    Import-Blatt: Quelle, Vorschau, Zielordner, Einfügemodus
    csv_reader.dart     CSV zerlegen (Quoting, Trennzeichen, Kodierung)
    update_service.dart Neue Version finden, herunterladen, prüfen
    update_view.dart    Update-Hinweis, Update-Blatt, Warnung bei abgelehntem Update
    app_installer.dart  Brücke zum Android-Installer (MethodChannel)
    overview_view.dart  Reiter „Übersicht": Wertverlauf, Set-Fortschritt, Set-Detail
    price_history.dart  Preisverlauf je Set laden (Datei-Zwischenspeicher), Wertverlauf rechnen
    set_progress.dart   Set-Fortschritt rechnen, Set-Namen lesen — ohne UI
    line_chart.dart     Liniendiagramm, Preiskurve je Karte, Fortschrittsbalken (CustomPainter)
    wishlist.dart       Wunschliste als gemeinsames Modell (ChangeNotifier) — ohne UI
    wishlist_view.dart  Wunschlisten-Seite, Zusammenfassung, Stern zum Vormerken
    decks_view.dart     Deck-Tab: Umschalter Turnierdecks | Meine Decks, Sammlungsabgleich
    deck_model.dart     Turnier-Decklisten einlesen und nachladen
    my_decks.dart       Eigene Decks: Modell, Regelprüfung, Statistik, Text-Ein/Ausgabe — ohne UI
    my_decks_view.dart  Deckliste, Editor, Kartensuche, Leaderwahl, Kostenkurve
    price_store.dart    Tagesaktuelle Preise nachladen
    widgets.dart        Gemeinsame Bausteine und Farben (inkl. geprüfter Diagrammfarben)
  assets/             cards.json, decks.json, sets.json, versions.json (in die App eingebacken)
  test/               291 Tests, laufen ohne Gerät (davon 6 Oberflächentests der Kartendetails)
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
1. scripts/build-db.js              npm-Paket -> data/cards.normalized.json (alle Motive)
2. scripts/fetch-cardmarket.js      Cardmarket-Exporte -> data/cm_*.json (Einzelkarten,
                                    Preise, versiegelte Produkte fuer die Ausgabe-Namen)
   scripts/import-cardmarket-prices.js  ordnet Preise den Motiven zu -> data/versions.json
                                    (Logik in cardmarket-zuordnung.js)
3. scripts/build-image-hashes.js    lädt ~2.200 Bilder, berechnet Fingerabdrücke
4. scripts/fetch-decks.js           Turnierdecks -> docs/data/decks.json
   scripts/build-price-file.js      schlanke Preisdatei -> docs/data/prices.json
   scripts/build-price-history.js   Verlauf je Set -> docs/data/history/<SET>.json
   scripts/sync-cards.js            verteilt alles an App und Web
```

`npm run data:all` macht das in der richtigen Reihenfolge. Die Datentests laufen mit
`npm run test:data` (Node, ohne Netz, mit einem Wegwerf-Git-Repository).

`build-db.js` schreibt seit v0.10.0 zusätzlich `data/sets.json` (Set-Code → Produktname) und
übernimmt `colors` als **Liste** sowie den `counter`-Wert. Vorher ging die zweite Farbe der
154 zweifarbigen Leader verloren. Seit v0.12.0 kommen die **`types`** dazu („East Blue",
„Straw Hat Crew") — die Deckprüfung braucht sie für Leader wie P-117 Nami, die nur einen Typ
erlauben.

**Alle Motive und ihre IDs (seit v0.13.0).** Bandais Katalog kennt 4.845 Drucke zu 2.785 Nummern;
bis v0.12 kam je Nummer nur die erste Alt-Art in den Katalog, 968 Motive fehlten — vor allem die
Nachdrucke aus „The Best" (PRB-01/02). Jetzt kommen alle mit, mit `produkt` und `produktSets`
(aus welchem Produkt das Motiv stammt). Die IDs sind heikel, weil gespeicherte Sammlungen auf sie
verweisen:

| Regel | Warum |
| --- | --- |
| Ein schon ausgeliefertes Bild behält seine ID — für immer. Register: der versionierte `android_app/assets/cards.json` (liegt auch in der GitHub Action vor) | Bei 234 Nummern ist die bisherige `-ALT` gar nicht das Motiv `_p1`. Ein Schema nach Bildnummer hätte gespeicherte Karten still umgedeutet |
| Neue Bilder: erste Normalversion → Nummer, erste Alt-Art → `-ALT`, alle weiteren → `-ALT2`, `-ALT3` … | wie bisher, nur ohne Verlust |
| `build-db.js` bricht ab, wenn eine ausgelieferte ID ihr Bild wechseln würde | lieber kein Katalog als ein still falscher |
| Doppelte japanische IDs (z. B. `OP01-114-ALT` dreimal): der **letzte** Eintrag behält die ID | genau den fand die App bisher; die anderen waren unerreichbar |

Der **Scanner** unterscheidet weiterhin nur Normalversion und `-ALT` per Bild-Fingerabdruck
(`build-image-hashes.js` rechnet nur für diese). Viele neue Motive sehen einander sehr ähnlich;
mehr Kandidaten hätten die Treffsicherheit ungeprüft verändert. Erst mit einer Messung an echten
Kamerabildern erweitern — bis dahin stellt der Nutzer weitere Motive in den Details um.

Im **Set-Fortschritt** zählen als Alt-Arts nur Motive aus dem eigenen Produkt des Sets
(`SetProgress.gehoertZumSet`): Die Parallele aus dem OP01-Booster gehört zu OP01, der PRB-01-
Nachdruck derselben Nummer nicht — sonst wären OP01 bis OP10 durch 317 PRB-Motive nie komplett.

**Produktnamen:** Seit OP-17 bzw. ST-31 schreibt Bandai „BOOSTER PACK -THE WORLD'S STRONGEST
WARRIORS-" und „STARTER DECK -RED Monkey.D.Luffy-". Die Übersicht zeigte deshalb „Booster Pack
-The World's …" und „STARTER DECK -RED …". `parseProduct` entfernt die Produktart und schreibt nur
noch ganz groß geschriebene Wörter um („PURPLE/BLACK" → „Purple/Black", „Monkey.D.Luffy" bleibt).

**Set-Namen** kommen aus dem Feld `card_sets` der Quelle („-ROMANCE DAWN- [OP-01]"). Ein einfacher
Mehrheitsentscheid wäre falsch: Nachdrucke stehen in fremden Produkten, und die EB04-Karten
stecken in zwei verschiedenen Boostern (OP-14 und OP-15). Gezählt wird deshalb nur ein Produkt,
dessen Code **mit dem Set beginnt**. Gibt es keins, bleibt der Name leer und die Produkte stehen
als „enthalten in". Promos heißen fest „Promokarten".

### Der Preisverlauf

`docs/data/prices.json` wird täglich überschrieben — jeder frühere Stand steht aber in der
Git-Historie. `build-price-history.js` holt alle Stände per `git log` / `git show` zurück, nimmt den
gerade geschriebenen Stand dazu und schreibt **je Set eine Datei**:
`{dates: [...], prices: {"OP01-001": [187, 185, null, ...]}}` — Cent als ganze Zahlen, an `dates`
ausgerichtet, `null` = kein Preis an diesem Tag. Doppelte Tage (am 06.10. dreimal committet):
der spätere Stand gewinnt.

Je Set eine Datei, weil die App nie alles braucht: Die Kartendetails laden nur das Set der Karte,
der Wertverlauf nur die Sets der Sammlung. Stand 14.11.2026: 36 Tage, 60 Dateien, zusammen 485 KB.
Nach einem Jahr werden es um die 300 KB je Set sein. Falls das stört: ältere Tage auf Wochenwerte
verdichten.

**Zwei Schutzmechanismen, die nicht entfernt werden dürfen:**

| Schutz | Wogegen |
| --- | --- |
| Abbruch bei flacher Git-Kopie (`git rev-parse --is-shallow-repository`) | GitHub Actions klont standardmäßig nur den letzten Commit. Ohne volle Historie schrumpfte der Verlauf auf einen Tag und überschriebe den vorhandenen. Der Workflow setzt deshalb `fetch-depth: 0` |
| Abbruch, wenn der neue Verlauf **kürzer** wäre als der vorhandene | fast immer ein Lesefehler, kein echter Datenstand. `--erzwingen` überschreibt bewusst |

In der App lädt `HistoryStore` die Dateien bei Bedarf und speichert sie **als Dateien** im
App-Verzeichnis, nicht in SharedPreferences — die Einstellungsdatei liegt bei Android vollständig
im Arbeitsspeicher. Gilt 6 Stunden als frisch; ohne Netz wird der alte Stand weiterbenutzt.

`WertVerlauf` rechnet, was die **heutigen** Karten an jedem Tag wert waren. Lücken werden
vorwärts gefüllt (sonst Einbrüche, die es am Markt nie gab); vor dem ersten bekannten Preis zählt
eine Karte nicht mit. **Bekannte Grenze:** Gerechnet wird mit der automatisch zugeordneten
Druckvariante. Für vom Nutzer gewählte Versionen gibt es keinen Verlauf — die Versionslisten
(`options`) werden nicht archiviert. Die App sagt das dazu.

### Wunschliste

Ein gemeinsames Modell (`Wunschliste` in `wishlist.dart`, ein `ChangeNotifier`) für alle Ansichten.
Ein gesetzter Stern erscheint dadurch sofort überall — auch in einer gerade geöffneten
Set-Ansicht, die als eigene Seite aufliegt und sonst nichts von der Änderung mitbekäme.

| Entscheidung | Begründung |
| --- | --- |
| Gespeichert in `collection_v2` unter `wishlist` | steckt damit ohne Zutun in der JSON-Sicherung, im Wiederherstellen und im Rückgängig nach einem Import. Leere Liste wird nicht geschrieben; ältere Stände ohne das Feld laden weiter |
| Speichern über `onAenderung`, **nicht** beim `laden()` | sonst löste schon das Einlesen beim Start einen Speichervorgang aus — womöglich bevor die Sammlung selbst geladen ist |
| Mehrfaches Hinzufügen: **größere** Anzahl statt Summe | wer eine Karte einmal fürs Set und dreimal fürs Deck braucht, braucht drei, nicht vier |
| Alt-Art hakt den Wunsch nach der Normalversion ab, nicht umgekehrt | fürs Spielen ist das Artwork egal; wer die Alt-Art sucht, will aber die Alt-Art |
| Deck-Wünsche: Normalversion, Anzahl = Bedarf − Besitz | Besitz zählt jedes Artwork (`ownedCount` über die Basisnummer) |
| Teilen im Deckformat `4xOP01-001` | versteht jeder Händler, und der eigene Import liest es wieder ein (Test vorhanden) |

### Eigene Decks (seit v0.12.0)

`my_decks.dart` enthält Modell und Regeln ohne UI, `my_decks_view.dart` die Ansichten. `MeineDecks`
ist wie die Wunschliste ein `ChangeNotifier` mit `onAenderung`, gespeichert in `collection_v2`
unter `myDecks` — damit in Sicherung, Wiederherstellen und Rückgängig enthalten. Die
Sammlungsabdeckung zählt jedes Artwork (`ownedCount` über die Basisnummer), Fehlendes geht als
Normalversion auf die Wunschliste.

**Die Regeln stammen aus den offiziellen Comprehensive Rules v1.2.1 (28.08.2026)**, nicht aus dem
Gedächtnis:

| Regel | Umsetzung |
| --- | --- |
| 5-1-2: genau 1 Leader, 50 Karten | der Leader steht in `leaderId`, nie in `karten` |
| 5-1-2-1: Character, Event, Stage | anderes → `falscherTyp` |
| 5-1-2-2: nur Farben des Leaders | eine mehrfarbige Karte braucht **alle** ihre Farben im Leader — sonst ist sie zugleich eine Karte einer nicht enthaltenen Farbe |
| 5-1-2-3: höchstens 4 je Kartennummer | gezählt über `baseId`, Alt-Arts zählen mit |
| 5-1-2-4: Karteneffekte gehen vor | „any number of this card in your deck" hebt die Grenze auf (Pacifista OP01-075, Biscuit Warrior OP08-072, Prisoner of Impel Down OP16-042). Leader-Grenzen per Regex aus dem Effekttext: Rayleigh OP12-001 (Kosten ≥ 5), Imu OP13-079 (Events ab Kosten 2), Nami P-117 (nur {East Blue}) |

`LeaderSonderregel.aus` liest nur Sätze mit „Under the rules of this game". Handelt so ein Satz vom
Deckbau (Merkmal: „include", vorsorglich auch „contain" und „any number of"), passt aber auf kein
bekanntes Muster, landet er in `ungeprueft` → die App zeigt *spielbereit\** mit dem Wortlaut statt
eines stillen „spielbereit". Sätze ohne Deckbezug werden übergangen: Brook OP15-022 („you do not
lose when your deck has 0 cards") und Enel OP15-058 („your DON!! deck consists of 6 cards") sind
Spielregeln. In der ersten Fassung lösten beide einen Vorbehalt aus — ein Fehlalarm, gefunden
durch den Katalogtest unten.

**Geprüft gegen die Wirklichkeit** (`test/deck_rules_real_test.dart`): Wer auf einem Turnier
platziert war, hatte ein regelkonformes Deck. Meldet die App dort einen Fehler, ist entweder die
Regel falsch umgesetzt oder die Quelle hat sich verschrieben. Stand 14.11.2026:

| | |
| --- | --- |
| Turnierdecks / davon vollständig im Katalog | 5.043 / 4.918 |
| spielbereit | 4.773 (97,1 %) |
| Anzahl ≠ 50 | 116 — unvollständig abgeschrieben (56× 49, 17× 48, 14× 51 Karten) |
| Farbfehler | 19 — Zahlendreher in der Quelle, z. B. „YP Pudding" mit Leader OP08-098 (Kalgara) statt OP08-058 (Pudding) |
| ohne Leader | 9 — die Leader-Zeile fehlt in der Quelle, die Liste beginnt mit einer Figur |
| Kopienfehler | 6 — dieselbe Nummer zweimal gelistet (`4xEB04-011 4xEB04-011`) |
| Leader-Regel verletzt | 0 — bei 85 Decks mit Rayleigh (26), Imu (51) oder Nami P-117 (8) |

Die Kopienregel fiel zunächst bei 37 Decks durch, bis die Ausnahme „any number of this card"
eingebaut war. Der Test trennt Quell- von Regelfehlern: Er scheitert an jedem Kopienfehler, den
kein doppelter Eintrag in der Quelle erklärt, an jeder verletzten Leader-Regel und an mehr als 1 %
Farbfehlern. Ein zweiter Test verlangt, dass **keine** Deckbau-Regel eines Leaders im Katalog
ungeprüft bleibt — bringt ein neues Set eine neue Formulierung, schlägt er beim nächsten
Katalog-Update an.

**Nicht geprüft:** Sperrlisten — in den Quelldaten stehen sie nicht. Die App sagt das im Editor
dazu. Eine Sperrliste wäre die naheliegende Erweiterung (siehe Abschnitt 9).

### Diagramme

Eigener `CustomPainter` (`line_chart.dart`), kein Paket — passend zur Projektlinie. Gestaltet nach
den dataviz-Regeln: 2-px-Linie, Fläche als 10-%-Hauch, Endpunkt mit Ring in der Flächenfarbe,
haardünne durchgezogene Hilfslinien, Achsentext in Textfarbe. Antippen zeigt eine einrastende
senkrechte Linie mit Wert und Datum; dieselben Werte gibt es als Liste.

Die Diagrammfarben sind **gerechnet, nicht geschätzt**: Das App-Gold `#FFB703` liegt bei
OKLCH-Helligkeit 0,825 und fiel beim Palettenprüfer durch (zulässig auf dunklem Grund: 0,48–0,67).
Deshalb `kChartLinie = #BD8701` — derselbe Farbton, auf 0,66 abgestuft. Grün für „komplett" ist
neben dem Gold bei Rot-Grün-Sehschwäche nur knapp unterscheidbar (ΔE 7,5) und erscheint deshalb nie
allein, sondern immer mit Haken und dem Wort „komplett".

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
| Preisverlauf | Git-Historie von `docs/data/prices.json` | seit 04.10.2026, ein Stand pro Tag |
| Set-Namen | Feld `card_sets` im npm-Paket | siehe oben |
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

Zu **1.083 Kartennummern gibt es eine Normalversion und mindestens eine Alt-Art**, bei identischer
Nummer und identischem Namen. Am Text sind sie nicht unterscheidbar.

Lösung: `scripts/build-image-hashes.js` lädt die 2.166 Bilder von Normalversion und erster Alt-Art
(`-ALT`) und berechnet je einen dHash (9×8 Graustufen, waagerechte Nachbarvergleiche, 64 Bit). Die
App berechnet denselben Hash aus dem Kamerabild (`image_hash.dart`) und nimmt die ähnlichere
Version. Die weiteren Motive (`-ALT2` …, seit v0.13 im Katalog) bekommen bewusst keinen
Fingerabdruck — siehe Abschnitt 3.

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

Cardmarket führt **pro Kartennummer im Schnitt 4,5 Produkte**, teils über 20: Booster-Druck,
Parallelen, Nachdrucke in späteren Produkten, Promos, Turnierpreise — und je Booster eine
asiatische („Asia Region Legal") und eine japanische Auflage („Non-English"). Die Preise liegen
weit auseinander: OP17-040 gibt es viermal zwischen 0,06 € und 74 €, OP01-006 siebzehnmal.

Der Einzelkarten-Export nennt je Produkt nur Name, Nummer und **Ausgabe-ID** (`idExpansion`).
Innerhalb einer Ausgabe heißen alle Versionen einer Nummer gleich. Bandais Katalog kennt umgekehrt
jedes Motiv mit Bild und Produkt, aber keine Cardmarket-Nummern. Eine feste Zuordnung wie bei
Scryfall (dort trägt jeder Druck seine `cardmarket_id`) gibt es für One Piece nicht — sie muss
abgeleitet werden.

### Die Lösung (seit v0.13, `scripts/cardmarket-zuordnung.js`)

1. **Ausgaben bekommen Namen** über die versiegelten Produkte derselben Ausgabe
   (`products_nonsingles_18.json`): „The World's Strongest Warriors Booster (Asia Region Legal)"
   → Ausgabe 6723 = „The World's Strongest Warriors (Asia Region Legal)". 145 von 153 Ausgaben
   bekommen so ihren Namen; der Rest sind gemischte Promo-Sammlungen („Promos · Nr. 5262").
   Regeln: gemeinsamer Wortanfang aller Produkte, sonst der häufigste Name; bei gemischten
   Ausgaben nur ein Anfang, den mindestens 60 % teilen, oder ein einzelnes kleines Produkt.
2. **Originalausgabe je Set** = die englische Ausgabe, in der das Set die meisten Karten stellt
   (mindestens die Hälfte). Ausgaben mit Sprach-/Regionszusatz kommen nie in Frage.
3. **Jedes Motiv sucht seine Ausgabe** über Bandais Produktangabe: eigenes Set → Originalausgabe;
   sonst per Set-Code (`[ST-15]`) oder Namensvergleich („One Piece Card the Best" → „The Best").
   Genommen wird die erste passende Ausgabe, die die Nummer überhaupt führt.
4. **Innerhalb der Ausgabe nach Preis verteilt:** Normalversion und Nachdrucke (`_r`) bekommen
   die günstigsten Versionen, Parallelen (`_p`) die teuersten.
5. **Ausweichregeln, alle „unsicher":** Das Grundmotiv bekommt immer einen Preis (günstigste
   freie Version ohne Zusatz); ein Nachdruck ohne eigene Version den der Normalversion; eine
   Alt-Art eine freie Version der eigenen Originalausgabe (Promo-Alt-Arts liegen bei Cardmarket
   in der Promo-Ausgabe). **Aus fremden Promo-Sammlungen wird nie geraten** — bei OP01-006 wäre
   das eine Turnier-Version für 5.000 € gewesen.

Stand 24.11.2026: 4.624 von 4.958 Motiven haben einen Preis — 2.404 eindeutig, 1.518 als
Normal/Parallele-Paar, 702 unsicher. Ohne Preis bleiben vor allem Turnier- und Sammelmotive ohne
erkennbares Cardmarket-Gegenstück; dort wählt der Nutzer selbst.

**Alle Versionen sind in der App wählbar** (`docs/data/versions.json`, täglich, 258 KB, gzip
74 KB): je Nummer `[idProduct, idExpansion, Cent, [Motive]]`, die Motive sind die Plätze, deren
automatische Version das ist (0 Normal, 1 `-ALT`, k `-ALTk`). Bewusst eine eigene Datei: App-
Versionen bis 0.12 lesen `prices.json` streng und verlören bei einem geänderten Format alle
Tagespreise. `prices.json` behält deshalb sein Format, inklusive `options`.

### Der Fehler bis v0.12: japanische Preise für OP05 bis OP16

Die erste Fassung nahm als Originalausgabe die **zuerst angelegte** „reine" Ausgabe (90 % eines
Sets). Japanische Booster erscheinen aber Monate vor den englischen, und Cardmarket legt ihre
Ausgabe „(Non-English)" zuerst an. Ergebnis: Für **OP05 bis OP13, EB01 und EB02** zeigte die App
die Preise der japanischen Auflage, für **OP14 bis OP16 und EB03** die der asiatischen. Nur OP01
bis OP04 und OP17 waren englisch. Aufgefallen bei der Frage, ob die App ihre Preise „wie Scryfall"
ermittelt. Der Test `Echte Daten: keine Originalausgabe in anderer Sprache` in
`scripts/cardmarket-zuordnung.test.js` und der gleichnamige Dart-Test verhindern die Rückkehr.

Der Preisverlauf vor dem 24.11.2026 bleibt falsch — die englischen Preise jener Tage wurden nie
gespeichert. Der Wertverlauf macht an dem Tag deshalb einen Sprung; die App-Anleitung sagt das.

### Tagesaktualität und die Wahl des Nutzers

Die Preise stecken **nicht** fest in der App. `docs/data/prices.json` und `docs/data/versions.json`
werden täglich per GitHub Action aktualisiert, die App lädt sie beim Start. Ohne Netz gelten die
zuletzt geladenen, davor die mitgelieferten (`assets/versions.json`).

Die Wahl des Nutzers wird als **Cardmarket-Produktnummer** gespeichert (`versionChoice` in
`collection_v2`). Bis v0.12 war es der **Platz in der Preisliste** — der zeigte auf eine andere
Version, sobald sich zwei Versionen im Preis überholten, also jeden Tag ein paar. Alte Plätze
werden beim ersten Start einmalig übersetzt (`produktZumAltenPlatz`).

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

Nach Verkäuferland und Zustand nicht möglich. Die Export-Dateien enthalten nur europaweite
Aggregate (`avg`, `low`, `trend`, `avg1`, `avg7`, `avg30`, jeweils auch für Foil). Verkäuferland
und Zustand existieren bei Cardmarket nur auf **Angebotsebene** — erreichbar nur über die API
oder die Website.

**Nach Sprache doch** (seit v0.13 erkannt): Japanische und asiatische Drucke führt Cardmarket als
**eigene Ausgaben** („… (Non-English)", „… (Asia Region Legal)"). Über die Namen der versiegelten
Produkte sind sie erkennbar und in der App als Version wählbar.

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
Eine Spracherkennung bräuchte ein zusätzliches japanisches ML-Kit-Modell in der App. Die Preise
ließen sich inzwischen trennen (die japanischen Drucke liegen in den „(Non-English)"-Ausgaben),
deshalb wählt der Nutzer seine Version in den Kartendetails selbst.

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
`UTF8Encoding($false)` verwenden. Zweimal passiert: am 13.11. in `ENTWICKLUNG.md` selbst, und beim
Release v0.10.0 las `release.ps1` die Notizdatei ohne `-Encoding UTF8` — „zurÃ¼ck" stand so in
`version.json` und wäre im Update-Dialog erschienen. Vor dem ersten Abruf korrigiert; das Skript
liest jetzt mit `-Encoding UTF8`.

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

**Die Kamera lief im Hintergrund weiter (bis v0.12).** Der Scanner sitzt im `IndexedStack` und
bleibt dort aufgebaut, auch wenn ein anderer Reiter offen ist. Seine Kamera lief deshalb immer -
mit Texterkennung alle 350 ms. Wer in der Sammlung blätterte und das Handy über Karten hielt,
bekam sie unbemerkt eingetragen; dazu kam der Akkuverbrauch. Jetzt bekommt `ScannerView` ein
`aktiv` (nur Reiter 0), gibt die Kamera beim Wechsel frei und verwirft eine Erkennung, die vor
dem Wechsel begonnen hat.

**Besitzzählung im Deck-Reiter.** `_ownedCount` lief für jede Abfrage einmal durch die ganze
Sammlung, mit zwei `toUpperCase` je Karte. Der Deck-Reiter fragt für rund 5.000 Turnierdecks mit
je 15 bis 20 Karten — bei 1.000 gesammelten Karten über 80 Millionen Vergleiche je Aufbau, und
weil der `IndexedStack` alle Reiter mit aufbaut, nach jedem einzelnen Scan. Jetzt wird je Aufbau
einmal gezählt (`_besitzZaehlen`).

**Netzabrufe ohne Zeitlimit.** `PriceStore` und `DeckStore` warteten ohne Limit; in einem WLAN mit
Anmeldeseite hing die ganze Startkette, die Update-Prüfung wartete dahinter. Jetzt 15 s für den
Verbindungsaufbau, 20 bis 45 s für die Antwort - wie bei Update und Verlauf.

**Widget-Tests und echte Dateien.** Ein Test, der Schriften von der Platte lädt, hing endlos:
In `testWidgets` werden echte Dateizugriffe nur innerhalb von `tester.runAsync(...)` fertig.

**`| Select-Object -First` beendet Node mitten im Schreiben.** `node scripts/sync-cards.js |
Select-Object -First 2` sollte nur die Ausgabe kürzen — PowerShell beendet aber den Prozess,
sobald zwei Zeilen da sind. `assets/decks.json` blieb dabei mit **0 Byte** zurück; aufgefallen ist
es nur, weil danach ein Test scheiterte. `sync-cards.js` schreibt seitdem erst in eine `.tmp`-Datei,
vergleicht die Größe und benennt dann um — ein Abbruch hinterlässt die alte Datei, keine halbe.
Trotzdem: hinter Skripten, die Dateien schreiben, nie `Select-Object -First`; `-Last` liest alles.

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

**Erledigt aus der Nutzerwunsch-Recherche (Stand 2026-11-14):** Import (v0.8.0), Aktualisierung
aus der App (v0.9.0), Übersicht mit Wert- und Preisverlauf und Set-Vervollständigung (v0.10.0),
Wunschliste (v0.11.0), eigene Decks mit Regelprüfung (v0.12.0).

**Naheliegende Erweiterungen:**
- Scanner auch für die weiteren Motive (`-ALT2` …): vorher an echten Kamerabildern messen, ob die
  Treffsicherheit bei mehr und ähnlicheren Kandidaten hält
- Version je Exemplar statt je Karte: Heute gilt eine gewählte Cardmarket-Version für alle
  Exemplare derselben Karte; wer eine englische und eine asiatische hat, kann das nicht abbilden
- Sperrliste in die Deckprüfung (bräuchte eine gepflegte Datenquelle)
- Zustand der Karten erfassen (bei 4 von 6 Konkurrenz-Apps vorhanden)
- Mehrere Karten gleichzeitig scannen (Binderseite) — riskant, die Stärke der App ist Treffsicherheit
- Die Web-Version nachziehen — sie steht auf dem Stand vor den Tabs

**Bewusst nicht gemacht:**
- Web-Version aktuell halten (vom Nutzer als nicht benötigt eingestuft)
- Play-Store-Veröffentlichung (bräuchte Signaturschlüssel, Datenschutzerklärung, Bildrechte-Klärung)
