// Nur fuer lokale Vorschau waehrend der Entwicklung. Die eigentliche App ist eine
// rein statische PWA (public/) - produktiv wird sie ueber GitHub Pages/Netlify o.ae. ausgeliefert,
// nicht ueber dieses Skript.
const express = require("express");
const path = require("path");

const app = express();
app.use(express.static(path.join(__dirname, "..", "public")));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Lokale Vorschau: http://localhost:${PORT}`));
