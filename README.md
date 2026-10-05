# One Piece TCG Scanner

**Live:** https://feyzaras.github.io/onepiece-scanner/

Installierbare PWA (Progressive Web App): Handy-Kamera auf eine One-Piece-TCG-Karte halten,
auslösen, Karte wird erkannt und mit (aktuell: Platzhalter-)Preis angezeigt.

Projektkontext: `2.7.Pythagoras/Projekte/P-001_TCG_Marktplatz_DE/02_Konzeption_Kartenscanner_OnePiece.md`
im Obsidian-Vault.

## Warum PWA und nicht die ursprünglich geplante Flutter-App?

Die Technikentscheidung `KS-D3` (Konzeptionsdatei) sah Flutter vor. Diese Entwicklungsumgebung
hier hatte aber **kein Flutter/Android-SDK installiert** und keinen Zugriff auf ein physisches
Android-Gerät (nur dieser Windows-Rechner, kein verbundenes Handy). Eine Flutter-Umgebung
unbeaufsichtigt komplett neu aufzusetzen (Android Studio, SDK, Emulator) wäre ein Mehrstunden-Risiko
mit ungewissem Ausgang gewesen. Eine PWA ist dagegen in Android Chrome vollwertig: echter
Kamerazugriff, "Zum Startbildschirm hinzufügen" verhält sich wie eine installierte App, Offline-Cache
über Service Worker. Das ist eine bewusste, dokumentierte Abweichung — keine stille Änderung.
Native (Flutter) bleibt eine spätere Option, falls echte On-Device-Performance/Store-Vertrieb
gebraucht wird.

## Starten (lokale Vorschau am Rechner)

```
npm install
npm run build-db   # Kartendaten neu zusammenfuehren + in docs/data/cards.json kopieren
npm run dev        # Vorschau unter http://localhost:3000
```

**Live-Version (GitHub Pages):** siehe oben verlinkt / im Repo unter Settings → Pages.

**Auf dem Handy nutzen:** Live-URL in Chrome auf dem Android-Handy öffnen → Menü →
"Zum Startbildschirm hinzufügen" (oder der "Als App installieren"-Hinweis in der App selbst).
Danach startet sie wie eine normale App, mit eigenem Icon.

## Architektur

Komplett **client-seitig**, kein eigener Server nötig für den Betrieb. Liegt im Ordner `docs/`
(GitHub-Pages-Konvention: Branch-Deploy direkt aus `/docs`, keine Actions/Build-Pipeline nötig):
- `docs/index.html` + `docs/js/app.js` — Kamera-UI, Aufnahme, Steuerung
- `docs/js/match.js` — Textabgleich OCR-Ergebnis → Katalogeintrag
- `docs/js/price-mock.js` — Preisberechnung (aktuell Platzhalter, siehe unten)
- `docs/data/cards.json` — Kartenkatalog (statisch, aus `data/cards.normalized.json` generiert)
- `docs/manifest.json` + `docs/sw.js` — PWA-Installierbarkeit + Offline-Cache
- OCR läuft im Browser über `tesseract.js` (von jsDelivr-CDN geladen, Version gepinnt)
- `server/dev-server.js` — **nur** lokale Vorschau, nicht Teil des Produkts
- `server/build-db.js` + `scripts/sync-cards.js` — Kartendaten-Pipeline (einmalig/bei Updates ausführen)

## Was ist echt, was ist Platzhalter?

| Teil | Status |
| --- | --- |
| Kamera-UI, Aufnahme, Installierbarkeit, Offline-Cache | **echt**, fertig gebaut |
| OCR-Erkennung | **echt**, läuft wirklich (tesseract.js) |
| Matching OCR-Text → Karte | **echt, aber einfach** — kann gleichnamige Karten (z.B. mehrere "Roronoa Zoro"-Varianten) nicht unterscheiden. Ausbaustufe: Bild-Hash/Embedding-Abgleich statt/zusätzlich zu Text. |
| Kartenkatalog | **echt, aktuell gepflegt** — Quelle: npm-Paket [`one-piece-card-game-json`](https://www.npmjs.com/package/one-piece-card-game-json) ([github.com/bountycards/onePieceCardGameParser](https://github.com/bountycards/onePieceCardGameParser)), zuletzt aktualisiert 09/2026. 3.868 Karten, deckt OP01–OP17, EB01–04, Promos und ST01–36 ab. |
| **Preise** | **Platzhalter (Mock), keine echten Zahlen** — siehe unten |

## Preise: aktueller Stand und was noch fehlt

Cardmarket veröffentlicht offizielle, frei nutzbare tägliche Preis-Export-Dateien (seit 07/2025,
One Piece Card Game ausdrücklich abgedeckt, kein API-Antrag nötig). **Der direkte Download dieser
Datei war aus der Entwicklungs-Sandbox, in der dieses Projekt gebaut wurde, mit HTTP 403
(Cloudflare-Block) nicht möglich** — getestet, nicht nur vermutet, auch mit Browser-User-Agent.

Das ist ein Befund zu dieser einen Sandbox-Umgebung, keine Aussage über dein eigenes Netzwerk.
Nächster Schritt dafür: von einem normalen Rechner/Server aus `https://www.cardmarket.com/OnePiece/Data/Price-Guide`
testen. Funktioniert das, kann ein kleines Importskript (täglich per GitHub Action o.ä.) die echten
Preise in `docs/data/cards.json` einspielen — das ist noch nicht geschrieben.

## Grenzen (ehrlich, nicht beschönigt)

1. Kein echtes Handyfoto konnte in dieser Entwicklungsumgebung getestet werden (kein Gerät
   angeschlossen) — nur der saubere Katalog-Scan. Realistische Bedingungen (Winkel, Beleuchtung,
   Hochglanzfolie) sind ungetestet.
2. Kamera-Berechtigung/PWA-Installierbarkeit/Service-Worker-Verhalten konnten nur per Code-Review
   und durch Laden der statischen Dateien geprüft werden, nicht durch echte Browser-Interaktion
   (diese Sandbox hat keinen echten Browser mit Kamera). Bitte beim ersten echten Test auf dem Handy
   kurz Rückmeldung geben, falls etwas nicht wie erwartet reagiert.
3. Matching unterscheidet nicht zwischen gleichnamigen Karten (siehe Tabelle oben).
4. Preise sind Platzhalter, keine echten Cardmarket-Zahlen.
5. Kein automatischer Aktualisierungs-Mechanismus für die Kartendaten eingerichtet — `npm run build-db`
   muss manuell erneut ausgeführt werden, wenn `one-piece-card-game-json` ein Update bekommt (z.B. neues Set).

## Nächste sinnvolle Schritte
- Cardmarket-Preis-Download von außerhalb dieser Sandbox verifizieren, dann Importskript bauen.
- Matching um Set-Code/Kartennummer aus dem OCR-Zuschnitt erweitern.
- Mit echtem Handyfoto testen, Feinschliff an Kamera-Fokus/Ausleuchtung-Hinweisen.
- Optional: `npm run build-db` regelmäßig automatisiert laufen lassen (z.B. GitHub Action, wöchentlich),
  damit neue Sets automatisch einfließen.
