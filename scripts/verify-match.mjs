// Einmaliger Sanity-Check: bestaetigt, dass die nach public/js/ portierte Browser-Logik
// (match.js, price-mock.js) fuer denselben echten OCR-Text dasselbe Ergebnis liefert
// wie die bereits bewiesene Node-Variante aus dem ersten Prototyp-Durchlauf.
import { findMatches } from "../public/js/match.js";
import { mockPriceFor } from "../public/js/price-mock.js";
import fs from "node:fs";

const cards = JSON.parse(fs.readFileSync(new URL("../data/cards.normalized.json", import.meta.url)));
const realOcrText = `£ ye
mm 5000 %
—\\
= <8 =
> dl iq Pr Cl
2S s | |
~1 J LP
= rd E 2
>, \\ 1 ) /
WPLE
5 |W
ar " ofiyour; Characters gain caf
——
- LEADER [A :
Roronoa Zoro rll
Supernovas/Straw Hat Crew oo01.001 um §
&`;

const matches = findMatches(realOcrText, cards, 5);
console.log(`Treffer: ${matches.length}`);
for (const { card, score } of matches) {
  console.log(`- ${card.id} ${card.name} (score=${score}) price=${JSON.stringify(mockPriceFor(card))}`);
}

const top = matches[0]?.card;
if (top?.id === "OP01-001") {
  console.log("OK: Top-Treffer ist OP01-001 wie erwartet.");
} else {
  console.error("ABWEICHUNG: Top-Treffer ist NICHT OP01-001 -", top?.id);
  process.exit(1);
}
