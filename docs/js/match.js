// Abgleich von OCR-Rohtext gegen den Kartenkatalog.
//
// Uebernommen wird eine Karte **nur** bei gelesener Kartennummer (z.B. OP07-055, unten rechts
// auf der Karte). Der Kartenname allein reicht nicht: viele Karten heissen gleich, und Namen
// anderer Karten stehen im Effekttext - beim Scannen von "Snake Dance" wurden so reihum
// "Gina" und "Portgas.D.Ace" erkannt.
//
// OCR liest die Nummer oft fehlerhaft ("oo01.001" statt "OP01-001"), deshalb werden tolerante
// Varianten gebildet und nur akzeptiert, wenn sie eine real existierende Karten-ID ergeben.

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

function differsByOne(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) diff++;
  return diff === 1;
}

function prefixCandidates(letters) {
  const out = new Set();
  if (KNOWN_PREFIXES.includes(letters)) out.add(letters);
  for (const known of KNOWN_PREFIXES) {
    if (differsByOne(letters, known)) out.add(known);
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

function nameOnlyGuess(cards, joined) {
  for (const card of cards) {
    const nameJoined = normalizeText(card.name).join(" ");
    if (nameJoined.length > 4 && joined.includes(nameJoined)) return card.name;
  }
  return null;
}

/// Ergebnis: { card, nameConfirmed, how } bei Treffer, sonst { nameOnlyHint }.
export function matchCard(ocrText, cards) {
  const id = extractCardId(ocrText, cards);
  const joined = normalizeText(ocrText).join(" ");

  if (id) {
    const card = idIndex(cards).get(id);
    if (card) {
      const nameJoined = normalizeText(card.name).join(" ");
      const nameConfirmed = nameJoined.length > 2 && joined.includes(nameJoined);
      return { card, nameConfirmed, how: nameConfirmed ? "number+name" : "number" };
    }
  }
  return { nameOnlyHint: nameOnlyGuess(cards, joined) };
}
