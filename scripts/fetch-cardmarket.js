// Laedt die taeglichen Cardmarket-Export-Dateien fuer One Piece (Spiel-ID 18) nach data/.
// Diese Dateien stellt Cardmarket selbst oeffentlich bereit - kein API-Zugang, kein Scraping.
// Hinweis: www.cardmarket.com ist durch Cloudflare geschuetzt und liefert 403; der hier genutzte
// Datei-Server downloads.s3.cardmarket.com ist davon nicht betroffen.

const fs = require("fs");
const path = require("path");

const GAME_ID = 18; // One Piece
const BASE = "https://downloads.s3.cardmarket.com/productCatalog";
const TARGETS = [
  { url: `${BASE}/productList/products_singles_${GAME_ID}.json`, file: `cm_products_${GAME_ID}.json` },
  { url: `${BASE}/priceGuide/price_guide_${GAME_ID}.json`, file: `cm_prices_${GAME_ID}.json` },
];

async function download({ url, file }) {
  const target = path.join(__dirname, "..", "data", file);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
  const buffer = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(target, buffer);
  console.log(`OK: ${file} (${(buffer.length / 1024 / 1024).toFixed(2)} MB)`);
}

(async () => {
  for (const t of TARGETS) await download(t);
  console.log("Fertig. Weiter mit: node scripts/import-cardmarket-prices.js");
})();
