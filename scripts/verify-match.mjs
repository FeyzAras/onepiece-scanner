// Sanity-Checks fuer die Erkennungslogik und die eingespielten Cardmarket-Preise.
// Ausfuehren: node scripts/verify-match.mjs
import { matchCard, extractCardId } from "../docs/js/match.js";
import fs from "node:fs";

const cards = JSON.parse(fs.readFileSync(new URL("../data/cards.normalized.json", import.meta.url)));

let failed = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  console.log(`${ok ? "OK  " : "FAIL"} ${label}: ${actual}${ok ? "" : ` (erwartet: ${expected})`}`);
  if (!ok) failed++;
}
function checkTrue(label, condition, info = "") {
  console.log(`${condition ? "OK  " : "FAIL"} ${label}${info ? `: ${info}` : ""}`);
  if (!condition) failed++;
}

console.log("— Kartennummer erkennen —");
check("sauber 'OP01-001'", extractCardId("Roronoa Zoro OP01-001", cards), "OP01-001");
check("Punkt statt Bindestrich", extractCardId("blah OP01.001 blah", cards), "OP01-001");
check("P statt O verlesen", extractCardId("Supernovas oo01.001 um", cards), "OP01-001");
check("Starter-Deck-Nummer", extractCardId("ST01-013 Roronoa Zoro", cards), "ST01-013");
check("kein Treffer bei Unsinn", extractCardId("nur wirrer text ohne nummer", cards), null);

const realOcrText = `£ ye
mm 5000 %
- LEADER [A :
Roronoa Zoro rll
Supernovas/Straw Hat Crew oo01.001 um §`;
const real = matchCard(realOcrText, cards);
check("echter OCR-Text -> Karte", real.card?.id, "OP01-001");
check("Name zusaetzlich bestaetigt", real.how, "number+name");

console.log("\n— Ohne Nummer wird nichts uebernommen —");
const nameOnly = matchCard("LEADER Roronoa Zoro Supernovas Straw Hat Crew", cards);
checkTrue("Name allein ergibt keinen Treffer", !nameOnly.card);
check("stattdessen Hinweis fuer den Nutzer", nameOnly.nameOnlyHint, "Roronoa Zoro");

const foreignName = matchCard("Snake Dance gib Portgas.D.Ace und Gina Kraft", cards);
checkTrue("fremder Name im Effekttext loest nichts aus", !foreignName.card);

const garbage = matchCard("zzz qqq wirrer text", cards);
checkTrue("wirrer Text: weder Treffer noch Hinweis", !garbage.card && !garbage.nameOnlyHint);

console.log("\n— Cardmarket-Preise —");
const withPrice = cards.filter((c) => c.price);
checkTrue("ueber 95% der Karten haben einen Preis",
  withPrice.length / cards.length > 0.95,
  `${withPrice.length} von ${cards.length}`);

const zoro = cards.find((c) => c.id === "OP01-001");
checkTrue("Beispielkarte hat echten Cardmarket-Preis",
  zoro?.price?.source === "cardmarket" && zoro.price.amount > 0,
  `${zoro?.price?.amount} ${zoro?.price?.currency} (${zoro?.price?.basis}, Stand ${zoro?.price?.asOf})`);

checkTrue("alle Preise sind positive Zahlen",
  withPrice.every((c) => typeof c.price.amount === "number" && c.price.amount > 0));

console.log(failed === 0 ? "\nAlle Checks bestanden." : `\n${failed} Check(s) fehlgeschlagen.`);
process.exit(failed === 0 ? 0 : 1);
