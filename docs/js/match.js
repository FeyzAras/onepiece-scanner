// Abgleich von OCR-Rohtext gegen den Kartenkatalog.
//
// Zwei Stufen:
//  1. Kartennummer (z.B. "OP01-001", "ST13-002", "P-015") - eindeutig und loest das Problem
//     mehrerer Karten mit identischem Namen. OCR liest die Nummer oft fehlerhaft
//     (z.B. "oo01.001" statt "OP01-001"), deshalb werden tolerante Varianten gebildet und
//     nur akzeptiert, wenn sie eine real existierende Karten-ID ergeben.
//  2. Kartenname - Fallback, wenn die Nummer nicht lesbar war.

const KNOWN_PREFIXES = ["OP", "ST", "EB", "PRB", "P"];
const CANDIDATE_RE = /\b([A-Za-z0-9]{1,5})\s*[-–—_.·]\s*(\d{3})\b/g;

let _idIndex = null;
let _idIndexSource = null;

function idIndex(cards) {
  if (_idIndex && _idIndexSource === cards) return _idIndex;
  _idIndex = new Map(cards.map((c) => [c.id.toUpperCase(), c]));
  _idIndexSource = cards;
  return _idIndex;
}

function editDistance1(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) diff++;
  return diff === 1;
}

function prefixCandidates(letters) {
  const out = new Set();
  if (KNOWN_PREFIXES.includes(letters)) out.add(letters);
  for (const known of KNOWN_PREFIXES) {
    if (editDistance1(letters, known)) out.add(known);
  }
  if (out.size === 0) out.add(letters);
  return [...out];
}

export function normalizeText(text) {
  return (text || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

// Liefert eine real existierende Karten-ID oder null.
export function extractCardId(text, cards) {
  const index = idIndex(cards);
  const haystack = text || "";
  CANDIDATE_RE.lastIndex = 0;
  let m;
  while ((m = CANDIDATE_RE.exec(haystack)) !== null) {
    const rawHead = m[1].toUpperCase();
    const tail = m[2];
    // Kopf in Buchstaben- und Zifferteil zerlegen, typische OCR-Verwechslungen ausgleichen
    const parts = /^([A-Z0-9]*?)([0-9O]{0,2})$/.exec(rawHead);
    const letters = (parts ? parts[1] : rawHead).replace(/0/g, "O").replace(/1/g, "I");
    const digits = (parts ? parts[2] : "").replace(/O/g, "0");

    for (const prefix of prefixCandidates(letters)) {
      const ids = [];
      if (digits) ids.push(`${prefix}${digits.padStart(2, "0")}-${tail}`);
      ids.push(`${prefix}-${tail}`);
      for (const id of ids) {
        if (index.has(id)) return id;
      }
    }
  }
  return null;
}

function scoreCard(ocrTokens, ocrJoined, card) {
  const nameTokens = normalizeText(card.name);
  if (nameTokens.length === 0) return 0;

  let overlap = 0;
  for (const t of nameTokens) {
    if (ocrTokens.includes(t)) overlap += 1;
  }
  let score = overlap / nameTokens.length;

  const nameJoined = nameTokens.join(" ");
  if (nameJoined.length > 2 && ocrJoined.includes(nameJoined)) {
    score += 1; // voller Name als Teilstring gefunden
  }
  return score;
}

export function findMatches(ocrText, cards, limit = 5) {
  const id = extractCardId(ocrText, cards);
  if (id) {
    const card = idIndex(cards).get(id);
    if (card) return [{ card, score: 3, how: "number" }];
  }

  const ocrTokens = normalizeText(ocrText);
  const ocrJoined = ocrTokens.join(" ");
  return cards
    .map((card) => ({ card, score: scoreCard(ocrTokens, ocrJoined, card), how: "name" }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}
