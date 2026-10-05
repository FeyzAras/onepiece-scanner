// Einfache, abhaengigkeitsfreie Textaehnlichkeit zum Abgleich von OCR-Rohtext gegen Kartennamen.
// Portiert aus server/match.js (Node-Prototyp) - identische Logik, laeuft hier im Browser.
// Bewusst simpel (Wortueberschneidung + Teilstring-Bonus). Kann nicht zwischen gleichnamigen
// Karten unterscheiden (z.B. mehrere "Roronoa Zoro"-Karten) - Ausbaustufe: Bild-Hash/Embedding.

export function normalizeText(text) {
  return (text || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

function scoreCard(ocrTokens, card) {
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
    score += 1;
  }
  return score;
}

export function findMatches(ocrText, cards, limit = 5) {
  const ocrTokens = normalizeText(ocrText);
  return cards
    .map((card) => ({ card, score: scoreCard(ocrTokens, card) }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}
