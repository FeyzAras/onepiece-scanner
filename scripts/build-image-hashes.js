// Berechnet Bild-Fingerabdruecke (dHash) fuer alle Karten, deren Nummer mehrere Artworks hat.
//
// Hintergrund: Die Kartennummer (z.B. OP01-001) ist nicht eindeutig - es gibt zu vielen Nummern
// eine normale und eine Alt-Art-Version mit identischer Nummer und identischem Namen. Welche
// davon vor der Kamera liegt, laesst sich nur am Bild erkennen.
//
// dHash: Bild auf 9x8 Graustufen verkleinern, je zwei waagerecht benachbarte Pixel vergleichen
// -> 64 Bit. Robust gegen Helligkeit und leichte Unschaerfe, empfindlich fuer Bildinhalt.
//
// Ausfuehren: npm install --no-save sharp && node scripts/build-image-hashes.js
// Laeuft lange (laedt ueber 2000 Bilder) und cached sie unter data/img-cache/.

const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const DATA = path.join(__dirname, "..", "data");
const CACHE = path.join(DATA, "img-cache");
const CARDS = path.join(DATA, "cards.normalized.json");
const CONCURRENCY = 6;

async function dHash(buffer) {
  const { data } = await sharp(buffer)
    .greyscale()
    .resize(9, 8, { fit: "fill" })
    .raw()
    .toBuffer({ resolveWithObject: true });

  let bits = "";
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const left = data[row * 9 + col];
      const right = data[row * 9 + col + 1];
      bits += left > right ? "1" : "0";
    }
  }
  // 64 Bit als 16 Hex-Zeichen
  let hex = "";
  for (let i = 0; i < 64; i += 4) {
    hex += parseInt(bits.slice(i, i + 4), 2).toString(16);
  }
  return hex;
}

async function fetchImage(card) {
  const safeName = card.id.replace(/[^A-Za-z0-9_-]/g, "_") + ".png";
  const cached = path.join(CACHE, safeName);
  if (fs.existsSync(cached)) return fs.readFileSync(cached);

  const res = await fetch(card.img, { headers: { "User-Agent": "onepiece-scanner/1.0" } });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const buffer = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(cached, buffer);
  return buffer;
}

async function main() {
  fs.mkdirSync(CACHE, { recursive: true });
  const cards = JSON.parse(fs.readFileSync(CARDS, "utf8").replace(/^﻿/, ""));

  // Nur Karten, deren Nummer mehrdeutig ist - nur dort hilft der Bildvergleich.
  const byBase = new Map();
  for (const c of cards) {
    if (!byBase.has(c.baseId)) byBase.set(c.baseId, []);
    byBase.get(c.baseId).push(c);
  }
  const targets = cards.filter((c) => c.img && byBase.get(c.baseId).length > 1);
  console.log(`${targets.length} Karten mit mehrdeutiger Nummer - Fingerabdruecke werden berechnet`);

  let done = 0;
  let failed = 0;
  const queue = [...targets];

  async function worker() {
    while (queue.length) {
      const card = queue.pop();
      try {
        const buffer = await fetchImage(card);
        card.imgHash = await dHash(buffer);
      } catch (e) {
        failed++;
        if (failed <= 5) console.warn(`  Fehler bei ${card.id}: ${e.message}`);
      }
      done++;
      if (done % 100 === 0) console.log(`  ${done}/${targets.length} …`);
    }
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  fs.writeFileSync(CARDS, JSON.stringify(cards, null, 2), "utf8");
  const withHash = cards.filter((c) => c.imgHash).length;
  console.log(`Fertig: ${withHash} Fingerabdruecke gespeichert, ${failed} fehlgeschlagen.`);
}

main();
