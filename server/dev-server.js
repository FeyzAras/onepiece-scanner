// Nur fuer lokale Vorschau waehrend der Entwicklung. Die eigentliche App ist eine
// rein statische PWA (docs/) - produktiv wird sie ueber GitHub Pages ausgeliefert,
// nicht ueber dieses Skript. Ordnername "docs" ist GitHub-Pages-Konvention (Branch-Deploy aus /docs).
const express = require("express");
const path = require("path");

const app = express();
app.use(express.static(path.join(__dirname, "..", "docs")));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Lokale Vorschau: http://localhost:${PORT}`));
