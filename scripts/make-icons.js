// Einmaliges Hilfsskript: erzeugt PNG-Icons aus icons/icon.svg. Nicht Teil der Laufzeit-App.
const sharp = require("sharp");
const path = require("path");

const src = path.join(__dirname, "..", "docs", "icons", "icon.svg");
const sizes = [192, 512];

(async () => {
  for (const size of sizes) {
    const out = path.join(__dirname, "..", "docs", "icons", `icon-${size}.png`);
    await sharp(src).resize(size, size).png().toFile(out);
    console.log("OK:", out);
  }
})();
