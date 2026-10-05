// Spielt echte Cardmarket-Preise in data/cards.normalized.json ein.
//
// Quelle: die von Cardmarket selbst taeglich veroeffentlichten Export-Dateien
// (angekuendigt 07/2025, ausdruecklich zur freien Nutzung in eigenen Anwendungen):
//   https://downloads.s3.cardmarket.com/productCatalog/productList/products_singles_18.json
//   https://downloads.s3.cardmarket.com/productCatalog/priceGuide/price_guide_18.json
// 18 = One Piece. Die Produktnamen tragen die Kartennummer im Format "Name (OP01-001)",
// darueber laeuft die Zuordnung zu unserem Katalog.
//
// Neu laden:  node scripts/fetch-cardmarket.js   (laedt beide Dateien nach data/)
// Einspielen: node scripts/import-cardmarket-prices.js

const fs = require("fs");
const path = require("path");

const DATA = path.join(__dirname, "..", "data");
const CARD_NUMBER_RE = /\(([A-Z]{1,4}\d{0,2}-\d{3})\)/;

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.join(DATA, file), "utf8").replace(/^﻿/, ""));
}

function pickPrice(entry) {
  if (!entry) return null;
  for (const key of ["trend", "avg", "avg7", "avg30", "low"]) {
    const value = entry[key];
    if (typeof value === "number" && value > 0) {
      return { amount: Math.round(value * 100) / 100, basis: key };
    }
  }
  return null;
}

function main() {
  const products = readJson("cm_products_18.json");
  const prices = readJson("cm_prices_18.json");
  const cards = readJson("cards.normalized.json");

  const priceByProduct = new Map(prices.priceGuides.map((p) => [p.idProduct, p]));

  // Kartennummer -> bester verfuegbarer Preis. Zu einer Nummer koennen mehrere
  // Produkte gehoeren (verschiedene Drucke); wir nehmen den ersten mit echtem Preis.
  const priceByCardNumber = new Map();
  let withoutNumber = 0;
  for (const product of products.products) {
    const m = CARD_NUMBER_RE.exec(product.name);
    if (!m) { withoutNumber++; continue; }
    const cardNumber = m[1];
    if (priceByCardNumber.has(cardNumber)) continue;
    const price = pickPrice(priceByProduct.get(product.idProduct));
    if (price) {
      priceByCardNumber.set(cardNumber, { ...price, idProduct: product.idProduct });
    }
  }

  const asOf = (prices.createdAt || "").slice(0, 10);
  let matched = 0;
  for (const card of cards) {
    const hit = priceByCardNumber.get(card.baseId);
    if (hit) {
      card.price = {
        amount: hit.amount,
        currency: "EUR",
        basis: hit.basis, // trend | avg | avg7 | avg30 | low
        source: "cardmarket",
        asOf,
      };
      matched++;
    } else {
      delete card.price;
    }
  }

  fs.writeFileSync(path.join(DATA, "cards.normalized.json"), JSON.stringify(cards, null, 2), "utf8");

  const pct = ((matched / cards.length) * 100).toFixed(1);
  console.log(`Cardmarket-Stand:      ${asOf}`);
  console.log(`Produkte gelesen:      ${products.products.length} (davon ohne Kartennummer: ${withoutNumber})`);
  console.log(`Preise zugeordnet:     ${priceByCardNumber.size} Kartennummern`);
  console.log(`Karten mit Preis:      ${matched} von ${cards.length} (${pct} %)`);
}

main();
