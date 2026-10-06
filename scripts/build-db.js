// Baut public/data/cards.json aus dem gepflegten npm-Paket "one-piece-card-game-json"
// (https://www.npmjs.com/package/one-piece-card-game-json, Quelle: github.com/bountycards/onePieceCardGameParser).
// Deckt (Stand Installation) OP01-OP17, EB01-04, Promos und ST01-36 ab - deutlich vollstaendiger
// als die zuvor genutzte statische GitHub-Datei (nur bis OP06). Englische Version (en/cards.json).

const fs = require("fs");
const path = require("path");
const raw = require("one-piece-card-game-json/en/cards.json");

function normalize(card) {
  const id = card.card_number || "";
  const costLife = card.cost && card.cost !== "-" ? card.cost : (card.life && card.life !== "-" ? card.life : null);
  return {
    id: card.is_alternate_art ? `${id}-ALT` : id,
    baseId: id,
    alt: !!card.is_alternate_art,
    name: card.card_name || "",
    rarity: card.rarity || "",
    cardType: card.card_type || "",
    color: (card.colors || [])[0] || "",
    power: card.power && card.power !== "-" ? Number(card.power) : null,
    costLife: costLife !== null ? Number(costLife) : null,
    effect: card.effects || "",
    img: card.image_url || null,
  };
}

/// Preise und Bild-Fingerabdruecke stammen aus eigenen Schritten (import-cardmarket-prices.js,
/// build-image-hashes.js). Beim Neuaufbau des Katalogs werden sie uebernommen, damit ein
/// erneuter Lauf diese Arbeit nicht zunichtemacht.
function carryOver(outPath) {
  if (!fs.existsSync(outPath)) return new Map();
  try {
    const previous = JSON.parse(fs.readFileSync(outPath, "utf8").replace(/^﻿/, ""));
    return new Map(previous.map((c) => [c.id, { price: c.price, imgHash: c.imgHash }]));
  } catch {
    return new Map();
  }
}

function main() {
  const dataDir = path.join(__dirname, "..", "data");
  // data/ ist bewusst nicht versioniert (Zwischendateien), fehlt also im frischen Checkout
  fs.mkdirSync(dataDir, { recursive: true });
  const outPath = path.join(dataDir, "cards.normalized.json");
  const previous = carryOver(outPath);

  const list = Array.isArray(raw) ? raw : raw.all || [];
  const seen = new Set();
  const normalized = [];
  let keptPrices = 0;
  let keptHashes = 0;
  for (const card of list) {
    const entry = normalize(card);
    if (!entry.id || !entry.name) continue;
    if (seen.has(entry.id)) continue;
    seen.add(entry.id);

    const old = previous.get(entry.id);
    if (old?.price) {
      entry.price = old.price;
      keptPrices++;
    }
    if (old?.imgHash) {
      entry.imgHash = old.imgHash;
      keptHashes++;
    }
    normalized.push(entry);
  }

  fs.writeFileSync(outPath, JSON.stringify(normalized, null, 2), "utf8");
  console.log(`OK: ${normalized.length} Karten aus ${list.length} Rohdatensaetzen -> ${outPath}`);
  console.log(`    uebernommen: ${keptPrices} Preise, ${keptHashes} Bild-Fingerabdruecke`);
}

main();
