// Erzeugt docs/data/prices.json - eine schlanke Preisdatei, die die App beim Start laedt.
//
// Warum getrennt von cards.json: Der Kartenkatalog (rund 3 MB) steckt als Asset in der App und
// aendert sich selten. Die Preise aendern sich taeglich. Sie hier herauszuloesen heisst:
// Die App holt sich jeden Tag rund 150 KB statt bei jeder Preisaenderung neu gebaut zu werden.
//
// Ausfuehren nach dem Preisimport:
//   node scripts/build-db.js && node scripts/fetch-cardmarket.js
//   && node scripts/import-cardmarket-prices.js && node scripts/build-price-file.js

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const CARDS = path.join(root, "data", "cards.normalized.json");
const OUT = path.join(root, "docs", "data", "prices.json");

function main() {
  const cards = JSON.parse(fs.readFileSync(CARDS, "utf8").replace(/^﻿/, ""));

  // Preis je Karten-ID (normale Version und Alt-Art getrennt)
  const prices = {};
  // Alle Cardmarket-Versionen je Kartennummer, aufsteigend. Die App braucht sie, damit
  // eine vom Nutzer gewaehlte Version auch nach einer Preisaktualisierung noch stimmt.
  const options = {};
  let asOf = "";

  for (const card of cards) {
    if (!card.price) continue;
    prices[card.id] = card.price.amount;
    if (!asOf && card.price.asOf) asOf = card.price.asOf;
    if (card.priceOptions?.length > 1 && !options[card.baseId]) {
      options[card.baseId] = card.priceOptions;
    }
  }

  const payload = {
    asOf,
    generatedAt: new Date().toISOString().slice(0, 10),
    source: "cardmarket",
    prices,
    options,
  };

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(payload), "utf8");

  const kb = Math.round(fs.statSync(OUT).size / 1024);
  console.log(`OK: ${Object.keys(prices).length} Preise, ${Object.keys(options).length} Versionslisten`);
  console.log(`    Stand ${asOf} -> ${OUT} (${kb} KB)`);
}

main();
