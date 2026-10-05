// Fuehrt CardDb.json / CardDb2.json / CardDb3.json (Quelle: github.com/nemesis312/OnePieceTCGEngCardList)
// zu einer flachen, normalisierten Kartenliste zusammen. Nur Struktur/Logik des Prototyps -
// keine eigene Kartendatenbank, Quelle bleibt extern und muss fuer Produktion ersetzt/aktualisiert werden
// (siehe README: Datenstand April 2024, deckt nur OP01-OP06 + Promos + ST01-13 ab).

const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(__dirname, "..", "data");
const SOURCE_FILES = ["CardDb.json", "CardDb2.json", "CardDb3.json"];

function loadCards() {
  const all = [];
  for (const file of SOURCE_FILES) {
    const fullPath = path.join(DATA_DIR, file);
    if (!fs.existsSync(fullPath)) {
      console.warn(`Fehlt, wird uebersprungen: ${file}`);
      continue;
    }
    const text = fs.readFileSync(fullPath, "utf8").replace(/^﻿/, ""); // BOM-sicher
    const raw = JSON.parse(text);
    const cards = raw.Cards || raw.cards || [];
    all.push(...cards);
  }
  return all;
}

function normalize(raw) {
  const id = (raw.CardNum || "").replace(/^#/, "");
  return {
    id: raw.Alt ? `${id}-ALT` : id,
    baseId: id,
    alt: !!raw.Alt,
    name: raw.Name || "",
    rarity: raw["Rarity"] || "",
    cardType: raw["Card Type"] || "",
    color: raw["Primary color"] || "",
    power: raw["Power"] ?? null,
    costLife: raw["Cost/Life"] ?? null,
    effect: raw["Effect"] || "",
    img: raw["Img"] || null,
    // Keine echte Preis-Quelle aus dieser Kartendatenbank. Siehe price-mock.js
  };
}

function main() {
  const rawCards = loadCards();
  const seen = new Set();
  const normalized = [];
  for (const raw of rawCards) {
    const card = normalize(raw);
    if (!card.id || !card.name) continue;
    const key = card.id;
    if (seen.has(key)) continue; // einfache Dedupe ueber id (inkl. -ALT-Suffix)
    seen.add(key);
    normalized.push(card);
  }
  const outPath = path.join(DATA_DIR, "cards.normalized.json");
  fs.writeFileSync(outPath, JSON.stringify(normalized, null, 2), "utf8");
  console.log(`OK: ${normalized.length} Karten aus ${rawCards.length} Rohdatensaetzen -> ${outPath}`);
}

main();
