// Verteilt die fertigen Datendateien an die beiden Anwendungen:
//   data/cards.normalized.json -> docs/data/cards.json        (Web-App)
//                              -> android_app/assets/cards.json (Android-App)
//   docs/data/decks.json       -> android_app/assets/decks.json
//   data/sets.json             -> android_app/assets/sets.json  (Set-Namen fuer die Uebersicht)
//   docs/data/versions.json    -> android_app/assets/versions.json (Cardmarket-Versionen, Rueckfall ohne Netz)
//
// Immer nach einer Datenaenderung ausfuehren, sonst arbeiten die Apps mit altem Stand.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");

const copies = [
  { from: "data/cards.normalized.json", to: "docs/data/cards.json" },
  { from: "data/cards.normalized.json", to: "android_app/assets/cards.json" },
  { from: "docs/data/decks.json", to: "android_app/assets/decks.json" },
  { from: "data/sets.json", to: "android_app/assets/sets.json" },
  { from: "docs/data/versions.json", to: "android_app/assets/versions.json" },
];

for (const { from, to } of copies) {
  const src = path.join(root, from);
  if (!fs.existsSync(src)) {
    console.warn(`übersprungen (fehlt): ${from}`);
    continue;
  }
  const dest = path.join(root, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  // Erst in eine Zwischendatei, dann umbenennen. Wird das Skript mitten im Kopieren
  // beendet, bleibt so die alte Datei stehen statt einer halben. Genau das ist einmal
  // passiert: "node sync-cards.js | Select-Object -First 2" in PowerShell beendete Node
  // nach zwei Ausgabezeilen - assets/decks.json blieb mit 0 Byte zurueck.
  const zwischen = `${dest}.tmp`;
  fs.copyFileSync(src, zwischen);
  if (fs.statSync(zwischen).size !== fs.statSync(src).size) {
    fs.unlinkSync(zwischen);
    throw new Error(`Kopie unvollstaendig: ${from}`);
  }
  fs.renameSync(zwischen, dest);

  const mb = (fs.statSync(dest).size / 1024 / 1024).toFixed(2);
  console.log(`${from} -> ${to} (${mb} MB)`);
}
