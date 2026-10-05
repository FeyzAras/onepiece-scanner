import { createWorker } from "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.esm.min.js";
import { findMatches } from "./match.js";
import { mockPriceFor } from "./price-mock.js";

const video = document.getElementById("video");
const stillCanvas = document.getElementById("stillCanvas");
const guideFrame = document.getElementById("guideFrame");
const shutter = document.getElementById("shutter");
const galleryBtn = document.getElementById("galleryBtn");
const fileFallback = document.getElementById("fileFallback");
const statusBar = document.getElementById("statusBar");
const statusText = document.getElementById("statusText");
const progressTrack = document.getElementById("progressTrack");
const progressFill = document.getElementById("progressFill");
const resultSheet = document.getElementById("resultSheet");
const resultBody = document.getElementById("resultBody");
const scanAgainBtn = document.getElementById("scanAgainBtn");
const closeSheetBtn = document.getElementById("closeSheetBtn");
const openCatalogBtn = document.getElementById("openCatalogBtn");
const closeCatalogBtn = document.getElementById("closeCatalogBtn");
const catalogPanel = document.getElementById("catalogPanel");
const catalogSearch = document.getElementById("catalogSearch");
const catalogList = document.getElementById("catalogList");
const installPill = document.getElementById("installPill");
const permissionScreen = document.getElementById("permissionScreen");
const retryPermissionBtn = document.getElementById("retryPermissionBtn");
const useGalleryInstead = document.getElementById("useGalleryInstead");

let cards = [];
let worker = null;
let workerReady = false;
let cameraStream = null;

function showStatus(text, progress) {
  statusBar.classList.add("show");
  statusText.textContent = text;
  if (typeof progress === "number") {
    progressTrack.style.display = "block";
    progressFill.style.width = `${Math.round(progress * 100)}%`;
  } else {
    progressTrack.style.display = "none";
  }
}
function hideStatus() {
  statusBar.classList.remove("show");
}

async function loadCards() {
  const res = await fetch("data/cards.json");
  cards = await res.json();
  console.log(`Kartendatenbank geladen: ${cards.length} Karten`);
}

async function getWorker() {
  if (workerReady) return worker;
  showStatus("Erkennungsmodell wird geladen...", 0);
  worker = await createWorker("eng", 1, {
    logger: (m) => {
      if (m.status && typeof m.progress === "number") {
        const label = m.status === "recognizing text" ? "Lese Karte..." : "Modell wird geladen...";
        showStatus(label, m.progress);
      }
    },
  });
  workerReady = true;
  return worker;
}

async function startCamera() {
  permissionScreen.classList.add("hidden");
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 1280 } },
      audio: false,
    });
    video.srcObject = cameraStream;
    await video.play();
    shutter.removeAttribute("disabled");
  } catch (err) {
    console.warn("Kamera nicht verfuegbar:", err);
    permissionScreen.classList.remove("hidden");
  }
}

function freezeFrameToCanvas(sourceEl, naturalWidth, naturalHeight) {
  stillCanvas.width = naturalWidth;
  stillCanvas.height = naturalHeight;
  const ctx = stillCanvas.getContext("2d");
  ctx.drawImage(sourceEl, 0, 0, naturalWidth, naturalHeight);
  video.style.display = "none";
  stillCanvas.style.display = "block";
}

function resumeLiveView() {
  stillCanvas.style.display = "none";
  video.style.display = "block";
  resultSheet.classList.remove("open");
}

async function runRecognition() {
  shutter.setAttribute("disabled", "true");
  try {
    const w = await getWorker();
    showStatus("Lese Karte...", 0);
    const { data } = await w.recognize(stillCanvas);
    hideStatus();
    const matches = findMatches(data.text, cards, 5).map(({ card, score }) => ({
      ...card,
      matchScore: Math.round(score * 100) / 100,
      price: mockPriceFor(card),
    }));
    renderResult(matches, data.text);
  } catch (err) {
    console.error(err);
    hideStatus();
    renderResult([], "(Fehler bei der Erkennung: " + err.message + ")");
  } finally {
    shutter.removeAttribute("disabled");
  }
}

function renderResult(matches, ocrText) {
  if (matches.length === 0) {
    resultBody.innerHTML = `<div id="noMatch">Keine Karte erkannt. Versuch es mit besserem Licht oder näher an die Karte.</div>
      <div id="ocrDebug">${escapeHtml(ocrText || "(kein Text)")}</div>`;
  } else {
    resultBody.innerHTML = matches.map((m, i) => `
      <div class="resultCard">
        ${m.img ? `<img src="${m.img}" alt="">` : ""}
        <div>
          <div class="name">${escapeHtml(m.name)} ${i === 0 ? '<span class="badge best">beste Übereinstimmung</span>' : `<span class="badge">${m.matchScore}</span>`}</div>
          <div class="meta">${escapeHtml(m.id)} · ${escapeHtml(m.cardType)} · ${escapeHtml(m.color)} · Rarity ${escapeHtml(m.rarity)}</div>
          <div class="price">${m.price.amount.toFixed(2)} ${m.price.currency}<span class="mocktag">${m.price.source}</span></div>
        </div>
      </div>
    `).join("") + `<div id="ocrDebug">${escapeHtml(ocrText.trim() || "(kein Text)")}</div>`;
  }
  resultSheet.classList.add("open");
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

shutter.addEventListener("click", async () => {
  if (!video.videoWidth) return;
  freezeFrameToCanvas(video, video.videoWidth, video.videoHeight);
  await runRecognition();
});

scanAgainBtn.addEventListener("click", resumeLiveView);
closeSheetBtn.addEventListener("click", () => resultSheet.classList.remove("open"));

galleryBtn.addEventListener("click", () => fileFallback.click());
useGalleryInstead.addEventListener("click", () => fileFallback.click());

fileFallback.addEventListener("change", async () => {
  const file = fileFallback.files[0];
  if (!file) return;
  const img = new Image();
  img.onload = async () => {
    freezeFrameToCanvas(img, img.naturalWidth, img.naturalHeight);
    await runRecognition();
  };
  img.src = URL.createObjectURL(file);
});

retryPermissionBtn.addEventListener("click", startCamera);

// --- Katalog ---
function renderCatalog(list) {
  catalogList.innerHTML = list.slice(0, 80).map((c) => `
    <div class="catalogItem">
      ${c.img ? `<img src="${c.img}" alt="">` : ""}
      <div><div class="n">${escapeHtml(c.name)}</div><div class="m">${escapeHtml(c.id)} · ${escapeHtml(c.cardType)} · ${escapeHtml(c.rarity)}</div></div>
    </div>
  `).join("") || `<p style="color:var(--text-dim); text-align:center; margin-top:20px">Keine Treffer</p>`;
}
openCatalogBtn.addEventListener("click", () => {
  catalogPanel.classList.add("open");
  renderCatalog(cards.slice(0, 80));
});
closeCatalogBtn.addEventListener("click", () => catalogPanel.classList.remove("open"));
let searchTimer = null;
catalogSearch.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    const q = catalogSearch.value.trim().toLowerCase();
    renderCatalog(q ? cards.filter((c) => c.name.toLowerCase().includes(q)) : cards);
  }, 250);
});

// --- PWA Install ---
let deferredInstallPrompt = null;
window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  deferredInstallPrompt = e;
  installPill.classList.add("show");
});
installPill.addEventListener("click", async () => {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  installPill.classList.remove("show");
});

// --- Service Worker ---
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("sw.js").catch((e) => console.warn("SW-Registrierung fehlgeschlagen:", e));
  });
}

// --- Start ---
(async function init() {
  shutter.setAttribute("disabled", "true");
  await loadCards();
  await startCamera();
})();
