import { createWorker } from "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.esm.min.js";
import { findMatches } from "./match.js";
import { mockPriceFor } from "./price-mock.js";

const MATCH_THRESHOLD = 1.3; // ab diesem Score gilt ein Treffer als sicher genug zum Auto-Hinzufuegen
const SAME_CARD_COOLDOWN_MS = 4000; // verhindert Doppel-Eintrag derselben Karte, solange sie im Bild bleibt
const LOOP_IDLE_GAP_MS = 350; // kurze Pause zwischen zwei Scan-Versuchen (schont Akku/CPU etwas)

const video = document.getElementById("video");
const stillCanvas = document.getElementById("stillCanvas");
const guideFrame = document.getElementById("guideFrame");
const toggleScanBtn = document.getElementById("toggleScanBtn");
const scanModeLabel = document.getElementById("scanModeLabel");
const galleryBtn = document.getElementById("galleryBtn");
const fileFallback = document.getElementById("fileFallback");
const statusBar = document.getElementById("statusBar");
const statusText = document.getElementById("statusText");
const progressTrack = document.getElementById("progressTrack");
const progressFill = document.getElementById("progressFill");
const scanStatusPill = document.getElementById("scanStatusPill");
const scanStatusText = document.getElementById("scanStatusText");
const scanListSheet = document.getElementById("scanListSheet");
const scanListPeek = document.getElementById("scanListPeek");
const scanCount = document.getElementById("scanCount");
const scanTotal = document.getElementById("scanTotal");
const scanListEmpty = document.getElementById("scanListEmpty");
const scanListItems = document.getElementById("scanListItems");
const clearListBtn = document.getElementById("clearListBtn");
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
let scanning = false; // true = kontinuierliche Schleife aktiv
let busy = false; // true waehrend ein einzelner Erkennungsdurchlauf laeuft
let lastAdded = { id: null, at: 0 };
const sessionList = []; // { uid, card, price, addedAt }

function formatEUR(n) {
  return n.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " â‚¬";
}

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

function flashPill(text, ok, duration = 1500) {
  scanStatusText.textContent = text;
  scanStatusPill.classList.toggle("ok", !!ok);
  scanStatusPill.classList.add("show");
  if (flashPill._t) clearTimeout(flashPill._t);
  flashPill._t = setTimeout(() => {
    scanStatusPill.classList.remove("ok");
    scanStatusText.textContent = "Scanne...";
    if (!scanning) scanStatusPill.classList.remove("show");
  }, duration);
}

async function loadCards() {
  const res = await fetch("data/cards.json");
  cards = await res.json();
  console.log(`Kartendatenbank geladen: ${cards.length} Karten`);
}

async function getWorker() {
  if (workerReady) return worker;
  showStatus("Erkennungsmodell wird geladen (einmalig)...", 0);
  worker = await createWorker("eng", 1, {
    logger: (m) => {
      if (m.status && typeof m.progress === "number" && m.status !== "recognizing text") {
        showStatus("Erkennungsmodell wird geladen...", m.progress);
      }
    },
  });
  workerReady = true;
  hideStatus();
  return worker;
}

async function startCamera() {
  permissionScreen.classList.add("hidden");
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" }, width: { ideal: 1920 }, height: { ideal: 1920 } },
      audio: false,
    });
    video.srcObject = cameraStream;
    await video.play();
    toggleScanBtn.removeAttribute("disabled");
    beginScanning();
  } catch (err) {
    console.warn("Kamera nicht verfuegbar:", err);
    permissionScreen.classList.remove("hidden");
  }
}

// Schneidet genau den Bereich innerhalb des Kartenrahmens aus dem echten Kamera-Stream aus
// (nicht aus dem skalierten CSS-Bild), damit OCR nur die Karte sieht statt des ganzen Raums.
function captureGuideFrameToCanvas() {
  const vw = video.videoWidth, vh = video.videoHeight;
  if (!vw || !vh) return false;
  const viewportW = window.innerWidth, viewportH = window.innerHeight;
  const scale = Math.max(viewportW / vw, viewportH / vh);
  const cropOffsetX = (vw * scale - viewportW) / 2;
  const cropOffsetY = (vh * scale - viewportH) / 2;
  const rect = guideFrame.getBoundingClientRect();

  const srcX = Math.max(0, (rect.left + cropOffsetX) / scale);
  const srcY = Math.max(0, (rect.top + cropOffsetY) / scale);
  const srcW = Math.min(vw - srcX, rect.width / scale);
  const srcH = Math.min(vh - srcY, rect.height / scale);
  if (srcW <= 0 || srcH <= 0) return false;

  const outW = 700;
  const outH = Math.round(outW * (srcH / srcW));
  stillCanvas.width = outW;
  stillCanvas.height = outH;
  stillCanvas.getContext("2d").drawImage(video, srcX, srcY, srcW, srcH, 0, 0, outW, outH);
  return true;
}

function addToSessionList(card, price, how = "name") {
  const entry = { uid: `${card.id}-${Date.now()}`, card, price, how, addedAt: Date.now() };
  sessionList.unshift(entry);
  renderSessionList();
  if (!scanListSheet.classList.contains("open")) {
    scanListSheet.classList.add("peek-bounce");
    setTimeout(() => scanListSheet.classList.remove("peek-bounce"), 400);
  }
}

function renderSessionList() {
  scanCount.textContent = String(sessionList.length);
  const total = sessionList.reduce((sum, e) => sum + e.price.amount, 0);
  scanTotal.textContent = `Gesamt: ${formatEUR(total)}`;
  scanListEmpty.style.display = sessionList.length ? "none" : "block";
  clearListBtn.style.display = sessionList.length ? "block" : "none";
  scanListItems.innerHTML = sessionList.map((e) => `
    <div class="scanRow" data-uid="${e.uid}">
      ${e.card.img ? `<img src="${e.card.img}" alt="">` : ""}
      <div class="info">
        <div class="name">${escapeHtml(e.card.name)}</div>
        <div class="meta">${escapeHtml(e.card.id)} Â· ${escapeHtml(e.card.rarity)}</div>
        <div class="how ${e.how === "number" ? "exact" : ""}">${e.how === "number" ? "Ã¼ber Kartennummer" : "Ã¼ber Name"}</div>
      </div>
      <div class="price">${e.price.amount.toFixed(2)} â‚¬<span class="mocktag">MOCK</span></div>
      <button class="removeBtn" data-remove="${e.uid}">âœ•</button>
    </div>
  `).join("");
}

scanListItems.addEventListener("click", (ev) => {
  const uid = ev.target?.dataset?.remove;
  if (!uid) return;
  const idx = sessionList.findIndex((e) => e.uid === uid);
  if (idx !== -1) sessionList.splice(idx, 1);
  renderSessionList();
});

clearListBtn.addEventListener("click", () => {
  if (sessionList.length && confirm(`${sessionList.length} Karte(n) aus der Liste entfernen?`)) {
    sessionList.length = 0;
    renderSessionList();
  }
});

scanListPeek.addEventListener("click", () => scanListSheet.classList.toggle("open"));

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function attemptRecognition(sourceCanvas) {
  const w = await getWorker();
  const { data } = await w.recognize(sourceCanvas);
  const matches = findMatches(data.text, cards, 3);
  if (matches.length === 0) return null;
  const top = matches[0];
  if (top.score < MATCH_THRESHOLD) return null;
  return { card: top.card, score: top.score, how: top.how };
}

async function scanLoop() {
  if (!scanning || busy) return;
  if (!video.videoWidth) { scheduleNext(); return; }
  busy = true;
  try {
    if (!captureGuideFrameToCanvas()) { scheduleNext(); return; }
    const found = await attemptRecognition(stillCanvas);
    if (found) {
      const now = Date.now();
      const isCooldownBlock = found.card.id === lastAdded.id && (now - lastAdded.at) < SAME_CARD_COOLDOWN_MS;
      if (!isCooldownBlock) {
        const price = mockPriceFor(found.card);
        addToSessionList(found.card, price, found.how);
        lastAdded = { id: found.card.id, at: now };
        flashPill(`âœ“ ${found.card.name} hinzugefÃ¼gt`, true);
      }
    }
  } catch (err) {
    console.error("Scan-Fehler:", err);
  } finally {
    busy = false;
    scheduleNext();
  }
}
function scheduleNext() {
  if (scanning) setTimeout(scanLoop, LOOP_IDLE_GAP_MS);
}

function beginScanning() {
  scanning = true;
  toggleScanBtn.classList.remove("paused");
  scanModeLabel.textContent = "lÃ¤uft";
  scanStatusPill.classList.add("show");
  scanStatusText.textContent = "Scanne...";
  scanLoop();
}
function pauseScanning() {
  scanning = false;
  toggleScanBtn.classList.add("paused");
  scanModeLabel.textContent = "pausiert";
  scanStatusPill.classList.remove("show");
}

toggleScanBtn.addEventListener("click", () => (scanning ? pauseScanning() : beginScanning()));

galleryBtn.addEventListener("click", () => fileFallback.click());
useGalleryInstead.addEventListener("click", () => fileFallback.click());

fileFallback.addEventListener("change", async () => {
  const file = fileFallback.files[0];
  if (!file) return;
  const img = new Image();
  img.onload = async () => {
    const outW = 700, outH = Math.round(outW * (img.naturalHeight / img.naturalWidth));
    stillCanvas.width = outW; stillCanvas.height = outH;
    stillCanvas.getContext("2d").drawImage(img, 0, 0, outW, outH);
    showStatus("Lese Bild...");
    const found = await attemptRecognition(stillCanvas).catch((e) => { console.error(e); return null; });
    hideStatus();
    if (found) {
      addToSessionList(found.card, mockPriceFor(found.card), found.how);
      lastAdded = { id: found.card.id, at: Date.now() };
      flashPill(`âœ“ ${found.card.name} hinzugefÃ¼gt`, true, 2200);
      scanStatusPill.classList.add("show");
    } else {
      flashPill("Keine Karte im Bild erkannt", false, 2200);
      scanStatusPill.classList.add("show");
    }
  };
  img.src = URL.createObjectURL(file);
  fileFallback.value = "";
});

retryPermissionBtn.addEventListener("click", startCamera);

// --- Katalog ---
function renderCatalog(list) {
  catalogList.innerHTML = list.slice(0, 80).map((c) => `
    <div class="catalogItem">
      ${c.img ? `<img src="${c.img}" alt="">` : ""}
      <div><div class="n">${escapeHtml(c.name)}</div><div class="m">${escapeHtml(c.id)} Â· ${escapeHtml(c.cardType)} Â· ${escapeHtml(c.rarity)}</div></div>
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
  toggleScanBtn.setAttribute("disabled", "true");
  renderSessionList();
  await loadCards();
  await startCamera();
})();

