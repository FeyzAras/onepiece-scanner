// Spielt echte Cardmarket-Preise in data/cards.normalized.json ein.
//
// Quelle: die von Cardmarket selbst taeglich veroeffentlichten Export-Dateien
// (angekuendigt 07/2025, ausdruecklich zur freien Nutzung in eigenen Anwendungen).
// Laden mit: node scripts/fetch-cardmarket.js
//
// ── Das Zuordnungsproblem ────────────────────────────────────────────────────
// Cardmarket fuehrt pro Kartennummer im Schnitt 4,2 Produkte, teils ueber 20:
// Originaldruck, Alt-Art, Nachdrucke in spaeteren Sets, Promos, Turnierpreise.
// Bei rund 80 % der Nummern liegt zwischen guenstigster und teuerster Version
// mindestens Faktor 5 - bei OP01-001 zwischen 1,87 EUR und 610 EUR.
// Einfach "irgendeinen" Preis zu nehmen waere also grob irrefuehrend.
//
// ── Wie hier zugeordnet wird ─────────────────────────────────────────────────
// Cardmarket liefert keine Editionsnamen, nur Nummern (idExpansion). Welches Set
// eine Edition ist, laesst sich aber aus den enthaltenen Kartennummern ableiten:
// Enthaelt eine Edition zu >=90 % Karten mit der Vorsilbe "OP01", ist es das OP01-Set.
// Pro Set wird die **zuerst angelegte** solche Edition als Originaldruck genommen.
//
// Innerhalb dieser Edition bleiben je Kartennummer meist ein oder zwei Produkte:
//   1 Produkt  -> eindeutig
//   2 Produkte -> normales Artwork und Alt-Art. Welches welches ist, sagt Cardmarket
//                 nicht (beide heissen identisch). Angenommen wird: die teurere ist
//                 die Alt-Art. Wo beide fast gleich teuer sind, ist die Wahl ohnehin
//                 folgenlos; wo sie weit auseinanderliegen, trifft die Annahme zu.
//   mehr       -> guenstigste als Normalversion, teuerste als Alt-Art, als unsicher markiert
//
// Jede Karte bekommt zusaetzlich `priceOptions`: alle Cardmarket-Versionen dieser
// Nummer mit Preis. Damit kann die App die Spanne anzeigen und der Nutzer umschalten,
// falls die Zuordnung danebenliegt.

const fs = require("fs");
const path = require("path");

const DATA = path.join(__dirname, "..", "data");
const NUMBER_RE = /\(([A-Z]{1,4}\d{0,2})-(\d{3})\)/;
const PURE_SHARE = 0.9; // ab diesem Anteil gilt eine Edition als eindeutig einem Set zugehoerig

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

/** Ordnet jeder Cardmarket-Edition das Set zu, aus dem ihre Karten stammen. */
function mapExpansionsToSets(products) {
  const perExpansion = new Map();
  for (const p of products) {
    const m = NUMBER_RE.exec(p.name);
    if (!m) continue;
    if (!perExpansion.has(p.idExpansion)) {
      perExpansion.set(p.idExpansion, { total: 0, sets: new Map(), firstAdded: p.dateAdded });
    }
    const e = perExpansion.get(p.idExpansion);
    e.total++;
    e.sets.set(m[1], (e.sets.get(m[1]) || 0) + 1);
    if (p.dateAdded < e.firstAdded) e.firstAdded = p.dateAdded;
  }

  // Pro Set die zuerst angelegte "reine" Edition = Originaldruck
  const mainExpansionOfSet = new Map();
  for (const [idExpansion, e] of perExpansion) {
    const [topSet, topCount] = [...e.sets.entries()].sort((a, b) => b[1] - a[1])[0];
    if (topCount / e.total < PURE_SHARE) continue; // gemischte Edition (Promos, Sammlungen)
    const current = mainExpansionOfSet.get(topSet);
    if (!current || e.firstAdded < current.firstAdded) {
      mainExpansionOfSet.set(topSet, { idExpansion, firstAdded: e.firstAdded, size: e.total });
    }
  }
  return mainExpansionOfSet;
}

function main() {
  const productFile = readJson("cm_products_18.json");
  const priceFile = readJson("cm_prices_18.json");
  const cards = readJson("cards.normalized.json");

  const priceByProduct = new Map(priceFile.priceGuides.map((p) => [p.idProduct, p]));
  const mainExpansionOfSet = mapExpansionsToSets(productFile.products);

  // Alle Produkte je Kartennummer sammeln, mit Preis und Edition
  const byNumber = new Map();
  let withoutNumber = 0;
  for (const p of productFile.products) {
    const m = NUMBER_RE.exec(p.name);
    if (!m) { withoutNumber++; continue; }
    const cardNumber = `${m[1]}-${m[2]}`;
    const price = pickPrice(priceByProduct.get(p.idProduct));
    if (!price) continue;
    if (!byNumber.has(cardNumber)) byNumber.set(cardNumber, []);
    byNumber.get(cardNumber).push({
      idProduct: p.idProduct,
      idExpansion: p.idExpansion,
      setPrefix: m[1],
      ...price,
    });
  }

  const asOf = (priceFile.createdAt || "").slice(0, 10);
  const stats = { eindeutig: 0, paar: 0, mehrdeutig: 0, ohneHauptedition: 0, ohnePreis: 0 };

  /** Waehlt fuer eine Kartennummer die Preise fuer Normalversion und Alt-Art. */
  function resolve(cardNumber) {
    const all = byNumber.get(cardNumber);
    if (!all || all.length === 0) return null;

    const setPrefix = all[0].setPrefix;
    const main = mainExpansionOfSet.get(setPrefix);
    let candidates = main ? all.filter((x) => x.idExpansion === main.idExpansion) : [];
    let confidence;

    if (candidates.length === 0) {
      // Keine Hauptedition gefunden (Promo, gemischte Edition): alles heranziehen
      candidates = all;
      confidence = "unsicher";
      stats.ohneHauptedition++;
    } else if (candidates.length === 1) {
      confidence = "eindeutig";
      stats.eindeutig++;
    } else if (candidates.length === 2) {
      confidence = "paar";
      stats.paar++;
    } else {
      confidence = "unsicher";
      stats.mehrdeutig++;
    }

    const sorted = [...candidates].sort((a, b) => a.amount - b.amount);
    const guenstigste = sorted[0];
    const teuerste = sorted[sorted.length - 1];

    return {
      normal: guenstigste,
      alt: teuerste,
      confidence,
      options: [...all].sort((a, b) => a.amount - b.amount),
    };
  }

  const resolvedCache = new Map();
  let matched = 0;

  for (const card of cards) {
    if (!resolvedCache.has(card.baseId)) resolvedCache.set(card.baseId, resolve(card.baseId));
    const resolved = resolvedCache.get(card.baseId);

    if (!resolved) {
      delete card.price;
      delete card.priceOptions;
      stats.ohnePreis++;
      continue;
    }

    const chosen = card.alt ? resolved.alt : resolved.normal;
    card.price = {
      amount: chosen.amount,
      currency: "EUR",
      basis: chosen.basis,
      source: "cardmarket",
      asOf,
      idProduct: chosen.idProduct,
      // eindeutig | paar | unsicher - wie sicher die Zuordnung zur Druckvariante ist
      confidence: resolved.confidence,
    };
    // Nur die Betraege, aufsteigend - die App zeigt damit die Spanne und laesst umschalten.
    // Bei nur einer Version waere die Liste redundant zum Preis selbst.
    if (resolved.options.length > 1) {
      card.priceOptions = resolved.options.map((o) => o.amount);
    } else {
      delete card.priceOptions;
    }
    matched++;
  }

  fs.writeFileSync(path.join(DATA, "cards.normalized.json"), JSON.stringify(cards, null, 2), "utf8");

  const pct = ((matched / cards.length) * 100).toFixed(1);
  console.log(`Cardmarket-Stand:        ${asOf}`);
  console.log(`Produkte gelesen:        ${productFile.products.length} (ohne Kartennummer: ${withoutNumber})`);
  console.log(`Editionen -> Set erkannt: ${mainExpansionOfSet.size}`);
  console.log(`Karten mit Preis:        ${matched} von ${cards.length} (${pct} %)`);
  console.log(`  davon Zuordnung eindeutig : ${stats.eindeutig}`);
  console.log(`  normal + Alt-Art (Paar)   : ${stats.paar}`);
  console.log(`  unsicher                  : ${stats.mehrdeutig + stats.ohneHauptedition}`);
  console.log(`  ohne Preis                : ${stats.ohnePreis}`);
}

main();
