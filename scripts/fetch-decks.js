// Liest die Turnier-Decklisten von onepiecetopdecks.com und schreibt sie nach
// docs/data/decks.json. Die App laedt diese Datei und bekommt so neue Decks,
// ohne dass eine neue App-Version noetig ist.
//
// Die Seitenliste wird nicht fest eingetragen, sondern aus der Sitemap der Seite geholt.
// Damit kommen kuenftige Sets von allein dazu.
//
// Jede Deckliste steht maschinenlesbar in der Tabelle:
//   Spalte 1: "1nOP09-062a4nOP17-113a..."  (<Anzahl>n<Kartennummer>, getrennt durch "a")
//   Link:     deckgen?dn=<Deckname>&date=..&cn=<Region>&au=<Spieler>&pl=<Platzierung>&...
//
// Ausfuehren: node scripts/fetch-decks.js
//
// Zur Quelle: Die robots.txt erlaubt automatisierte Zugriffe ausdruecklich (nur /wp-admin/
// ist gesperrt). Es wird einmal taeglich gelesen, mit Pause zwischen den Seiten, und die
// Quelle wird in der App genannt und verlinkt.

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const SITEMAP = "https://onepiecetopdecks.com/wp-sitemap-posts-page-1.xml";
const OUT = path.join(__dirname, "..", "docs", "data", "decks.json");
const PAUSE_MS = 2500; // Pause zwischen zwei Seitenabrufen
const MAX_JE_ARCHETYP = 5; // wie viele Listen je Deckname und Set behalten werden

/** "10/4/2026" -> vergleichbarer Zahlenwert. Unlesbares Datum wird zu 0 (sortiert nach hinten). */
function datumWert(roh) {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec((roh ?? "").trim());
  if (!m) return 0;
  return Number(m[3]) * 10000 + Number(m[1]) * 100 + Number(m[2]);
}

// Kurios, aber reproduzierbar: Die kurze Plattform-Kennung wird durchgelassen, eine
// ausfuehrliche Chrome-Kennung dagegen blockiert.
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";

// Node-eigene Anfragen beantwortet die Seite mit HTTP 403 (vermutlich TLS-Erkennung),
// curl dagegen problemlos. curl liegt sowohl auf Windows als auch auf GitHub-Runnern bereit.
function fetchText(url) {
  return execFileSync("curl", ["-sS", "-L", "--max-time", "90", "-A", UA, url], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function decodeEntities(s) {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ");
}

/** Leitet Format und Set aus der Adresse der Seite ab. */
function describe(url) {
  const slug = url.replace(/\/$/, "").split("/").pop();
  const japanisch = /^(jp|japan|japanese)[-_]/.test(slug);
  // Erstes vorkommendes Set-Kuerzel, z.B. "op-14" oder "op17" oder "eb-02"
  const m = /\b(op|eb|prb)[-_ ]?(\d{1,2})\b/i.exec(slug);
  const set = m ? `${m[1].toUpperCase()}${m[2].padStart(2, "0")}` : "?";
  return { format: japanisch ? "Japanisch" : "Englisch", set, slug };
}

/** "1nOP09-062a4nOP17-113" -> [{ id: 'OP09-062', qty: 1 }, ...] */
function parseDeckString(raw) {
  const cards = [];
  for (const part of decodeEntities(raw).split("a")) {
    const m = /^(\d+)n([A-Z]{1,4}\d{0,2}-\d{3})$/.exec(part.trim());
    if (m) cards.push({ id: m[2], qty: parseInt(m[1], 10) });
  }
  return cards;
}

function parseQuery(href) {
  const out = {};
  const q = decodeEntities(href).split("?")[1] ?? "";
  for (const pair of q.split("&")) {
    const idx = pair.indexOf("=");
    if (idx === -1) continue;
    out[pair.slice(0, idx)] = decodeURIComponent(pair.slice(idx + 1).replace(/\+/g, " "));
  }
  return out;
}

function parseRows(html, source) {
  const decks = [];
  const rowRe = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
  let row;
  while ((row = rowRe.exec(html)) !== null) {
    const inner = row[1];
    const listMatch = /<td class="column-1">([^<]*)<\/td>/.exec(inner);
    const linkMatch =
      /href='([^']*deckgen\?[^']*)'/.exec(inner) || /href="([^"]*deckgen\?[^"]*)"/.exec(inner);
    if (!listMatch || !linkMatch) continue;

    const cards = parseDeckString(listMatch[1]);
    if (cards.length < 5) continue; // unvollstaendige Zeile

    const q = parseQuery(linkMatch[1]);
    decks.push({
      name: q.dn || "Unbenannt",
      leaderId: cards[0]?.id ?? null,
      date: q.date || null,
      region: q.cn || null,
      player: q.au || null,
      placement: q.pl || null,
      tournament: q.tn || null,
      host: q.hs || null,
      set: source.set,
      format: source.format,
      cards,
      cardCount: cards.reduce((s, c) => s + c.qty, 0),
    });
  }
  return decks;
}

/** Holt die Liste der Decklisten-Seiten aus der Sitemap. */
function discoverPages() {
  const xml = fetchText(SITEMAP);
  const urls = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  return urls.filter(
    (u) =>
      u.includes("/deck-list/") &&
      !u.endsWith("/deck-list/") &&
      !u.includes("/deckgen"), // Generator-Unterseite, keine Liste
  );
}

async function main() {
  process.stdout.write("Seitenliste aus der Sitemap holen … ");
  let pages;
  try {
    pages = discoverPages();
  } catch (e) {
    console.log(`FEHLER: ${e.message}`);
    process.exit(1);
  }
  console.log(`${pages.length} Decklisten-Seiten`);

  const all = [];
  const seen = new Set();
  let leer = 0;

  for (const url of pages) {
    const source = describe(url);
    await sleep(PAUSE_MS);
    let html;
    try {
      html = fetchText(url);
    } catch (e) {
      console.log(`  ${source.slug}: FEHLER ${e.message.slice(0, 60)}`);
      continue;
    }
    const decks = parseRows(html, source);
    if (decks.length === 0) {
      leer++;
      console.log(`  ${source.slug}: 0 Decks (${Math.round(html.length / 1024)} KB)`);
      continue;
    }

    // Dasselbe Deck steht teils auf mehreren Seiten - ueber Spieler, Datum und Kartenliste entdoppeln
    let neu = 0;
    for (const deck of decks) {
      const key = [deck.player, deck.date, deck.placement, deck.cards.map((c) => c.id + c.qty).join("")].join("|");
      if (seen.has(key)) continue;
      seen.add(key);
      all.push(deck);
      neu++;
    }
    console.log(`  ${source.set} ${source.format}: ${decks.length} Decks (${neu} neu)`);
  }

  if (all.length === 0) {
    console.error("Keine Decks gefunden - Seitenstruktur hat sich vermutlich geaendert. Datei bleibt unveraendert.");
    process.exit(1);
  }

  // Die Seiten enthalten ueber 12.000 Decks, aber nur rund 1.900 verschiedene Archetypen -
  // derselbe Deckname taucht pro Set bis zu 120-mal mit leicht abweichenden Listen auf.
  // Je Archetyp bleiben die neuesten Eintraege. Das haelt alle Archetypen und 96 % der
  // Kartenabdeckung, senkt die Datei aber von 4 MB auf gut 1,5 MB - wichtig, weil die
  // App sie aufs Handy laedt.
  const proArchetyp = new Map();
  const auswahl = [];
  const sortiert = [...all].sort((a, b) => datumWert(b.date) - datumWert(a.date));
  for (const deck of sortiert) {
    const key = `${deck.set}|${deck.format}|${deck.name}`;
    const n = proArchetyp.get(key) ?? 0;
    if (n >= MAX_JE_ARCHETYP) continue;
    proArchetyp.set(key, n + 1);
    auswahl.push(deck);
  }
  console.log(
    `\nAus ${all.length} Decks ausgewaehlt: ${auswahl.length} ` +
      `(${proArchetyp.size} Archetypen, hoechstens ${MAX_JE_ARCHETYP} je Archetyp)`,
  );

  // Kompaktes Format: kurze Schluessel, Kartenliste als Zeichenkette "4xOP17-113 4xOP17-107 …"
  // statt als Liste von Objekten - spart gegenueber ausgeschriebenem JSON rund die Haelfte.
  const payload = {
    updatedAt: new Date().toISOString().slice(0, 10),
    source: {
      name: "onepiecetopdecks.com",
      urls: [{ set: "alle", title: "Deck-Listen", url: "https://onepiecetopdecks.com/deck-list/" }],
    },
    decks: auswahl.map((d) => ({
      n: d.name,
      l: d.leaderId,
      d: d.date,
      r: d.region,
      p: d.player,
      pl: d.placement,
      t: d.tournament,
      h: d.host,
      s: d.set,
      f: d.format === "Japanisch" ? "jp" : "en",
      c: d.cards.map((c) => `${c.qty}x${c.id}`).join(" "),
    })),
  };
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(payload), "utf8");

  const sets = new Set(all.map((d) => `${d.set} ${d.format}`));
  const karten = new Set();
  for (const d of all) for (const c of d.cards) karten.add(c.id);
  const mb = (fs.statSync(OUT).size / 1024 / 1024).toFixed(2);
  console.log(`\nGespeichert: ${all.length} Decks aus ${sets.size} Set/Format-Kombinationen`);
  console.log(`             ${karten.size} verschiedene Karten, ${leer} Seiten ohne Treffer`);
  console.log(`             ${OUT} (${mb} MB)`);
}

main();
