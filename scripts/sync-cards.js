// Kopiert die von server/build-db.js erzeugte Kartenliste in den statischen App-Ordner.
const fs = require("fs");
const path = require("path");

const src = path.join(__dirname, "..", "data", "cards.normalized.json");
const dest = path.join(__dirname, "..", "public", "data", "cards.json");
fs.copyFileSync(src, dest);
console.log(`Kopiert: ${src} -> ${dest}`);
