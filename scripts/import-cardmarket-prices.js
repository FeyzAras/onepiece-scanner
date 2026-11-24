// Spielt echte Cardmarket-Preise in data/cards.normalized.json ein und schreibt
// data/versions.json - alle Cardmarket-Versionen je Kartennummer, mit Ausgabe.
//
// Quelle: die von Cardmarket selbst taeglich veroeffentlichten Export-Dateien
// (angekuendigt 07/2025, ausdruecklich zur freien Nutzung in eigenen Anwendungen).
// Laden mit: node scripts/fetch-cardmarket.js
//
// ── Das Zuordnungsproblem ────────────────────────────────────────────────────
// Cardmarket fuehrt pro Kartennummer im Schnitt 4,2 Produkte, teils ueber 20:
// Originaldruck, Alt-Art, Nachdrucke in spaeteren Sets, Promos, Turnierpreise, dazu
// asiatische und nicht-englische Auflagen. Bei rund 80 % der Nummern liegt zwischen
// guenstigster und teuerster Version mindestens Faktor 5 - bei OP01-001 zwischen
// 1,96 EUR und 620 EUR. Einfach "irgendeinen" Preis zu nehmen waere grob irrefuehrend.
//
// Wie zugeordnet wird, steht in cardmarket-zuordnung.js. Kurz: Jedes Bandai-Motiv
// nennt sein Produkt; darueber wird die Cardmarket-Ausgabe gesucht, und innerhalb der
// Ausgabe nach Preis verteilt. Jede Karte bekommt
//   price         - die automatisch zugeordnete Version, mit "confidence"
//   priceOptions  - alle Preise dieser Nummer aufsteigend (nur noch fuer App-Versionen
//                   bis 0.12, die die Wahl als Listenplatz speichern)
// und data/versions.json die vollstaendige Liste zum Auswaehlen in der App.

const fs = require("fs");
const path = require("path");
const Z = require("./cardmarket-zuordnung");

const DATA = path.join(__dirname, "..", "data");

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.join(DATA, file), "utf8").replace(/^﻿/, ""));
}

/** Bester verfuegbarer Preiswert eines Produkts, mit Angabe worauf er beruht. */
function pickPrice(entry) {
  if (!entry) return null;
  for (const basis of ["trend", "avg", "avg7", "avg30", "low"]) {
    const value = entry[basis];
    if (typeof value === "number" && value > 0) {
      return { amount: Math.round(value * 100) / 100, basis };
    }
  }
  return null;
}

/// Eine Version fuer die App, so knapp wie moeglich - die Datei wird taeglich geladen:
/// [idProduct, idExpansion, Preis in Cent, [Motive]?]
/// Motive = Plaetze der Motive, deren automatische Version das ist (0 Normal, 1 -ALT,
/// k -ALTk). Meist eins, bei einem Nachdruck auch zwei. Fehlt, wenn die Version keinem
/// Motiv zugeordnet ist - die gibt es nur zum Auswaehlen.
function versionsEintrag(p, motiveJeProdukt) {
  const e = [p.idProduct, p.idExpansion, Math.round(p.amount * 100)];
  const motive = motiveJeProdukt.get(p.idProduct);
  if (motive && motive.length) e.push([...motive].sort((a, b) => a - b));
  return e;
}

function main() {
  const productFile = readJson("cm_products_18.json");
  const priceFile = readJson("cm_prices_18.json");
  const nonsinglesDatei = path.join(DATA, "cm_nonsingles_18.json");
  const nonsingles = fs.existsSync(nonsinglesDatei) ? readJson("cm_nonsingles_18.json").products : [];
  if (!nonsingles.length) console.warn("Hinweis: cm_nonsingles_18.json fehlt - Ausgaben bleiben ohne Namen.");
  const cards = readJson("cards.normalized.json");

  const priceByProduct = new Map(priceFile.priceGuides.map((p) => [p.idProduct, p]));
  const ausgaben = Z.ausgabenBenennen(productFile.products, nonsingles);
  const ctx = { ausgaben, haupt: Z.hauptAusgaben(productFile.products, ausgaben) };

  // Alle Produkte je Kartennummer, mit Preis und Ausgabe
  const byNumber = new Map();
  let withoutNumber = 0;
  for (const p of productFile.products) {
    const m = Z.NUMMER_RE.exec(p.name);
    if (!m) { withoutNumber++; continue; }
    const price = pickPrice(priceByProduct.get(p.idProduct));
    if (!price) continue;
    const nummer = `${m[1]}-${m[2]}`;
    if (!byNumber.has(nummer)) byNumber.set(nummer, []);
    byNumber.get(nummer).push({ idProduct: p.idProduct, idExpansion: p.idExpansion, ...price });
  }

  const motiveJeNummer = new Map();
  for (const card of cards) {
    if (!motiveJeNummer.has(card.baseId)) motiveJeNummer.set(card.baseId, []);
    motiveJeNummer.get(card.baseId).push(card);
  }

  const asOf = (priceFile.createdAt || "").slice(0, 10);
  const stats = { eindeutig: 0, paar: 0, unsicher: 0, ohnePreis: 0 };
  const versionen = {};
  const benutzt = new Set();

  for (const [nummer, motive] of motiveJeNummer) {
    const produkte = byNumber.get(nummer) || [];
    const { standard } = produkte.length ? Z.ordneZu(nummer, motive, produkte, ctx) : { standard: new Map() };
    const optionen = [...produkte].sort((a, b) => a.amount - b.amount).map((p) => p.amount);

    for (const card of motive) {
      const s = standard.get(card.id);
      if (!s) {
        delete card.price;
        stats.ohnePreis++;
      } else {
        card.price = {
          amount: s.produkt.amount,
          currency: "EUR",
          basis: s.produkt.basis,
          source: "cardmarket",
          asOf,
          idProduct: s.produkt.idProduct,
          // eindeutig | paar | unsicher - wie sicher die Zuordnung zur Druckvariante ist
          confidence: s.sicherheit,
        };
        stats[s.sicherheit]++;
      }
      if (optionen.length > 1) card.priceOptions = optionen;
      else delete card.priceOptions;
    }

    // Eine Auswahl braucht es nur, wenn es etwas zu waehlen gibt
    if (produkte.length > 1 || (produkte.length && motive.length > 1)) {
      const motiveJeProdukt = new Map();
      for (const [id, s] of standard) {
        const p = s.produkt.idProduct;
        if (!motiveJeProdukt.has(p)) motiveJeProdukt.set(p, []);
        motiveJeProdukt.get(p).push(Z.motivIndex(id, nummer));
      }
      versionen[nummer] = [...produkte]
        .sort((a, b) => a.amount - b.amount || a.idProduct - b.idProduct)
        .map((p) => {
          benutzt.add(p.idExpansion);
          return versionsEintrag(p, motiveJeProdukt);
        });
    }
  }

  fs.writeFileSync(path.join(DATA, "cards.normalized.json"), JSON.stringify(cards, null, 2), "utf8");

  const ausgabenNamen = {};
  for (const id of [...benutzt].sort((a, b) => a - b)) ausgabenNamen[id] = ausgaben.get(id)?.label || `Ausgabe ${id}`;
  fs.writeFileSync(
    path.join(DATA, "versions.json"),
    JSON.stringify({ asOf, ausgaben: ausgabenNamen, versionen }),
    "utf8",
  );

  const matched = cards.length - stats.ohnePreis;
  const pct = ((matched / cards.length) * 100).toFixed(1);
  const allgemein = [...ausgaben.values()].filter((a) => a.allgemein).length;
  console.log(`Cardmarket-Stand:        ${asOf}`);
  console.log(`Produkte gelesen:        ${productFile.products.length} (ohne Kartennummer: ${withoutNumber})`);
  console.log(`Ausgaben benannt:        ${ausgaben.size - allgemein} von ${ausgaben.size} (Rest: Promo-Sammlungen)`);
  console.log(`Hauptausgaben je Set:    ${ctx.haupt.size}`);
  console.log(`Karten mit Preis:        ${matched} von ${cards.length} (${pct} %)`);
  console.log(`  davon Zuordnung eindeutig : ${stats.eindeutig}`);
  console.log(`  normal + Alt-Art (Paar)   : ${stats.paar}`);
  console.log(`  unsicher                  : ${stats.unsicher}`);
  console.log(`  ohne Preis                : ${stats.ohnePreis}`);
  console.log(`Versionslisten:          ${Object.keys(versionen).length} Nummern, ${Object.values(versionen).reduce((s, v) => s + v.length, 0)} Versionen`);
}

module.exports = { pickPrice, versionsEintrag };

if (require.main === module) main();
