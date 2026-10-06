// Verteilt die fertigen Datendateien an die beiden Anwendungen:
//   data/cards.normalized.json -> docs/data/cards.json        (Web-App)
//                              -> android_app/assets/cards.json (Android-App)
//   docs/data/decks.json       -> android_app/assets/decks.json
//
// Immer nach einer Datenaenderung ausfuehren, sonst arbeiten die Apps mit altem Stand.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");

const copies = [
  { from: "data/cards.normalized.json", to: "docs/data/cards.json" },
  { from: "data/cards.normalized.json", to: "android_app/assets/cards.json" },
  { from: "docs/data/decks.json", to: "android_app/assets/decks.json" },
];

for (const { from, to } of copies) {
  const src = path.join(root, from);
  if (!fs.existsSync(src)) {
    console.warn(`übersprungen (fehlt): ${from}`);
    continue;
  }
  const dest = path.join(root, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  const mb = (fs.statSync(dest).size / 1024 / 1024).toFixed(2);
  console.log(`${from} -> ${to} (${mb} MB)`);
}
