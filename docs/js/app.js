import { createWorker } from "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.esm.min.js";
import { matchCard } from "./match.js";
import { formatPrice, priceLabel, sumPrices } from "./price.js";

const CONFIRMATIONS_NEEDED = 2; // dieselbe Kartennummer muss so oft gelesen werden, bevor uebernommen wird
const CONFIRMATION_WINDOW_MS = 4000; // laeuft die Bestaetigung laenger, wird neu angefangen
const SAME_CARD_COOLDOWN_MS = 4000; // verhindert Doppel-Eintrag derselben Karte, solange sie im Bild bleibt
const LOOP_IDLE_GAP_MS = 350; // kurze Pause zwischen zwei Scan-Versuchen
const GAME_NAME = "One Piece Card Game"; // aktuell einziges Spiel, Liste gruppiert aber schon danach

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
let scanning = false;
let busy = false;
let lastAdded = { id: null, at: 0 };
const sessionList = [];

function formatEUR(n) {
  return n.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
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
  const withPrice = cards.filter((c) => c.price).length;
  console.log(`Kartendatenbank geladen: ${cards.length} Karten, davon ${withPrice} mit Cardmarket-Preis`);
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

// Schneidet genau den Bereich innerhalb des Kartenrahmens aus dem Kamerabild aus,
// damit die Texterkennung nur die Karte sieht statt des ganzen Raums.
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

function addToSessionList(card, how = "name") {
  sessionList.unshift({ uid: `${card.id}-${Date.now()}`, card, how, addedAt: Date.now() });
  renderSessionList();
  if (!scanListSheet.classList.contains("open")) {
    scanListSheet.classList.add("peek-bounce");
    setTimeout(() => scanListSheet.classList.remove("peek-bounce"), 400);
  }
}

function groupByGame(entries) {
  const groups = new Map();
  for (const entry of entries) {
    const game = entry.card.game || GAME_NAME;
    if (!groups.has(game)) groups.set(game, []);
    groups.get(game).push(entry);
  }
  return groups;
}

function renderSessionList() {
  scanCount.textContent = String(sessionList.length);
  scanTotal.textContent = `Gesamt: ${formatEUR(sumPrices(sessionList))}`;
  scanListEmpty.style.display = sessionList.length ? "none" : "block";
  clearListBtn.style.display = sessionList.length ? "block" : "none";

  const groups = groupByGame(sessionList);
  let html = "";
  for (const [game, entries] of groups) {
    html += `
      <div class="gameHeader">
        <span class="folder">🗂</span>
        <span class="gameName">${escapeHtml(game)}</span>
        <span class="gameSum">${entries.length} · ${formatEUR(sumPrices(entries))}</span>
      </div>`;
    html += entries.map((e) => `
      <div class="scanRow" data-uid="${e.uid}">
        ${e.card.img ? `<img src="${e.card.img}" alt="">` : ""}
        <div class="info">
          <div class="name">${escapeHtml(e.card.name)}</div>
          <div class="meta">${escapeHtml(e.card.id)} · ${escapeHtml(e.card.rarity)}</div>
          <div class="how ${e.how === "number" ? "exact" : ""}">${e.how === "number" ? "über Kartennummer" : "über Name"}</div>
        </div>
        <div class="price">${formatPrice(e.card.price)}<span class="pricesrc">${escapeHtml(priceLabel(e.card.price))}</span></div>
        <button class="removeBtn" data-remove="${e.uid}">✕</button>
      </div>`).join("");
  }
  scanListItems.innerHTML = html;
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

async function attemptRecognition(sourceCanvas) {
  const w = await getWorker();
  const { data } = await w.recognize(sourceCanvas);
  return matchCard(data.text, cards);
}

// Mehrfachbestaetigung: dieselbe Kartennummer muss mehrmals gelesen werden,
// bevor die Karte uebernommen wird.
let pending = { id: null, count: 0, since: 0 };

function handleCandidate(result) {
  const now = Date.now();
  if (result.card.id === lastAdded.id && now - lastAdded.at < SAME_CARD_COOLDOWN_MS) return;

  if (pending.id !== result.card.id || now - pending.since > CONFIRMATION_WINDOW_MS) {
    pending = { id: result.card.id, count: 1, since: now };
  } else {
    pending.count++;
  }

  if (pending.count >= CONFIRMATIONS_NEEDED) {
    addToSessionList(result.card, result.how);
    lastAdded = { id: result.card.id, at: now };
    pending = { id: null, count: 0, since: 0 };
    flashPill(`✓ ${result.card.name} · ${result.card.id}`, true);
  } else {
    flashPill(`Prüfe ${result.card.id} …`, false, 1200);
  }
}

async function scanLoop() {
  if (!scanning || busy) return;
  if (!video.videoWidth) { scheduleNext(); return; }
  busy = true;
  try {
    if (!captureGuideFrameToCanvas()) { scheduleNext(); return; }
    const outcome = await attemptRecognition(stillCanvas);
    if (outcome.card) {
      handleCandidate(outcome);
    } else if (outcome.nameOnlyHint) {
      flashPill(`„${outcome.nameOnlyHint}" – Kartennummer ins Bild halten`, false, 1800);
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
  scanModeLabel.textContent = "läuft";
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
    const outcome = await attemptRecognition(stillCanvas).catch((e) => { console.error(e); return null; });
    hideStatus();
    scanStatusPill.classList.add("show");
    if (outcome?.card) {
      // Einzelbild aus der Galerie: hier reicht ein Treffer, es gibt keine Folgebilder.
      addToSessionList(outcome.card, outcome.how);
      lastAdded = { id: outcome.card.id, at: Date.now() };
      flashPill(`✓ ${outcome.card.name} · ${outcome.card.id}`, true, 2200);
    } else if (outcome?.nameOnlyHint) {
      flashPill(`„${outcome.nameOnlyHint}" – Kartennummer nicht lesbar`, false, 2600);
    } else {
      flashPill("Keine Kartennummer im Bild gefunden", false, 2200);
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
      <div>
        <div class="n">${escapeHtml(c.name)}</div>
        <div class="m">${escapeHtml(c.id)} · ${escapeHtml(c.cardType)} · ${escapeHtml(c.rarity)} · ${formatPrice(c.price)}</div>
      </div>
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
    renderCatalog(q ? cards.filter((c) => c.name.toLowerCase().includes(q) || c.id.toLowerCase().includes(q)) : cards);
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
