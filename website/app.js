// NEELx Official Website — Multi-Tab Interactive Engine
// Features:
//  - Smooth animated multi-tab navigation + URL hash sync
//  - Proper sculpted 3D vector human face rotating in true 3D perspective inside the 80-tick enrollment ring
//  - Interactive Backlit HDR Shadow Recovery before/after split demo
//  - Interactive Studio Light & Chromatic Prism Rim simulator
//  - Interactive Stage 3 Neural 3D Depth Inferno heatmap + cross-section
//  - Original Windows Fluent Prism Horizon animated canvas
//  - 1-click Copy buttons for every terminal command & SHA-256 checksum
//  - Live GitHub Releases sync + Screenshot-capable Cloudflare/Brevo feedback form

const REPO = "ChandranilDas/NEELx";
const FEEDBACK_EMAIL = "chandranildas925@gmail.com";

// ---------------------------------------------------------------------------
// 1. Multi-Tab Navigation with Smooth Animated Transitions
// ---------------------------------------------------------------------------
function initTabs() {
  const tabBtns = document.querySelectorAll(".tab-btn[data-tab]");
  const panels = document.querySelectorAll(".tab-panel");

  function activateTab(tabId, pushHash = true) {
    const targetPanel = document.getElementById(`tab-${tabId}`);
    if (!targetPanel) return;

    tabBtns.forEach((btn) => {
      const isMatch = btn.getAttribute("data-tab") === tabId;
      btn.classList.toggle("active", isMatch);
      btn.setAttribute("aria-selected", isMatch ? "true" : "false");
    });

    panels.forEach((panel) => {
      const isMatch = panel.id === `tab-${tabId}`;
      panel.classList.toggle("active", isMatch);
    });

    if (pushHash) {
      history.replaceState(null, "", `#${tabId}`);
    }
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => activateTab(btn.getAttribute("data-tab")));
  });

  document.querySelectorAll("[data-go-tab]").forEach((el) => {
    el.addEventListener("click", () => {
      const dlPlatform = el.getAttribute("data-select-dl");
      if (dlPlatform) {
        selectPlatformGroup("download", dlPlatform);
      }
      activateTab(el.getAttribute("data-go-tab"));
    });
  });

  const initialHash = window.location.hash.replace(/^#/, "");
  if (initialHash && document.getElementById(`tab-${initialHash}`)) {
    activateTab(initialHash, false);
  }
}

function selectPlatformGroup(group, platform) {
  document.querySelectorAll(`.platform-pill[data-platform-group="${group}"]`).forEach((btn) => {
    const isMatch = btn.getAttribute("data-platform") === platform;
    btn.classList.toggle("active", isMatch);
  });
  ["macos", "windows"].forEach((p) => {
    const pane = document.getElementById(`${group}-${p}`);
    if (pane) pane.classList.toggle("active", p === platform);
  });
  if (group === "bench") {
    const sub = document.getElementById("benchSub");
    if (sub) {
      sub.textContent =
        platform === "windows"
          ? "Measured on Windows 11 · ONNX Runtime DirectML (DirectX 12 GPU / Copilot+ NPU)"
          : "Benchmarked on Apple M4 · Runs natively on M1, M2, M3, M4, M5+ & Intel";
    }
  }
}

function initPlatformSwitchers() {
  document.querySelectorAll(".platform-pill[data-platform-group]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const group = btn.getAttribute("data-platform-group");
      const platform = btn.getAttribute("data-platform");
      if (group && platform) {
        selectPlatformGroup(group, platform);
      }
    });
  });

  // Auto-select Windows download & overview pane when visiting from a Windows PC
  if (/Windows/i.test(navigator.userAgent || "")) {
    selectPlatformGroup("overview", "windows");
    selectPlatformGroup("download", "windows");
    selectPlatformGroup("bench", "windows");
  }
}

// ---------------------------------------------------------------------------
// 2. 1-Click Copy Buttons (Commands & SHA-256 Checksums)
// ---------------------------------------------------------------------------
function initCopyButtons() {
  document.querySelectorAll(".btn-copy[data-copy-target]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const selector = btn.getAttribute("data-copy-target");
      const target = selector ? document.querySelector(selector) : null;
      const text = target?.textContent?.trim();
      if (!text) return;

      try {
        await navigator.clipboard.writeText(text);
        const orig = btn.textContent;
        btn.textContent = "Copied ✓";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = orig;
          btn.classList.remove("copied");
        }, 1800);
      } catch {
        // Fallback selection
        const ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        ta.remove();
        btn.textContent = "Copied ✓";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = "Copy";
          btn.classList.remove("copied");
        }, 1800);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// 3. Live GitHub Releases Sync (SemVer-Aware & Downgrade-Protected)
// ---------------------------------------------------------------------------
function parseSemVer(tag) {
  const clean = String(tag || "").replace(/^v/, "").trim();
  const match = clean.match(/^(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.]+))?$/);
  if (!match) return { major: 0, minor: 0, patch: 0, beta: 0, raw: clean };
  const major = parseInt(match[1], 10) || 0;
  const minor = parseInt(match[2], 10) || 0;
  const patch = parseInt(match[3], 10) || 0;
  let beta = 0;
  if (match[4]) {
    const betaMatch = match[4].match(/(?:beta|alpha|rc)\.?(\d+)/i);
    if (betaMatch) {
      beta = parseInt(betaMatch[1], 10) || 0;
    } else {
      const numMatch = match[4].match(/\d+/);
      beta = numMatch ? parseInt(numMatch[0], 10) : 1;
    }
  } else {
    beta = 999999;
  }
  return { major, minor, patch, beta, raw: clean };
}

function compareSemVer(v1, v2) {
  const p1 = parseSemVer(v1);
  const p2 = parseSemVer(v2);
  if (p1.major !== p2.major) return p1.major - p2.major;
  if (p1.minor !== p2.minor) return p1.minor - p2.minor;
  if (p1.patch !== p2.patch) return p1.patch - p2.patch;
  return p1.beta - p2.beta;
}

async function syncLatestRelease() {
  try {
    let latest = null;

    // 1. Try official releases/latest endpoint first
    try {
      const latestRes = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
        headers: { Accept: "application/vnd.github+json" },
      });
      if (latestRes.ok) {
        const item = await latestRes.json();
        if (item && !item.draft && Array.isArray(item.assets) && item.assets.length > 0) {
          latest = item;
        }
      }
    } catch {
      // Fall through to list query
    }

    // 2. Fetch recent releases list (up to 30) and sort descending by SemVer
    let sortedLatest = null;
    let totalDownloads = 0;
    try {
      const listRes = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, {
        headers: { Accept: "application/vnd.github+json" },
      });
      if (listRes.ok) {
        const releases = await listRes.json();
        if (Array.isArray(releases)) {
          // Calculate real cumulative downloads across all historical and current releases
          for (const r of releases) {
            if (Array.isArray(r.assets)) {
              for (const a of r.assets) {
                totalDownloads += (Number(a.download_count) || 0);
              }
            }
          }
          const valid = releases.filter((r) => !r.draft && Array.isArray(r.assets) && r.assets.length > 0);
          valid.sort((a, b) => compareSemVer(b.tag_name, a.tag_name));
          if (valid.length > 0) {
            sortedLatest = valid[0];
          }
        }
      }
    } catch {
      // Ignore network errors
    }

    if (totalDownloads > 0) {
      document.querySelectorAll("[data-total-downloads]").forEach((el) => {
        el.textContent = `${totalDownloads.toLocaleString()}+`;
      });
    }

    // Select the highest SemVer candidate between /releases/latest and sorted list
    if (sortedLatest) {
      if (!latest || compareSemVer(sortedLatest.tag_name, latest.tag_name) > 0) {
        latest = sortedLatest;
      }
    }

    if (!latest) return;

    // 3. Downgrade prevention: never overwrite static HTML with an older version
    const firstVerEl = document.querySelector("[data-release-version]");
    const currentDomTag = firstVerEl ? firstVerEl.textContent.trim() : "";
    if (currentDomTag && compareSemVer(latest.tag_name, currentDomTag) < 0) {
      return;
    }

    const tag = latest.tag_name;
    document.querySelectorAll("[data-release-version]").forEach((el) => {
      el.textContent = tag;
    });

    const macAsset = latest.assets.find((a) => !a.name.includes("lite") && a.name.endsWith(".dmg"));
    const winAsset = latest.assets.find((a) => a.name.includes("windows") && !a.name.includes("lite") && a.name.endsWith(".zip"));

    if (macAsset) {
      const mb = (macAsset.size / (1024 * 1024)).toFixed(1);
      const macBtn = document.getElementById("btnDownloadMac") || document.getElementById("btnDownloadFull");
      const macSize = document.getElementById("macSize") || document.getElementById("fullSize");
      if (macBtn) macBtn.href = macAsset.browser_download_url;
      if (macSize) macSize.textContent = `${mb} MB · Universal`;
    }
    if (winAsset) {
      const mb = (winAsset.size / (1024 * 1024)).toFixed(1);
      const winBtn = document.getElementById("btnDownloadWin") || document.getElementById("btnDownloadWinPortable");
      const winSize = document.getElementById("winSize") || document.getElementById("winPortableSize");
      if (winBtn) winBtn.href = winAsset.browser_download_url;
      if (winSize) winSize.textContent = `${mb} MB · Standalone Win x64`;
    }
  } catch {
    // Keep pre-populated links seamlessly
  }
}

// ---------------------------------------------------------------------------
// Shared Sculpted 3D Human Face Renderer (used across macOS, Windows & Depth Lab)
// ---------------------------------------------------------------------------
function renderSculptedHumanFace(ctx, opts) {
  const {
    cx,
    cy,
    scale = 1,
    yaw = 0,
    pitch = 0,
    blinkPhase = 0,
    strokeMain = "rgba(245, 245, 247, 0.90)",
    strokeSoft = "rgba(255, 255, 255, 0.26)",
    fillTop = "rgba(235, 238, 245, 0.22)",
    fillMid = "rgba(120, 126, 140, 0.12)",
    fillEdge = "rgba(20, 24, 34, 0.45)",
    pupilColor = "#f5f5f7",
    showShoulders = true,
    showMeridians = true,
    smileBoost = 0,
    lineWidthScale = 1,
    shadowGlow = null,
  } = opts;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(scale, scale);

  if (shadowGlow) {
    ctx.shadowColor = shadowGlow;
    ctx.shadowBlur = 10;
  }

  // 3D parallax offsets (nose shifts farthest, jaw/head shifts least)
  const headX = yaw * 6.5;
  const headY = pitch * 5.5;
  const midX = yaw * 12;
  const midY = pitch * 9;
  const noseX = yaw * 18;
  const noseY = pitch * 13;

  // Neck & shoulders silhouette
  if (showShoulders) {
    ctx.fillStyle = "rgba(255, 255, 255, 0.05)";
    ctx.strokeStyle = strokeSoft;
    ctx.lineWidth = 1.1 * lineWidthScale;
    ctx.beginPath();
    ctx.ellipse(headX * 0.45, 56 + headY * 0.25, 38, 18, 0, Math.PI, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  }

  // Sculpted 3D head contour (forehead -> cheekbones -> tapered jaw -> chin)
  const faceGrad = ctx.createRadialGradient(noseX - 6, noseY - 10, 4, headX, headY, 44);
  faceGrad.addColorStop(0, fillTop);
  faceGrad.addColorStop(0.55, fillMid);
  faceGrad.addColorStop(1, fillEdge);

  ctx.fillStyle = faceGrad;
  ctx.strokeStyle = strokeMain;
  ctx.lineWidth = 1.65 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(headX, headY - 37);
  ctx.bezierCurveTo(headX + 26, headY - 37, headX + 31, headY - 13, headX + 27, headY + 6);
  ctx.bezierCurveTo(headX + 24, headY + 23, headX + 13, headY + 37, headX, headY + 40);
  ctx.bezierCurveTo(headX - 13, headY + 37, headX - 24, headY + 23, headX - 27, headY + 6);
  ctx.bezierCurveTo(headX - 31, headY - 13, headX - 26, headY - 37, headX, headY - 37);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Subtle 3D topographic contour meridians
  if (showMeridians) {
    ctx.strokeStyle = strokeSoft;
    ctx.lineWidth = 0.9 * lineWidthScale;
    ctx.beginPath();
    ctx.moveTo(headX, headY - 36);
    ctx.quadraticCurveTo(noseX, noseY, headX, headY + 39);
    ctx.moveTo(headX - 26, headY - 6);
    ctx.quadraticCurveTo(midX, midY - 2, headX + 26, headY - 6);
    ctx.moveTo(headX - 23, headY + 12);
    ctx.quadraticCurveTo(midX, midY + 16, headX + 23, headY + 12);
    ctx.stroke();
  }

  // Sculpted eyebrows
  ctx.strokeStyle = strokeMain;
  ctx.lineWidth = 1.9 * lineWidthScale;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(midX - 18.5, midY - 13.5);
  ctx.quadraticCurveTo(midX - 11.5, midY - 17.5, midX - 4, midY - 13.5);
  ctx.moveTo(midX + 4, midY - 13.5);
  ctx.quadraticCurveTo(midX + 11.5, midY - 17.5, midX + 18.5, midY - 13.5);
  ctx.stroke();

  // Expressive eyes (periodic blink + pupil tracking)
  const eyeOpen = blinkPhase > 0.94 ? 0.16 : 1.0;
  for (const side of [-1, 1]) {
    const ex = midX + side * 11.8;
    const ey = midY - 6;
    ctx.fillStyle = "rgba(8, 10, 14, 0.72)";
    ctx.strokeStyle = strokeMain;
    ctx.lineWidth = 1.3 * lineWidthScale;
    ctx.beginPath();
    ctx.ellipse(ex, ey, 5.6, 2.8 * eyeOpen, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    if (eyeOpen > 0.5) {
      ctx.fillStyle = pupilColor;
      ctx.beginPath();
      ctx.arc(ex + yaw * 1.4, ey + pitch * 0.9, 1.9, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // Protruding 3D nose bridge + tip + wings
  ctx.strokeStyle = strokeMain;
  ctx.lineWidth = 1.55 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(midX, midY - 11);
  ctx.quadraticCurveTo(noseX, noseY - 1, noseX, noseY + 7.5);
  ctx.quadraticCurveTo(noseX - 4.2, noseY + 10.2, noseX - 5.8, noseY + 8.6);
  ctx.moveTo(noseX, noseY + 7.5);
  ctx.quadraticCurveTo(noseX + 4.2, noseY + 10.2, noseX + 5.8, noseY + 8.6);
  ctx.stroke();

  // Sculpted upper & lower lips
  ctx.strokeStyle = strokeMain;
  ctx.lineWidth = 1.6 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(midX - 9.5, midY + 18.5);
  ctx.quadraticCurveTo(midX, midY + 21 + smileBoost, midX + 9.5, midY + 18.5);
  ctx.stroke();

  ctx.strokeStyle = strokeSoft;
  ctx.lineWidth = 1.15 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(midX - 5.5, midY + 22);
  ctx.quadraticCurveTo(midX, midY + 24.2 + smileBoost * 0.5, midX + 5.5, midY + 22);
  ctx.stroke();

  ctx.restore();
}

// ---------------------------------------------------------------------------
// 4. Interactive 80-Tick 360° Notch Ring with Proper Sculpted 3D Human Face
// ---------------------------------------------------------------------------
function initEnrollmentSimulator() {
  const canvas = document.getElementById("enrollmentCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const size = 248;
  canvas.width = size * dpr;
  canvas.height = size * dpr;
  ctx.scale(dpr, dpr);

  const statusEl = document.getElementById("enrollmentStatus");
  const demoBtn = document.getElementById("btnSimulateSweep");
  const resetBtn = document.getElementById("btnResetSweep");

  const tickCount = 80;
  const capturedSectors = new Set();
  let pointerYaw = 0;   // -1 .. 1
  let pointerPitch = 0; // -1 .. 1
  let targetYaw = 0;
  let targetPitch = 0;
  let pointerAngle = null;
  let autoAnimating = false;
  let autoAngle = 0;
  let blinkPhase = 0;

  function drawSculpted3DFace(cx, cy, yaw, pitch, isComplete) {
    ctx.save();
    ctx.translate(cx, cy);

    // Subtle dark-glass camera vignette circle behind the face
    const bgGrad = ctx.createRadialGradient(yaw * 10, pitch * 8 - 8, 6, 0, 0, 62);
    bgGrad.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.16)" : "rgba(255, 255, 255, 0.08)");
    bgGrad.addColorStop(1, "rgba(8, 9, 12, 0.92)");
    ctx.fillStyle = bgGrad;
    ctx.beginPath();
    ctx.arc(0, 0, 61, 0, Math.PI * 2);
    ctx.fill();

    // Clip to camera lens circle
    ctx.beginPath();
    ctx.arc(0, 0, 60, 0, Math.PI * 2);
    ctx.clip();

    // 3D parallax offsets (closer features like nose shift more than ears/jaw)
    const headX = yaw * 7;
    const headY = pitch * 6;
    const midX = yaw * 13;
    const midY = pitch * 10;
    const noseX = yaw * 19;
    const noseY = pitch * 14;

    const strokeMain = isComplete ? "rgba(48, 209, 88, 0.92)" : "rgba(245, 245, 247, 0.86)";
    const strokeSoft = isComplete ? "rgba(48, 209, 88, 0.35)" : "rgba(255, 255, 255, 0.24)";

    // Neck & shoulders silhouette
    ctx.fillStyle = "rgba(255, 255, 255, 0.05)";
    ctx.beginPath();
    ctx.ellipse(headX * 0.5, 56 + headY * 0.3, 38, 19, 0, Math.PI, Math.PI * 2);
    ctx.fill();

    // Sculpted 3D head silhouette with subtle lighting gradient
    const faceGrad = ctx.createRadialGradient(
      noseX - 6, noseY - 10, 4,
      headX, headY, 44
    );
    faceGrad.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.24)" : "rgba(235, 238, 245, 0.20)");
    faceGrad.addColorStop(0.55, "rgba(120, 126, 140, 0.11)");
    faceGrad.addColorStop(1, "rgba(25, 28, 36, 0.45)");

    ctx.fillStyle = faceGrad;
    ctx.strokeStyle = strokeMain;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    // Forehead -> cheeks -> tapered jawline -> chin
    ctx.moveTo(headX, headY - 36);
    ctx.bezierCurveTo(headX + 26, headY - 36, headX + 30, headY - 12, headX + 27, headY + 6);
    ctx.bezierCurveTo(headX + 25, headY + 23, headX + 13, headY + 37, headX, headY + 39);
    ctx.bezierCurveTo(headX - 13, headY + 37, headX - 25, headY + 23, headX - 27, headY + 6);
    ctx.bezierCurveTo(headX - 30, headY - 12, headX - 26, headY - 36, headX, headY - 36);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();

    // Subtle 3D mesh contour meridians (gives true TrueDepth 3D topography feel)
    ctx.strokeStyle = strokeSoft;
    ctx.lineWidth = 0.85;
    ctx.beginPath();
    ctx.moveTo(headX, headY - 35);
    ctx.quadraticCurveTo(noseX, noseY, headX, headY + 38);
    ctx.moveTo(headX - 25, headY - 6);
    ctx.quadraticCurveTo(midX, midY - 2, headX + 25, headY - 6);
    ctx.moveTo(headX - 23, headY + 12);
    ctx.quadraticCurveTo(midX, midY + 16, headX + 23, headY + 12);
    ctx.stroke();

    // Eyebrows
    ctx.strokeStyle = strokeMain;
    ctx.lineWidth = 1.8;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(midX - 18, midY - 13);
    ctx.quadraticCurveTo(midX - 11, midY - 17, midX - 4, midY - 13);
    ctx.moveTo(midX + 4, midY - 13);
    ctx.quadraticCurveTo(midX + 11, midY - 17, midX + 18, midY - 13);
    ctx.stroke();

    // Expressive eyes (with natural periodic blink + pupil tracking)
    const eyeOpen = blinkPhase > 0.94 ? 0.18 : 1.0;
    for (const side of [-1, 1]) {
      const ex = midX + side * 11.5;
      const ey = midY - 6;
      ctx.fillStyle = "rgba(10, 12, 16, 0.7)";
      ctx.strokeStyle = strokeMain;
      ctx.lineWidth = 1.25;
      ctx.beginPath();
      ctx.ellipse(ex, ey, 5.4, 2.7 * eyeOpen, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();

      if (eyeOpen > 0.5) {
        ctx.fillStyle = isComplete ? "#30d158" : "#f5f5f7";
        ctx.beginPath();
        ctx.arc(ex + yaw * 1.4, ey + pitch * 0.9, 1.8, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // Sculpted 3D nose bridge + protruding tip (shifts farthest for authentic 3D parallax)
    ctx.strokeStyle = strokeMain;
    ctx.lineWidth = 1.45;
    ctx.beginPath();
    ctx.moveTo(midX, midY - 11);
    ctx.quadraticCurveTo(noseX, noseY - 1, noseX, noseY + 7);
    ctx.quadraticCurveTo(noseX - 4, noseY + 10, noseX - 5.5, noseY + 8.5);
    ctx.moveTo(noseX, noseY + 7);
    ctx.quadraticCurveTo(noseX + 4, noseY + 10, noseX + 5.5, noseY + 8.5);
    ctx.stroke();

    // Soft sculpted lips
    ctx.strokeStyle = strokeMain;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(midX - 9, midY + 18);
    ctx.quadraticCurveTo(midX, midY + (isComplete ? 22.5 : 20.5), midX + 9, midY + 18);
    ctx.stroke();

    // Subtle lower lip highlight
    ctx.strokeStyle = strokeSoft;
    ctx.lineWidth = 1.1;
    ctx.beginPath();
    ctx.moveTo(midX - 5.5, midY + 21.5);
    ctx.quadraticCurveTo(midX, midY + 23.5, midX + 5.5, midY + 21.5);
    ctx.stroke();

    ctx.restore();
  }

  function render() {
    ctx.clearRect(0, 0, size, size);
    const cx = size / 2;
    const cy = size / 2;
    const innerR = 72;
    const baseLen = 15;
    const complete = capturedSectors.size >= 8;

    // Smoothly interpolate head pose
    pointerYaw += (targetYaw - pointerYaw) * 0.16;
    pointerPitch += (targetPitch - pointerPitch) * 0.16;
    blinkPhase = (blinkPhase + 0.008) % 1;

    // Draw 80 radial Apple-style Face ID ticks
    for (let i = 0; i < tickCount; i++) {
      const deg = (i / tickCount) * 360;
      const rad = ((deg - 90) * Math.PI) / 180;
      const sector = Math.floor(((deg + 22.5) % 360) / 45);
      const isCaptured = capturedSectors.has(sector);

      let extraLen = 0;
      let isActive = false;
      if (pointerAngle !== null) {
        let diff = Math.abs(deg - pointerAngle);
        if (diff > 180) diff = 360 - diff;
        if (diff < 24) {
          isActive = true;
          extraLen = (1 - diff / 24) * 8;
        }
      }

      const len = baseLen + (isCaptured ? 4.5 : 0) + extraLen;
      const x1 = cx + Math.cos(rad) * innerR;
      const y1 = cy + Math.sin(rad) * innerR;
      const x2 = cx + Math.cos(rad) * (innerR + len);
      const y2 = cy + Math.sin(rad) * (innerR + len);

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.lineWidth = isCaptured || isActive ? 2.5 : 1.7;
      ctx.lineCap = "round";
      if (isCaptured) {
        ctx.strokeStyle = "#30d158";
      } else if (isActive) {
        ctx.strokeStyle = "#f5f5f7";
      } else {
        ctx.strokeStyle = "rgba(255, 255, 255, 0.18)";
      }
      ctx.stroke();
    }

    drawSculpted3DFace(cx, cy, pointerYaw, pointerPitch, complete);

    if (statusEl) {
      if (complete) {
        statusEl.innerHTML = `<strong>360° 3D Face Profile Complete</strong> · 8 / 8 sectors`;
      } else {
        statusEl.innerHTML = `Move cursor around the face · <strong>${capturedSectors.size} / 8 sectors</strong>`;
      }
    }

    requestAnimationFrame(render);
  }

  function updateFromCoords(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const dx = clientX - (rect.left + rect.width / 2);
    const dy = clientY - (rect.top + rect.height / 2);
    const maxR = rect.width * 0.45;
    targetYaw = Math.max(-1, Math.min(1, dx / maxR));
    targetPitch = Math.max(-1, Math.min(1, dy / maxR));
    const dist = Math.hypot(dx, dy);
    if (dist < 14) return;
    let deg = (Math.atan2(dy, dx) * 180) / Math.PI + 90;
    if (deg < 0) deg += 360;
    pointerAngle = deg;
    const sector = Math.floor(((deg + 22.5) % 360) / 45);
    capturedSectors.add(sector);
  }

  canvas.addEventListener("pointermove", (e) => {
    if (!autoAnimating) updateFromCoords(e.clientX, e.clientY);
  });

  canvas.addEventListener("pointerleave", () => {
    if (!autoAnimating) {
      pointerAngle = null;
      targetYaw = 0;
      targetPitch = 0;
    }
  });

  demoBtn?.addEventListener("click", () => {
    capturedSectors.clear();
    autoAnimating = true;
    autoAngle = 0;
    function step() {
      if (!autoAnimating) return;
      const rad = ((autoAngle - 90) * Math.PI) / 180;
      pointerAngle = autoAngle % 360;
      targetYaw = Math.cos(rad) * 0.85;
      targetPitch = Math.sin(rad) * 0.85;
      const sector = Math.floor(((pointerAngle + 22.5) % 360) / 45);
      capturedSectors.add(sector);
      autoAngle += 6;
      if (autoAngle <= 370) {
        requestAnimationFrame(step);
      } else {
        autoAnimating = false;
        pointerAngle = null;
        targetYaw = 0;
        targetPitch = 0;
      }
    }
    requestAnimationFrame(step);
  });

  resetBtn?.addEventListener("click", () => {
    autoAnimating = false;
    capturedSectors.clear();
    pointerAngle = null;
    targetYaw = 0;
    targetPitch = 0;
  });

  render();
}

// ---------------------------------------------------------------------------
// 5. Interactive Backlit HDR Shadow Recovery Canvas + Studio Light Preview
// ---------------------------------------------------------------------------
function initHowItWorksDemos() {
  const hdrCanvas = document.getElementById("hdrCanvas");
  const hdrSlider = document.getElementById("hdrSlider");
  if (hdrCanvas && hdrSlider) {
    const ctx = hdrCanvas.getContext("2d");
    const W = hdrCanvas.width;
    const H = hdrCanvas.height;

    function drawBacklitDemo(splitPct) {
      const splitX = (splitPct / 100) * W;
      ctx.clearRect(0, 0, W, H);

      // Left side (Raw backlit silhouette: blown-out evening window, pitch-dark face)
      function renderHalf(isHDR) {
        // Evening sunlit window background
        const sunGrad = ctx.createLinearGradient(0, 0, W, H);
        if (isHDR) {
          sunGrad.addColorStop(0, "#7c6a53");
          sunGrad.addColorStop(0.5, "#b7996e");
          sunGrad.addColorStop(1, "#3d3935");
        } else {
          sunGrad.addColorStop(0, "#ffe4ad");
          sunGrad.addColorStop(0.45, "#fff8e1");
          sunGrad.addColorStop(1, "#b89f74");
        }
        ctx.fillStyle = sunGrad;
        ctx.fillRect(0, 0, W, H);

        // Window mullion lines
        ctx.strokeStyle = isHDR ? "rgba(20,22,26,0.38)" : "rgba(255,255,255,0.45)";
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(W * 0.25, 0); ctx.lineTo(W * 0.25, H);
        ctx.moveTo(W * 0.75, 0); ctx.lineTo(W * 0.75, H);
        ctx.moveTo(0, H * 0.45); ctx.lineTo(W, H * 0.45);
        ctx.stroke();

        // User shoulders & head in center
        const cx = W * 0.5;
        const cy = H * 0.48;
        ctx.fillStyle = isHDR ? "#3a3634" : "#0b0b0d";
        ctx.beginPath();
        ctx.ellipse(cx, H + 12, 95, 58, 0, Math.PI, Math.PI * 2);
        ctx.fill();

        const skinGrad = ctx.createRadialGradient(cx - 6, cy - 8, 6, cx, cy, 56);
        if (isHDR) {
          skinGrad.addColorStop(0, "#d8aa88");
          skinGrad.addColorStop(0.65, "#9c7054");
          skinGrad.addColorStop(1, "#5c4132");
        } else {
          skinGrad.addColorStop(0, "#1d1a19");
          skinGrad.addColorStop(0.7, "#111011");
          skinGrad.addColorStop(1, "#070708");
        }
        ctx.fillStyle = skinGrad;
        ctx.beginPath();
        ctx.ellipse(cx, cy, 42, 54, 0, 0, Math.PI * 2);
        ctx.fill();

        // Facial landmarks visible on HDR side
        if (isHDR) {
          ctx.strokeStyle = "rgba(48, 209, 88, 0.85)";
          ctx.lineWidth = 1.4;
          ctx.strokeRect(cx - 46, cy - 58, 92, 116);
          ctx.fillStyle = "#30d158";
          for (const [px, py] of [[cx - 15, cy - 8], [cx + 15, cy - 8], [cx, cy + 8], [cx - 11, cy + 25], [cx + 11, cy + 25]]) {
            ctx.beginPath();
            ctx.arc(px, py, 2.5, 0, Math.PI * 2);
            ctx.fill();
          }
          ctx.fillStyle = "rgba(17, 18, 21, 0.82)";
          ctx.fillRect(W - 154, 12, 142, 24);
          ctx.fillStyle = "#30d158";
          ctx.font = "600 10.5px ui-monospace, Menlo, monospace";
          ctx.fillText("HDR FACE DETECTED", W - 144, 28);
        } else {
          ctx.fillStyle = "rgba(17, 18, 21, 0.82)";
          ctx.fillRect(12, 12, 140, 24);
          ctx.fillStyle = "#ff8078";
          ctx.font = "600 10.5px ui-monospace, Menlo, monospace";
          ctx.fillText("RAW · SILHOUETTE", 22, 28);
        }
      }

      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, splitX, H);
      ctx.clip();
      renderHalf(false);
      ctx.restore();

      ctx.save();
      ctx.beginPath();
      ctx.rect(splitX, 0, W - splitX, H);
      ctx.clip();
      renderHalf(true);
      ctx.restore();

      // Divider line
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(splitX, 0);
      ctx.lineTo(splitX, H);
      ctx.stroke();
    }

    hdrSlider.addEventListener("input", () => drawBacklitDemo(Number(hdrSlider.value)));
    drawBacklitDemo(Number(hdrSlider.value));
  }

  // Studio Light Preview switcher
  const box = document.getElementById("studioPreviewBox");
  const lbl = document.getElementById("studioPreviewLabel");
  document.querySelectorAll("[data-studio-mode]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const mode = btn.getAttribute("data-studio-mode");
      box.className = "studio-box";
      if (mode === "warm") {
        box.classList.add("mode-warm");
        lbl.textContent = "Warm 3800K Studio Light Rim · Active";
      } else if (mode === "cyan") {
        box.classList.add("mode-cyan");
        lbl.textContent = "Cyan Spectral Prism Rim · Anti-Replay";
      } else if (mode === "magenta") {
        box.classList.add("mode-magenta");
        lbl.textContent = "Magenta Spectral Prism Rim · Anti-Replay";
      } else {
        lbl.textContent = "Ambient Room Sufficient · Illumination Off";
      }
    });
  });
}

// ---------------------------------------------------------------------------
// 6. Interactive Stage 3 Neural 3D Depth Heatmap & Cross-Section Visualizer
// ---------------------------------------------------------------------------
function infernoColor(t) {
  const stops = [
    [0.0, 13, 8, 41],
    [0.25, 87, 15, 110],
    [0.5, 188, 55, 84],
    [0.75, 249, 142, 9],
    [1.0, 252, 255, 164],
  ];
  const clamped = Math.max(0, Math.min(1, t));
  for (let i = 0; i < stops.length - 1; i++) {
    const s0 = stops[i];
    const s1 = stops[i + 1];
    if (clamped >= s0[0] && clamped <= s1[0]) {
      const f = (clamped - s0[0]) / (s1[0] - s0[0]);
      return [
        Math.round(s0[1] + f * (s1[1] - s0[1])),
        Math.round(s0[2] + f * (s1[2] - s0[2])),
        Math.round(s0[3] + f * (s1[3] - s0[3])),
      ];
    }
  }
  return [252, 255, 164];
}

function initDepthLab() {
  const canvas = document.getElementById("depthHeatmapCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const W = 460;
  const H = 310;
  canvas.width = W;
  canvas.height = H;

  const btnReal = document.getElementById("btnModeReal");
  const btnSpoof = document.getElementById("btnModeSpoof");
  const btnToggleScan = document.getElementById("btnToggleDepthScan");
  const verdictEl = document.getElementById("depthVerdict");

  const cx = W * 0.5;
  const cy = H * 0.41;

  function setBar(id, valText, pct, color) {
    const vEl = document.getElementById(`${id}Val`);
    const bEl = document.getElementById(`${id}Bar`);
    if (vEl) vEl.textContent = valText;
    if (bEl) {
      bEl.style.width = `${Math.max(2, Math.min(100, pct))}%`;
      bEl.style.background = color;
    }
  }

  // Pre-compute high-resolution anatomical 3D depth maps & offscreen base images for silky 60 FPS animated scan
  function buildDepthScene(mode) {
    const off = document.createElement("canvas");
    off.width = W;
    off.height = H;
    const octx = off.getContext("2d");
    const img = octx.createImageData(W, H);
    const data = img.data;
    const grid = new Float32Array(W * H);

    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let d = 0.06 + 0.045 * (y / H);

        if (mode === "real") {
          // Shoulders & neck
          const sx = (x - cx) / 142;
          const sy = (y - (H - 36)) / 56;
          if (sx * sx + sy * sy < 1) {
            const sh = Math.sqrt(Math.max(0, 1 - sx * sx - sy * sy));
            d = Math.max(d, 0.34 + sh * 0.16);
          }
          const neckX = (x - cx) / 28;
          const neckY = (y - (cy + 86)) / 36;
          if (Math.abs(neckX) < 1 && neckY > -0.7 && neckY < 1.1) {
            d = Math.max(d, 0.42 + Math.sqrt(Math.max(0, 1 - neckX * neckX)) * 0.14);
          }

          // Anatomically tapered human head shape (wider at temples/cheeks, tapered jawline/chin)
          const dy = y - cy;
          const halfW = dy < 0 ? 64 : Math.max(22, 64 - (dy / 88) * 26);
          const nx = (x - cx) / halfW;
          const ny = dy / 86;
          const r2 = nx * nx + ny * ny;

          if (r2 < 1.0) {
            const dome = Math.sqrt(1 - r2);
            let faceD = 0.50 + dome * 0.27;

            // Forehead / brow ridge slight prominence
            const brow = ((x - cx) / 44) ** 2 + ((y - (cy - 28)) / 10) ** 2;
            faceD += Math.exp(-brow * 2.2) * 0.045;

            // Deep twin recessed eye sockets (creates unmistakable twin valleys in z(x)!)
            const el = ((x - (cx - 23)) / 15) ** 2 + ((y - (cy - 12)) / 10.5) ** 2;
            const er = ((x - (cx + 23)) / 15) ** 2 + ((y - (cy - 12)) / 10.5) ** 2;
            faceD -= Math.exp(-el * 2.1) * 0.115;
            faceD -= Math.exp(-er * 2.1) * 0.115;

            // Sculpted cheekbone prominences
            const cl = ((x - (cx - 28)) / 18) ** 2 + ((y - (cy + 10)) / 14) ** 2;
            const cr = ((x - (cx + 28)) / 18) ** 2 + ((y - (cy + 10)) / 14) ** 2;
            faceD += Math.exp(-cl * 2.0) * 0.045;
            faceD += Math.exp(-cr * 2.0) * 0.045;

            // Sharp protruding 3D nose bridge + nose tip (peaks brightest in Inferno!)
            const noseBridge = ((x - cx) / 9) ** 2 + ((y - (cy - 2)) / 24) ** 2;
            const noseTip = ((x - cx) / 11.5) ** 2 + ((y - (cy + 13)) / 11) ** 2;
            faceD += Math.exp(-noseBridge * 2.1) * 0.135;
            faceD += Math.exp(-noseTip * 2.2) * 0.195;

            // Sculpted lips & chin relief
            const lips = ((x - cx) / 21) ** 2 + ((y - (cy + 36)) / 8.5) ** 2;
            const chin = ((x - cx) / 18) ** 2 + ((y - (cy + 58)) / 13) ** 2;
            faceD += Math.exp(-lips * 2.3) * 0.055;
            faceD += Math.exp(-chin * 2.0) * 0.048;

            d = Math.max(d, Math.min(0.99, faceD));
          }
        } else {
          // 2D Phone / Photo Spoof: rounded smartphone held upright at uniform flat depth plane
          const px = Math.abs(x - cx);
          const py = Math.abs(y - cy);
          const halfPW = 78;
          const halfPH = 104;
          const cornerR = 16;
          const dxC = Math.max(0, px - (halfPW - cornerR));
          const dyC = Math.max(0, py - (halfPH - cornerR));
          const insidePhone = dxC * dxC + dyC * dyC <= cornerR * cornerR && px <= halfPW && py <= halfPH;
          if (insidePhone) {
            // Flat coplanar screen surface (tiny natural linear camera tilt, ZERO facial 3D relief)
            d = 0.565 + ((x - cx) / W) * 0.025 + ((y - cy) / H) * 0.018;
          }
        }

        grid[y * W + x] = d;
        const [r, g, b] = infernoColor(d);
        const idx = (y * W + x) * 4;
        data[idx] = r;
        data[idx + 1] = g;
        data[idx + 2] = b;
        data[idx + 3] = 255;
      }
    }

    octx.putImageData(img, 0, 0);

    if (mode === "real") {
      // Crisp translucent 3D sculpted topographic face overlay so it unmistakably reads as a real human face
      renderSculptedHumanFace(octx, {
        cx,
        cy: cy + 2,
        scale: 1.92,
        yaw: 0,
        pitch: 0,
        blinkPhase: 0,
        strokeMain: "rgba(255, 250, 232, 0.52)",
        strokeSoft: "rgba(255, 240, 200, 0.24)",
        fillTop: "rgba(255, 255, 255, 0.02)",
        fillMid: "rgba(255, 255, 255, 0)",
        fillEdge: "rgba(0, 0, 0, 0)",
        pupilColor: "rgba(255, 252, 238, 0.65)",
        showShoulders: false,
        showMeridians: true,
        lineWidthScale: 0.72,
      });
    } else {
      // Realistic smartphone bezel + Dynamic Island + subtle glass reflection displaying a proper sculpted human face photo!
      const px = cx - 78;
      const py = cy - 104;
      const pw = 156;
      const ph = 208;

      octx.save();
      octx.strokeStyle = "rgba(255, 255, 255, 0.58)";
      octx.lineWidth = 2.4;
      octx.beginPath();
      octx.roundRect(px, py, pw, ph, 16);
      octx.stroke();

      // Inner screen bezel
      octx.strokeStyle = "rgba(10, 12, 18, 0.65)";
      octx.lineWidth = 5;
      octx.beginPath();
      octx.roundRect(px + 4, py + 4, pw - 8, ph - 8, 12);
      octx.stroke();

      // Top camera pill on spoof phone
      octx.fillStyle = "rgba(10, 12, 18, 0.85)";
      octx.beginPath();
      octx.roundRect(cx - 18, py + 10, 36, 9, 5);
      octx.fill();

      // Clip inside phone display & draw the flat 2D photo of a proper sculpted human face
      octx.beginPath();
      octx.roundRect(px + 6, py + 6, pw - 12, ph - 12, 11);
      octx.clip();

      renderSculptedHumanFace(octx, {
        cx,
        cy: cy + 8,
        scale: 1.55,
        yaw: 0,
        pitch: 0,
        blinkPhase: 0,
        strokeMain: "rgba(255, 236, 230, 0.78)",
        strokeSoft: "rgba(255, 210, 200, 0.25)",
        fillTop: "rgba(255, 255, 255, 0.08)",
        fillMid: "rgba(255, 255, 255, 0.03)",
        fillEdge: "rgba(0, 0, 0, 0.12)",
        pupilColor: "rgba(255, 240, 236, 0.85)",
        showShoulders: true,
        showMeridians: false,
        lineWidthScale: 0.78,
      });

      // Diagonal OLED specular glass glare across the flat phone photo
      const glare = octx.createLinearGradient(px, py, px + pw, py + ph);
      glare.addColorStop(0.28, "rgba(255,255,255,0)");
      glare.addColorStop(0.45, "rgba(255,255,255,0.16)");
      glare.addColorStop(0.58, "rgba(255,255,255,0)");
      octx.fillStyle = glare;
      octx.fillRect(px, py, pw, ph);

      // Small corner label inside phone
      octx.fillStyle = "rgba(12, 14, 20, 0.75)";
      octx.beginPath();
      octx.roundRect(px + 12, py + ph - 28, pw - 24, 18, 5);
      octx.fill();
      octx.fillStyle = "#ff9b95";
      octx.font = "600 9.5px ui-monospace, Menlo, monospace";
      octx.textAlign = "center";
      octx.fillText("2D PHOTO ON PHONE SCREEN", cx, py + ph - 16);
      octx.restore();
    }

    return { off, grid };
  }

  const scenes = {
    real: buildDepthScene("real"),
    spoof: buildDepthScene("spoof"),
  };

  let activeMode = "real";
  let scanPaused = false;
  let manualScanY = null;
  let sweepPhase = 0.56; // starts right near the protruding nose tip!

  function updateTelemetry(mode) {
    if (mode === "real") {
      setBar("mNose", "+0.084", 84, "#30d158");
      setBar("mCurve", "0.071", 78, "#30d158");
      setBar("mCliff", "0.46", 82, "#30d158");
      setBar("mSpoof", "4%", 4, "#30d158");
      if (verdictEl) {
        verdictEl.textContent = "PASS · 3D FACE VERIFIED (22.6 ms ANE)";
        verdictEl.className = "verdict-pill verdict-pass";
      }
    } else {
      setBar("mNose", "+0.004", 6, "#ff453a");
      setBar("mCurve", "0.009", 10, "#ff453a");
      setBar("mCliff", "0.02", 5, "#ff453a");
      setBar("mSpoof", "94%", 94, "#ff453a");
      if (verdictEl) {
        verdictEl.textContent = "BLOCKED · FLAT 2D SPOOF DETECTED";
        verdictEl.className = "verdict-pill verdict-deny";
      }
    }
  }

  function sliceLabel(mode, y) {
    if (mode === "spoof") {
      return "z(x): Flat coplanar plateau — 2D photo on phone has zero nose relief";
    }
    const rel = y - cy;
    if (rel < -22) return "z(x): Rounded 3D Forehead & Brow Dome";
    if (rel < -2) return "z(x): Twin Recessed Eye Socket Valleys + Nasal Bridge";
    if (rel < 24) return "z(x): Sharp Protruding 3D Nose Tip Peak (+0.084) + Room Cliff";
    if (rel < 46) return "z(x): Sculpted Lips & Tapered Cheek Relief";
    return "z(x): Defined Chin Contour + Head-to-Background Cliff";
  }

  canvas.addEventListener("pointermove", (e) => {
    const r = canvas.getBoundingClientRect();
    const py = ((e.clientY - r.top) / r.height) * H;
    manualScanY = Math.max(36, Math.min(H - 70, py));
  });

  canvas.addEventListener("pointerleave", () => {
    manualScanY = null;
  });

  btnReal?.addEventListener("click", () => {
    activeMode = "real";
    btnReal.classList.add("active");
    btnSpoof?.classList.remove("active");
    updateTelemetry("real");
  });

  btnSpoof?.addEventListener("click", () => {
    activeMode = "spoof";
    btnSpoof.classList.add("active");
    btnReal?.classList.remove("active");
    updateTelemetry("spoof");
  });

  btnToggleScan?.addEventListener("click", () => {
    scanPaused = !scanPaused;
    btnToggleScan.textContent = scanPaused ? "Resume Scan" : "Pause Scan";
  });

  updateTelemetry("real");

  function frame() {
    const scene = scenes[activeMode];
    ctx.clearRect(0, 0, W, H);
    ctx.drawImage(scene.off, 0, 0);

    // Calm, gracefully paced vertical scanline sweep (~6.5s full down-and-up cycle)
    if (!scanPaused && manualScanY === null) {
      sweepPhase += 0.0065;
    }
    const autoY = (cy - 68) + ((Math.sin(sweepPhase) + 1) * 0.5) * 136;
    const scanY = Math.round(manualScanY !== null ? manualScanY : autoY);

    // Luminous horizontal depth-probe laser line
    const lineAccent = activeMode === "real" ? "#30d158" : "#ff453a";
    const glowGrad = ctx.createLinearGradient(0, scanY - 8, 0, scanY + 8);
    glowGrad.addColorStop(0, "rgba(0,0,0,0)");
    glowGrad.addColorStop(0.5, activeMode === "real" ? "rgba(48, 209, 88, 0.34)" : "rgba(255, 69, 58, 0.34)");
    glowGrad.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = glowGrad;
    ctx.fillRect(0, scanY - 8, W, 16);

    ctx.strokeStyle = activeMode === "real" ? "rgba(180, 255, 200, 0.85)" : "rgba(255, 165, 160, 0.85)";
    ctx.lineWidth = 1.4;
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    ctx.moveTo(0, scanY);
    ctx.lineTo(W, scanY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Live cross-section z(x) waveform box at bottom
    const boxH = 62;
    ctx.fillStyle = "rgba(8, 10, 14, 0.84)";
    ctx.fillRect(0, H - boxH, W, boxH);
    ctx.strokeStyle = "rgba(255, 255, 255, 0.1)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, H - boxH);
    ctx.lineTo(W, H - boxH);
    ctx.stroke();

    // Waveform fill + crisp stroke sampled live from depthGrid[scanY]
    const rowOffset = scanY * W;
    ctx.beginPath();
    ctx.moveTo(0, H - 6);
    for (let x = 0; x < W; x++) {
      const d = scene.grid[rowOffset + x];
      const py = H - 7 - d * 38;
      ctx.lineTo(x, py);
    }
    ctx.lineTo(W, H - 6);
    ctx.closePath();
    ctx.fillStyle = activeMode === "real" ? "rgba(48, 209, 88, 0.14)" : "rgba(255, 69, 58, 0.14)";
    ctx.fill();

    ctx.strokeStyle = lineAccent;
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let x = 0; x < W; x++) {
      const d = scene.grid[rowOffset + x];
      const py = H - 7 - d * 38;
      if (x === 0) ctx.moveTo(x, py);
      else ctx.lineTo(x, py);
    }
    ctx.stroke();

    ctx.fillStyle = "rgba(245, 245, 247, 0.86)";
    ctx.font = "500 10.5px ui-monospace, Menlo, monospace";
    ctx.textAlign = "left";
    ctx.fillText(sliceLabel(activeMode, scanY), 12, H - boxH + 16);

    requestAnimationFrame(frame);
  }

  frame();
}

// ---------------------------------------------------------------------------
// 7. Windows 11 Fluent Prism Core — Studio-Grade Kinetic 3D Orbital Renderer
//    (Matches real Windows 11 PrismHorizonOverlay.xaml + macOS studio quality)
// ---------------------------------------------------------------------------
function draw3DOrbitalRing(ctx, cx, cy, radius, tiltX, rotZ, strokeColor, glowColor, lineWidth, alpha) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(rotZ);
  ctx.scale(1, Math.max(0.14, Math.abs(tiltX)));
  ctx.globalAlpha = alpha;

  // Soft motion-blur volumetric halo (matching macOS orbital glow richness)
  ctx.strokeStyle = glowColor;
  ctx.lineWidth = lineWidth * 2.8;
  ctx.shadowColor = glowColor;
  ctx.shadowBlur = 18;
  ctx.beginPath();
  ctx.arc(0, 0, radius, 0, Math.PI * 2);
  ctx.stroke();

  // Crisp luminous core arc
  ctx.shadowBlur = 8;
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = lineWidth;
  ctx.beginPath();
  ctx.arc(0, 0, radius, 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();
}

/**
 * Renders the studio-grade Windows 11 Fluent Prism Core kinetic emblem.
 * mode: "scanning" | "backlit" | "verified" | "spoof"
 * animatedLoop: true for How It Works phase cards (plays full smooth transition cycle)
 */
function drawKineticPrismCore(ctx, cx, cy, radius, mode, t, opts = {}) {
  const {
    yaw = 0,
    pitch = 0,
    animatedLoop = false,
    blinkPhase = 0,
  } = opts;

  ctx.save();

  let phase = 1;
  let shakeX = 0;
  if (animatedLoop) {
    if (mode === "verified") {
      // Calm 4.4s loop: 0..0.38 orbital spin -> 0.38..0.58 emerald circle snap -> 0.52..0.76 checkmark draw -> hold
      phase = (t * 0.24) % 1;
    } else if (mode === "spoof") {
      // Calm 4.0s loop: 0..0.34 cyan scan -> 0.34..0.58 damped spring recoil + coral X -> hold
      phase = (t * 0.26) % 1;
      if (phase >= 0.34 && phase < 0.62) {
        const sp = (phase - 0.34) / 0.28;
        shakeX = Math.sin(sp * Math.PI * 4) * Math.exp(-sp * 3.4) * (radius * 0.16);
      }
    }
  } else if (mode === "spoof") {
    shakeX = Math.sin(t * 2.4) * 1.2;
  }

  ctx.translate(cx + shakeX, cy);

  // Determine current color palette based on mode & animation phase
  let primary = "#38bdf8";
  let secondary = "#818cf8";
  let bloomRgba = "rgba(56, 189, 248, 0.22)";

  if (mode === "backlit") {
    primary = "#fbbf24";
    secondary = "#38bdf8";
    bloomRgba = "rgba(251, 191, 36, 0.22)";
  } else if (mode === "verified" && (!animatedLoop || phase >= 0.36)) {
    primary = "#30d158";
    secondary = "#34d399";
    bloomRgba = "rgba(48, 209, 88, 0.26)";
  } else if (mode === "spoof" && (!animatedLoop || phase >= 0.34)) {
    primary = "#fb7185";
    secondary = "#f59e0b";
    bloomRgba = "rgba(251, 113, 133, 0.24)";
  }

  // Deep atmospheric radial bloom behind the emblem
  const aura = ctx.createRadialGradient(0, 0, radius * 0.15, 0, 0, radius * 1.45);
  aura.addColorStop(0, bloomRgba);
  aura.addColorStop(1, "rgba(0, 0, 0, 0)");
  ctx.fillStyle = aura;
  ctx.beginPath();
  ctx.arc(0, 0, radius * 1.45, 0, Math.PI * 2);
  ctx.fill();

  const isLockedVerified = mode === "verified" && (!animatedLoop || phase >= 0.42);
  const isLockedSpoof = mode === "spoof" && (!animatedLoop || phase >= 0.38);

  // 1. Dual 3D Tilted Orbital Prism Rings (scanning) OR clean luminous Circle (verified / spoof)
  if (!isLockedVerified && !isLockedSpoof) {
    const speed = mode === "verified" ? 1.5 : 1.15;
    const tiltA = 0.42 + Math.sin(t * speed) * 0.42;
    const tiltB = 0.42 + Math.cos(t * speed * 0.85) * 0.42;
    draw3DOrbitalRing(ctx, 0, 0, radius * 0.96, tiltA, t * 0.65, primary, primary, Math.max(2.6, radius * 0.055), 0.9);
    draw3DOrbitalRing(ctx, 0, 0, radius * 0.96, tiltB, -t * 0.52 + 1.1, secondary, secondary, Math.max(2.2, radius * 0.046), 0.78);
  } else {
    // Soft converged outer circular glow halo
    ctx.save();
    ctx.strokeStyle = primary;
    ctx.globalAlpha = 0.24;
    ctx.lineWidth = Math.max(7, radius * 0.14);
    ctx.shadowColor = primary;
    ctx.shadowBlur = 24;
    ctx.beginPath();
    ctx.arc(0, 0, radius * 0.94, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();

    // Crisp luminous circle enclosing the tick or cross
    ctx.save();
    ctx.strokeStyle = primary;
    ctx.lineWidth = Math.max(3.6, radius * 0.068);
    ctx.globalAlpha = 0.96;
    ctx.shadowColor = primary;
    ctx.shadowBlur = 18;
    ctx.beginPath();
    ctx.arc(0, 0, radius * 0.94, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  // 3. Center Biometric Emblem:
  //    - Scanning / Backlit: Proper Sculpted 3D Human Face + volumetric depth laser sweep
  //    - Verified: Smooth spring-drawn Emerald Checkmark
  //    - Spoof: Bold Coral-Amber Prism X
  if (!isLockedVerified && !isLockedSpoof) {
    const faceScale = (radius / 76) * 1.15;
    renderSculptedHumanFace(ctx, {
      cx: 0,
      cy: 0,
      scale: faceScale,
      yaw,
      pitch,
      blinkPhase,
      strokeMain: mode === "backlit" ? "rgba(255, 240, 195, 0.95)" : "rgba(232, 246, 255, 0.94)",
      strokeSoft: mode === "backlit" ? "rgba(251, 191, 36, 0.34)" : "rgba(56, 189, 248, 0.36)",
      fillTop: mode === "backlit" ? "rgba(251, 191, 36, 0.26)" : "rgba(56, 189, 248, 0.24)",
      fillMid: "rgba(129, 140, 248, 0.12)",
      fillEdge: "rgba(8, 12, 22, 0.55)",
      pupilColor: primary,
      showShoulders: false,
      showMeridians: true,
      lineWidthScale: 1.05,
      shadowGlow: primary,
    });

    // Calm volumetric horizontal laser scanline gliding across the sculpted 3D face
    const scanY = Math.sin(t * 1.65) * (radius * 0.58);
    const beamW = radius * 1.28;
    const beamGrad = ctx.createLinearGradient(-beamW / 2, scanY, beamW / 2, scanY);
    beamGrad.addColorStop(0, "rgba(0,0,0,0)");
    beamGrad.addColorStop(0.5, primary);
    beamGrad.addColorStop(1, "rgba(0,0,0,0)");
    ctx.strokeStyle = beamGrad;
    ctx.lineWidth = Math.max(2, radius * 0.036);
    ctx.shadowColor = primary;
    ctx.shadowBlur = 12;
    ctx.beginPath();
    ctx.moveTo(-beamW / 2, scanY);
    ctx.lineTo(beamW / 2, scanY);
    ctx.stroke();
  } else if (isLockedVerified) {
    // Progressive smooth checkmark draw-on
    const drawProg = animatedLoop ? Math.min(1, Math.max(0, (phase - 0.44) / 0.24)) : 1;
    const eased = 1 - Math.pow(1 - drawProg, 3);
    const p0 = { x: -radius * 0.34, y: radius * 0.02 };
    const p1 = { x: -radius * 0.08, y: radius * 0.29 };
    const p2 = { x: radius * 0.38, y: -radius * 0.26 };

    ctx.save();
    ctx.strokeStyle = "#30d158";
    ctx.lineWidth = Math.max(4.5, radius * 0.095);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.shadowColor = "#30d158";
    ctx.shadowBlur = 20;
    ctx.beginPath();
    ctx.moveTo(p0.x, p0.y);
    if (eased < 0.42) {
      const f = eased / 0.42;
      ctx.lineTo(p0.x + (p1.x - p0.x) * f, p0.y + (p1.y - p0.y) * f);
    } else {
      ctx.lineTo(p1.x, p1.y);
      const f = (eased - 0.42) / 0.58;
      ctx.lineTo(p1.x + (p2.x - p1.x) * f, p1.y + (p2.y - p1.y) * f);
    }
    ctx.stroke();
    ctx.restore();
  } else if (isLockedSpoof) {
    // Bold Coral-Amber Spoof Blocked X
    const drawProg = animatedLoop ? Math.min(1, Math.max(0, (phase - 0.40) / 0.20)) : 1;
    const eased = 1 - Math.pow(1 - drawProg, 3);
    const d = radius * 0.30 * eased;
    ctx.save();
    ctx.strokeStyle = "#fb7185";
    ctx.lineWidth = Math.max(4.4, radius * 0.09);
    ctx.lineCap = "round";
    ctx.shadowColor = "#fb7185";
    ctx.shadowBlur = 18;
    ctx.beginPath();
    ctx.moveTo(-d, -d);
    ctx.lineTo(d, d);
    ctx.moveTo(d, -d);
    ctx.lineTo(-d, d);
    ctx.stroke();
    ctx.restore();
  }

  ctx.restore();
}

function initWindowsPrismCanvas() {
  const canvas = document.getElementById("windowsPrismCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const W = canvas.width;
  const H = canvas.height;
  let t = 0;

  function frame() {
    t += 0.022;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = "#06080d";
    ctx.fillRect(0, 0, W, H);

    const verified = Math.sin(t * 0.42) > 0.55;
    drawKineticPrismCore(ctx, W * 0.5, H * 0.46, 44, verified ? "verified" : "scanning", t, {
      yaw: Math.sin(t * 0.8) * 0.45,
      pitch: Math.cos(t * 0.6) * 0.25,
      blinkPhase: (t * 0.14) % 1,
    });

    ctx.fillStyle = verified ? "#5ee984" : "rgba(125, 211, 252, 0.82)";
    ctx.font = "500 10px ui-monospace, Menlo, monospace";
    ctx.textAlign = "center";
    ctx.fillText(
      verified ? "NEELx WINDOWS · PRISM CORE VERIFIED" : "NEELx WINDOWS · DIRECTML 3D SCANNING",
      W * 0.5,
      H - 10
    );

    requestAnimationFrame(frame);
  }

  frame();
}

function initMacNotchArchCanvas() {
  const canvas = document.getElementById("macNotchArchCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const W = 420;
  const H = 150;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  ctx.scale(dpr, dpr);

  let t = 0;
  let blinkPhase = 0;

  function frame() {
    t += 0.022;
    blinkPhase = (blinkPhase + 0.007) % 1;
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = "#06080d";
    ctx.fillRect(0, 0, W, H);

    const cx = W * 0.5;
    const cy = H * 0.47;
    const cycle = (t * 0.24) % 1; // smooth 4.4s cycle: scan -> verify emerald checkmark
    const verified = cycle >= 0.58;

    // Subtle MacBook top hardware notch pill
    ctx.fillStyle = "#000000";
    ctx.strokeStyle = "rgba(255,255,255,0.12)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.roundRect(cx - 38, -4, 76, 16, 7);
    ctx.fill();
    ctx.stroke();

    // Subtle FaceTime camera dot
    ctx.fillStyle = verified ? "#30d158" : "#243b55";
    ctx.beginPath();
    ctx.arc(cx, 5, 2.4, 0, Math.PI * 2);
    ctx.fill();

    // Soft emerald radial aura behind the notch ring
    const aura = ctx.createRadialGradient(cx, cy, 8, cx, cy, 62);
    aura.addColorStop(0, verified ? "rgba(48, 209, 88, 0.24)" : "rgba(48, 209, 88, 0.12)");
    aura.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = aura;
    ctx.beginPath();
    ctx.arc(cx, cy, 62, 0, Math.PI * 2);
    ctx.fill();

    // 48 crisp radial Face ID ticks
    const tickCount = 48;
    const sweepHead = (cycle / 0.58) * tickCount;
    for (let i = 0; i < tickCount; i++) {
      const ang = (i / tickCount) * Math.PI * 2 - Math.PI / 2;
      const lit = verified || i <= sweepHead;
      const rIn = 34;
      const rOut = lit ? 43 : 40;
      ctx.strokeStyle = lit ? "#30d158" : "rgba(255, 255, 255, 0.16)";
      ctx.lineWidth = lit ? 2 : 1.3;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(ang) * rIn, cy + Math.sin(ang) * rIn);
      ctx.lineTo(cx + Math.cos(ang) * rOut, cy + Math.sin(ang) * rOut);
      ctx.stroke();
    }

    if (!verified) {
      // Proper sculpted 3D human face inside the Face ID ring
      renderSculptedHumanFace(ctx, {
        cx,
        cy,
        scale: 0.64,
        yaw: Math.sin(t * 1.1) * 0.55,
        pitch: Math.cos(t * 0.85) * 0.3,
        blinkPhase,
        strokeMain: "rgba(245, 245, 247, 0.92)",
        strokeSoft: "rgba(48, 209, 88, 0.34)",
        fillTop: "rgba(48, 209, 88, 0.20)",
        fillMid: "rgba(120, 126, 140, 0.10)",
        fillEdge: "rgba(12, 16, 20, 0.55)",
        pupilColor: "#30d158",
        showShoulders: false,
        showMeridians: true,
        lineWidthScale: 1.25,
      });
    } else {
      // Smooth spring-drawn emerald Face ID checkmark
      const drawP = Math.min(1, (cycle - 0.58) / 0.16);
      const eased = 1 - Math.pow(1 - drawP, 3);
      const p0 = { x: cx - 14, y: cy + 1 };
      const p1 = { x: cx - 3, y: cy + 12 };
      const p2 = { x: cx + 16, y: cy - 11 };

      ctx.save();
      ctx.strokeStyle = "#30d158";
      ctx.lineWidth = 3.8;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.shadowColor = "#30d158";
      ctx.shadowBlur = 14;
      ctx.beginPath();
      ctx.moveTo(p0.x, p0.y);
      if (eased < 0.42) {
        const f = eased / 0.42;
        ctx.lineTo(p0.x + (p1.x - p0.x) * f, p0.y + (p1.y - p0.y) * f);
      } else {
        ctx.lineTo(p1.x, p1.y);
        const f = (eased - 0.42) / 0.58;
        ctx.lineTo(p1.x + (p2.x - p1.x) * f, p1.y + (p2.y - p1.y) * f);
      }
      ctx.stroke();
      ctx.restore();
    }

    ctx.fillStyle = verified ? "#5ee984" : "rgba(245, 245, 247, 0.72)";
    ctx.font = "500 10px ui-monospace, Menlo, monospace";
    ctx.textAlign = "center";
    ctx.fillText(
      verified ? "NEELx macOS · KEYCHAIN UNLOCK VERIFIED" : "NEELx macOS · ANE 3D DEPTH SCANNING",
      cx,
      H - 10
    );

    requestAnimationFrame(frame);
  }

  frame();
}

function initWinHeroCanvas() {
  const canvas = document.getElementById("winHeroCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const W = 380;
  const H = 248;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  ctx.scale(dpr, dpr);

  const statusEl = document.getElementById("winHeroStatus");

  let mode = "scanning";
  let t = 0;
  let targetYaw = 0;
  let targetPitch = 0;
  let yaw = 0;
  let pitch = 0;
  let blinkPhase = 0;

  canvas.addEventListener("pointermove", (e) => {
    const r = canvas.getBoundingClientRect();
    targetYaw = Math.max(-1, Math.min(1, ((e.clientX - r.left) / r.width - 0.5) * 2));
    targetPitch = Math.max(-1, Math.min(1, ((e.clientY - r.top) / r.height - 0.5) * 2));
  });
  canvas.addEventListener("pointerleave", () => {
    targetYaw = 0;
    targetPitch = 0;
  });

  function setMode(m) {
    mode = m;
    if (!statusEl) return;
    if (m === "verified") statusEl.innerHTML = `Identity &amp; 3D Depth Verified · <strong>DPAPI Session Unlocked</strong>`;
    else if (m === "spoof") statusEl.innerHTML = `Flat 2D Surface Detected · <strong>Blocked by DirectML 3D Gate</strong>`;
    else statusEl.innerHTML = `Move cursor around face · <strong>Prism 3D Active</strong>`;
  }

  document.getElementById("btnWinHeroScan")?.addEventListener("click", () => setMode("scanning"));
  document.getElementById("btnWinHeroUnlock")?.addEventListener("click", () => setMode("verified"));
  document.getElementById("btnWinHeroSpoof")?.addEventListener("click", () => setMode("spoof"));

  function render() {
    t += 0.022;
    blinkPhase = (blinkPhase + 0.007) % 1;
    yaw += (targetYaw - yaw) * 0.14;
    pitch += (targetPitch - pitch) * 0.14;

    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = "#04060a";
    ctx.fillRect(0, 0, W, H);

    drawKineticPrismCore(ctx, W * 0.5, H * 0.46, 76, mode, t, {
      yaw,
      pitch,
      blinkPhase,
      animatedLoop: false,
    });

    ctx.fillStyle = mode === "verified" ? "#5ee984" : mode === "spoof" ? "#fda4af" : "rgba(186, 230, 253, 0.72)";
    ctx.font = "500 10.5px ui-monospace, Consolas, monospace";
    ctx.textAlign = "center";
    ctx.fillText(
      mode === "verified"
        ? "PRISM 3D VERIFIED · Δz nose = +0.088 · DPAPI UNLOCKED"
        : mode === "spoof"
          ? "FLAT 2D SPOOF BLOCKED · Δz nose = +0.004"
          : "DIRECTML 3D MESH · MULTI-FRAME DEPTH ACTIVE",
      W * 0.5,
      H - 14
    );

    requestAnimationFrame(render);
  }

  render();
}

function initWinHowItWorksSimulators() {
  const phaseConfigs = [
    { id: "winPhaseScan", state: "scanning" },
    { id: "winPhaseUnlock", state: "verified" },
    { id: "winPhaseSpoof", state: "spoof" },
  ];

  const phaseCanvases = phaseConfigs
    .map((cfg) => ({ ...cfg, el: document.getElementById(cfg.id) }))
    .filter((item) => item.el);

  const lockSim = document.getElementById("winLockSimCanvas");
  let simState = "scanning";

  document.querySelectorAll("[data-win-sim]").forEach((btn) => {
    btn.addEventListener("click", () => {
      simState = btn.getAttribute("data-win-sim") || "scanning";
    });
  });

  let t = 0;
  let blinkPhase = 0;
  function tick() {
    t += 0.022;
    blinkPhase = (blinkPhase + 0.007) % 1;

    // 1. Three studio-grade pure-obsidian Windows Phase Cards (matching macOS .mp4 quality & visual presence!)
    for (const item of phaseCanvases) {
      const ctx = item.el.getContext("2d");
      const W = item.el.width;
      const H = item.el.height;
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = "#000000";
      ctx.fillRect(0, 0, W, H);

      drawKineticPrismCore(ctx, W * 0.5, H * 0.5, 96, item.state, t, {
        yaw: item.state === "scanning" ? Math.sin(t * 0.7) * 0.55 : 0,
        pitch: item.state === "scanning" ? Math.cos(t * 0.5) * 0.3 : 0,
        blinkPhase,
        animatedLoop: true,
      });
    }

    // 2. Full Interactive Windows 11 Lock Screen Simulator showing the exact floating Prism Core Card
    if (lockSim) {
      const ctx = lockSim.getContext("2d");
      const W = lockSim.width;
      const H = lockSim.height;
      ctx.clearRect(0, 0, W, H);

      const bg = ctx.createRadialGradient(W * 0.5, H * 0.9, 50, W * 0.5, H * 0.5, W * 0.65);
      bg.addColorStop(
        0,
        simState === "verified"
          ? "rgba(48,209,88,0.16)"
          : simState === "spoof"
            ? "rgba(251,113,133,0.15)"
            : simState === "backlit"
              ? "rgba(251,191,36,0.16)"
              : "rgba(56,189,248,0.17)"
      );
      bg.addColorStop(1, "#05070c");
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, W, H);

      // Floating Obsidian Mica Prism Core Card (exact match to Windows PrismHorizonOverlay.xaml!)
      const cardW = 198;
      const cardH = 164;
      const cardX = (W - cardW) / 2;
      const cardY = 14;
      const borderCol =
        simState === "verified"
          ? "rgba(48, 209, 88, 0.5)"
          : simState === "spoof"
            ? "rgba(251, 113, 133, 0.5)"
            : simState === "backlit"
              ? "rgba(251, 191, 36, 0.5)"
              : "rgba(56, 189, 248, 0.45)";

      ctx.save();
      ctx.fillStyle = "rgba(8, 10, 15, 0.95)";
      ctx.strokeStyle = borderCol;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.roundRect(cardX, cardY, cardW, cardH, 22);
      ctx.fill();
      ctx.stroke();
      ctx.restore();

      drawKineticPrismCore(ctx, W * 0.5, cardY + 66, 48, simState, t, {
        yaw: simState === "scanning" || simState === "backlit" ? Math.sin(t * 0.8) * 0.45 : 0,
        pitch: Math.cos(t * 0.6) * 0.2,
        blinkPhase,
        animatedLoop: false,
      });

      const titleMap = {
        scanning: "PRISM 3D · SCANNING",
        backlit: "BACKLIT · HDR LIFT",
        verified: "UNLOCKED · 3D VERIFIED",
        spoof: "2D SPOOF BLOCKED",
      };
      const titleCol =
        simState === "verified"
          ? "#30d158"
          : simState === "spoof"
            ? "#fb7185"
            : simState === "backlit"
              ? "#fbbf24"
              : "#38bdf8";

      ctx.textAlign = "center";
      ctx.fillStyle = titleCol;
      ctx.font = "600 10.5px 'Segoe UI', -apple-system, sans-serif";
      ctx.fillText(titleMap[simState] || titleMap.scanning, W * 0.5, cardY + cardH - 22);
      ctx.fillStyle = "#8e97a8";
      ctx.font = "400 9.5px 'Segoe UI', -apple-system, sans-serif";
      ctx.fillText("DirectML GPU · Windows DPAPI", W * 0.5, cardY + cardH - 9);

      // Windows 11 Lock Screen time & caption beneath the floating card
      ctx.fillStyle = "rgba(255,255,255,0.88)";
      ctx.font = "600 40px 'Segoe UI Variable Display', -apple-system, sans-serif";
      ctx.fillText("09:41", W / 2, 224);

      ctx.fillStyle = "rgba(255,255,255,0.52)";
      ctx.font = "400 12.5px 'Segoe UI', -apple-system, sans-serif";
      const subText =
        simState === "verified"
          ? "Welcome back · Signing in via NEELx Credential Provider…"
          : simState === "spoof"
            ? "NEELx blocked a 2D spoof · Enter PIN or look directly at webcam"
            : simState === "backlit"
              ? "Backlit window detected · HDR shadow recovery active"
              : "Looking for your 3D face via DirectML…";
      ctx.fillText(subText, W / 2, 254);
    }

    requestAnimationFrame(tick);
  }

  tick();
}

// ---------------------------------------------------------------------------
// 8. Direct Feedback Form (Auto-detected Browser Info + Screenshots + Email Picker)
// ---------------------------------------------------------------------------
function detectBasicBrowserEnv() {
  const ua = navigator.userAgent || "";
  const os = /Mac OS X/i.test(ua)
    ? "macOS"
    : /Windows/i.test(ua)
      ? "Windows"
      : /Linux/i.test(ua)
        ? "Linux"
        : "Browser";
  const browser = /Edg\//.test(ua)
    ? "Edge"
    : /Chrome\//.test(ua)
      ? "Chrome"
      : /Safari\//.test(ua)
        ? "Safari"
        : /Firefox\//.test(ua)
          ? "Firefox"
          : "Web";
  return `${os} · ${browser} (${window.screen.width}×${window.screen.height})`;
}

function initFeedbackForm() {
  const form = document.getElementById("feedbackForm");
  if (!form) return;
  const statusEl = document.getElementById("feedbackStatus");
  const githubBtn = document.getElementById("btnFeedbackGitHub");
  const emailMenuBtn = document.getElementById("btnEmailMenu");
  const emailMenu = document.getElementById("emailMenu");
  const dropzone = document.getElementById("fbDropzone");
  const fileInput = document.getElementById("fbFiles");
  const pickBtn = document.getElementById("btnPickScreenshots");
  const previewsEl = document.getElementById("fbPreviews");

  const screenshots = [];

  async function compressImageFile(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error("Could not read image"));
      reader.onload = () => {
        const img = new Image();
        img.onerror = () => reject(new Error("Unsupported image format"));
        img.onload = () => {
          const maxDim = 1440;
          const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
          const w = Math.max(1, Math.round(img.width * scale));
          const h = Math.max(1, Math.round(img.height * scale));
          const canvas = document.createElement("canvas");
          canvas.width = w;
          canvas.height = h;
          canvas.getContext("2d").drawImage(img, 0, 0, w, h);
          const dataUrl = canvas.toDataURL("image/jpeg", 0.82);
          const base64 = dataUrl.split(",")[1] || "";
          const baseName = (file.name || `screenshot-${Date.now()}`).replace(/\.[^.]+$/, "");
          resolve({
            id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
            name: `${baseName}.jpg`,
            dataUrl,
            base64,
          });
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
  }

  function renderPreviews() {
    if (!previewsEl) return;
    previewsEl.innerHTML = "";
    for (const item of screenshots) {
      const card = document.createElement("div");
      card.className = "upload-thumb";
      card.title = item.name;
      const img = document.createElement("img");
      img.src = item.dataUrl;
      img.alt = item.name;
      const rm = document.createElement("button");
      rm.type = "button";
      rm.className = "upload-thumb-remove";
      rm.textContent = "×";
      rm.addEventListener("click", (e) => {
        e.stopPropagation();
        const idx = screenshots.findIndex((s) => s.id === item.id);
        if (idx >= 0) screenshots.splice(idx, 1);
        renderPreviews();
      });
      card.appendChild(img);
      card.appendChild(rm);
      previewsEl.appendChild(card);
    }
  }

  async function addFiles(fileList) {
    const remaining = 3 - screenshots.length;
    if (remaining <= 0) {
      statusEl.textContent = "Maximum 3 screenshots allowed.";
      statusEl.style.color = "#ff9f0a";
      return;
    }
    const candidates = Array.from(fileList).filter((f) => f.type.startsWith("image/")).slice(0, remaining);
    for (const file of candidates) {
      try {
        screenshots.push(await compressImageFile(file));
      } catch {
        statusEl.textContent = `Could not process ${file.name}.`;
        statusEl.style.color = "#ff453a";
      }
    }
    renderPreviews();
  }

  pickBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    fileInput?.click();
  });
  dropzone?.addEventListener("click", () => fileInput?.click());
  fileInput?.addEventListener("change", () => {
    if (fileInput.files?.length) addFiles(fileInput.files);
    fileInput.value = "";
  });
  dropzone?.addEventListener("dragover", (e) => {
    e.preventDefault();
    dropzone.classList.add("drag-over");
  });
  dropzone?.addEventListener("dragleave", () => dropzone.classList.remove("drag-over"));
  dropzone?.addEventListener("drop", (e) => {
    e.preventDefault();
    dropzone.classList.remove("drag-over");
    if (e.dataTransfer?.files?.length) addFiles(e.dataTransfer.files);
  });
  form.addEventListener("paste", (e) => {
    const items = e.clipboardData?.items;
    if (!items) return;
    const imgs = [];
    for (const item of items) {
      if (item.type.startsWith("image/")) {
        const f = item.getAsFile();
        if (f) imgs.push(f);
      }
    }
    if (imgs.length) addFiles(imgs);
  });

  function collectData() {
    return {
      category: document.getElementById("fbCategory")?.value || "Feedback",
      macModel: detectBasicBrowserEnv(),
      rating: document.getElementById("fbRating")?.value || "5/5",
      message: document.getElementById("fbMessage")?.value.trim() || "",
      attachments: screenshots.map((s) => ({ name: s.name, content: s.base64 })),
    };
  }

  function buildBody(d) {
    return `Category: ${d.category}\nEnvironment: ${d.macModel}\nRating: ${d.rating}\n\n${d.message}`;
  }

  function buildSubject(d) {
    return `[${d.category}] NEELx Beta Feedback (${d.rating})`;
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const d = collectData();
    if (!d.message) {
      statusEl.textContent = "Please write a short note first.";
      statusEl.style.color = "#ff453a";
      return;
    }
    statusEl.textContent = screenshots.length
      ? `Sending feedback + ${screenshots.length} screenshot(s)…`
      : "Sending feedback…";
    statusEl.style.color = "#f5f5f7";

    try {
      const apiEndpoint = window.location.hostname.endsWith(".workers.dev")
        ? "/api/feedback"
        : "https://neelx.chandranildas925.workers.dev/api/feedback";
      const res = await fetch(apiEndpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(d),
      });
      if (res.ok) {
        statusEl.textContent = screenshots.length
          ? `Feedback + ${screenshots.length} screenshot(s) sent directly — thank you!`
          : "Feedback sent directly — thank you!";
        statusEl.style.color = "#30d158";
        form.reset();
        screenshots.length = 0;
        renderPreviews();
        return;
      }
    } catch {
      // Fall back to GitHub Issue
    }

    const params = new URLSearchParams({ title: buildSubject(d), body: buildBody(d) });
    window.open(`https://github.com/${REPO}/issues/new?${params.toString()}`, "_blank", "noopener");
    statusEl.textContent = "Opened pre-filled GitHub Issue.";
    statusEl.style.color = "#30d158";
  });

  githubBtn?.addEventListener("click", () => {
    const d = collectData();
    const params = new URLSearchParams({ title: buildSubject(d), body: buildBody(d) });
    window.open(`https://github.com/${REPO}/issues/new?${params.toString()}`, "_blank", "noopener");
  });

  emailMenuBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    const isHidden = emailMenu.hasAttribute("hidden");
    if (isHidden) {
      emailMenu.removeAttribute("hidden");
      emailMenuBtn.setAttribute("aria-expanded", "true");
    } else {
      emailMenu.setAttribute("hidden", "");
      emailMenuBtn.setAttribute("aria-expanded", "false");
    }
  });

  document.addEventListener("click", () => {
    if (emailMenu && !emailMenu.hasAttribute("hidden")) {
      emailMenu.setAttribute("hidden", "");
      emailMenuBtn?.setAttribute("aria-expanded", "false");
    }
  });

  emailMenu?.addEventListener("click", async (e) => {
    const btn = e.target.closest("button[data-email-client]");
    if (!btn) return;
    const client = btn.getAttribute("data-email-client");
    emailMenu.setAttribute("hidden", "");
    emailMenuBtn?.setAttribute("aria-expanded", "false");

    const d = collectData();
    const subject = encodeURIComponent(buildSubject(d));
    const body = encodeURIComponent(buildBody(d));

    if (client === "gmail") {
      window.open(`https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(FEEDBACK_EMAIL)}&su=${subject}&body=${body}`, "_blank", "noopener");
      statusEl.textContent = "Opened pre-filled draft in Gmail.";
    } else if (client === "outlook") {
      window.open(`https://outlook.live.com/mail/0/deeplink/compose?to=${encodeURIComponent(FEEDBACK_EMAIL)}&subject=${subject}&body=${body}`, "_blank", "noopener");
      statusEl.textContent = "Opened pre-filled draft in Outlook Web.";
    } else if (client === "yahoo") {
      window.open(`https://compose.mail.yahoo.com/?to=${encodeURIComponent(FEEDBACK_EMAIL)}&subject=${subject}&body=${body}`, "_blank", "noopener");
      statusEl.textContent = "Opened pre-filled draft in Yahoo Mail.";
    } else if (client === "native") {
      const a = document.createElement("a");
      a.href = `mailto:${FEEDBACK_EMAIL}?subject=${subject}&body=${body}`;
      a.style.display = "none";
      document.body.appendChild(a);
      a.click();
      a.remove();
      statusEl.textContent = "Handed draft to your default Mail app.";
    } else if (client === "copy") {
      await navigator.clipboard.writeText(`To: ${FEEDBACK_EMAIL}\nSubject: ${buildSubject(d)}\n\n${buildBody(d)}`);
      statusEl.textContent = `Copied draft & ${FEEDBACK_EMAIL} to clipboard!`;
    }
    statusEl.style.color = "#30d158";
  });
}

document.addEventListener("DOMContentLoaded", () => {
  initTabs();
  initPlatformSwitchers();
  initCopyButtons();
  syncLatestRelease();
  initEnrollmentSimulator();
  initWinHeroCanvas();
  initHowItWorksDemos();
  initWinHowItWorksSimulators();
  initDepthLab();
  initWindowsPrismCanvas();
  initMacNotchArchCanvas();
  initFeedbackForm();
});
