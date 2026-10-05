// MOCK-Preisquelle. KEINE echte Cardmarket-Anbindung.
//
// Hintergrund (siehe 02_Konzeption_Kartenscanner_OnePiece.md, Abschnitt 1.5/1.3):
// Cardmarket veroeffentlicht seit 07/2025 offizielle taegliche Preis-Export-Dateien
// (cardmarket.com/<Spiel>/Data/Price-Guide), die One Piece Card Game abdecken.
// Direkter Abruf von cardmarket.com wurde aus dieser Entwicklungsumgebung heraus
// getestet und mit HTTP 403 (Cloudflare) blockiert - auch mit Browser-User-Agent.
// Das ist eine Infrastruktur-/Umgebungsfrage dieser Session, keine Aussage ueber die
// Produktionsumgebung. Bis zum echten Import liefert dieses Modul einen deterministischen,
// klar erkennbaren Platzhalterpreis, damit die restliche Pipeline (Erkennung -> Anzeige)
// end-to-end testbar ist.

function mockPriceFor(card) {
  const rarityWeight = {
    L: 6, SEC: 20, SR: 8, R: 3, UC: 1.2, C: 0.4, P: 2, "L-Alt": 10,
  };
  const base = rarityWeight[card.rarity] ?? 1;
  let hash = 0;
  for (const ch of card.id) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  const jitter = (hash % 500) / 100; // 0.00 - 4.99
  const price = Math.round((base + jitter) * 100) / 100;
  return {
    amount: price,
    currency: "EUR",
    source: "MOCK - keine echte Cardmarket-Anbindung (siehe Kommentar in price-mock.js)",
    asOf: null,
  };
}

module.exports = { mockPriceFor };
