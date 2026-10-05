// Erzeugt die Android-Launcher-Icons aus docs/icons/icon.svg.
// Einmalig ausfuehren (braucht sharp): npm install --no-save sharp && node scripts/make-android-icons.js
const sharp = require("sharp");
const path = require("path");

const src = path.join(__dirname, "..", "docs", "icons", "icon.svg");
const resRoot = path.join(__dirname, "..", "android_app", "android", "app", "src", "main", "res");

const densities = {
  "mipmap-mdpi": 48,
  "mipmap-hdpi": 72,
  "mipmap-xhdpi": 96,
  "mipmap-xxhdpi": 144,
  "mipmap-xxxhdpi": 192,
};

(async () => {
  for (const [dir, size] of Object.entries(densities)) {
    const out = path.join(resRoot, dir, "ic_launcher.png");
    await sharp(src).resize(size, size).png().toFile(out);
    console.log(`OK: ${out} (${size}px)`);
  }
})();
