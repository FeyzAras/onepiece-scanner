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

function main() {
  const list = Array.isArray(raw) ? raw : raw.all || [];
  const seen = new Set();
  const normalized = [];
  for (const card of list) {
    const entry = normalize(card);
    if (!entry.id || !entry.name) continue;
    if (seen.has(entry.id)) continue;
    seen.add(entry.id);
    normalized.push(entry);
  }
  const outPath = path.join(__dirname, "..", "data", "cards.normalized.json");
  fs.writeFileSync(outPath, JSON.stringify(normalized, null, 2), "utf8");
  console.log(`OK: ${normalized.length} Karten aus ${list.length} Rohdatensaetzen -> ${outPath}`);
}

main();
