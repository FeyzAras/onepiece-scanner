// Preise stammen aus den taeglich von Cardmarket selbst veroeffentlichten Export-Dateien
// und liegen bereits in cards.json an der jeweiligen Karte (siehe scripts/import-cardmarket-prices.js).
// Diese Datei kuemmert sich nur noch um die Darstellung.

const BASIS_LABEL = {
  trend: "Trend",
  avg: "Durchschnitt",
  avg7: "Ø 7 Tage",
  avg30: "Ø 30 Tage",
  low: "günstigster",
};

export function priceOf(card) {
  return card.price ?? null;
}

export function formatPrice(price) {
  if (!price) return "–";
  return `${price.amount.toFixed(2)} ${price.currency === "EUR" ? "€" : price.currency}`;
}

export function priceLabel(price) {
  if (!price) return "kein Preis hinterlegt";
  return `Cardmarket ${BASIS_LABEL[price.basis] ?? price.basis}`;
}

export function sumPrices(entries) {
  return entries.reduce((sum, e) => sum + (e.card.price?.amount ?? 0), 0);
}
