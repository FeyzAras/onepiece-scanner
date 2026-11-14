// Tests fuer den Preisverlauf und die Set-Namen.
// Ausfuehren: npm run test:data   (oder: node --test "scripts/*.test.js")
//
// Der wichtigste Test ist der mit dem Wegwerf-Repository: Er prueft, dass der Verlauf
// wirklich aus der Git-Historie kommt, doppelte Tage richtig aufgeloest werden - und dass
// ein kuerzerer Verlauf den vorhandenen NICHT ueberschreibt.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const { buildHistory, readSnapshotsFromGit, writeHistory, setCodeOf } = require("./build-price-history.js");
const { parseProduct, buildSets, normalize } = require("./build-db.js");

test("Setcode aus der Karten-ID", () => {
  assert.equal(setCodeOf("OP01-001"), "OP01");
  assert.equal(setCodeOf("OP01-001-ALT"), "OP01");
  assert.equal(setCodeOf("P-001"), "P");
  assert.equal(setCodeOf("PRB01-001"), "PRB01");
});

test("Verlauf: Tage sortiert, Preise in Cent, ausgerichtet", () => {
  const h = buildHistory([
    { asOf: "2026-10-02", prices: { "OP01-001": 2.0 } },
    { asOf: "2026-10-01", prices: { "OP01-001": 1.87, "ST01-001": 0.15 } },
  ]);
  assert.deepEqual(h.dates, ["2026-10-01", "2026-10-02"]);
  assert.deepEqual(h.sets.OP01["OP01-001"], [187, 200]);
  assert.deepEqual(h.sets.ST01["ST01-001"], [15, null], "fehlender Tag ist null, nicht 0");
});

test("Verlauf: doppelter Tag - der spaetere Stand gewinnt", () => {
  const h = buildHistory([
    { asOf: "2026-10-06", prices: { "OP01-001": 1.0 } },
    { asOf: "2026-10-06", prices: { "OP01-001": 1.5 } },
  ]);
  assert.deepEqual(h.dates, ["2026-10-06"]);
  assert.deepEqual(h.sets.OP01["OP01-001"], [150]);
});

test("Verlauf: neue Karte taucht erst spaeter auf", () => {
  const h = buildHistory([
    { asOf: "2026-10-01", prices: { "OP01-001": 1 } },
    { asOf: "2026-10-02", prices: { "OP01-001": 1, "OP18-001": 5 } },
  ]);
  assert.deepEqual(h.sets.OP18["OP18-001"], [null, 500]);
});

test("Verlauf: unbrauchbare Staende und Werte werden uebersprungen", () => {
  const h = buildHistory([
    null,
    { prices: { "OP01-001": 1 } },
    { asOf: "2026-10-01", prices: { "OP01-001": 0, "OP01-002": -3, "OP01-003": "x", "OP01-004": 2.345 } },
  ]);
  assert.deepEqual(h.dates, ["2026-10-01"]);
  assert.equal(h.sets.OP01["OP01-001"], undefined);
  assert.deepEqual(h.sets.OP01["OP01-004"], [235]);
});

test("Verlauf aus einem echten Git-Repository", (t) => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "preisverlauf-"));
  t.after(() => fs.rmSync(repo, { recursive: true, force: true }));
  const git = (...a) => execFileSync("git", a, { cwd: repo, encoding: "utf8" });
  git("init", "-q");
  git("config", "user.email", "test@example.invalid");
  git("config", "user.name", "Test");

  const datei = path.join(repo, "docs", "data", "prices.json");
  fs.mkdirSync(path.dirname(datei), { recursive: true });
  const stand = (asOf, preis) => {
    fs.writeFileSync(datei, JSON.stringify({ asOf, prices: { "OP01-001": preis } }));
    git("add", ".");
    git("commit", "-q", "-m", asOf);
  };
  stand("2026-10-01", 1.0);
  stand("2026-10-01", 1.1); // zweiter Commit am selben Tag
  stand("2026-10-02", 1.2);

  const snapshots = readSnapshotsFromGit(repo, "docs/data/prices.json");
  assert.equal(snapshots.length, 3);
  const h = buildHistory(snapshots);
  assert.deepEqual(h.dates, ["2026-10-01", "2026-10-02"]);
  assert.deepEqual(h.sets.OP01["OP01-001"], [110, 120]);

  // Schreiben, dann ein kuerzerer Verlauf: muss abgelehnt werden
  const aus = path.join(repo, "history");
  writeHistory(h, aus);
  assert.ok(fs.existsSync(path.join(aus, "OP01.json")));
  const kurz = buildHistory([{ asOf: "2026-10-02", prices: { "OP01-001": 1 } }]);
  assert.throws(() => writeHistory(kurz, aus), /Abbruch/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(aus, "index.json"))).days, 2, "vorhandener Verlauf unangetastet");
});

test("Flache Git-Kopie wird erkannt und abgelehnt", (t) => {
  const basis = fs.mkdtempSync(path.join(os.tmpdir(), "flach-"));
  t.after(() => fs.rmSync(basis, { recursive: true, force: true }));
  const quelle = path.join(basis, "quelle");
  fs.mkdirSync(quelle);
  const git = (cwd, ...a) => execFileSync("git", a, { cwd, encoding: "utf8" });
  git(quelle, "init", "-q");
  git(quelle, "config", "user.email", "test@example.invalid");
  git(quelle, "config", "user.name", "Test");
  for (const tag of ["2026-10-01", "2026-10-02"]) {
    fs.writeFileSync(path.join(quelle, "prices.json"), JSON.stringify({ asOf: tag, prices: {} }));
    git(quelle, "add", ".");
    git(quelle, "commit", "-q", "-m", tag);
  }
  const kopie = path.join(basis, "kopie");
  git(basis, "clone", "-q", "--depth", "1", `file://${quelle.replace(/\\/g, "/")}`, kopie);

  assert.throws(() => readSnapshotsFromGit(kopie, "prices.json"), /Flache Git-Kopie/);
});

test("Produktname: Klammercode und Schreibweise", () => {
  assert.deepEqual(parseProduct("-ROMANCE DAWN- [OP-01]"), { name: "Romance Dawn", codes: ["OP01"] });
  assert.deepEqual(parseProduct("-500 YEARS IN THE FUTURE- [OP-07]").name, "500 Years in the Future");
  assert.deepEqual(parseProduct("-ADVENTURE ON KAMI'S ISLAND- [OP-15-EB04]").codes, ["OP15", "EB04"]);
  assert.equal(parseProduct("-Straw Hat Crew- [ST-01]").name, "Straw Hat Crew", "gemischte Schreibweise bleibt");
  assert.equal(parseProduct("-ONE PIECE CARD THE BEST vol.2- [PRB-02]").name, "One Piece Card the Best Vol.2");
});

test("Set-Namen: nur ein Produkt, das mit dem Set beginnt, gibt den Namen", () => {
  const karten = [
    { card_number: "OP01-001", card_sets: "-ROMANCE DAWN- [OP-01]" },
    { card_number: "OP01-002", card_sets: "-ROMANCE DAWN- [OP-01]" },
    { card_number: "OP01-003", card_sets: "-ONE PIECE CARD THE BEST- [PRB-01]" },
    { card_number: "OP01-004", card_sets: "-ONE PIECE CARD THE BEST- [PRB-01]" },
    { card_number: "OP01-005", card_sets: "-ONE PIECE CARD THE BEST- [PRB-01]" }, // Nachdrucke in der Mehrheit
    { card_number: "EB04-001", card_sets: "-ADVENTURE ON KAMI'S ISLAND- [OP-15-EB04]" },
    { card_number: "EB04-002", card_sets: "-THE AZURE SEA'S SEVEN- [OP-14-EB04]" },
    { card_number: "P-001", card_sets: "Included in Promotion Pack 2022" },
  ];
  const sets = Object.fromEntries(buildSets(karten).map((s) => [s.code, s]));
  assert.equal(sets.OP01.name, "Romance Dawn", "Nachdrucke in der Mehrheit duerfen den Namen nicht kapern");
  assert.equal(sets.EB04.name, null);
  assert.deepEqual([...sets.EB04.enthalten].sort(), ["Adventure on Kami's Island", "The Azure Sea's Seven"]);
  assert.equal(sets.P.name, "Promokarten");
});

test("Zweifarbige Karten behalten beide Farben", () => {
  const law = normalize({ card_number: "OP01-002", card_name: "Trafalgar Law", colors: ["Red", "Green"], counter: "-" });
  assert.deepEqual(law.colors, ["Red", "Green"]);
  assert.equal(law.color, "Red", "erste Farbe bleibt fuer die Web-Version");
  assert.equal(law.counter, null);
  const figur = normalize({ card_number: "OP01-004", card_name: "x", colors: ["Red"], counter: "2000" });
  assert.equal(figur.counter, 2000);
});
