// Tests fuer den Katalogaufbau: IDs der Motive und Produktnamen.
// Ausfuehren: npm run test:data  (node --test "scripts/*.test.js")

const test = require("node:test");
const assert = require("node:assert/strict");
const { vergibIds, parseProduct } = require("./build-db");

const druck = (nummer, bild, alt = true, sets = "") => ({
  card_number: nummer,
  is_alternate_art: alt,
  image_url: `https://example/${bild}.png`,
  card_sets: sets,
});

test("IDs: ausgelieferte Bilder behalten ihre ID, neue bekommen die naechste freie", () => {
  // In der Quelle steht _p3 vor _p1 - frueher bekam deshalb _p3 die ID -ALT
  const quelle = [
    druck("OP01-006", "OP01-006", false),
    druck("OP01-006", "OP01-006_p3"),
    druck("OP01-006", "OP01-006_p4"),
    druck("OP01-006", "OP01-006_r1"),
    druck("OP01-006", "OP01-006_p1"),
  ];
  const register = new Map([
    ["https://example/OP01-006.png", "OP01-006"],
    ["https://example/OP01-006_p3.png", "OP01-006-ALT"],
  ]);
  const ids = vergibIds(quelle, register);
  const nachBild = Object.fromEntries([...ids].map(([r, id]) => [r.image_url.split("/").pop(), id]));
  assert.deepEqual(nachBild, {
    "OP01-006.png": "OP01-006",
    "OP01-006_p3.png": "OP01-006-ALT", // unveraendert
    "OP01-006_p4.png": "OP01-006-ALT2",
    "OP01-006_r1.png": "OP01-006-ALT3",
    "OP01-006_p1.png": "OP01-006-ALT4",
  });

  // Gleiche Quelle, Register mit den neuen IDs (= der naechste Lauf): alles bleibt
  const register2 = new Map([...ids].map(([r, id]) => [r.image_url, id]));
  const umgedreht = vergibIds([...quelle].reverse(), register2);
  for (const [r, id] of umgedreht) assert.equal(id, ids.get(quelle.find((q) => q.image_url === r.image_url)));
});

test("IDs: ohne Register wie bisher, ein zweiter Normaldruck wird nie -ALT", () => {
  const quelle = [
    druck("OP01-052", "OP01-052", false),
    druck("OP01-052", "OP01-052_p1", false, "Included in Event Pack Vol.2"),
    druck("OP01-052", "OP01-052_p3"),
    druck("OP01-052", "OP01-052_p3"), // doppelt in der Quelle
  ];
  const ids = vergibIds(quelle);
  assert.equal(ids.get(quelle[0]), "OP01-052");
  assert.equal(ids.get(quelle[1]), "OP01-052-ALT2", "-ALT bleibt der ersten echten Alt-Art");
  assert.equal(ids.get(quelle[2]), "OP01-052-ALT");
  assert.equal(ids.has(quelle[3]), false, "doppeltes Bild faellt weg");
});

test("IDs: Registereintrag einer fremden Nummer wird ignoriert", () => {
  const quelle = [druck("OP02-001", "OP02-001", false)];
  const ids = vergibIds(quelle, new Map([["https://example/OP02-001.png", "OP01-001"]]));
  assert.equal(ids.get(quelle[0]), "OP02-001");
});

test("Produktnamen: alte und neue Bandai-Schreibweisen", () => {
  const faelle = [
    ["-ROMANCE DAWN- [OP-01]", "Romance Dawn", ["OP01"]],
    ["-500 YEARS IN THE FUTURE- [OP-07]", "500 Years in the Future", ["OP07"]],
    ["BOOSTER PACK -THE WORLD’S STRONGEST WARRIORS- [OP-17]", "The World’s Strongest Warriors", ["OP17"]],
    ["STARTER DECK -RED Monkey.D.Luffy- [ST-31]", "Red Monkey.D.Luffy", ["ST31"]],
    ["STARTER DECK -YELLOW Eustass\"Captain\"Kid- [ST-36]", "Yellow Eustass\"Captain\"Kid", ["ST36"]],
    ["-GREEN/YELLOW Yamato- [ST-28]", "Green/Yellow Yamato", ["ST28"]],
    ["-PURPLE/BLACK Monkey.D.Luffy- [ST-26]", "Purple/Black Monkey.D.Luffy", ["ST26"]],
    ["-ADVENTURE ON KAMI'S ISLAND- [OP-15-EB04]", "Adventure on Kami's Island", ["OP15", "EB04"]],
    ["-ONE PIECE CARD THE BEST vol.2- [PRB-02]", "One Piece Card the Best Vol.2", ["PRB02"]],
    ["-3D2Y- [ST-14]", "3D2Y", ["ST14"]],
    ["Premium Card Collection -25th Edition-", "Premium Card Collection 25th Edition", []],
    ["Included in Event Pack Vol.2", "Event Pack Vol.2", []],
    ["OP14-EB04 Dash Pack Campaign", "OP14-EB04 Dash Pack Campaign", []],
  ];
  for (const [roh, name, codes] of faelle) {
    assert.deepEqual(parseProduct(roh), { name, codes }, roh);
  }
});
