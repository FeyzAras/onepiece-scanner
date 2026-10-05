// Kleines Testskript: schickt das lokale Testbild an /api/scan und gibt die Antwort aus.
// Zweck: End-to-End-Nachweis, dass OCR + Matching + Mock-Preis wirklich laufen (nicht nur Code, der kompiliert).
const fs = require("fs");
const path = require("path");

async function main() {
  const imgPath = path.join(__dirname, "..", "data", "sample_OP01-001.png");
  const buffer = fs.readFileSync(imgPath);
  const form = new FormData();
  form.append("image", new Blob([buffer], { type: "image/png" }), "sample_OP01-001.png");

  console.log("Sende Testbild an /api/scan ...");
  const started = Date.now();
  const res = await fetch("http://localhost:3000/api/scan", { method: "POST", body: form });
  const data = await res.json();
  console.log(`HTTP ${res.status} nach ${Date.now() - started}ms`);
  console.log(JSON.stringify(data, null, 2));
}

main().catch((e) => {
  console.error("FEHLER:", e);
  process.exit(1);
});
