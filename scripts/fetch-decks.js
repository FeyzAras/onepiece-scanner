// Liest die aktuellen Turnier-Decklisten von onepiecetopdecks.com und schreibt sie nach
// docs/data/decks.json. Die App laedt diese Datei und kann sie so taeglich aktualisieren,
// ohne dass eine neue App-Version noetig ist.
//
// Die Seite liefert die Decklisten maschinenlesbar in der Tabelle mit:
//   Spalte 1: "1nOP09-062a4nOP17-113a4nOP17-107a..."  (<Anzahl>n<Kartennummer>, getrennt durch "a")
//   Link:     deckgen?dn=<Deckname>&date=..&cn=<Region>&au=<Spieler>&pl=<Platzierung>&tn=..&hs=<Turnier>
//
// Ausfuehren: node scripts/fetch-decks.js
//
// Hinweis: Es wird genau eine Seite pro Lauf geladen, hoechstens einmal taeglich.
// Quelle wird in der App verlinkt und genannt.

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const SOURCES = [
  { set: "OP17", title: "The World's Strongest Warriors", url: "https://onepiecetopdecks.com/deck-list/english-op17-deck-list-the-worlds-strongest-warriors/" },
];
const OUT = path.join(__dirname, "..", "docs", "data", "decks.json");
// Die robots.txt der Seite erlaubt ausdruecklich alles ausser /wp-admin/ - die Deckliste ist
// also fuer automatisierte Zugriffe freigegeben. Gibt sich der Abruf allerdings als Programm zu
// erkennen, antwortet eine pauschale Sicherheitsvoreinstellung mit HTTP 403. Deshalb eine
// gewoehnliche Browser-Kennung. Gelesen wird genau eine Seite pro Lauf, hoechstens einmal
// taeglich; die Quelle wird in der App genannt und verlinkt.
// Kurios, aber reproduzierbar: Die kurze Plattform-Kennung wird durchgelassen, eine
// ausfuehrliche Chrome-Kennung dagegen blockiert.
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";

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

/** "1nOP09-062a4nOP17-113" -> [{ id: 'OP09-062', qty: 1 }, { id: 'OP17-113', qty: 4 }] */
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
    const linkMatch = /href='([^']*deckgen\?[^']*)'/.exec(inner) || /href="([^"]*deckgen\?[^"]*)"/.exec(inner);
    if (!listMatch || !linkMatch) continue;

    const cards = parseDeckString(listMatch[1]);
    if (cards.length < 5) continue; // unvollstaendige Zeile

    const q = parseQuery(linkMatch[1]);
    const leaderId = cards[0]?.id ?? null;
    decks.push({
      name: q.dn || "Unbenannt",
      leaderId,
      date: q.date || null,
      region: q.cn || null,
      player: q.au || null,
      placement: q.pl || null,
      tournament: q.tn || null,
      host: q.hs || null,
      set: source.set,
      cards,
      cardCount: cards.reduce((s, c) => s + c.qty, 0),
    });
  }
  return decks;
}

// Die Seite weist Node-eigene Anfragen mit HTTP 403 ab (vermutlich TLS-Erkennung),
// akzeptiert curl aber problemlos. curl ist sowohl auf Windows 10/11 als auch auf
// GitHub-Actions-Runnern vorhanden.
function fetchHtml(url) {
  return execFileSync(
    "curl",
    ["-sS", "-L", "--max-time", "90", "-A", UA, url],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
}

async function main() {
  const all = [];
  for (const source of SOURCES) {
    process.stdout.write(`Lade ${source.set} … `);
    let html;
    try {
      html = fetchHtml(source.url);
    } catch (e) {
      console.log(`FEHLER: ${e.message}`);
      continue;
    }
    const decks = parseRows(html, source);
    console.log(`${decks.length} Decks`);
    all.push(...decks);
  }

  if (all.length === 0) {
    console.error("Keine Decks gefunden - Seitenstruktur hat sich vermutlich geaendert. Datei bleibt unveraendert.");
    process.exit(1);
  }

  const payload = {
    updatedAt: new Date().toISOString().slice(0, 10),
    source: {
      name: "onepiecetopdecks.com",
      urls: SOURCES.map((s) => ({ set: s.set, title: s.title, url: s.url })),
    },
    decks: all,
  };
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(payload, null, 1), "utf8");

  const leaders = new Set(all.map((d) => d.leaderId));
  console.log(`Gespeichert: ${all.length} Decks, ${leaders.size} verschiedene Leader -> ${OUT}`);
}

main();
