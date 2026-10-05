# One Piece TCG Scanner — Prototyp

Validierungs-Prototyp für das Projekt `P-001` / Sub-Konzept "Kartenscanner One Piece TCG"
(siehe Obsidian: `2.7.Pythagoras/Projekte/P-001_TCG_Marktplatz_DE/02_Konzeption_Kartenscanner_OnePiece.md`).

**Zweck:** vor dem Bau der eigentlichen Flutter-App (Entscheidung `KS-D3`) die zwei riskantesten
Fragen klären: (1) Ist eine Kartenerkennung aus einem Foto mit frei verfügbarer Technik überhaupt
machbar? (2) Sind Kartendaten + Preisdaten tatsächlich beschaffbar? Dieser Prototyp ist **kein**
Vorgriff auf die Plattform-Entscheidung — er läuft als Node/Web-Demo, weil das in dieser
Entwicklungsumgebung sofort lauffähig war (kein Flutter/Android-SDK installiert).

## Status: läuft, End-to-End getestet

```
npm install
npm run build-db   # fuehrt CardDb.json/2/3 zu data/cards.normalized.json zusammen
npm start           # Server unter http://localhost:3000
```

Im Browser `http://localhost:3000` öffnen → "Testbild nutzen" → "Scannen". Auf dem Handy
funktioniert auch die echte Kamera über den Datei-Upload-Button (`capture="environment"`).

Echter Testlauf (siehe `server/test-scan.js`, `node server/test-scan.js` bei laufendem Server):
Testbild OP01-001 (Roronoa Zoro) → OCR erkennt u.a. den Klartext "Roronoa Zoro" → Matching findet
`OP01-001` als Treffer (zusammen mit anderen Karten, die ebenfalls "Roronoa Zoro" heißen — siehe
Grenzen unten).

## Was ist echt, was ist Mock/Platzhalter?

| Teil | Status | Quelle |
| --- | --- | --- |
| Kartenkatalog (Name, Typ, Bild-URL) | **echt**, aber veraltet | [github.com/nemesis312/OnePieceTCGEngCardList](https://github.com/nemesis312/OnePieceTCGEngCardList) — Stand April 2024, deckt nur OP01–OP06 + Promos + ST01–13 ab. Aktuelle Sets (OP07+) fehlen. |
| Kartenbilder | **echt** | Direkte URLs zu `en.onepiece-cardgame.com` (offizielle Bandai-Seite), aus dem Katalog übernommen. |
| OCR-Erkennung | **echt**, läuft wirklich | `tesseract.js` (WASM, kein natives Tesseract nötig). Funktioniert auf sauberem Kartenscan; bei echtem Handyfoto (Spiegelung, Winkel, Folie) unklar — nicht getestet, kein echtes Kartenfoto verfügbar. |
| Matching (Foto → Katalogeintrag) | **echt, aber simpel** | Nur Wortabgleich gegen den Kartennamen. Kann nicht zwischen mehreren Karten mit demselben Namen unterscheiden (z.B. "Roronoa Zoro" kommt als Leader, Charakter, Alt-Art etc. mehrfach vor) — siehe Konzeption `KS-D5`/`KS-20`, genau das soll die spätere Hash-/Embedding-Stufe lösen. |
| Preise | **MOCK**, nicht echt | Siehe `server/price-mock.js`. Deterministisch nach Rarity, aber **keine echte Cardmarket-Zahl**. |

## Warum Preise gemockt sind (konkreter Befund, kein Blindflug)

Direkter Abruf von `cardmarket.com` (sowohl die Website als auch der dokumentierte
Price-Guide-Pfad `cardmarket.com/OnePiece/Data/Price-Guide`) wurde aus dieser Entwicklungsumgebung
heraus getestet — **HTTP 403, Cloudflare-Block**, auch mit Browser-User-Agent. Das ist ein Befund
zu *dieser Sandbox-Umgebung*, keine Aussage über die künftige Produktionsumgebung (eigener Server,
andere IP/Netzwerk). Vor dem echten Import muss das von einer Umgebung aus getestet werden, die
nicht hinter diesem Sandbox-Netzwerk sitzt.

## Bekannte Grenzen / offene Punkte

1. **Kartendatenbank veraltet** — nur bis OP06 + Promos + ST01-13 (Stand 04/2024). Für Produktion:
   aktuellere/vollständigere Quelle nötig (`optcgapi.com` sollte eine bessere Abdeckung haben,
   aber die echten API-Endpunkte wurden in dieser Session nicht gefunden — `/about` gab 404,
   mehrere Pfad-Rateversuche ebenfalls 404. Für den Prototyp daher auf die GitHub-JSON-Quelle
   ausgewichen, die direkt funktionierte).
2. **Matching unterscheidet nicht zwischen gleichnamigen Karten** (siehe Tabelle oben). Für die
   echte App braucht es mindestens den Set-Code/Kartennummer-Textbereich der Karte im OCR-Zuschnitt,
   oder direkt die Hash-/Embedding-Stufe aus `KS-20`.
3. **Kein echtes Handyfoto getestet**, nur der saubere Katalog-Scan als Testbild. Reale Bedingungen
   (Blickwinkel, Beleuchtung, Hochglanzfolie) sind unklar.
4. **Cardmarket-Preis-Import nicht möglich aus dieser Sandbox** (siehe oben) — Code dafür ist noch
   nicht geschrieben, nur der Mock als Platzhalter mit klarer Kennzeichnung.
5. Dies ist eine Desktop/Web-Demo, keine Mobile-App — Flutter-Entscheidung (`KS-D3`) bleibt
   unverändert für das Produkt, dieser Prototyp testet nur die Risiko-Annahmen.

## Nächste sinnvolle Schritte
- Cardmarket-Export-Download von einer Nicht-Sandbox-Umgebung aus verifizieren.
- Aktuelle One-Piece-Kartenquelle mit vollständiger Abdeckung finden/bestätigen (echte
  `optcgapi.com`-Dokumentation klären, z.B. über deren Discord laut Website-Hinweis).
- Matching um Set-Code/Kartennummer-Erkennung erweitern, um gleichnamige Karten zu trennen.
- Mit einem echten Handyfoto (schräger Winkel, normales Licht) testen, sobald eins vorliegt.
