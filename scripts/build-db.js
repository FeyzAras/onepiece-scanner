// Baut public/data/cards.json aus dem gepflegten npm-Paket "one-piece-card-game-json"
// (https://www.npmjs.com/package/one-piece-card-game-json, Quelle: github.com/bountycards/onePieceCardGameParser).
// Deckt (Stand Installation) OP01-OP17, EB01-04, Promos und ST01-36 ab - deutlich vollstaendiger
// als die zuvor genutzte statische GitHub-Datei (nur bis OP06). Englische Version (en/cards.json).

const fs = require("fs");
const path = require("path");
const raw = require("one-piece-card-game-json/en/cards.json");
const rawJp = require("one-piece-card-game-json/jp/cards.json");

function normalize(card) {
  const id = card.card_number || "";
  const costLife = card.cost && card.cost !== "-" ? card.cost : (card.life && card.life !== "-" ? card.life : null);
  const colors = Array.isArray(card.colors) ? card.colors.filter(Boolean) : [];
  return {
    id: card.is_alternate_art ? `${id}-ALT` : id,
    baseId: id,
    alt: !!card.is_alternate_art,
    name: card.card_name || "",
    rarity: card.rarity || "",
    cardType: card.card_type || "",
    // Erste Farbe bleibt fuer die Web-Version erhalten. Die vollstaendige Liste steht in
    // `colors`: 154 Leader sind zweifarbig (z.B. OP01-002 Rot/Gruen). Frueher ging die
    // zweite Farbe hier verloren - beim Deckbau haette ein rot-gruener Leader dann nur
    // rote Karten zugelassen.
    color: colors[0] || "",
    colors,
    power: card.power && card.power !== "-" ? Number(card.power) : null,
    costLife: costLife !== null ? Number(costLife) : null,
    counter: card.counter && card.counter !== "-" ? Number(card.counter) || null : null,
    effect: card.effects || "",
    img: card.image_url || null,
  };
}

/// Setcode einer Kartennummer: "OP01-001" -> "OP01", "P-001" -> "P".
function setCodeOf(cardNumber) {
  return String(cardNumber || "").split("-")[0];
}

/// "-ROMANCE DAWN- [OP-01]" -> { name: "Romance Dawn", codes: ["OP01"] }
/// "-ADVENTURE ON KAMI'S ISLAND- [OP-15-EB04]" -> { codes: ["OP15", "EB04"] }
function parseProduct(label) {
  const text = String(label || "").trim();
  const klammer = text.match(/\[([^\]]+)\]\s*$/);
  const codes = [];
  if (klammer) {
    // "OP-15-EB04" -> OP15, EB04 ; "PRB-01" -> PRB01 ; "ST-01" -> ST01
    const teile = klammer[1].toUpperCase().match(/[A-Z]+-?\d+/g) || [];
    for (const t of teile) codes.push(t.replace("-", ""));
  }
  let name = (klammer ? text.slice(0, klammer.index) : text).trim().replace(/^-+|-+$/g, "").trim();
  // Die Quelle schreibt die meisten Namen in Grossbuchstaben - fuer die Anzeige normalisieren.
  // "Ueberwiegend gross" statt "ganz gross": "ONE PIECE CARD THE BEST vol.2" soll mit.
  const buchstaben = name.replace(/[^\p{L}]/gu, "");
  const gross = buchstaben.replace(/[^\p{Lu}]/gu, "").length;
  if (buchstaben.length && gross / buchstaben.length > 0.7) name = titelSchreibweise(name);
  return { name, codes };
}

/// Englische Titelschreibweise: kleine Fuellwoerter bleiben klein, ausser am Anfang.
/// "500 YEARS IN THE FUTURE" -> "500 Years in the Future"
function titelSchreibweise(text) {
  const klein = new Set(["a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"]);
  return text
    .toLowerCase()
    .split(" ")
    .map((wort, i) => {
      if (i > 0 && klein.has(wort)) return wort;
      return wort.replace(/\p{L}/u, (b) => b.toUpperCase());
    })
    .join(" ");
}

/// Set-Namen aus den Produktangaben der Karten.
///
/// Ein einfacher Mehrheitsentscheid waere falsch: Die EB04-Karten stecken in zwei
/// verschiedenen Produkten (OP-14 und OP-15), und Nachdrucke tauchen in fremden Produkten
/// auf. Deshalb zaehlt nur ein Produkt, dessen Code mit dem Set BEGINNT. Gibt es keins,
/// bleibt der Name leer und die Produkte werden als "enthalten in" genannt.
function buildSets(cards) {
  const proSet = new Map();
  for (const card of cards) {
    const code = setCodeOf(card.card_number);
    if (!code) continue;
    if (!proSet.has(code)) proSet.set(code, new Map());
    const label = String(card.card_sets || "").trim();
    if (label) proSet.get(code).set(label, (proSet.get(code).get(label) || 0) + 1);
  }

  const sets = [];
  for (const [code, labels] of [...proSet.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const produkte = [...labels.entries()]
      .map(([label, anzahl]) => ({ ...parseProduct(label), anzahl }))
      .sort((a, b) => b.anzahl - a.anzahl);

    if (code === "P") {
      sets.push({ code, name: "Promokarten" });
      continue;
    }

    const eigenes = produkte.find((p) => p.codes[0] === code && p.name);
    if (eigenes) {
      sets.push({ code, name: eigenes.name });
      continue;
    }

    const enthalten = produkte.filter((p) => p.codes.includes(code) && p.name).map((p) => p.name);
    sets.push(enthalten.length ? { code, name: null, enthalten } : { code, name: null });
  }
  return sets;
}

/// Nimmt Karten auf, die es nur im japanischen Katalog gibt.
///
/// Hintergrund: Der japanische Katalog enthaelt dieselben lateinischen Namen und englischen
/// Effekttexte wie der englische - nur die Bildadressen unterscheiden sich (japanisches
/// Artwork). Japanische Karten tragen dieselbe Kartennummer in lateinischer Schrift und
/// werden deshalb ohnehin erkannt. Was fehlt, sind die Karten, die nie auf Englisch
/// erschienen sind: ohne sie findet die App beim Scannen schlicht keinen Eintrag.
function japanOnly(vorhandeneIds) {
  const liste = Array.isArray(rawJp) ? rawJp : rawJp.all || [];
  const ergaenzt = [];
  for (const card of liste) {
    const entry = normalize(card);
    if (!entry.id || !entry.name || vorhandeneIds.has(entry.id)) continue;
    entry.jpOnly = true; // in der App als "nur japanisch erschienen" kenntlich
    ergaenzt.push(entry);
  }
  return ergaenzt;
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

  // Karten ergaenzen, die nur auf Japanisch erschienen sind
  const nurJp = japanOnly(seen);
  for (const entry of nurJp) {
    const old = previous.get(entry.id);
    if (old?.price) entry.price = old.price;
    if (old?.imgHash) entry.imgHash = old.imgHash;
    normalized.push(entry);
  }

  fs.writeFileSync(outPath, JSON.stringify(normalized, null, 2), "utf8");
  console.log(`OK: ${normalized.length} Karten aus ${list.length} Rohdatensaetzen -> ${outPath}`);
  console.log(`    davon nur auf Japanisch erschienen: ${nurJp.length}`);
  console.log(`    uebernommen: ${keptPrices} Preise, ${keptHashes} Bild-Fingerabdruecke`);
  console.log(`    zweifarbig: ${normalized.filter((c) => c.colors.length > 1).length}`);

  // Set-Namen fuer die Uebersicht in der App
  const sets = buildSets(list);
  const setsPath = path.join(dataDir, "sets.json");
  fs.writeFileSync(setsPath, JSON.stringify(sets, null, 2), "utf8");
  const ohneName = sets.filter((s) => !s.name).map((s) => s.code);
  console.log(`OK: ${sets.length} Sets -> ${setsPath}` + (ohneName.length ? ` (ohne eigenen Namen: ${ohneName.join(", ")})` : ""));
}

module.exports = { normalize, parseProduct, buildSets, setCodeOf };

// Nur beim direkten Aufruf bauen - so lassen sich die Funktionen oben testen
if (require.main === module) main();
