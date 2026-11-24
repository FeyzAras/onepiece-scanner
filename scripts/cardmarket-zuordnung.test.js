// Tests fuer die Benennung der Cardmarket-Ausgaben und die Zuordnung der Motive.
// Ausfuehren: npm run test:data  (node --test "scripts/*.test.js")
//
// Die Beispiele sind echten Faellen nachgebaut (Ausgabe-IDs und Namen wie bei Cardmarket).

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const Z = require("./cardmarket-zuordnung");

/// Einzelkarten einer Ausgabe: n Karten mit Nummern aus den angegebenen Sets.
function karten(idExpansion, erst, sets) {
  const liste = [];
  for (const [set, n] of Object.entries(sets)) {
    for (let i = 1; i <= n; i++) {
      liste.push({ idExpansion, dateAdded: erst, name: `Karte (${set}-${String(i).padStart(3, "0")})` });
    }
  }
  return liste;
}
const versiegelt = (idExpansion, namen) => namen.map((name) => ({ idExpansion, name }));

test("Zusatz und Stamm eines Produktnamens", () => {
  assert.equal(Z.zusatzVon("The World's Strongest Warriors Booster (Asia Region Legal)"), "Asia Region Legal");
  assert.equal(Z.zusatzVon("Egghead Crisis Booster Box (Asia Region Lega)"), "Asia Region Legal", "Tippfehler in den Daten");
  assert.equal(Z.zusatzVon("Romance Dawn Booster Box Case (12x Booster Box) (Non-English)"), "Non-English");
  assert.equal(Z.zusatzVon("Romance Dawn Booster Box Case (12x Booster Box)"), null);
  assert.equal(Z.zusatzVon("1st Anniversary Set (English Version)"), null, "Englisch ist der Normalfall");

  assert.equal(Z.stammVon("Romance Dawn Booster Box Case (12x Booster Box)"), "Romance Dawn");
  assert.equal(Z.stammVon("Romance Dawn Box Promotion Booster"), "Romance Dawn");
  assert.equal(Z.stammVon("Common / Uncommon / Rare Set - Romance Dawn (OP01)"), "Romance Dawn");
  assert.equal(Z.stammVon("Alternate Art Leader Set - Romance Dawn (OP01)"), "Romance Dawn");
  assert.equal(Z.stammVon("Starter Deck: Edward.Newgate Deck Pack"), "Starter Deck: Edward.Newgate");
  assert.equal(Z.stammVon('Starter Deck EX: ""Gear 5"" Deck Pack'), 'Starter Deck EX: "Gear 5"');
  assert.equal(Z.stammVon("The Best Vol.2 Sleeved Booster Pack Case (20x Packs)"), "The Best Vol.2");
});

test("Ausgaben bekommen den Namen ihrer versiegelten Produkte", () => {
  const singles = [
    ...karten(6492, "2026-08-20", { OP17: 159, EB04: 2 }),
    ...karten(6723, "2026-08-28", { OP17: 159, EB04: 2 }),
    ...karten(5484, "2024-05-03", { OP01: 154 }),
    ...karten(5267, "2023-02-22", { P: 30, OP01: 14, ST01: 14, OP02: 10 }),
    ...karten(5510, "2023-02-15", { OP07: 43, OP01: 34, OP09: 29, OP05: 20 }),
    ...karten(6625, "2026-01-09", { P: 28, OP09: 7, OP13: 5 }),
    ...karten(6501, "2026-02-20", { OP01: 9, ST01: 2 }),
    ...karten(5230, "2022-12-28", { P: 201 }),
    ...karten(5511, "2023-02-15", { P: 175 }),
  ];
  const nonsingles = [
    ...versiegelt(6492, [
      "OP17 Booster Box Case", "The World's Strongest Warriors Booster Box", "The World's Strongest Warriors Booster",
      "Double Pack Set Vol.12", "Common Set - The World's Strongest Warriors (OP17)",
      "Full Set - The World's Strongest Warriors (OP17)", "The World's Strongest Warriors Sleeved Booster",
    ]),
    ...versiegelt(6723, [
      "The World's Strongest Warriors Booster (Asia Region Legal)",
      "The World's Strongest Warriors Booster Box (Asia Region Legal)",
      "The World's Strongest Warriors Booster Box Case (Asia Region Legal)",
    ]),
    ...versiegelt(5484, ["Romance Dawn Booster (Non-English)", "Romance Dawn Booster Box (Non-English)"]),
    ...versiegelt(5267, [
      "Premium Card Collection 25th Edition (Non-English)", "Premium Card Collection 25th Edition",
      "Premium Card Collection -ONE PIECE FILM RED Edition-", "Premium Card Collection - Best Selection Vol.1",
      "1st Anniversary Set (English Version)", "Seven Warlords of the Sea Binder Set",
    ]),
    ...versiegelt(5510, [
      "Chinese New Year Red Envelope - Roronoa Zoro", "Chinese New Year Red Envelope - Monkey.D.Luffy",
      "Chinese New Year Red Envelope - Boa Hancock", "Let’s Get Started Promotion Pack (Non-English)",
      "3rd Anniversary! One Piece Card Treasure Campaign Pack", 'Sound Loader Volume 4 ""Ace&Sabo Edition"" (SL-04)',
    ]),
    ...versiegelt(6625, ["Premium Card Collection - Best Selection Vol.2 (Asia Region Legal)"]),
    ...versiegelt(6501, [
      "Demo Deck: Monkey.D.Luffy (OP01-003)", "Demo Deck: Roronoa Zoro (OP01-001) (Incl. 1x Promotion Pack 2023 Vol.1)",
      "Demo Deck: Monkey.D.Luffy (OP01-003) (Pre-Errate Map)",
    ]),
    ...versiegelt(5511, ["July Exchange Meeting 2025 Theme Pack"]),
  ];
  const a = Z.ausgabenBenennen(singles, nonsingles);

  assert.equal(a.get(6492).label, "The World's Strongest Warriors");
  assert.equal(a.get(6723).label, "The World's Strongest Warriors (Asia Region Legal)");
  assert.equal(a.get(5484).label, "Romance Dawn (Non-English)");
  assert.equal(a.get(5267).label, "Premium Card Collection", "gemeinsamer Anfang der Mehrheit");
  assert.equal(a.get(6625).label, "Premium Card Collection - Best Selection Vol.2 (Asia Region Legal)");
  assert.equal(a.get(6501).label, "Demo Deck", "nicht nach dem haeufigsten Deck benannt");
  // 470 Promokarten heissen nicht nach drei Umschlaegen; ein einzelnes "Theme Pack"
  // benennt keine 175 Promokarten
  assert.match(a.get(5510).label, /^Promo-Sammlung/);
  assert.match(a.get(5511).label, /^Promos/);
  // Zwei allgemeine "Promos" bleiben unterscheidbar
  assert.notEqual(a.get(5230).label, a.get(5511).label);
});

test("Originalausgabe: nie eine andere Sprache, und der Booster schlaegt das Turnier-Pack", () => {
  const singles = [
    // Japanischer Booster, Monate vor dem englischen angelegt
    ...karten(5481, "2023-09-18", { OP05: 147 }),
    ...karten(5426, "2023-11-30", { OP05: 147, ST01: 2 }),
    // Turnier-Pack mit einem Teil desselben Sets
    ...karten(5565, "2023-11-29", { OP05: 75 }),
    // OP17: nur 89 % eigene Karten - frueher am 90-%-Schwellwert gescheitert
    ...karten(6492, "2026-08-20", { OP17: 159, EB04: 2, P: 2, OP12: 15 }),
    ...karten(5230, "2022-12-28", { P: 201 }),
  ];
  const nonsingles = [
    ...versiegelt(5481, ["Awakening of the New Era Booster (Non-English)"]),
    ...versiegelt(5426, ["Awakening of the New Era Booster"]),
    ...versiegelt(5565, ["1st Anniversary Tournament Pack"]),
    ...versiegelt(6492, ["The World's Strongest Warriors Booster"]),
  ];
  const ausgaben = Z.ausgabenBenennen(singles, nonsingles);
  const haupt = Z.hauptAusgaben(singles, ausgaben);
  assert.equal(haupt.get("OP05"), 5426, "englisch, nicht die zuerst angelegte japanische");
  assert.equal(haupt.get("OP17"), 6492);
  assert.equal(haupt.get("P"), 5230);
});

test("Bandai-Produkt -> Cardmarket-Ausgabe", () => {
  const singles = [
    ...karten(5805, "2024-11-07", { OP06: 61, OP05: 56, OP03: 45 }),
    ...karten(6242, "2025-10-01", { OP09: 41, PRB02: 36, P: 31 }),
    ...karten(5229, "2022-12-28", { OP01: 157 }),
    ...karten(5267, "2023-02-22", { P: 30, OP01: 14, ST01: 14 }),
  ];
  const nonsingles = [
    ...versiegelt(5805, ["The Best Booster Box", "The Best Booster"]),
    ...versiegelt(6242, ["The Best Vol.2 Booster", "The Best Vol.2 Booster Box"]),
    ...versiegelt(5229, ["Romance Dawn Booster"]),
    ...versiegelt(5267, ["Premium Card Collection 25th Edition", "Premium Card Collection - Best Selection Vol.1"]),
  ];
  const ausgaben = Z.ausgabenBenennen(singles, nonsingles);
  const ctx = { ausgaben, haupt: Z.hauptAusgaben(singles, ausgaben) };

  assert.equal(Z.findeAusgabe("One Piece Card the Best", ["PRB01"], ctx), 5805);
  assert.equal(Z.findeAusgabe("One Piece Card the Best vol.2", ["PRB02"], ctx), 6242, "Vol.2 schlaegt Vol.1");
  assert.equal(Z.findeAusgabe("Premium Card Collection 25th Edition", [], ctx), 5267);
  assert.equal(Z.findeAusgabe("Romance Dawn", ["OP01"], ctx), 5229, "Set-Code vor Namensvergleich");
  assert.equal(Z.findeAusgabe("Japanese 3rd Anniversary Set", [], ctx), null);
});

test("Zuordnung: Normal und Parallele im Booster, Asien-Auflage bleibt zur Auswahl", () => {
  const ausgaben = new Map([
    [6492, { name: "The World's Strongest Warriors", zusatz: null, staemme: [], gemischt: false, erst: "2026-08-20" }],
    [6723, { name: "The World's Strongest Warriors", zusatz: "Asia Region Legal", staemme: [], gemischt: false, erst: "2026-08-28" }],
  ]);
  const ctx = { ausgaben, haupt: new Map([["OP17", 6492]]) };
  const motive = [
    { id: "OP17-040", alt: false, img: "x/OP17-040.png", produktSets: ["OP17"] },
    { id: "OP17-040-ALT", alt: true, img: "x/OP17-040_p1.png", produktSets: ["OP17"] },
  ];
  const produkte = [
    { idProduct: 904022, idExpansion: 6492, amount: 0.17 },
    { idProduct: 904023, idExpansion: 6492, amount: 30.87 },
    { idProduct: 904855, idExpansion: 6723, amount: 0.02 },
  ];
  const { standard } = Z.ordneZu("OP17-040", motive, produkte, ctx);
  assert.equal(standard.get("OP17-040").produkt.idProduct, 904022);
  assert.equal(standard.get("OP17-040").sicherheit, "paar");
  assert.equal(standard.get("OP17-040-ALT").produkt.idProduct, 904023, "die teurere ist die Parallele");
  assert.ok(![...standard.values()].some((s) => s.produkt.idProduct === 904855), "Asien-Auflage nie automatisch");
});

test("Zuordnung: Nachdrucke und Parallelen aus einem fremden Produkt, nichts Geratenes aus Promo-Sammlungen", () => {
  const ausgaben = new Map([
    [5229, { name: "Romance Dawn", zusatz: null, staemme: ["Romance Dawn"], gemischt: false, erst: "2022-12-28" }],
    [5805, { name: "The Best", zusatz: null, staemme: ["The Best"], gemischt: true, erst: "2024-11-07" }],
    [5262, { name: "Promos", allgemein: true, zusatz: null, staemme: [], gemischt: true, erst: "2023-02-09" }],
  ]);
  const ctx = { ausgaben, haupt: new Map([["OP01", 5229]]) };
  const motive = [
    { id: "OP01-006", alt: false, img: "x/OP01-006.png", produkt: "Romance Dawn", produktSets: ["OP01"] },
    { id: "OP01-006-ALT", alt: true, img: "x/OP01-006_p3.png", produkt: "One Piece Card the Best", produktSets: ["PRB01"] },
    { id: "OP01-006-ALT2", alt: true, img: "x/OP01-006_r1.png", produkt: "One Piece Card the Best", produktSets: ["PRB01"] },
    { id: "OP01-006-ALT3", alt: true, img: "x/OP01-006_p1.png", produkt: "Japanese 1st Anniversary Set" },
  ];
  const produkte = [
    { idProduct: 690371, idExpansion: 5229, amount: 0.17 },
    { idProduct: 799187, idExpansion: 5805, amount: 0.16 },
    { idProduct: 799189, idExpansion: 5805, amount: 9.69 },
    { idProduct: 729829, idExpansion: 5262, amount: 5000 },
  ];
  const { standard } = Z.ordneZu("OP01-006", motive, produkte, ctx);
  assert.equal(standard.get("OP01-006").produkt.idProduct, 690371);
  assert.equal(standard.get("OP01-006-ALT2").produkt.idProduct, 799187, "Nachdruck: die guenstige Version");
  assert.equal(standard.get("OP01-006-ALT").produkt.idProduct, 799189, "Parallele: die teure Version");
  assert.equal(standard.get("OP01-006-ALT").sicherheit, "paar");
  assert.equal(standard.has("OP01-006-ALT3"), false, "kein Preis statt 5.000 EUR aus einer Promo-Sammlung");
});

test("Zuordnung: Ausweichregeln fuer Grundmotiv, Nachdruck und Promo-Alt-Art", () => {
  const ausgaben = new Map([
    [5230, { name: "Promos", allgemein: true, zusatz: null, staemme: [], gemischt: true, erst: "2022-12-28" }],
    [5244, { name: "Promo-Sammlung", allgemein: true, zusatz: null, staemme: ["Premium Card Collection Live Action Edition"], gemischt: true, erst: "2023-01-13" }],
  ]);
  const ctx = { ausgaben, haupt: new Map([["P", 5230]]) };
  // Promo: beide Versionen liegen in der Promo-Ausgabe, Bandai nennt fuer die Alt-Art aber
  // ein Sammelprodukt
  const motive = [
    { id: "P-047", alt: false, img: "x/P-047.png", produkt: "Sealed Battle 2023 Vol.1" },
    { id: "P-047-ALT", alt: true, img: "x/P-047_p1.png", produkt: "Premium Card Collection Live Action Edition" },
  ];
  const produkte = [
    { idProduct: 1, idExpansion: 5230, amount: 9.55 },
    { idProduct: 2, idExpansion: 5230, amount: 68.16 },
  ];
  const { standard } = Z.ordneZu("P-047", motive, produkte, ctx);
  assert.equal(standard.get("P-047").produkt.idProduct, 1);
  assert.equal(standard.get("P-047-ALT").produkt.idProduct, 2);
  assert.equal(standard.get("P-047-ALT").sicherheit, "unsicher");

  // Nachdruck ohne eigene Version: der Preis der Normalversion
  const { standard: s2 } = Z.ordneZu(
    "OP02-028",
    [
      { id: "OP02-028", alt: false, img: "x/OP02-028.png", produktSets: ["OP02"] },
      { id: "OP02-028-ALT", alt: true, img: "x/OP02-028_r1.png", produkt: "Uta", produktSets: ["ST11"] },
    ],
    [{ idProduct: 7, idExpansion: 5263, amount: 0.04 }],
    { ausgaben: new Map([[5263, { name: "Paramount War", zusatz: null, staemme: [], gemischt: false, erst: "2023-02-10" }]]), haupt: new Map([["OP02", 5263]]) },
  );
  assert.equal(s2.get("OP02-028-ALT").produkt.idProduct, 7);
  assert.equal(s2.get("OP02-028-ALT").sicherheit, "unsicher");
});

test("Motiv-Index", () => {
  assert.equal(Z.motivIndex("OP01-001", "OP01-001"), 0);
  assert.equal(Z.motivIndex("OP01-001-ALT", "OP01-001"), 1);
  assert.equal(Z.motivIndex("OP01-001-ALT7", "OP01-001"), 7);
  assert.equal(Z.motivIndex("OP01-0011", "OP01-001"), -1);
});

// ── Mit den echten Daten (nur wenn sie lokal vorliegen; data/ ist nicht versioniert) ──
const DATA = path.join(__dirname, "..", "data");
const echt = ["cm_products_18.json", "cm_nonsingles_18.json"].every((f) => fs.existsSync(path.join(DATA, f)));

test("Echte Daten: keine Originalausgabe in anderer Sprache, OP05 ist englisch", { skip: !echt && "Cardmarket-Daten fehlen" }, () => {
  const singles = JSON.parse(fs.readFileSync(path.join(DATA, "cm_products_18.json"), "utf8")).products;
  const nonsingles = JSON.parse(fs.readFileSync(path.join(DATA, "cm_nonsingles_18.json"), "utf8")).products;
  const ausgaben = Z.ausgabenBenennen(singles, nonsingles);
  const haupt = Z.hauptAusgaben(singles, ausgaben);
  for (const [set, id] of haupt) {
    assert.equal(ausgaben.get(id).zusatz, null, `${set}: Originalausgabe ${ausgaben.get(id).label}`);
  }
  for (const [set, name] of [["OP01", "Romance Dawn"], ["OP05", "Awakening of the New Era"], ["OP13", "Carrying on his Will"], ["OP17", "The World's Strongest Warriors"]]) {
    assert.equal(ausgaben.get(haupt.get(set)).label, name, set);
  }
  // Keine zwei Ausgaben mit demselben Namen
  const labels = [...ausgaben.values()].map((a) => a.label);
  assert.equal(new Set(labels).size, labels.length);
});
