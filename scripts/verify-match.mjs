// Sanity-Checks fuer die Erkennungslogik (public/docs/js/match.js), ausgefuehrt mit Node.
// Deckt beide Stufen ab: Kartennummer-Erkennung (inkl. typischer OCR-Fehler) und Namensabgleich.
import { findMatches, extractCardId } from "../docs/js/match.js";
import { mockPriceFor } from "../docs/js/price-mock.js";
import fs from "node:fs";

const cards = JSON.parse(fs.readFileSync(new URL("../data/cards.normalized.json", import.meta.url)));

let failed = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: ${actual}${ok ? "" : ` (erwartet: ${expected})`}`);
  if (!ok) failed++;
}

// 1) Echter OCR-Text aus einem tatsaechlichen Testlauf (Karte OP01-001, tesseract.js)
const realOcrText = `£ ye
mm 5000 %
ar " ofiyour; Characters gain caf
- LEADER [A :
Roronoa Zoro rll
Supernovas/Straw Hat Crew oo01.001 um §`;

const top = findMatches(realOcrText, cards, 5)[0];
check("echter OCR-Text -> Karte", top?.card?.id, "OP01-001");
console.log(`     erkannt ueber: ${top?.how}, Score ${top?.score}`);

// 2) Kartennummer-Erkennung mit sauberem und mit verrauschtem Text
check("sauber 'OP01-001'", extractCardId("Roronoa Zoro OP01-001", cards), "OP01-001");
check("Punkt statt Bindestrich", extractCardId("blah OP01.001 blah", cards), "OP01-001");
check("P statt O verlesen", extractCardId("Supernovas oo01.001 um", cards), "OP01-001");
check("Starter-Deck-Nummer", extractCardId("ST01-013 Roronoa Zoro", cards), "ST01-013");
check("kein Treffer bei Unsinn", extractCardId("nur wirrer text ohne nummer", cards), null);

// 3) Namensabgleich ohne lesbare Nummer
const byName = findMatches("LEADER Roronoa Zoro Supernovas Straw Hat Crew", cards, 3)[0];
check("Namensabgleich findet Karte", byName?.card?.name, "Roronoa Zoro");
check("Namensabgleich meldet Methode", byName?.how, "name");

// 4) Preisfunktion liefert plausiblen Wert
const price = mockPriceFor(cards.find((c) => c.id === "OP01-001"));
check("Preis ist Zahl", typeof price.amount, "number");

console.log(failed === 0 ? "\nAlle Checks bestanden." : `\n${failed} Check(s) fehlgeschlagen.`);
process.exit(failed === 0 ? 0 : 1);
