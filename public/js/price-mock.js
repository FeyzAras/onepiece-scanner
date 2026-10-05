// MOCK-Preisquelle. KEINE echte Cardmarket-Anbindung - siehe README.md, Abschnitt "Preise".
// Cardmarkets offizieller Preis-Export (cardmarket.com/OnePiece/Data/Price-Guide) war aus der
// Entwicklungs-Sandbox heraus mit HTTP 403 (Cloudflare) blockiert. Ob das von einem echten
// Nutzer-Geraet/Server aus funktioniert, ist offen (siehe README "Naechste Schritte").

const RARITY_WEIGHT = {
  L: 6, SEC: 20, SR: 8, R: 3, UC: 1.2, C: 0.4, P: 2,
  "L-Alt": 10, "SR-Alt": 9, "SEC-Alt": 22,
};

export function mockPriceFor(card) {
  const base = RARITY_WEIGHT[card.rarity] ?? 1;
  let hash = 0;
  for (const ch of card.id) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  const jitter = (hash % 500) / 100;
  const price = Math.round((base + jitter) * 100) / 100;
  return {
    amount: price,
    currency: "EUR",
    source: "MOCK - keine echte Cardmarket-Anbindung",
    asOf: null,
  };
}
