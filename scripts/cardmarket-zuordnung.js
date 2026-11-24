// Cardmarket-Ausgaben benennen und die Motive einer Kartennummer den Cardmarket-Produkten
// zuordnen. Reine Funktionen ohne Dateizugriff - getestet in cardmarket-zuordnung.test.js.
//
// ── Das Problem ──────────────────────────────────────────────────────────────
// Cardmarkets Einzelkarten-Export nennt je Produkt nur Name, Nummer und Ausgabe-ID
// ("Edward.Newgate (OP17-040)", idExpansion 6723). Welche Ausgabe das ist, steht nirgends -
// und innerhalb einer Ausgabe heissen alle Versionen einer Nummer gleich.
//
// ── Was hier passiert ────────────────────────────────────────────────────────
// 1. Ausgaben bekommen Namen ueber die versiegelten Produkte derselben Ausgabe
//    ("The World's Strongest Warriors Booster (Asia Region Legal)" -> 6723 =
//    "The World's Strongest Warriors (Asia Region Legal)").
// 2. Jedes Bandai-Motiv nennt sein Produkt ("-ONE PIECE CARD THE BEST- [PRB-01]").
//    Darueber wird die passende Ausgabe gesucht: erst per Set-Code, dann per Name.
// 3. Innerhalb einer Ausgabe werden die Produkte nach Preis auf die Motive verteilt:
//    Normalversion und Nachdrucke (_r) bekommen die guenstigsten, Parallelen (_p) die
//    teuersten. Eindeutig ist das nur bei einem Produkt je Motiv - alles andere ist als
//    "paar" oder "unsicher" markiert, und die App laesst den Nutzer waehlen.

const NUMMER_RE = /\(([A-Z]{1,4}\d{0,2})-(\d{3})\)/;

/// Zusaetze, die eine Ausgabe als andere Sprache oder Region kennzeichnen. Bewusst
/// Cardmarkets eigene Woerter: So findet man die Version dort wieder.
const ZUSAETZE = [
  [/asia region lega/i, "Asia Region Legal"], // auch der Tippfehler "(Asia Region Lega)" in den Daten
  [/non-english/i, "Non-English"],
  [/pre-errat/i, "Pre-Errata"],
  [/^japanese$/i, "Japanese"],
  [/chinese edition/i, "Chinese Edition"],
  [/french version/i, "French Version"],
];

/// Woerter ohne Unterscheidungskraft beim Namensvergleich.
const FUELLWOERTER = new Set([
  "one", "piece", "card", "cards", "the", "of", "a", "an", "and", "booster", "pack", "packs",
  "set", "edition", "version", "deck", "starter", "game", "vol", "included", "in",
]);

/// Cardmarkets Daten enthalten verdoppelte Anfuehrungszeichen (""Gear 5"").
function bereinigt(text) {
  return String(text || "").replace(/""/g, '"').replace(/\s+/g, " ").trim();
}

/// Zusatz eines Produktnamens ("Asia Region Legal", "Non-English" ...) oder null.
function zusatzVon(name) {
  for (const [, inhalt] of bereinigt(name).matchAll(/\(([^)]*)\)/g)) {
    for (const [muster, zusatz] of ZUSAETZE) if (muster.test(inhalt.trim())) return zusatz;
  }
  return null;
}

/// "Romance Dawn Booster Box Case (12x Booster Box)" -> "Romance Dawn"
/// "Common Set - Romance Dawn (OP01)" -> "Romance Dawn"
/// "Starter Deck: Edward.Newgate Deck Pack" -> "Starter Deck: Edward.Newgate"
function stammVon(name) {
  let s = bereinigt(name).replace(/\s*\([^)]*\)/g, " ");
  s = s.replace(
    /^\s*(?:common \/ uncommon \/ rare|common \/ rare|c\/uc\/r|alternate art leader|alternate art|special card|super rare|uncommon|unommon|common|rare|leader|full)\s+set\s*-\s*/i,
    "",
  );
  const ende =
    /\s+(?:sleeved booster pack case|sleeved booster|booster box case|booster box|booster pack|booster display|box promotion booster|box promotion|bonus pack booster|bonus pack|god deck pack|deck pack|booster|display|case)$/i;
  let vorher;
  do {
    vorher = s;
    s = s.trim().replace(ende, "");
  } while (s !== vorher);
  return s.replace(/\s+/g, " ").replace(/^[-–:\s]+|[-–:\s]+$/g, "").trim();
}

/// Bedeutungstragende Woerter, klein geschrieben, ohne Apostrophe und Fuellwoerter.
function woerter(text) {
  return new Set(
    bereinigt(text)
      .toLowerCase()
      .replace(/[’']/g, "")
      .split(/[^a-z0-9]+/)
      .filter((w) => w && !FUELLWOERTER.has(w)),
  );
}

/// Laengster gemeinsamer Wortanfang, den mindestens [anteil] der Namen teilen.
function gemeinsamerAnfang(namen, anteil) {
  const listen = namen.map((n) => n.split(" "));
  let bester = "";
  for (let laenge = 1; ; laenge++) {
    const zaehler = new Map();
    for (const w of listen) {
      if (w.length < laenge) continue;
      const k = w.slice(0, laenge).join(" ");
      const schluessel = k.toLowerCase();
      if (!zaehler.has(schluessel)) zaehler.set(schluessel, { text: k, n: 0 });
      zaehler.get(schluessel).n++;
    }
    const top = [...zaehler.values()].sort((a, b) => b.n - a.n)[0];
    if (!top || top.n < Math.ceil(namen.length * anteil) || top.n < 1) break;
    bester = top.text;
  }
  return bester.replace(/[-–:\s]+$/g, "").trim();
}

/// Kennzahlen je Ausgabe aus der Einzelkarten-Liste: Anzahl, erstes Datum, Set-Mischung.
function ausgabenKennzahlen(singles) {
  const k = new Map();
  for (const p of singles) {
    if (!k.has(p.idExpansion)) k.set(p.idExpansion, { anzahl: 0, mitNummer: 0, erst: p.dateAdded || "", sets: new Map() });
    const e = k.get(p.idExpansion);
    e.anzahl++;
    if (p.dateAdded && p.dateAdded < e.erst) e.erst = p.dateAdded;
    const m = NUMMER_RE.exec(p.name || "");
    if (m) {
      e.mitNummer++;
      e.sets.set(m[1], (e.sets.get(m[1]) || 0) + 1);
    }
  }
  for (const e of k.values()) {
    const top = [...e.sets.entries()].sort((a, b) => b[1] - a[1])[0];
    e.topSet = top ? top[0] : null;
    e.topAnzahl = top ? top[1] : 0;
    e.topAnteil = top && e.mitNummer ? top[1] / e.mitNummer : 0;
  }
  return k;
}

/// Name je Ausgabe: Map idExpansion -> { name, zusatz, label, gemischt, topSet, erst, staemme }.
///
/// Gemischt heisst: kein Set stellt die Haelfte der Karten, oder es sind Promos (P-...).
/// Dort sagt der Name eines einzelnen versiegelten Produkts wenig - die Ausgabe 5511 etwa
/// fuehrt 181 Promokarten und genau ein versiegeltes Produkt, ein "Theme Pack".
function ausgabenBenennen(singles, nonsingles) {
  const kennzahlen = ausgabenKennzahlen(singles);
  const namen = new Map();
  for (const p of nonsingles) {
    if (!namen.has(p.idExpansion)) namen.set(p.idExpansion, []);
    namen.get(p.idExpansion).push(bereinigt(p.name));
  }

  const ergebnis = new Map();
  for (const [id, k] of kennzahlen) {
    const liste = namen.get(id) || [];
    const staemme = liste.map(stammVon).filter(Boolean);
    const gemischt = k.topAnteil < 0.5 || k.topSet === "P";

    // Zusatz nur, wenn er mindestens die Haelfte der Produkte betrifft
    const zusaetze = new Map();
    for (const n of liste) {
      const z = zusatzVon(n);
      if (z) zusaetze.set(z, (zusaetze.get(z) || 0) + 1);
    }
    const topZusatz = [...zusaetze.entries()].sort((a, b) => b[1] - a[1])[0];
    const zusatz = topZusatz && topZusatz[1] * 2 >= liste.length ? topZusatz[0] : null;

    let name = null;
    if (staemme.length === 1) {
      // Ein einziges versiegeltes Produkt benennt eine gemischte Ausgabe nur, wenn sie klein
      // ist: Die Ausgabe 5511 fuehrt 175 Promokarten und als einziges Produkt ein "Theme Pack".
      if (!gemischt || k.anzahl <= 60) name = staemme[0];
    } else if (staemme.length > 1) {
      // 1. Gemeinsamer Anfang ALLER Namen ("Demo Deck", "Judge Pack", "Romance Dawn")
      const alle = gemeinsamerAnfang(staemme, 1);
      const laenge = alle ? alle.split(" ").length : 0;
      if (laenge >= 2 || (laenge === 1 && !gemischt)) name = alle;

      // 2. Haeufigster Name, wenn er mindestens die Haelfte stellt (Booster-Ausgaben)
      if (!name && !gemischt) {
        const zaehler = new Map();
        for (const s of staemme) {
          const key = s.toLowerCase();
          if (!zaehler.has(key)) zaehler.set(key, { text: s, n: 0 });
          zaehler.get(key).n++;
        }
        const sortiert = [...zaehler.values()].sort((a, b) => b.n - a.n || a.text.length - b.text.length);
        if (sortiert[0].n * 2 >= staemme.length) name = sortiert[0].text;
      }

      // 3. Gemischte Ausgaben: ein Anfang, den deutlich mehr als die Haelfte teilt
      //    ("Premium Card Collection", 17 von 26). Bei genau der Haelfte nicht: Die Ausgabe
      //    5510 hiesse sonst nach drei von sechs Produkten "Chinese New Year Red Envelope",
      //    fuehrt aber 470 Promokarten.
      if (!name && gemischt) {
        const mehrheit = gemeinsamerAnfang(staemme, 0.6);
        if (mehrheit.split(" ").length >= 2) name = mehrheit;
      }
    }
    if (!name && !gemischt && k.topSet) name = `Sonderausgabe ${k.topSet}`;

    ergebnis.set(id, {
      name: name || (k.topSet === "P" ? "Promos" : "Promo-Sammlung"),
      allgemein: !name,
      zusatz,
      gemischt,
      topSet: k.topSet,
      erst: (k.erst || "").slice(0, 10),
      staemme,
    });
  }

  // Gleiche Namen unterscheidbar machen ("Promos" gibt es mehrfach, alle aus 02/2023)
  const proLabel = new Map();
  for (const [id, a] of ergebnis) {
    a.label = a.zusatz ? `${a.name} (${a.zusatz})` : a.name;
    if (!proLabel.has(a.label)) proLabel.set(a.label, []);
    proLabel.get(a.label).push(id);
  }
  for (const ids of proLabel.values()) {
    if (ids.length < 2) continue;
    for (const id of ids) ergebnis.get(id).label += ` · Nr. ${id}`;
  }
  return ergebnis;
}

/// Je Set-Code die Ausgabe des Originaldrucks: die englische Ausgabe, in der dieses Set
/// die meisten Karten stellt (mindestens die Haelfte der Ausgabe).
///
/// Zwei Fallen, in die die erste Fassung (bis v0.12) gelaufen ist:
///  - "Zuerst angelegt" taugt nicht: Japanische Booster erscheinen Monate frueher, und
///    Cardmarket legt ihre Ausgabe "(Non-English)" zuerst an. Die App zeigte dadurch fuer
///    OP05 bis OP16 und EB01 bis EB03 japanische bzw. asiatische Preise.
///    Deshalb zaehlen Ausgaben mit Sprach-/Regionszusatz hier gar nicht.
///  - "Rein" (90 % eines Sets) ist zu streng: OP17 kam durch Nachdrucke aus anderen Sets
///    auf 89 % und fiel heraus. Starterdecks enthalten oft nur gut die Haelfte eigene Karten.
/// Unter mehreren Kandidaten gewinnt die groesste - so schlaegt der Booster mit 150 Karten
/// das am selben Tag angelegte Turnier-Pack mit 75.
function hauptAusgaben(singles, ausgaben) {
  const k = ausgabenKennzahlen(singles);
  const haupt = new Map();
  for (const [id, e] of k) {
    if (!e.topSet || e.topAnteil < 0.5) continue;
    if (ausgaben && ausgaben.get(id)?.zusatz) continue;
    const bisher = haupt.get(e.topSet);
    const besser = !bisher || e.topAnzahl > bisher.anzahl || (e.topAnzahl === bisher.anzahl && e.erst < bisher.erst);
    if (besser) haupt.set(e.topSet, { idExpansion: id, anzahl: e.topAnzahl, erst: e.erst });
  }
  return new Map([...haupt.entries()].map(([set, v]) => [set, v.idExpansion]));
}

/// Sucht die Cardmarket-Ausgaben zu einem Bandai-Produkt, beste zuerst. Leer, wenn keine passt.
///
/// [produkt]: Bandais Produktname ("One Piece Card the Best"), [codes]: seine Set-Codes
/// (["PRB01"]). Ausgaben mit Zusatz (Asia, Non-English ...) kommen nicht in Frage - Bandais
/// englischer Katalog beschreibt die englischen Drucke.
///
/// Eine Liste statt eines Treffers: "Premium Card Collection Best Selection Vol.4" passt
/// zur Promo-Sammlung, die das versiegelte Produkt fuehrt, UND zur Ausgabe "Premium Card
/// Collection". Wo die Karte tatsaechlich liegt, entscheidet der Aufrufer.
function findeAusgaben(produkt, codes, ctx) {
  const ergebnis = [];
  for (const code of codes || []) {
    const id = ctx.haupt.get(code);
    if (id !== undefined && !ergebnis.includes(id)) ergebnis.push(id);
  }
  const gesucht = woerter(produkt);
  if (!gesucht.size) return ergebnis;

  const treffer = [];
  for (const [id, a] of ctx.ausgaben) {
    if (a.zusatz || ergebnis.includes(id)) continue;
    let beste = 0;
    for (const k of [a.allgemein ? null : a.name, ...a.staemme].filter(Boolean)) {
      const w = woerter(k);
      if (!w.size || ![...w].every((x) => gesucht.has(x))) continue;
      if (w.size < 2 && !(w.size === 1 && gesucht.size === 1)) continue;
      beste = Math.max(beste, w.size);
    }
    if (beste) treffer.push({ id, punkte: beste, gemischt: a.gemischt, erst: a.erst });
  }
  treffer.sort(
    (a, b) => b.punkte - a.punkte || Number(a.gemischt) - Number(b.gemischt) || a.erst.localeCompare(b.erst),
  );
  return [...ergebnis, ...treffer.map((t) => t.id)];
}

/// Die beste passende Ausgabe, oder null.
function findeAusgabe(produkt, codes, ctx) {
  return findeAusgaben(produkt, codes, ctx)[0] ?? null;
}

/// Platz eines Motivs in der Reihenfolge der App: Nummer -> 0, -ALT -> 1, -ALTk -> k.
function motivIndex(id, nummer) {
  if (id === nummer) return 0;
  const m = id.slice(nummer.length).match(/^-ALT(\d*)$/);
  if (!m) return -1;
  return m[1] ? Number(m[1]) : 1;
}

/// "OP01-006_r1.png" -> Nachdruck (gleiches Bild wie die Normalversion, andere Ausgabe).
function istNachdruck(karte) {
  return /_r\d+\.\w+$/.test(karte.img || "");
}

/// Verteilt die Cardmarket-Produkte einer Nummer auf ihre Motive.
///
/// [motive]: die Katalogeintraege dieser Nummer, [produkte]: { idProduct, idExpansion,
/// amount, basis } mit Preis. Gibt zurueck:
///   standard: Map Karten-ID -> { produkt, sicherheit } - der Preis, den die App ohne
///             eigene Wahl zeigt. Motive ohne passendes Produkt fehlen.
///   ausgabeJeMotiv: Map Karten-ID -> idExpansion (oder fehlt)
function ordneZu(nummer, motive, produkte, ctx) {
  const setCode = nummer.split("-")[0];
  const haupt = ctx.haupt.get(setCode);
  const ausgabeJeMotiv = new Map();
  const fuehrt = new Set(produkte.map((p) => p.idExpansion));
  for (const m of motive) {
    const eigenesSet = !m.alt || (m.produktSets || []).includes(setCode) || (!m.produkt && !m.produktSets);
    // Eigenes Set: dessen Originalausgabe. Gibt es keine (EB04 steckt in den Boostern
    // OP-14 und OP-15), hilft Bandais Produktangabe "[OP-14-EB04]" weiter. Sonst die
    // erste passende Ausgabe, die diese Nummer ueberhaupt fuehrt.
    const ausgabe =
      eigenesSet && haupt !== undefined
        ? haupt
        : findeAusgaben(m.produkt, m.produktSets, ctx).find((id) => fuehrt.has(id));
    if (ausgabe !== null && ausgabe !== undefined) ausgabeJeMotiv.set(m.id, ausgabe);
  }

  const standard = new Map();
  const gruppen = new Map();
  for (const m of motive) {
    const a = ausgabeJeMotiv.get(m.id);
    if (a === undefined) continue;
    if (!gruppen.has(a)) gruppen.set(a, []);
    gruppen.get(a).push(m);
  }

  for (const [ausgabe, ms] of gruppen) {
    const ps = produkte.filter((p) => p.idExpansion === ausgabe).sort((a, b) => a.amount - b.amount || a.idProduct - b.idProduct);
    if (!ps.length) continue;
    // Normalversion und Nachdrucke zuerst (guenstig), Parallelen danach (teuer)
    const normalArtig = ms.filter((m) => !m.alt || istNachdruck(m)).sort((a, b) => motivIndex(a.id, nummer) - motivIndex(b.id, nummer));
    const parallelen = ms.filter((m) => m.alt && !istNachdruck(m)).sort((a, b) => motivIndex(a.id, nummer) - motivIndex(b.id, nummer));

    let sicherheit;
    if (ps.length === 1 && ms.length === 1) sicherheit = "eindeutig";
    else if (ps.length === 2 && normalArtig.length <= 1 && parallelen.length <= 1) sicherheit = "paar";
    else sicherheit = "unsicher";

    if (ps.length === 1) {
      // Ein Produkt, mehrere Motive: nur das erste bekommt es - welches es ist, sagt
      // Cardmarket nicht
      const erstes = normalArtig[0] || parallelen[0];
      standard.set(erstes.id, { produkt: ps[0], sicherheit: ms.length === 1 ? "eindeutig" : "unsicher" });
      continue;
    }
    // Guenstigste nach oben fuer die Normalartigen, teuerste nach unten fuer die Parallelen
    let unten = 0;
    let oben = ps.length - 1;
    for (const m of normalArtig) {
      if (unten > oben) break;
      standard.set(m.id, { produkt: ps[unten++], sicherheit });
    }
    for (const m of [...parallelen].reverse()) {
      if (unten > oben) break;
      standard.set(m.id, { produkt: ps[oben--], sicherheit });
    }
  }

  // ── Ausweichregeln, alle "unsicher" ──────────────────────────────────────
  const nachPreis = (a, b) => a.amount - b.amount || a.idProduct - b.idProduct;
  const vergeben = () => new Set([...standard.values()].map((s) => s.produkt.idProduct));
  const sortiert = [...motive].sort((a, b) => motivIndex(a.id, nummer) - motivIndex(b.id, nummer));
  const grund = sortiert[0];

  // 1. Das Grundmotiv braucht immer einen Preis - so war es bisher auch. Promokarten etwa
  //    liegen bei Cardmarket ueber viele Ausgaben verstreut. Dann die guenstigste noch
  //    freie Version, bevorzugt ohne Sprach-/Regionszusatz.
  if (grund && !standard.has(grund.id) && produkte.length) {
    const belegt = vergeben();
    const frei = produkte.filter((p) => !belegt.has(p.idProduct));
    const ohneZusatz = frei.filter((p) => !ctx.ausgaben.get(p.idExpansion)?.zusatz);
    const auswahl = (ohneZusatz.length ? ohneZusatz : frei).sort(nachPreis);
    if (auswahl.length) standard.set(grund.id, { produkt: auswahl[0], sicherheit: "unsicher" });
  }

  for (const m of sortiert) {
    if (standard.has(m.id)) continue;
    // 2. Nachdruck (_r): gleiches Bild wie die Normalversion, also deren Version
    const normal = grund && standard.get(grund.id);
    if (istNachdruck(m) && normal) {
      standard.set(m.id, { produkt: normal.produkt, sicherheit: "unsicher" });
      continue;
    }
    // 3. Eine noch freie Version der eigenen Hauptausgabe - Cardmarket fuehrt etwa die
    //    Alt-Arts der Promokarten (P-047) in der Promo-Ausgabe, nicht beim Produkt, aus dem
    //    Bandai sie kennt. Aus fremden Ausgaben wird bewusst nichts geraten: Bei OP01-006
    //    waere das eine Turnier-Version fuer 5.000 EUR gewesen.
    if (haupt !== undefined) {
      const belegt = vergeben();
      const frei = produkte.filter((p) => p.idExpansion === haupt && !belegt.has(p.idProduct)).sort(nachPreis);
      if (frei.length) standard.set(m.id, { produkt: istNachdruck(m) ? frei[0] : frei[frei.length - 1], sicherheit: "unsicher" });
    }
  }
  return { standard, ausgabeJeMotiv };
}

module.exports = {
  NUMMER_RE,
  bereinigt,
  zusatzVon,
  stammVon,
  woerter,
  gemeinsamerAnfang,
  ausgabenBenennen,
  hauptAusgaben,
  findeAusgaben,
  findeAusgabe,
  motivIndex,
  istNachdruck,
  ordneZu,
};
