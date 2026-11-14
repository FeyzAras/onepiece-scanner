// Baut den Preisverlauf aus der Git-Historie von docs/data/prices.json.
//
// Die Preisdatei wird taeglich ueberschrieben - aber jeder fruehere Stand steckt in der
// Git-Historie. Dieses Skript holt alle Staende zurueck und schreibt je Set eine Datei:
//
//   docs/data/history/<SET>.json  = { dates: [...], prices: { "OP01-001": [187, 185, null, ...] } }
//   docs/data/history/index.json  = Ueberblick (Zeitraum, Sets, Kartenzahl)
//
// Preise in Cent als ganze Zahlen (kuerzer, keine Rundungsreste), an `dates` ausgerichtet.
// null = an diesem Tag kein Preis.
//
// Je Set eine eigene Datei, weil die App nie alles braucht: Die Kartendetails laden nur
// das Set dieser Karte, der Wertverlauf nur die Sets, aus denen die Sammlung besteht.
//
// Ausfuehren nach build-price-file.js, damit der heutige Stand mit drin ist.

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const PRICE_FILE = "docs/data/prices.json";
const OUT_DIR = "docs/data/history";

/// "OP01-001-ALT" -> "OP01", "P-001" -> "P"
function setCodeOf(cardId) {
  return String(cardId || "").split("-")[0];
}

/// Baut aus einzelnen Tagesstaenden den Verlauf je Set.
///
/// [snapshots] in der Reihenfolge, in der sie entstanden sind. Gibt es mehrere Staende
/// fuer dasselbe Datum (asOf), gewinnt der letzte - am 06.10.2026 wurde dreimal committet.
function buildHistory(snapshots) {
  const proTag = new Map();
  for (const s of snapshots) {
    if (!s || !s.asOf || !s.prices || typeof s.prices !== "object") continue;
    proTag.set(s.asOf, s.prices);
  }

  const dates = [...proTag.keys()].sort();
  const sets = {};
  dates.forEach((datum, i) => {
    for (const [cardId, betrag] of Object.entries(proTag.get(datum))) {
      if (typeof betrag !== "number" || !(betrag > 0)) continue;
      const code = setCodeOf(cardId);
      if (!code) continue;
      if (!sets[code]) sets[code] = {};
      if (!sets[code][cardId]) sets[code][cardId] = new Array(dates.length).fill(null);
      sets[code][cardId][i] = Math.round(betrag * 100);
    }
  });

  return { dates, sets };
}

/// Alle Staende einer Datei aus der Git-Historie, aeltester zuerst.
function readSnapshotsFromGit(repoDir, relPath) {
  const git = (...args) =>
    execFileSync("git", args, { cwd: repoDir, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });

  // Flache Kopie (Standard bei GitHub Actions) kennt nur den letzten Commit. Dann wuerde der
  // Verlauf auf einen Tag zusammenschrumpfen und den vorhandenen ueberschreiben.
  if (git("rev-parse", "--is-shallow-repository").trim() === "true") {
    throw new Error("Flache Git-Kopie - der Verlauf waere unvollstaendig. Im Workflow fetch-depth: 0 setzen.");
  }

  const hashes = git("log", "--format=%H", "--reverse", "--", relPath).split("\n").filter(Boolean);
  const snapshots = [];
  for (const hash of hashes) {
    try {
      const inhalt = git("show", `${hash}:${relPath.replace(/\\/g, "/")}`);
      const daten = JSON.parse(inhalt.replace(/^﻿/, ""));
      snapshots.push({ asOf: daten.asOf, prices: daten.prices, commit: hash });
    } catch {
      // Ein unlesbarer Stand darf den Rest nicht verhindern
    }
  }
  return snapshots;
}

function readWorkingSnapshot(file) {
  if (!fs.existsSync(file)) return null;
  try {
    const daten = JSON.parse(fs.readFileSync(file, "utf8").replace(/^﻿/, ""));
    return { asOf: daten.asOf, prices: daten.prices };
  } catch {
    return null;
  }
}

/// Schreibt die Set-Dateien. Weigert sich, wenn der neue Verlauf KUERZER waere als der
/// vorhandene - das ist fast immer ein Fehler beim Lesen, kein echter Datenstand.
function writeHistory(history, outDir, { erzwingen = false } = {}) {
  const indexPfad = path.join(outDir, "index.json");
  if (!erzwingen && fs.existsSync(indexPfad)) {
    try {
      const alt = JSON.parse(fs.readFileSync(indexPfad, "utf8"));
      if (typeof alt.days === "number" && history.dates.length < alt.days) {
        throw new Error(
          `Neuer Verlauf hat ${history.dates.length} Tage, vorhandener ${alt.days}. ` +
            "Abbruch, damit nichts verlorengeht. Mit --erzwingen ueberschreiben, falls gewollt."
        );
      }
    } catch (e) {
      if (e.message.startsWith("Neuer Verlauf")) throw e;
    }
  }

  fs.mkdirSync(outDir, { recursive: true });
  const index = {
    generated: new Date().toISOString().slice(0, 10),
    first: history.dates[0] || null,
    last: history.dates[history.dates.length - 1] || null,
    days: history.dates.length,
    sets: {},
  };

  const codes = Object.keys(history.sets).sort();
  for (const code of codes) {
    const datei = path.join(outDir, `${code}.json`);
    const inhalt = { dates: history.dates, prices: history.sets[code] };
    fs.writeFileSync(datei, JSON.stringify(inhalt), "utf8");
    index.sets[code] = { cards: Object.keys(history.sets[code]).length, bytes: fs.statSync(datei).size };
  }

  // Set-Dateien entfernen, die es nicht mehr gibt
  for (const f of fs.readdirSync(outDir)) {
    if (f === "index.json" || !f.endsWith(".json")) continue;
    if (!history.sets[f.replace(/\.json$/, "")]) fs.unlinkSync(path.join(outDir, f));
  }

  fs.writeFileSync(indexPfad, JSON.stringify(index, null, 2), "utf8");
  return index;
}

function main() {
  const root = path.join(__dirname, "..");
  const erzwingen = process.argv.includes("--erzwingen");

  const snapshots = readSnapshotsFromGit(root, PRICE_FILE);
  const heute = readWorkingSnapshot(path.join(root, PRICE_FILE));
  if (heute) snapshots.push(heute);

  const history = buildHistory(snapshots);
  if (history.dates.length === 0) {
    console.error("Keine Preisstaende gefunden - nichts geschrieben.");
    process.exit(1);
  }

  const index = writeHistory(history, path.join(root, OUT_DIR), { erzwingen });
  const kb = Object.values(index.sets).reduce((s, x) => s + x.bytes, 0) / 1024;
  console.log(`OK: ${snapshots.length} Staende gelesen, ${index.days} Tage (${index.first} bis ${index.last})`);
  console.log(`    ${Object.keys(index.sets).length} Sets, zusammen ${kb.toFixed(0)} KB -> ${OUT_DIR}/`);
}

module.exports = { buildHistory, readSnapshotsFromGit, writeHistory, setCodeOf };

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error(`FEHLER: ${e.message}`);
    process.exit(1);
  }
}
