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

Die Kamera läuft nur, solange der Reiter **Scannen** offen ist. Wechselst du in die Sammlung, geht
sie aus — bis Version 0.12 lief sie weiter und konnte dabei unbemerkt Karten aufnehmen, die gerade
im Bild lagen.

Erkannt wird beim Scannen die Normalversion oder die erste Alt-Art einer Nummer. Gibt es weitere
Motive (Nachdrucke, Sammel-Editionen), stellst du deine Karte danach in den Kartendetails um.

### Warum die Kartennummer, nicht der Name?

Der Kartenname allein reicht nicht aus. Viele Karten heißen gleich, und Namen anderer Karten
stehen im Effekttext — beim Scannen von „Snake Dance" wurden so reihum „Gina" und „Portgas.D.Ace"
erkannt. Die aufgedruckte Nummer ist dagegen eindeutig.

Deshalb gilt: **Ohne lesbare Nummer wird nichts übernommen.** Erkennt die App nur den Namen, zeigt
sie einen Hinweis („… erkannt – Kartennummer unten rechts ins Bild halten"), trägt aber nichts ein.

### Und wenn zwei Karten dieselbe Nummer haben?

Das kommt oft vor: Zu über 1.000 Kartennummern gibt es **mehrere Motive** — normales Artwork,
Parallelen, Nachdrucke in späteren Produkten. Nummer und Name sind identisch, nur das Bild
unterscheidet sich.

Die App vergleicht deshalb zusätzlich das Kamerabild mit der Normalversion und der ersten Alt-Art:
Für diese Bilder ist ein Bild-Fingerabdruck hinterlegt, die App berechnet denselben aus dem
Kamerabild und nimmt die ähnlichere Version. Liegt sie daneben oder hast du ein weiteres Motiv,
tippst du in den Kartendetails unter **Motiv** auf das richtige Bild.

**Der runde Knopf unten ist kein Auslöser**, sondern Pause/Weiter. Nützlich, wenn du kurz etwas
anderes machst und nicht willst, dass die App im Hintergrund weiter Karten einsammelt.

### Damit die Erkennung gut funktioniert
- **Licht**: gleichmäßig, nicht direkt von oben — Spiegelungen auf Folienkarten sind der häufigste Grund für Fehlversuche.
- **Abstand**: Karte den Rahmen gut ausfüllen lassen.
- **Ruhig halten**: ca. eine halbe Sekunde, die App wertet mehrmals pro Sekunde aus.
- **Gerade halten**: stark schräge Winkel erschweren das Lesen der Kartennummer.

---

## 3. Die Liste

Die App hat unten vier Reiter: **Scannen**, **Sammlung**, **Übersicht** und **Decks**.

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

Auf eine Karte tippen öffnet die Details: Preis mit Stand, Effekttext, Anzahl — und, wenn es die
Nummer mehrfach gibt, **alle Motive und alle Cardmarket-Versionen zum Auswählen** (siehe
[Welche Version hast du?](#welche-version-hast-du-ab-version-0130)). Auf das Bild tippen zeigt es
im **Vollbild**, dort lässt es sich mit zwei Fingern vergrößern.

### Decks

Oben schaltest du um zwischen **Turnierdecks** (fremde Decklisten, gleich hier beschrieben) und
**Meine Decks** (selbst bauen, siehe [Eigene Decks](#eigene-decks-ab-version-0120)).

Turnierdecks aus **allen Sets von OP01 bis OP17**, in englischem und japanischem Format — rund
4.900 Decklisten, 1.864 verschiedene Deck-Archetypen. Je Archetyp sind die fünf neuesten Listen
dabei; mehr wäre nur Wiederholung desselben Decks.

Für jedes Deck zeigt ein Balken, **wie viele Karten davon du schon besitzt.** Antippen zeigt die
vollständige Deckliste, Karte für Karte mit „2/4" — also wie viele du hast und wie viele das Deck
braucht. Grün heißt vollständig. Darunter: **„Als eigenes Deck übernehmen"** (eine Kopie zum
Umbauen) und **„Fehlende Karten auf die Wunschliste"**.

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
(Alt-Art, Ordner-ID, gewählte Cardmarket-Version) — die braucht die App beim Wiedereinlesen, im Alltag kannst du
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

### Übersicht (ab Version 0.10.0)

Der dritte Reiter unten, zwischen Sammlung und Decks. Er braucht beim ersten Öffnen kurz Internet,
danach geht er auch offline mit dem zuletzt geladenen Stand.

**Wert deiner Sammlung** — oben die große Zahl ist der heutige Wert, darunter die Veränderung
seit 7 und seit 30 Tagen (▲ grün = gestiegen, ▼ rot = gefallen). Die Kurve zeigt, was deine
**heutigen** Karten an jedem Tag wert waren — sie beginnt am 4. Oktober 2026, seitdem werden die
Preise gesammelt. **Antippen oder darüberwischen** zeigt Datum und Wert des jeweiligen Tages.
„Werte als Liste" darunter zeigt dieselben Zahlen zum Nachlesen. Nach unten ziehen lädt neu.

**Sets** — je Set, wie viele Grundkarten du hast, etwa *OP01 · Romance Dawn — 87 von 175*.
Alt-Arts werden daneben eigens gezählt, denn sie machen ein Set nicht unvollständig. Rechts steht,
was die fehlenden Karten zum heutigen Preis kosten würden. Antippen zeigt die fehlenden Karten,
günstigste zuerst. Ein komplettes Set bekommt einen grünen Haken und das Wort *komplett*.

Sets, aus denen du noch keine Karte hast, stehen eingeklappt unter **Weitere Sets**.

**Preiskurve je Karte** — in den Kartendetails (Karte in der Sammlung antippen) steht unter dem
Preis jetzt sein Verlauf, mit dem tiefsten und höchsten Stand.

> **Gut zu wissen:** Kurven und Set-Kosten rechnen mit der Druckvariante, die die App automatisch
> zugeordnet hat. Hast du bei einer Karte eine andere Version gewählt, steht ein Hinweis dabei.
> Nur auf Japanisch erschienene Karten zählen nicht zur Set-Gesamtzahl.

### Wunschliste (ab Version 0.11.0)

Karten, die du noch suchst — mit den Kosten zum heutigen Preis. Sie steht in der **Übersicht**
direkt unter dem Sammlungswert. Antippen öffnet die ganze Liste.

**So kommen Karten drauf:**

| Wo | Was passiert |
| --- | --- |
| Übersicht → ein Set antippen | ☆ neben jeder fehlenden Karte, oder **„Alle fehlenden auf die Wunschliste"** |
| Decks → ein Turnierdeck antippen | **„Fehlende Karten auf die Wunschliste"** — mit der Anzahl, die dir noch fehlt (das Deck braucht 4, du hast 1 → 3 gesucht) |
| Sammlung → eine Karte antippen | ☆ neben dem Namen, etwa um weitere Exemplare zu suchen |

Steht eine Karte schon drauf, zählt die **größere** Anzahl, nicht die Summe: Brauchst du sie
einmal fürs Set und dreimal fürs Deck, suchst du drei.

**In der Liste:** mit − und + die Anzahl ändern, das Teilen-Symbol oben schickt die Liste im
Deckformat (`4xOP01-001 …`) — passt in jeden Chat mit einem Händler. Der Papierkorb leert sie
nach Rückfrage.

**Beim Scannen wird automatisch abgehakt:** Hältst du eine gesuchte Karte vor die Kamera, zählt
die Wunschliste herunter und meldet es kurz. Eine **Alt-Art erfüllt dabei auch den Wunsch nach
der Normalversion** (zum Spielen ist das Artwork egal) — umgekehrt nicht: Wer die Alt-Art sucht,
will die Alt-Art.

Die Wunschliste steckt in der **Sicherung** mit drin und kommt beim Wiederherstellen zurück.

### Eigene Decks (ab Version 0.12.0)

Im Reiter **Decks** oben auf **Meine Decks** umschalten. Drei Wege zu einem Deck:

| Weg | So geht's |
| --- | --- |
| **Neues Deck** | Leader aussuchen (Suche nach Name, Nummer oder Farbe), dann „Karten hinzufügen" |
| **Liste einfügen** | eine Deckliste aus der Zwischenablage, etwa von einer Deck-Seite (`1xOP01-001 4xOP01-013 …`). Der Leader wird darin erkannt |
| **Turnierdeck als Vorlage** | **Turnierdecks** → ein Deck antippen → **„Als eigenes Deck übernehmen"**, danach nach Belieben umbauen |

**Im Deck siehst du, von oben nach unten:**

- den **Leader**, mit „Ändern" austauschbar
- die **Prüfung**: „38 / 50 Karten" mit Balken. Stimmt alles, steht dort ein grüner Haken und
  *spielbereit*. Sonst steht darunter in Worten, was fehlt oder nicht passt
- die **Kostenkurve**: wie viele Karten je Kosten 0 bis 10+, dazu Charaktere, Events, Stages und
  die Counter-Werte
- den **Abgleich mit der Sammlung**: „41 von 50 Karten in deiner Sammlung" — jedes Artwork zählt.
  Ein Knopf setzt die fehlenden auf die **Wunschliste**
- die **Karten**, nach Typ und Kosten geordnet, Anzahl mit − und +. Passt eine Karte nicht, steht
  es rot darunter, etwa „Farbe passt nicht zum Leader"

Oben rechts schickt das **Teilen-Symbol** die Liste im Deckformat, eine Zeile je Karte
(`4xOP01-013`), der Leader als `1x` zuerst — das verstehen Simulatoren und Deck-Seiten, und die
App liest es selbst wieder ein. Unter ⋮ stehen
**Umbenennen** (geht auch durch Antippen des Namens) und **Löschen**. Löschen entfernt nur die
Liste, nicht die Karten deiner Sammlung.

**„Karten hinzufügen"** zeigt nur, was zum Leader passt: seine Farben, und bei Leadern mit eigener
Regel nur erlaubte Karten. Bei Karten, die du besitzt, steht „×2 im Besitz" dabei. Ist eine Nummer
schon viermal im Deck, ist das + ausgegraut.

**Was geprüft wird** — nach den offiziellen Regeln (Comprehensive Rules 1.2.1):

| Regel | Im Detail |
| --- | --- |
| 1 Leader, genau 50 Karten | der Leader zählt nicht zu den 50 |
| höchstens 4 je Kartennummer | Alt-Arts haben dieselbe Nummer und zählen mit: 2× normal + 2× Alt-Art = 4 |
| nur Farben des Leaders | zweifarbige Leader erlauben beide Farben. Eine zweifarbige Karte braucht **beide** Farben im Leader |
| Karten ohne Kopiengrenze | z. B. Pacifista (OP01-075) — auf der Karte steht, dass beliebig viele erlaubt sind |
| Regeln einzelner Leader | Rayleigh (OP12-001): keine Karten ab Kosten 5 · Imu (OP13-079): keine Events ab Kosten 2 · Nami (P-117): nur {East Blue}-Karten |

> **Nicht geprüft: Sperrlisten** (verbotene oder begrenzte Karten). Die stehen nicht in den Daten
> der App. Vor einem Turnier die aktuelle Liste auf der offiziellen Seite ansehen.

Kommt ein neuer Leader mit einer Deckbau-Regel heraus, die die App noch nicht kennt, steht dort
*spielbereit\** mit Stern — samt dem Wortlaut der Regel zum Selbstprüfen. Die App sagt also nie
stillschweigend „spielbereit", wenn sie etwas nicht prüfen konnte.

**Wie verlässlich ist die Prüfung?** Getestet an **4.918 echten Turnierdecks**: 97 % gelten als
spielbereit. Bei den übrigen liegt der Fehler nachweislich in der abgeschriebenen Liste der Quelle
— 49 statt 50 Karten, dieselbe Karte zweimal gelistet, fehlende Leader-Zeile, Zahlendreher in
einer Nummer.

Deine Decks stecken in der **Sicherung** mit drin und kommen beim Wiederherstellen zurück.

---

## 4. Zu den Preisen

Die Preise sind **echte Cardmarket-Preise**. Angezeigt wird Cardmarkets **Trendpreis**, der Stand
steht unter dem Betrag. Fehlt der Trend, nimmt die App einen Durchschnittspreis — genauso macht es
Scryfall bei Magic.

Sie stammen aus den Export-Dateien, die Cardmarket seit Juli 2025 selbst täglich veröffentlicht und
ausdrücklich zur Nutzung in eigenen Anwendungen freigibt — kein API-Zugang, kein Scraping.

### Welche Version hast du? (ab Version 0.13.0)

Cardmarket führt **pro Kartennummer oft mehrere Versionen**: den Booster-Druck, Parallelen,
Nachdrucke in späteren Produkten (etwa „The Best"), Promos — und dazu asiatische und japanische
Auflagen. Die Preise liegen weit auseinander: Edward.Newgate **OP17-040** gibt es viermal, zwischen
0,06 € und 74 €.

In den **Kartendetails** (Karte in der Sammlung antippen) stehen deshalb zwei Abschnitte:

| Abschnitt | Was du dort machst |
| --- | --- |
| **Motiv** | Alle Bilder dieser Nummer — Normalversion, Parallelen, Nachdrucke, jeweils mit dem Produkt, aus dem sie stammen. Tippe auf das Bild, das deine Karte zeigt (lange drücken vergrößert). Hast du mehrere Exemplare, fragt die App, ob alle oder nur eins umgestellt werden |
| **Welche Version hast du?** | Alle Cardmarket-Versionen, nach Ausgabe sortiert, mit Preis. Tippe auf deine. Gehört sie zu einem anderen Motiv — etwa die 25-€-Version zur Parallele —, stellt die App das Motiv gleich mit um |

Die App schlägt selbst eine Version vor und sagt, wie sicher das ist:

| Angabe | Bedeutung |
| --- | --- |
| ✅ **automatisch, eindeutig zugeordnet** | In der Ausgabe dieses Motivs gibt es genau eine Version |
| ⚠️ **automatisch, Normal und Parallele unterschieden** | Zwei Versionen; die teurere gilt als Parallele |
| ❓ **automatisch, Zuordnung unsicher** | Mehrere Versionen in derselben Ausgabe — bitte kurz prüfen |
| ❓ **keine Version zugeordnet** | Zu diesem Motiv (meist ein Turnier- oder Sammelmotiv) fand sich bei Cardmarket nichts Passendes — bitte selbst wählen |
| ✓ **von dir gewählt** | Deine Wahl. „zurücksetzen" geht zurück zum Vorschlag |

Deine Wahl gilt für alle Exemplare dieser Karte und bleibt gespeichert. In der Sammlung zeigt ein
kleines **❓** neben dem Betrag, dass der Vorschlag unsicher war.

> **„Asia Region Legal"** sind englische Karten für den asiatischen Markt, **„Non-English"** meist
> japanische. Beide sind bei Cardmarket oft viel günstiger. Von sich aus nimmt die App immer die
> normale englische Ausgabe.

> ⚠️ **Mit Version 0.13.0 ändern sich viele Preise — zu Recht.** Bis dahin hat die App für die Sets
> **OP05 bis OP16 und EB01 bis EB03** versehentlich die Preise der japanischen bzw. asiatischen
> Auflage gezeigt: Cardmarket legt diese Ausgaben Monate vor der englischen an, und die App hielt
> die zuerst angelegte für das Original. Deshalb macht der Wertverlauf in der Übersicht am
> 24.11.2026 einen Sprung. Frühere Tage lassen sich nicht nachträglich korrigieren — die
> englischen Preise von damals sind nicht gespeichert.

### Bleiben die Preise aktuell?

Ja. Die App holt sich beim Start die **tagesaktuellen Preise** — eine neue App-Version ist dafür
nicht nötig. Der Stand steht unter jedem Betrag. Die Liste aller Versionen kommt ebenfalls täglich
neu; taucht bei Cardmarket eine neue Version auf (ein Nachdruck in einem neuen Set), erscheint sie
in der Auswahl.

Ohne Internet gelten die zuletzt geladenen Preise, und davor die in der App mitgelieferten. Es
steht also immer ein Preis da, höchstens ein älterer.

Deine Auswahl bleibt dabei richtig: Gespeichert wird **welche Version** du gewählt hast (ihre
Cardmarket-Nummer), nicht der Betrag und nicht ihr Platz in der Liste.

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
