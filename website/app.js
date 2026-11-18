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
    el.addEventListener("click", () => activateTab(el.getAttribute("data-go-tab")));
  });

  const initialHash = window.location.hash.replace(/^#/, "");
  if (initialHash && document.getElementById(`tab-${initialHash}`)) {
    activateTab(initialHash, false);
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
// 3. Live GitHub Releases Sync
// ---------------------------------------------------------------------------
async function syncLatestRelease() {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=5`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!res.ok) return;
    const releases = await res.json();
    const latest = releases.find((r) => !r.draft && r.assets && r.assets.length > 0);
    if (!latest) return;

    const tag = latest.tag_name;
    document.querySelectorAll("[data-release-version]").forEach((el) => {
      el.textContent = tag;
    });

    const liteAsset = latest.assets.find((a) => a.name.includes("lite") && a.name.endsWith(".dmg"));
    const fullAsset = latest.assets.find((a) => !a.name.includes("lite") && a.name.endsWith(".dmg"));

    if (liteAsset) {
      const mb = (liteAsset.size / (1024 * 1024)).toFixed(1);
      const liteBtn = document.getElementById("btnDownloadLite");
      const liteSize = document.getElementById("liteSize");
      if (liteBtn) liteBtn.href = liteAsset.browser_download_url;
      if (liteSize) liteSize.textContent = `${mb} MB · Universal`;
    }
    if (fullAsset) {
      const mb = (fullAsset.size / (1024 * 1024)).toFixed(1);
      const fullBtn = document.getElementById("btnDownloadFull");
      const fullSize = document.getElementById("fullSize");
      if (fullBtn) fullBtn.href = fullAsset.browser_download_url;
      if (fullSize) fullSize.textContent = `${mb} MB · Universal`;
    }
  } catch {
    // Keep pre-populated links seamlessly
  }
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
  const W = 420;
  const H = 280;
  canvas.width = W;
  canvas.height = H;

  const btnReal = document.getElementById("btnModeReal");
  const btnSpoof = document.getElementById("btnModeSpoof");
  const verdictEl = document.getElementById("depthVerdict");

  function setBar(id, valText, pct, color) {
    const vEl = document.getElementById(`${id}Val`);
    const bEl = document.getElementById(`${id}Bar`);
    if (vEl) vEl.textContent = valText;
    if (bEl) {
      bEl.style.width = `${Math.max(2, Math.min(100, pct))}%`;
      bEl.style.background = color;
    }
  }

  function renderDepth(mode) {
    const img = ctx.createImageData(W, H);
    const data = img.data;
    const cx = W * 0.5;
    const cy = H * 0.45;
    const crossSection = [];

    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let d = 0.08 + 0.04 * (y / H);

        if (mode === "real") {
          const nx = (x - cx) / 68;
          const ny = (y - cy) / 86;
          const r2 = nx * nx + ny * ny;

          const sx = (x - cx) / 145;
          const sy = (y - H * 0.96) / 62;
          if (sx * sx + sy * sy < 1) {
            const sh = Math.sqrt(Math.max(0, 1 - sx * sx - sy * sy));
            d = Math.max(d, 0.44 + sh * 0.16);
          }

          if (r2 < 1.0) {
            const dome = Math.sqrt(1 - r2);
            let faceD = 0.54 + dome * 0.28;
            const el = ((x - (cx - 24)) / 14) ** 2 + ((y - (cy - 12)) / 10) ** 2;
            const er = ((x - (cx + 24)) / 14) ** 2 + ((y - (cy - 12)) / 10) ** 2;
            faceD -= Math.exp(-el * 2.2) * 0.065;
            faceD -= Math.exp(-er * 2.2) * 0.065;
            const noseTip = ((x - cx) / 13) ** 2 + ((y - (cy + 8)) / 22) ** 2;
            faceD += Math.exp(-noseTip * 1.9) * 0.175;
            d = Math.max(d, faceD);
          }
        } else {
          const rx = Math.abs(x - cx);
          const ry = Math.abs(y - cy);
          if (rx < 94 && ry < 112) {
            d = 0.56 + ((x - cx) / W) * 0.05 + ((y - cy) / H) * 0.03;
            const nx = (x - cx) / 56;
            const ny = (y - cy) / 72;
            if (nx * nx + ny * ny < 1) d += 0.008;
          }
        }

        if (y === Math.round(cy + 6)) crossSection.push(d);
        const [r, g, b] = infernoColor(d);
        const idx = (y * W + x) * 4;
        data[idx] = r;
        data[idx + 1] = g;
        data[idx + 2] = b;
        data[idx + 3] = 255;
      }
    }

    ctx.putImageData(img, 0, 0);

    const scanY = Math.round(cy + 6);
    ctx.strokeStyle = "rgba(255,255,255,0.28)";
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(0, scanY);
    ctx.lineTo(W, scanY);
    ctx.stroke();
    ctx.setLineDash([]);

    ctx.fillStyle = "rgba(10, 11, 15, 0.78)";
    ctx.fillRect(0, H - 56, W, 56);
    ctx.strokeStyle = mode === "real" ? "#30d158" : "#ff453a";
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let x = 0; x < crossSection.length; x++) {
      const py = H - 8 - crossSection[x] * 42;
      if (x === 0) ctx.moveTo(x, py);
      else ctx.lineTo(x, py);
    }
    ctx.stroke();

    ctx.fillStyle = "rgba(255,255,255,0.75)";
    ctx.font = "10.5px ui-monospace, Menlo, monospace";
    ctx.fillText(
      mode === "real"
        ? "z(x): Sharp 3D nose peak + head-to-room cliff"
        : "z(x): Flat coplanar plateau (2D screen/photo)",
      12,
      H - 40
    );

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

  btnReal?.addEventListener("click", () => {
    btnReal.classList.add("active");
    btnSpoof.classList.remove("active");
    renderDepth("real");
  });

  btnSpoof?.addEventListener("click", () => {
    btnSpoof.classList.add("active");
    btnReal.classList.remove("active");
    renderDepth("spoof");
  });

  renderDepth("real");
}

// ---------------------------------------------------------------------------
// 7. Original Windows Fluent Prism Horizon Animated Canvas (Distinct from Mac!)
// ---------------------------------------------------------------------------
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

    // Subtle Fluent acrylic horizon line
    const cy = H * 0.5;
    const cx = W * 0.5;
    const cycle = (Math.sin(t) + 1) * 0.5; // 0..1 scanning pulse
    const verified = Math.sin(t * 0.45) > 0.65;

    // Horizontal laser wave sweep
    const grad = ctx.createLinearGradient(40, cy, W - 40, cy);
    grad.addColorStop(0, "rgba(255,255,255,0)");
    grad.addColorStop(0.5, verified ? "rgba(48, 209, 88, 0.85)" : "rgba(180, 210, 255, 0.72)");
    grad.addColorStop(1, "rgba(255,255,255,0)");

    ctx.strokeStyle = grad;
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let x = 36; x <= W - 36; x += 4) {
      const norm = (x - cx) / (W * 0.42);
      const env = Math.exp(-norm * norm * 3.5);
      const wave = verified ? 0 : Math.sin(x * 0.055 - t * 4.2) * 14 * env;
      const y = cy + wave;
      if (x === 36) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Faceted Geometric Diamond-Iris Aperture (Windows-original, NOT iPhone/Mac circular ring!)
    const r = 24 + (verified ? 2 : cycle * 4);
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(verified ? Math.PI / 4 : Math.PI / 4 + Math.sin(t * 0.8) * 0.14);
    ctx.strokeStyle = verified ? "#30d158" : "rgba(245, 245, 247, 0.85)";
    ctx.fillStyle = verified ? "rgba(48, 209, 88, 0.14)" : "rgba(255, 255, 255, 0.05)";
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.roundRect(-r * 0.75, -r * 0.75, r * 1.5, r * 1.5, 6);
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    // Status label
    ctx.fillStyle = verified ? "#5ee984" : "rgba(255,255,255,0.62)";
    ctx.font = "500 10.5px ui-monospace, Menlo, monospace";
    ctx.textAlign = "center";
    ctx.fillText(
      verified ? "NEELx WINDOWS · PRISM HORIZON VERIFIED" : "NEELx WINDOWS · DIRECTML 3D SCANNING",
      cx,
      H - 14
    );

    requestAnimationFrame(frame);
  }

  frame();
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
  initCopyButtons();
  syncLatestRelease();
  initEnrollmentSimulator();
  initHowItWorksDemos();
  initDepthLab();
  initWindowsPrismCanvas();
  initFeedbackForm();
});
