# Anleitung — One Piece Scanner

## 1. App installieren (Android)

### ⬇️ [**onepiece-scanner-arm64.apk herunterladen**](https://github.com/FeyzAras/onepiece-scanner/releases/latest/download/onepiece-scanner-arm64.apk)

1. Den Link oben **auf dem Handy** antippen. Er zeigt immer auf die neueste Fassung — kein Umweg
   über die Release-Seite, kein Suchen unter „Assets". Chrome fragt, ob die Datei heruntergeladen
   werden darf → **bestätigen**.
2. Die heruntergeladene Datei öffnen (Benachrichtigung antippen oder in „Downloads").
3. Android fragt: *„Aus dieser Quelle dürfen keine unbekannten Apps installiert werden"* →
   **Einstellungen** antippen → **„Aus dieser Quelle zulassen"** aktivieren → zurück → **Installieren**.
4. Play Protect warnt eventuell vor einem unbekannten Entwickler → **Trotzdem installieren**.
5. Beim ersten Start fragt die App nach der **Kamera-Berechtigung** → **Zulassen**.

> `arm64` ist die richtige Variante für aktuelle Handys, auch für das Samsung S24.
>
> **Eine neue Version legt sich einfach über die alte — die Sammlung bleibt erhalten.**
> Vorher deinstallieren würde sie löschen; das ist nicht nötig.

Alle Fassungen samt Änderungsnotizen:
[github.com/FeyzAras/onepiece-scanner/releases](https://github.com/FeyzAras/onepiece-scanner/releases)

> Die App ist mit einem Entwickler-Schlüssel signiert, nicht über den Play Store verteilt. Deshalb
> die Rückfrage von Android — das ist normal bei selbst gebauten Apps.

### Aktualisieren — ab Version 0.9.0 aus der App heraus

Die App sieht höchstens einmal am Tag selbst nach, ob es eine neue Version gibt. Ist eine da,
erscheint unten über der Leiste ein Hinweis **„Version … ist da"**. Antippen zeigt, was neu ist.

1. **Jetzt aktualisieren** antippen.
2. **Nur beim allerersten Mal:** Android muss erlauben, dass diese App Updates installieren darf.
   Die App führt dich hin → **„Aus dieser Quelle zulassen"** einschalten → zurück. Danach geht es
   von selbst weiter.
3. Die neue Version wird heruntergeladen, mit Fortschrittsanzeige. Abbrechen geht jederzeit.
4. Android fragt **„Aktualisieren?"** → bestätigen. Die App schließt sich kurz und startet in der
   neuen Version. **Die Sammlung bleibt erhalten.**

Gezielt nachsehen: Sammlung → **⋮** oben rechts → **Nach Update suchen**. Dort steht auch die
installierte Version.

> ⚠️ **Falls die App meldet, dass Android das Update ablehnt: nicht deinstallieren.** Damit wäre
> die Sammlung weg. Die bisherige Version läuft normal weiter. Im selben Dialog lässt sich die
> Sammlung sofort sichern — danach den Fehler melden.

Wer ein Update nicht will, tippt **„Diese Version überspringen"** — dann fragt die App erst bei der
nächsten Version wieder.

**Es gibt keine Internetpflicht:** Erkennung und Kartendaten liegen komplett in der App. Internet
wird nur benutzt, um die Kartenbilder in der Liste nachzuladen.

---

## 2. Scannen

So läuft es ab:

1. App öffnen — die Kamera startet und **scannt sofort von allein**. Kein Knopfdruck nötig.
2. Karte so halten, dass sie **im goldenen Rahmen** liegt. **Wichtig: Die Kartennummer unten
   rechts (z. B. `OP07-055`) muss lesbar sein** — im Rahmen ist die Stelle markiert.
3. Die App liest die Nummer und muss sie **zweimal bestätigen**, bevor sie die Karte übernimmt.
   Währenddessen steht unten „Prüfe OP07-055 …".
4. Sobald bestätigt:
   - kurzes **Vibrieren**
   - grüne Meldung oben: **✓ Kartenname · Nummer**
   - Miniaturbild erscheint unten im Streifen
5. Nächste Karte davor halten. Dieselbe Karte wird innerhalb von 5 Sekunden **nicht doppelt**
   eingetragen — du kannst sie also ruhig im Bild lassen.

### Warum die Kartennummer, nicht der Name?

Der Kartenname allein reicht nicht aus. Viele Karten heißen gleich, und Namen anderer Karten
stehen im Effekttext — beim Scannen von „Snake Dance" wurden so reihum „Gina" und „Portgas.D.Ace"
erkannt. Die aufgedruckte Nummer ist dagegen eindeutig.

Deshalb gilt: **Ohne lesbare Nummer wird nichts übernommen.** Erkennt die App nur den Namen, zeigt
sie einen Hinweis („… erkannt – Kartennummer unten rechts ins Bild halten"), trägt aber nichts ein.

### Und wenn zwei Karten dieselbe Nummer haben?

Das kommt oft vor: Zu 1.083 Kartennummern gibt es **zwei Versionen** — normales Artwork und
Alt-Art. Nummer und Name sind identisch, nur das Bild unterscheidet sich.

Die App vergleicht deshalb zusätzlich das Kamerabild mit beiden Versionen: Für jedes Kartenbild
ist ein Bild-Fingerabdruck hinterlegt, die App berechnet denselben aus dem Kamerabild und nimmt
die ähnlichere Version. Liegt sie trotzdem mal daneben, kannst du in den Kartendetails mit einem
Tipp auf **„wechseln"** das andere Artwork wählen.

**Der runde Knopf unten ist kein Auslöser**, sondern Pause/Weiter. Nützlich, wenn du kurz etwas
anderes machst und nicht willst, dass die App im Hintergrund weiter Karten einsammelt.

### Damit die Erkennung gut funktioniert
- **Licht**: gleichmäßig, nicht direkt von oben — Spiegelungen auf Folienkarten sind der häufigste Grund für Fehlversuche.
- **Abstand**: Karte den Rahmen gut ausfüllen lassen.
- **Ruhig halten**: ca. eine halbe Sekunde, die App wertet mehrmals pro Sekunde aus.
- **Gerade halten**: stark schräge Winkel erschweren das Lesen der Kartennummer.

---

## 3. Die Liste

Die App hat unten drei Tabs: **Scannen**, **Sammlung** und **Decks**.

### Ordner

Oben im Scannen-Tab steht, in welchen Ordner gescannt wird. Antippen öffnet die Ordnerverwaltung:
wechseln, neue anlegen, löschen. **Neu gescannte Karten landen immer im ausgewählten Ordner.**

### Sammlung

Kartengitter mit Bild, Name, Nummer und Preis.

| Element | Bedeutung |
| --- | --- |
| **×3** rote Ecke | So oft hast du diese Karte gescannt. Der Preis darunter ist der Gesamtwert aller Exemplare |
| **Suchfeld** | Durchsucht Name, Kartennummer, Set und Kartentyp |
| **Ordner-Knöpfe** | Auf einen Ordner einschränken oder „Alle Ordner" |
| **Sortierung** | Zuletzt gescannt, Name, Set (OP13, OP14, OP17 …) oder Preis |

Auf eine Karte tippen öffnet die Details: Preis mit Stand, Effekttext, Anzahl, und — falls es die
Karte mit **anderem Artwork** gibt — einen Knopf zum Wechseln. Auf das Bild tippen zeigt es im
**Vollbild**, dort lässt es sich mit zwei Fingern vergrößern.

### Decks

Turnierdecks aus **allen Sets von OP01 bis OP17**, in englischem und japanischem Format — rund
4.900 Decklisten, 1.864 verschiedene Deck-Archetypen. Je Archetyp sind die fünf neuesten Listen
dabei; mehr wäre nur Wiederholung desselben Decks.

Für jedes Deck zeigt ein Balken, **wie viele Karten davon du schon besitzt.** Antippen zeigt die
vollständige Deckliste, Karte für Karte mit „2/4" — also wie viele du hast und wie viele das Deck
braucht. Grün heißt vollständig.

Oben lässt sich nach Deck, Spieler, Set oder Turnier suchen, nach Format filtern (Englisch /
Japanisch) und auf Decks einschränken, von denen du mindestens die Hälfte besitzt.

Quelle ist onepiecetopdecks.com; der Stand steht oben. Die App holt sich neue Decklisten selbst,
eine neue App-Version ist dafür nicht nötig.

### Sammlung sichern

Oben rechts in der Sammlung öffnet das Teilen-Symbol die Sicherung. Dabei entstehen **zwei
Dateien**, die zusammen weitergegeben werden:

| Datei | Wofür |
| --- | --- |
| `sammlung-TT-MM-JJJJ.csv` | Zum Ansehen. Öffnet in Excel direkt richtig — Semikolon als Trennzeichen, Komma als Dezimalzeichen, kein Importdialog |
| `sammlung-TT-MM-JJJJ.json` | **Die eigentliche Sicherung.** Nur diese Datei lässt sich verlustfrei wieder einlesen |

Die CSV enthält Kartennummer, Name, Set, Seltenheit, Kartentyp, Farbe, Anzahl, Einzel- und
Gesamtpreis, Ordner, Erkennungsart und Scandatum. Ganz rechts stehen drei technische Spalten
(Alt-Art, Ordner-ID, Preiswahl) — die braucht die App beim Wiedereinlesen, im Alltag kannst du
sie ignorieren.

Gesichert wird **immer die ganze Sammlung**, auch wenn gerade ein Suchbegriff oder ein
Ordner-Filter aktiv ist. Darauf weist die App dann eigens hin.

> ⚠️ **Wichtig: Die Dateien liegen zunächst nur in der App selbst.** Das Teilen-Fenster zu öffnen
> genügt nicht — schick sie dir wirklich zu, in Google Drive, in die Downloads oder per Mail an
> dich selbst. Sonst sind sie bei einer Deinstallation mit weg.

### Liste einlesen

Das Symbol daneben (Pfeil nach unten) liest Karten **in** die Sammlung. Es ist immer da, auch
wenn die Sammlung leer ist — genau dann braucht man es nämlich.

Vier Arten von Listen werden erkannt, ohne dass du etwas einstellen musst:

| Was | Beispiel |
| --- | --- |
| **Sicherungsdatei** | die `.json` aus deiner eigenen Sicherung — stellt alles wieder her, samt Ordnern und Preisauswahl |
| **Eigene CSV** | die `.csv` aus deiner Sicherung |
| **Deckliste** | `4xOP01-001 2xST01-002 …` — das Format, das Deck-Seiten und Simulatoren ausgeben |
| **Nummernliste** | eine Nummer je Zeile. `OP01-001`, `OP01-001 x3`, `3 OP01-001` und `4x OP01-001` gehen alle |
| **Cardmarket-Export** | die Bestandsdatei aus deinem Cardmarket-Konto |

Zwei Wege hinein: **Datei auswählen** oder **Text einfügen** (für Decklisten aus der Zwischenablage).

**Vor dem Übernehmen kommt immer eine Vorschau** mit:

- wie viele Karten erkannt wurden und was sie wert sind
- welche Nummern über eine Korrektur gefunden wurden (`OP1-1` → `OP01-001`)
- welche Zeilen **nicht** zugeordnet werden konnten — aufklappbar, nichts verschwindet stillschweigend
- wohin die Karten sollen: aktueller Ordner, neuer Ordner, oder die Ordner aus der Datei
- wie gerechnet wird:

| | Was passiert |
| --- | --- |
| **Dazuzählen** | Alles kommt obendrauf. Der Normalfall. |
| **Auf Anzahl auffüllen** | Ergänzt nur, was noch fehlt — für Listen, die du schon halb gescannt hast |
| **Ersetzen** | Zielordner leeren und neu befüllen. Bei einer Sicherungsdatei die vollständige Wiederherstellung |

Falls doch etwas schiefgeht: Direkt nach dem Import steht **Rückgängig** in der Meldung, und
solange kein zweiter Import hinterherkommt, auch dauerhaft unten im Import-Fenster.

**Was aus Cardmarket nicht mitkommt:** Zustand, Sprache, Folierung und deine eigenen
Verkaufspreise — dafür hat die App kein Feld. Die Karten selbst werden über die Produktnummer
zugeordnet und treffen damit genau die richtige Druckvariante.

### Japanische Karten

Japanische Karten funktionieren ohne Zusatzschritt — die Kartennummer ist auch dort in
lateinischer Schrift aufgedruckt und wird normal erkannt.

Zusätzlich sind **115 Karten im Katalog, die nie auf Englisch erschienen sind** (vor allem Promos
und Starter-Deck-Karten). Die sind in den Kartendetails mit „nur auf Japanisch erschienen"
gekennzeichnet.

Was die App **nicht** unterscheiden kann: ob du den englischen oder den japanischen Druck
derselben Karte in der Hand hältst. Beide tragen dieselbe Nummer, und am Bild sind sie zu
ähnlich. Angezeigt wird dann das englische Artwork.

> **Die Sammlung bleibt erhalten.** Sie wird auf dem Gerät gespeichert und ist beim nächsten
> Öffnen wieder da.

---

## 4. Zu den Preisen

Die Preise sind **echte Cardmarket-Preise** — 3.865 von 3.868 Karten (99,9 %) haben einen.
Angezeigt wird Cardmarkets **Trendpreis**, der Stand steht unter dem Betrag.

Sie stammen aus den Export-Dateien, die Cardmarket seit Juli 2025 selbst täglich veröffentlicht und
ausdrücklich zur Nutzung in eigenen Anwendungen freigibt — kein API-Zugang, kein Scraping.

### Welche Version wird bepreist?

Das ist der kniffligste Teil. Cardmarket führt **pro Kartennummer mehrere Produkte**: Originaldruck,
Alt-Art, Nachdrucke in späteren Sets, Promos, Turnierpreise. Im Schnitt 4,2 Stück, bei manchen über
20 — und die Preise liegen weit auseinander. Bei OP01-001 zwischen **1,87 € und 610 €**.

Die App ordnet automatisch zu: Sie erkennt, welche Cardmarket-Edition dem Originalset der Karte
entspricht, und unterscheidet darin normales Artwork von Alt-Art. In den Kartendetails steht,
wie sicher das war:

| Angabe | Bedeutung |
| --- | --- |
| ✅ **eindeutig zugeordnet** | Es gibt nur eine Version — der Preis stimmt sicher |
| ⚠️ **normal/Alt-Art unterschieden** | Zwei Versionen; zugeordnet über die Annahme, dass die Alt-Art die teurere ist |
| ❓ **Zuordnung unsicher** | Mehr als zwei Versionen oder keine eindeutige Originaledition |

**Stimmt der Preis nicht, kannst du ihn selbst wählen.** In den Kartendetails stehen alle
Cardmarket-Versionen dieser Nummer als antippbare Beträge. Deine Wahl wird dauerhaft gespeichert
und mit „von dir ausgewählt" markiert; über „zurücksetzen" geht es wieder zur Automatik.

In der Übersicht zeigt ein kleines **❓** neben dem Betrag an, dass die Zuordnung unsicher ist.

### Bleiben die Preise aktuell?

Ja. Die App holt sich beim Start die **tagesaktuellen Preise** (rund 150 KB) — eine neue App-Version
ist dafür nicht nötig. Der Stand steht unter jedem Betrag.

Ohne Internet gelten die zuletzt geladenen Preise, und davor die in der App mitgelieferten. Es
steht also immer ein Preis da, höchstens ein älterer.

Deine manuelle Auswahl bleibt dabei richtig: Gespeichert wird **welche Version** du gewählt hast,
nicht der Betrag. Die aktualisiert sich also mit.

---

## 5. Wenn etwas nicht klappt

**Eingebaute Diagnose:** Halte den **Kopfbereich oben** (dort, wo „One Piece Scanner" steht) kurz
gedrückt. Dann erscheint eine Anzeige mit: wie viele Kamerabilder ankommen, wie viele davon
ausgewertet wurden, welches Bildformat die Kamera liefert, welchen Text die Erkennung zuletzt
gelesen hat und ob ein Fehler auftrat. Nochmal lange drücken blendet sie wieder aus.

Das ist der schnellste Weg, ein Problem einzugrenzen — mach davon einen Screenshot, wenn etwas
nicht geht.

| Problem | Was tun |
| --- | --- |
| Kamera bleibt schwarz | Berechtigung prüfen: Einstellungen → Apps → One Piece Scanner → Berechtigungen → Kamera |
| Es wird gar nichts erkannt | Diagnose einblenden (siehe oben). Steht bei „Bilder von der Kamera" eine Zahl, die steigt, kommt das Bild an. Steht bei „Gelesener Text" nichts, liegt es an Licht/Abstand/Drehung — Screenshot schicken |
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
