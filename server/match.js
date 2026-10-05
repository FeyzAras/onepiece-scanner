// Einfache, abhaengigkeitsfreie Textaehnlichkeit zum Abgleich von OCR-Rohtext gegen Kartennamen.
// Bewusst simpel gehalten (Prototyp): Wortueberschneidung + Teilstring-Bonus.
// Ausbaustufe laut Konzeption (KS-20): Bild-Hash/Embedding-Abgleich statt/zusaetzlich zu OCR-Text.

function normalizeText(text) {
  return (text || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

function scoreCard(ocrTokens, ocrRaw, card) {
  const nameTokens = normalizeText(card.name);
  if (nameTokens.length === 0) return 0;

  let overlap = 0;
  for (const t of nameTokens) {
    if (ocrTokens.includes(t)) overlap += 1;
  }
  let score = overlap / nameTokens.length;

  const nameNormalized = nameTokens.join(" ");
  const ocrNormalized = ocrTokens.join(" ");
  if (nameNormalized.length > 2 && ocrNormalized.includes(nameNormalized)) {
    score += 1; // voller Name als Teilstring im OCR-Text gefunden
  }

  return score;
}

function findMatches(ocrText, cards, limit = 5) {
  const ocrTokens = normalizeText(ocrText);
  const scored = cards
    .map((card) => ({ card, score: scoreCard(ocrTokens, ocrText, card) }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
  return scored;
}

module.exports = { findMatches, normalizeText };
