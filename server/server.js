const path = require("path");
const fs = require("fs");
const express = require("express");
const multer = require("multer");
const { createWorker } = require("tesseract.js");
const { findMatches } = require("./match");
const { mockPriceFor } = require("./price-mock");

const DATA_DIR = path.join(__dirname, "..", "data");
const CARDS_PATH = path.join(DATA_DIR, "cards.normalized.json");
const PORT = process.env.PORT || 3000;

if (!fs.existsSync(CARDS_PATH)) {
  console.error("cards.normalized.json fehlt. Erst ausfuehren: npm run build-db");
  process.exit(1);
}
const cards = JSON.parse(fs.readFileSync(CARDS_PATH, "utf8"));
console.log(`Kartendatenbank geladen: ${cards.length} Karten`);

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

app.use(express.static(path.join(__dirname, "..", "public")));
app.use("/data", express.static(DATA_DIR)); // fuer das lokale Testbild im Demo-UI

let workerPromise = null;
function getWorker() {
  if (!workerPromise) {
    console.log("Starte Tesseract-Worker (einmalig, erster Request dauert laenger)...");
    workerPromise = createWorker("eng");
  }
  return workerPromise;
}

app.get("/api/cards", (req, res) => {
  const q = (req.query.q || "").toLowerCase();
  const results = q
    ? cards.filter((c) => c.name.toLowerCase().includes(q)).slice(0, 50)
    : cards.slice(0, 50);
  res.json({ count: results.length, cards: results });
});

app.post("/api/scan", upload.single("image"), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "Kein Bild im Feld 'image' erhalten." });
  }
  const startedAt = Date.now();
  try {
    const worker = await getWorker();
    const { data } = await worker.recognize(req.file.buffer);
    const ocrText = data.text || "";

    const matches = findMatches(ocrText, cards, 5).map(({ card, score }) => ({
      ...card,
      matchScore: Math.round(score * 100) / 100,
      price: mockPriceFor(card),
    }));

    res.json({
      ocrText,
      durationMs: Date.now() - startedAt,
      matches,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Erkennung fehlgeschlagen", detail: String(err) });
  }
});

app.listen(PORT, () => {
  console.log(`Prototyp laeuft: http://localhost:${PORT}`);
});
