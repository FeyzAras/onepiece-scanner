// Baut public/data/cards.json aus dem gepflegten npm-Paket "one-piece-card-game-json"
// (https://www.npmjs.com/package/one-piece-card-game-json, Quelle: github.com/bountycards/onePieceCardGameParser).
// Deckt (Stand Installation) OP01-OP17, EB01-04, Promos und ST01-36 ab - deutlich vollstaendiger
// als die zuvor genutzte statische GitHub-Datei (nur bis OP06). Englische Version (en/cards.json).

const fs = require("fs");
const path = require("path");
const raw = require("one-piece-card-game-json/en/cards.json");
const rawJp = require("one-piece-card-game-json/jp/cards.json");

/// [id]: die vergebene ID (siehe vergibIds). Ohne Angabe gilt das alte Schema -
/// erste Normalversion = Nummer, Alt-Art = Nummer-ALT. So arbeitet weiterhin der
/// japanische Zusatzkatalog.
function normalize(card, id) {
  const nummer = card.card_number || "";
  const kartenId = id || (card.is_alternate_art ? `${nummer}-ALT` : nummer);
  const costLife = card.cost && card.cost !== "-" ? card.cost : (card.life && card.life !== "-" ? card.life : null);
  const colors = Array.isArray(card.colors) ? card.colors.filter(Boolean) : [];
  const produkt = parseProduct(card.card_sets);
  return {
    id: kartenId,
    baseId: nummer,
    // Jedes Motiv ausser der Normalversion. Nicht nur Bandais "is_alternate_art":
    // Ein paar Promo-Nachdrucke tragen dort "false", haben aber ein eigenes Bild.
    alt: kartenId !== nummer,
    name: card.card_name || "",
    rarity: card.rarity || "",
    cardType: card.card_type || "",
    // Erste Farbe bleibt fuer die Web-Version erhalten. Die vollstaendige Liste steht in
    // `colors`: 154 Leader sind zweifarbig (z.B. OP01-002 Rot/Gruen). Frueher ging die
    // zweite Farbe hier verloren - beim Deckbau haette ein rot-gruener Leader dann nur
    // rote Karten zugelassen.
    color: colors[0] || "",
    colors,
    power: card.power && card.power !== "-" ? Number(card.power) : null,
    costLife: costLife !== null ? Number(costLife) : null,
    counter: card.counter && card.counter !== "-" ? Number(card.counter) || null : null,
    // Typen wie "East Blue" oder "Straw Hat Crew" - manche Leader erlauben im Deck nur
    // Karten eines Typs (z.B. P-117 Nami: nur {East Blue}).
    types: Array.isArray(card.types) ? card.types.filter(Boolean) : [],
    effect: card.effects || "",
    img: card.image_url || null,
    // Aus welchem Produkt dieses Motiv stammt, z.B. "The Best" [PRB01] oder "Romance Dawn"
    // [OP01]. Zeigt die App bei den Motiven an; die Preiszuordnung sucht damit die
    // passende Cardmarket-Ausgabe.
    ...(produkt.name ? { produkt: produkt.name } : {}),
    ...(produkt.codes.length ? { produktSets: produkt.codes } : {}),
  };
}

/// Bisher ausgelieferte IDs, nach Bildadresse. Quelle ist der versionierte Katalog der
/// App (android_app/assets/cards.json) - er liegt auch in der GitHub Action vor.
function idRegister(pfad) {
  try {
    const liste = JSON.parse(fs.readFileSync(pfad, "utf8").replace(/^﻿/, ""));
    return new Map(liste.filter((c) => c.img && !c.jpOnly).map((c) => [c.img, c.id]));
  } catch {
    return new Map();
  }
}

/// Vergibt die IDs aller Motive. Gibt eine Map Datensatz -> ID zurueck; doppelte Bilder
/// fehlen darin.
///
/// Warum so umstaendlich: Gespeicherte Sammlungen verweisen auf diese IDs. Eine ID darf
/// deshalb nie ihre Bedeutung wechseln. Frueher hiess die erste Alt-Art in der
/// Reihenfolge der Quelle "-ALT", alle weiteren fielen weg - bei 1.083 Nummern ist
/// diese erste nicht das Motiv _p1, bei 469 stammt sie nicht einmal aus dem eigenen Set.
/// Ein Schema nach Bildnummer haette also gespeicherte Karten still umgedeutet.
///
///  1. Ein Bild, das schon einmal ausgeliefert wurde, behaelt seine ID - fuer immer.
///  2. Sonst wie bisher: erste Normalversion -> Nummer, erste Alt-Art -> Nummer-ALT,
///     jedes weitere Motiv -> Nummer-ALT2, -ALT3, ... (naechste freie Zahl).
function vergibIds(records, register = new Map()) {
  const proNummer = new Map();
  for (const r of records) {
    const n = r.card_number;
    if (!n) continue;
    if (!proNummer.has(n)) proNummer.set(n, []);
    proNummer.get(n).push(r);
  }

  const ergebnis = new Map();
  for (const [nummer, liste] of proNummer) {
    const vergeben = new Set();
    const bilder = new Set();
    const offen = [];
    for (const r of liste) {
      const bild = r.image_url || "";
      if (bild && bilder.has(bild)) continue; // derselbe Druck doppelt in der Quelle
      if (bild) bilder.add(bild);
      const bekannt = bild ? register.get(bild) : undefined;
      if (bekannt && (bekannt === nummer || bekannt.startsWith(`${nummer}-ALT`)) && !vergeben.has(bekannt)) {
        ergebnis.set(r, bekannt);
        vergeben.add(bekannt);
      } else {
        offen.push(r);
      }
    }
    for (const r of offen) {
      let id;
      if (!r.is_alternate_art && !vergeben.has(nummer)) id = nummer;
      else if (r.is_alternate_art && !vergeben.has(`${nummer}-ALT`)) id = `${nummer}-ALT`;
      else {
        let k = 2;
        while (vergeben.has(`${nummer}-ALT${k}`)) k++;
        id = `${nummer}-ALT${k}`;
      }
      ergebnis.set(r, id);
      vergeben.add(id);
    }
  }
  return ergebnis;
}

/// Setcode einer Kartennummer: "OP01-001" -> "OP01", "P-001" -> "P".
function setCodeOf(cardNumber) {
  return String(cardNumber || "").split("-")[0];
}

/// "-ROMANCE DAWN- [OP-01]" -> { name: "Romance Dawn", codes: ["OP01"] }
/// "-ADVENTURE ON KAMI'S ISLAND- [OP-15-EB04]" -> { codes: ["OP15", "EB04"] }
/// "BOOSTER PACK -THE WORLD’S STRONGEST WARRIORS- [OP-17]" -> "The World’s Strongest Warriors"
/// "STARTER DECK -RED Monkey.D.Luffy- [ST-31]" -> "Red Monkey.D.Luffy"
function parseProduct(label) {
  const text = String(label || "").trim();
  const klammer = text.match(/\[([^\]]+)\]\s*$/);
  const codes = [];
  if (klammer) {
    // "OP-15-EB04" -> OP15, EB04 ; "PRB-01" -> PRB01 ; "ST-01" -> ST01
    const teile = klammer[1].toUpperCase().match(/[A-Z]+-?\d+/g) || [];
    for (const t of teile) codes.push(t.replace("-", ""));
  }
  let name = (klammer ? text.slice(0, klammer.index) : text).trim();
  // Seit OP-17 bzw. ST-31 setzt Bandai die Produktart davor - die steckt schon im Code
  name = name.replace(/^(included in|booster pack|starter deck)\s+/i, "");
  // Bindestriche als Klammern: "-ROMANCE DAWN-", "Premium Card Collection -25th Edition-".
  // Nur an Wortgrenzen - "OP14-EB04" bleibt stehen.
  name = name.replace(/(^|\s)-+\s*/g, "$1").replace(/\s*-+(\s|$)/g, "$1").replace(/\s+/g, " ").trim();
  return { name: schreibweise(name), codes };
}

/// Englische Titelschreibweise, Wort fuer Wort: Nur ganz gross geschriebene Woerter
/// werden angepasst ("RED" -> "Red", "PURPLE/BLACK" -> "Purple/Black"); gemischt
/// geschriebene wie "Monkey.D.Luffy" oder Kuerzel mit Ziffern ("3D2Y") bleiben, wie sie
/// sind - ausser "vol.2", das wird "Vol.2". Kleine Fuellwoerter bleiben klein, ausser am
/// Anfang.
/// "500 YEARS IN THE FUTURE" -> "500 Years in the Future"
function schreibweise(text) {
  const klein = new Set(["a", "an", "and", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"]);
  return text
    .split(" ")
    .map((wort, i) =>
      wort
        .split("/")
        .map((teil, j) => {
          if (/^[a-z]+\.?\d/.test(teil)) return teil[0].toUpperCase() + teil.slice(1);
          const buchstaben = teil.replace(/[^\p{L}]/gu, "");
          if (buchstaben.length < 2 || /\d/.test(teil) || buchstaben !== buchstaben.toUpperCase()) return teil;
          const k = teil.toLowerCase();
          if ((i > 0 || j > 0) && klein.has(k)) return k;
          return k.replace(/\p{L}/u, (b) => b.toUpperCase());
        })
        .join("/"),
    )
    .join(" ");
}

/// Set-Namen aus den Produktangaben der Karten.
///
/// Ein einfacher Mehrheitsentscheid waere falsch: Die EB04-Karten stecken in zwei
/// verschiedenen Produkten (OP-14 und OP-15), und Nachdrucke tauchen in fremden Produkten
/// auf. Deshalb zaehlt nur ein Produkt, dessen Code mit dem Set BEGINNT. Gibt es keins,
/// bleibt der Name leer und die Produkte werden als "enthalten in" genannt.
function buildSets(cards) {
  const proSet = new Map();
  for (const card of cards) {
    const code = setCodeOf(card.card_number);
    if (!code) continue;
    if (!proSet.has(code)) proSet.set(code, new Map());
    const label = String(card.card_sets || "").trim();
    if (label) proSet.get(code).set(label, (proSet.get(code).get(label) || 0) + 1);
  }

  const sets = [];
  for (const [code, labels] of [...proSet.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const produkte = [...labels.entries()]
      .map(([label, anzahl]) => ({ ...parseProduct(label), anzahl }))
      .sort((a, b) => b.anzahl - a.anzahl);

    if (code === "P") {
      sets.push({ code, name: "Promokarten" });
      continue;
    }

    const eigenes = produkte.find((p) => p.codes[0] === code && p.name);
    if (eigenes) {
      sets.push({ code, name: eigenes.name });
      continue;
    }

    const enthalten = produkte.filter((p) => p.codes.includes(code) && p.name).map((p) => p.name);
    sets.push(enthalten.length ? { code, name: null, enthalten } : { code, name: null });
  }
  return sets;
}

/// Nimmt Karten auf, die es nur im japanischen Katalog gibt.
///
/// Hintergrund: Der japanische Katalog enthaelt dieselben lateinischen Namen und englischen
/// Effekttexte wie der englische - nur die Bildadressen unterscheiden sich (japanisches
/// Artwork). Japanische Karten tragen dieselbe Kartennummer in lateinischer Schrift und
/// werden deshalb ohnehin erkannt. Was fehlt, sind die Karten, die nie auf Englisch
/// erschienen sind: ohne sie findet die App beim Scannen schlicht keinen Eintrag.
function japanOnly(vorhandeneIds) {
  const liste = Array.isArray(rawJp) ? rawJp : rawJp.all || [];
  const ergaenzt = [];
  for (const card of liste) {
    // Bewusst das alte Schema (Nummer bzw. Nummer-ALT): So entstehen genau dieselben
    // IDs wie bisher, und gespeicherte japanische Karten bleiben auffindbar.
    const entry = normalize(card);
    if (!entry.id || !entry.name || vorhandeneIds.has(entry.id)) continue;
    entry.jpOnly = true; // in der App als "nur japanisch erschienen" kenntlich
    ergaenzt.push(entry);
  }

  // Mehrere japanische Motive bekamen frueher dieselbe ID (z.B. OP01-114-ALT dreimal).
  // Die App fand davon immer nur den LETZTEN Eintrag - der behaelt deshalb die ID, damit
  // gespeicherte Karten dasselbe Bild zeigen wie bisher. Die frueheren waren nie
  // erreichbar und bekommen jetzt eine eigene.
  const nachId = new Map();
  for (const e of ergaenzt) {
    if (!nachId.has(e.id)) nachId.set(e.id, []);
    nachId.get(e.id).push(e);
  }
  const belegt = new Set([...vorhandeneIds, ...nachId.keys()]);
  for (const liste of nachId.values()) {
    for (const e of liste.slice(0, -1)) {
      let k = 2;
      while (belegt.has(`${e.baseId}-ALT${k}`)) k++;
      e.id = `${e.baseId}-ALT${k}`;
      e.alt = true;
      belegt.add(e.id);
    }
  }
  return ergaenzt;
}

/// Preise und Bild-Fingerabdruecke stammen aus eigenen Schritten (import-cardmarket-prices.js,
/// build-image-hashes.js). Beim Neuaufbau des Katalogs werden sie uebernommen, damit ein
/// erneuter Lauf diese Arbeit nicht zunichtemacht.
function carryOver(outPath) {
  if (!fs.existsSync(outPath)) return new Map();
  try {
    const previous = JSON.parse(fs.readFileSync(outPath, "utf8").replace(/^﻿/, ""));
    return new Map(previous.map((c) => [c.id, { price: c.price, imgHash: c.imgHash }]));
  } catch {
    return new Map();
  }
}

function main() {
  const dataDir = path.join(__dirname, "..", "data");
  // data/ ist bewusst nicht versioniert (Zwischendateien), fehlt also im frischen Checkout
  fs.mkdirSync(dataDir, { recursive: true });
  const outPath = path.join(dataDir, "cards.normalized.json");
  const previous = carryOver(outPath);

  const list = Array.isArray(raw) ? raw : raw.all || [];
  // Die IDs richten sich nach dem, was die App schon kennt - siehe vergibIds
  const registerPfad = path.join(__dirname, "..", "android_app", "assets", "cards.json");
  const register = idRegister(registerPfad);
  const ids = vergibIds(list, register);

  const seen = new Set();
  const normalized = [];
  let keptPrices = 0;
  let keptHashes = 0;
  for (const card of list) {
    const id = ids.get(card);
    if (!id) continue; // doppeltes Bild
    const entry = normalize(card, id);
    if (!entry.id || !entry.name) continue;
    if (seen.has(entry.id)) continue;
    seen.add(entry.id);

    const old = previous.get(entry.id);
    if (old?.price) {
      entry.price = old.price;
      keptPrices++;
    }
    if (old?.imgHash) {
      entry.imgHash = old.imgHash;
      keptHashes++;
    }
    normalized.push(entry);
  }

  // Karten ergaenzen, die nur auf Japanisch erschienen sind
  const motiveJeNummer = new Map();
  for (const e of normalized) motiveJeNummer.set(e.baseId, (motiveJeNummer.get(e.baseId) || 0) + 1);
  const nurJp = japanOnly(seen);
  for (const entry of nurJp) {
    const old = previous.get(entry.id);
    if (old?.price) entry.price = old.price;
    if (old?.imgHash) entry.imgHash = old.imgHash;
    normalized.push(entry);
  }

  // Keine ausgelieferte ID darf verschwinden oder ihr Bild wechseln
  const neuNachId = new Map(normalized.map((e) => [e.id, e]));
  let verschwunden = 0;
  for (const [bild, id] of register) {
    const neu = neuNachId.get(id);
    if (!neu) verschwunden++;
    else if (neu.img !== bild) throw new Error(`ID ${id} wuerde ihr Bild wechseln: ${bild} -> ${neu.img}`);
  }

  fs.writeFileSync(outPath, JSON.stringify(normalized, null, 2), "utf8");
  console.log(`OK: ${normalized.length} Karten aus ${list.length} Rohdatensaetzen -> ${outPath}`);
  console.log(`    davon nur auf Japanisch erschienen: ${nurJp.length}`);
  console.log(`    IDs aus dem App-Katalog uebernommen: ${register.size - verschwunden} von ${register.size}` +
    (verschwunden ? ` (${verschwunden} nicht mehr in der Quelle)` : ""));
  console.log(`    Motive je Nummer: ${[...motiveJeNummer.values()].filter((n) => n > 1).length} Nummern mit mehreren`);
  console.log(`    uebernommen: ${keptPrices} Preise, ${keptHashes} Bild-Fingerabdruecke`);
  console.log(`    zweifarbig: ${normalized.filter((c) => c.colors.length > 1).length}`);

  // Set-Namen fuer die Uebersicht in der App
  const sets = buildSets(list);
  const setsPath = path.join(dataDir, "sets.json");
  fs.writeFileSync(setsPath, JSON.stringify(sets, null, 2), "utf8");
  const ohneName = sets.filter((s) => !s.name).map((s) => s.code);
  console.log(`OK: ${sets.length} Sets -> ${setsPath}` + (ohneName.length ? ` (ohne eigenen Namen: ${ohneName.join(", ")})` : ""));
}

module.exports = { normalize, parseProduct, schreibweise, buildSets, setCodeOf, vergibIds, idRegister };

// Nur beim direkten Aufruf bauen - so lassen sich die Funktionen oben testen
if (require.main === module) main();
