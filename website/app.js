// NEELx Official Website — Interactive Biometric Visualizers & Live GitHub Releases Sync

const REPO = "ChandranilDas/NEELx";
const FALLBACK_VERSION = "v2.0.0-beta.2";
const FEEDBACK_EMAIL = "chandranildas925@gmail.com";

// ---------------------------------------------------------------------------
// 1. Live GitHub Releases Sync (Auto-updates Download Links & Version Tag)
// ---------------------------------------------------------------------------
async function syncLatestRelease() {
  const versionEls = document.querySelectorAll("[data-release-version]");
  const liteBtn = document.getElementById("btnDownloadLite");
  const fullBtn = document.getElementById("btnDownloadFull");
  const heroBtn = document.getElementById("btnHeroDownload");
  const liteSizeEl = document.getElementById("liteSize");
  const fullSizeEl = document.getElementById("fullSize");

  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=5`, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!res.ok) return;
    const releases = (await res.json()).filter((r) => !r.draft);
    if (!releases.length) return;

    const latest = releases[0];
    const tag = latest.tag_name || FALLBACK_VERSION;
    versionEls.forEach((el) => (el.textContent = tag));

    const assets = latest.assets || [];
    const lite = assets.find((a) => a.name.toLowerCase().includes("lite") && a.name.endsWith(".dmg"));
    const full = assets.find((a) => !a.name.toLowerCase().includes("lite") && a.name.endsWith(".dmg"));

    if (lite) {
      if (liteBtn) liteBtn.href = lite.browser_download_url;
      if (heroBtn) heroBtn.href = lite.browser_download_url;
      if (liteSizeEl) liteSizeEl.textContent = `${(lite.size / (1024 * 1024)).toFixed(1)} MB · Universal`;
    }
    if (full) {
      if (fullBtn) fullBtn.href = full.browser_download_url;
      if (fullSizeEl) fullSizeEl.textContent = `${(full.size / (1024 * 1024)).toFixed(1)} MB · Universal`;
    }
  } catch {
    // Fallback links already point to v2.0.0-beta.2 directly in HTML
  }
}

// ---------------------------------------------------------------------------
// 2. Interactive 80-Tick 360° Circular Face ID Enrollment Simulator
// ---------------------------------------------------------------------------
function initEnrollmentSimulator() {
  const canvas = document.getElementById("enrollmentCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const statusEl = document.getElementById("notchSimStatus");
  const sectorEl = document.getElementById("sectorProgressText");
  const demoBtn = document.getElementById("btnAutoDemo");

  const dpr = window.devicePixelRatio || 1;
  const size = 260;
  canvas.width = size * dpr;
  canvas.height = size * dpr;
  ctx.scale(dpr, dpr);

  const tickCount = 80;
  const capturedSectors = new Set();
  let pointerAngle = null; // degrees 0..360 (0 = up, clockwise)
  let pointerMag = 0;
  let autoAnimating = false;
  let autoAngle = 0;

  function render() {
    ctx.clearRect(0, 0, size, size);
    const cx = size / 2;
    const cy = size / 2;
    const innerR = 76;
    const complete = capturedSectors.size === 8;

    // Subtle dark camera aperture circle
    const grad = ctx.createRadialGradient(cx, cy - 12, 10, cx, cy, innerR);
    grad.addColorStop(0, complete ? "rgba(52, 211, 153, 0.16)" : "rgba(56, 189, 248, 0.12)");
    grad.addColorStop(1, "rgba(10, 12, 18, 0.95)");
    ctx.beginPath();
    ctx.arc(cx, cy, innerR - 6, 0, Math.PI * 2);
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.08)";
    ctx.lineWidth = 1;
    ctx.stroke();

    // Minimalist wireframe face contour shifting subtly with pointerAngle
    const ox = pointerAngle !== null ? Math.sin((pointerAngle * Math.PI) / 180) * 10 * pointerMag : 0;
    const oy = pointerAngle !== null ? -Math.cos((pointerAngle * Math.PI) / 180) * 10 * pointerMag : 0;

    ctx.save();
    ctx.translate(cx + ox, cy + oy);
    ctx.strokeStyle = complete ? "#34d399" : "rgba(244,244,246,0.55)";
    ctx.lineWidth = 1.6;
    // Face oval
    ctx.beginPath();
    ctx.ellipse(0, 2, 26, 33, 0, 0, Math.PI * 2);
    ctx.stroke();
    // 5-point Vision landmarks (eyes, nose, mouth corners)
    const pts = [
      [-10, -6], [10, -6], [ox * 0.45, 4 + oy * 0.3], [-8, 16], [8, 16],
    ];
    ctx.fillStyle = complete ? "#34d399" : "#38bdf8";
    for (const [px, py] of pts) {
      ctx.beginPath();
      ctx.arc(px, py, 2.2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    // 80 radial ticks (exact geometry of NEELx's EnrollmentRingView.swift)
    for (let i = 0; i < tickCount; i++) {
      const deg = i * (360 / tickCount);
      const rad = ((deg - 90) * Math.PI) / 180;
      const sector = Math.round(deg / 45) % 8;
      const isLit = complete || capturedSectors.has(sector);

      let liveBoost = 0;
      if (pointerAngle !== null && !isLit) {
        let diff = Math.abs(deg - pointerAngle);
        if (diff > 180) diff = 360 - diff;
        if (diff < 26) liveBoost = (1 - diff / 26) * pointerMag;
      }

      const len = isLit ? 20 : 11 + liveBoost * 9;
      const x1 = cx + Math.cos(rad) * innerR;
      const y1 = cy + Math.sin(rad) * innerR;
      const x2 = cx + Math.cos(rad) * (innerR + len);
      const y2 = cy + Math.sin(rad) * (innerR + len);

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.lineWidth = isLit ? 2.4 : 1.7;
      ctx.lineCap = "round";
      ctx.strokeStyle = isLit
        ? "#34d399"
        : liveBoost > 0.1
        ? `rgba(56, 189, 248, ${0.4 + liveBoost * 0.6})`
        : "rgba(255,255,255,0.18)";
      ctx.stroke();
    }

    if (sectorEl) {
      sectorEl.textContent = complete
        ? "8/8 sectors + 9-zone 3D depth captured"
        : `${capturedSectors.size}/8 compass sectors · drag in a circle`;
    }
    if (statusEl) {
      statusEl.textContent = complete ? "3D FACE PROFILE ENROLLED" : "360° CIRCULAR CAPTURE READY";
      statusEl.style.color = complete ? "#34d399" : "#38bdf8";
    }
  }

  function updateFromCoords(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const x = clientX - rect.left - rect.width / 2;
    const y = clientY - rect.top - rect.height / 2;
    const dist = Math.hypot(x, y);
    if (dist < 18) return;
    let deg = (Math.atan2(x, -y) * 180) / Math.PI;
    if (deg < 0) deg += 360;
    pointerAngle = deg;
    pointerMag = Math.min(dist / 85, 1);
    const sector = Math.round(deg / 45) % 8;
    capturedSectors.add(sector);
    render();
  }

  canvas.addEventListener("pointermove", (e) => {
    if (autoAnimating) return;
    updateFromCoords(e.clientX, e.clientY);
  });

  canvas.addEventListener("pointerleave", () => {
    if (!autoAnimating) {
      pointerAngle = null;
      pointerMag = 0;
      render();
    }
  });

  if (demoBtn) {
    demoBtn.addEventListener("click", () => {
      capturedSectors.clear();
      autoAnimating = true;
      autoAngle = 0;
      function step() {
        if (!autoAnimating) return;
        pointerAngle = autoAngle % 360;
        pointerMag = 1;
        capturedSectors.add(Math.round(pointerAngle / 45) % 8);
        render();
        autoAngle += 9;
        if (autoAngle <= 360) {
          requestAnimationFrame(step);
        } else {
          autoAnimating = false;
          pointerAngle = null;
          pointerMag = 0;
          render();
        }
      }
      requestAnimationFrame(step);
    });
  }

  render();
}

// ---------------------------------------------------------------------------
// 3. Interactive Stage 3 Neural 3D Depth Heatmap & Cross-Section Visualizer
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
        let d = 0.08 + 0.04 * (y / H); // distant room wall

        if (mode === "real") {
          // 3D human head + protruding nose + recessed eye sockets + shoulders
          const nx = (x - cx) / 68;
          const ny = (y - cy) / 86;
          const r2 = nx * nx + ny * ny;

          // Shoulders
          const sx = (x - cx) / 145;
          const sy = (y - H * 0.96) / 62;
          if (sx * sx + sy * sy < 1) {
            const sh = Math.sqrt(Math.max(0, 1 - sx * sx - sy * sy));
            d = Math.max(d, 0.44 + sh * 0.16);
          }

          // Head ellipsoid with sharp background cliff
          if (r2 < 1.0) {
            const dome = Math.sqrt(1 - r2);
            let faceD = 0.54 + dome * 0.28;
            // Recessed left & right eye sockets
            const el = ((x - (cx - 24)) / 14) ** 2 + ((y - (cy - 12)) / 10) ** 2;
            const er = ((x - (cx + 24)) / 14) ** 2 + ((y - (cy - 12)) / 10) ** 2;
            faceD -= Math.exp(-el * 2.2) * 0.065;
            faceD -= Math.exp(-er * 2.2) * 0.065;
            // Protruding 3D nose bridge & tip
            const noseTip = ((x - cx) / 13) ** 2 + ((y - (cy + 8)) / 22) ** 2;
            faceD += Math.exp(-noseTip * 1.9) * 0.19;
            // Chin curvature
            const chin = ((x - cx) / 22) ** 2 + ((y - (cy + 50)) / 16) ** 2;
            faceD += Math.exp(-chin * 2.1) * 0.05;
            d = Math.max(d, faceD);
          }
        } else {
          // 2D Phone / Tablet Screen Spoof: uniform tilted plane inside rectangular bezel
          const inPhone = Math.abs(x - cx) < 92 && Math.abs(y - cy) < 118;
          if (inPhone) {
            // Flat tilted plane z = a*x + b*y + c (zero nose protrusion, zero 3D curvature!)
            d = 0.66 + ((x - cx) / W) * 0.09 + ((y - cy) / H) * 0.05;
          }
        }

        const [r, g, b] = infernoColor(d);
        const idx = (y * W + x) * 4;
        data[idx] = r;
        data[idx + 1] = g;
        data[idx + 2] = b;
        data[idx + 3] = 255;

        if (y === Math.round(cy + 8)) {
          crossSection.push(d);
        }
      }
    }
    ctx.putImageData(img, 0, 0);

    // Draw horizontal scanline + live elevation cross-section plot z(x) at bottom
    const scanY = Math.round(cy + 8);
    ctx.strokeStyle = "rgba(56, 189, 248, 0.45)";
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(0, scanY);
    ctx.lineTo(W, scanY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Elevation profile curve overlay at bottom of canvas
    ctx.fillStyle = "rgba(5, 6, 8, 0.72)";
    ctx.fillRect(0, H - 56, W, 56);
    ctx.strokeStyle = mode === "real" ? "#34d399" : "#f87171";
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (let x = 0; x < crossSection.length; x++) {
      const py = H - 10 - crossSection[x] * 40;
      if (x === 0) ctx.moveTo(x, py);
      else ctx.lineTo(x, py);
    }
    ctx.stroke();

    ctx.font = "10px 'SF Mono', ui-monospace, monospace";
    ctx.fillStyle = "#94a3b8";
    ctx.fillText(
      mode === "real"
        ? "z(x) nose-line cross-section: clear 3D nose peak + background cliff"
        : "z(x) nose-line cross-section: flat planar slab (RMSE ≈ 0.004)",
      10,
      H - 42
    );

    if (mode === "real") {
      setBar("mProtrusion", "+0.068", 88, "#34d399");
      setBar("mPlanarity", "0.049 RMSE", 82, "#38bdf8");
      setBar("mCliff", "+0.42", 86, "#34d399");
      setBar("mSpoof", "0% (Live 3D)", 4, "#34d399");
      if (verdictEl) {
        verdictEl.textContent = "UNLOCK VERIFIED · 22.4 ms ANE";
        verdictEl.classList.remove("denied");
      }
    } else {
      setBar("mProtrusion", "+0.001 (Flat)", 4, "#f87171");
      setBar("mPlanarity", "0.004 RMSE", 7, "#f87171");
      setBar("mCliff", "+0.02 (Coplanar)", 6, "#f87171");
      setBar("mSpoof", "94% · flatDepthSpoof", 94, "#f87171");
      if (verdictEl) {
        verdictEl.textContent = "SPOOF BLOCKED · 2D SURFACE";
        verdictEl.classList.add("denied");
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
// 4. Direct Feedback Form (Screenshots + Cloudflare/Brevo + Email App Chooser)
// ---------------------------------------------------------------------------
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

  // Stores up to 3 compressed screenshots: { id, name, dataUrl, base64 }
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
          const ctx = canvas.getContext("2d");
          ctx.drawImage(img, 0, 0, w, h);
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
      rm.setAttribute("aria-label", `Remove ${item.name}`);
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
      statusEl.style.color = "#fbbf24";
      return;
    }
    const candidates = Array.from(fileList).filter((f) => f.type.startsWith("image/")).slice(0, remaining);
    for (const file of candidates) {
      try {
        const compressed = await compressImageFile(file);
        screenshots.push(compressed);
      } catch {
        statusEl.textContent = `Could not process ${file.name}.`;
        statusEl.style.color = "#f87171";
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
      macModel: document.getElementById("fbMac")?.value.trim() || "Unspecified Mac",
      rating: document.getElementById("fbRating")?.value || "5/5",
      message: document.getElementById("fbMessage")?.value.trim() || "",
      attachments: screenshots.map((s) => ({ name: s.name, content: s.base64 })),
    };
  }

  function buildBody(d) {
    return `Category: ${d.category}\nMac / macOS: ${d.macModel}\nRating: ${d.rating}\n\n${d.message}`;
  }

  function buildSubject(d) {
    return `[${d.category}] NEELx Beta Feedback (${d.rating})`;
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const d = collectData();
    if (!d.message) {
      statusEl.textContent = "Please write a short note first.";
      statusEl.style.color = "#f87171";
      return;
    }
    statusEl.textContent = screenshots.length
      ? `Sending feedback + ${screenshots.length} screenshot(s)…`
      : "Sending feedback…";
    statusEl.style.color = "#38bdf8";

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
          ? `Feedback + ${screenshots.length} screenshot(s) sent directly to Chandranil — thank you!`
          : "Feedback sent directly to Chandranil — thank you!";
        statusEl.style.color = "#34d399";
        form.reset();
        screenshots.length = 0;
        renderPreviews();
        return;
      }
    } catch {
      // Fall back cleanly if offline
    }

    const params = new URLSearchParams({
      title: buildSubject(d),
      body: buildBody(d),
    });
    window.open(`https://github.com/${REPO}/issues/new?${params.toString()}`, "_blank", "noopener");
    statusEl.textContent = "Opened pre-filled GitHub Issue.";
    statusEl.style.color = "#34d399";
  });

  githubBtn?.addEventListener("click", () => {
    const d = collectData();
    const params = new URLSearchParams({
      title: buildSubject(d),
      body: buildBody(d),
    });
    window.open(`https://github.com/${REPO}/issues/new?${params.toString()}`, "_blank", "noopener");
  });

  // Email App Chooser popover
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
      window.open(
        `https://mail.google.com/mail/?view=cm&fs=1&to=${encodeURIComponent(FEEDBACK_EMAIL)}&su=${subject}&body=${body}`,
        "_blank",
        "noopener"
      );
      statusEl.textContent = "Opened pre-filled draft in Gmail.";
      statusEl.style.color = "#34d399";
    } else if (client === "outlook") {
      window.open(
        `https://outlook.live.com/mail/0/deeplink/compose?to=${encodeURIComponent(FEEDBACK_EMAIL)}&subject=${subject}&body=${body}`,
        "_blank",
        "noopener"
      );
      statusEl.textContent = "Opened pre-filled draft in Outlook Web.";
      statusEl.style.color = "#34d399";
    } else if (client === "yahoo") {
      window.open(
        `https://compose.mail.yahoo.com/?to=${encodeURIComponent(FEEDBACK_EMAIL)}&subject=${subject}&body=${body}`,
        "_blank",
        "noopener"
      );
      statusEl.textContent = "Opened pre-filled draft in Yahoo Mail.";
      statusEl.style.color = "#34d399";
    } else if (client === "native") {
      const a = document.createElement("a");
      a.href = `mailto:${FEEDBACK_EMAIL}?subject=${subject}&body=${body}`;
      a.style.display = "none";
      document.body.appendChild(a);
      a.click();
      a.remove();
      statusEl.textContent = "Handed draft to your default Mail app.";
      statusEl.style.color = "#34d399";
    } else if (client === "copy") {
      try {
        await navigator.clipboard.writeText(`To: ${FEEDBACK_EMAIL}\nSubject: ${buildSubject(d)}\n\n${buildBody(d)}`);
        statusEl.textContent = `Copied draft & ${FEEDBACK_EMAIL} to clipboard!`;
        statusEl.style.color = "#34d399";
      } catch {
        statusEl.textContent = `Email: ${FEEDBACK_EMAIL}`;
        statusEl.style.color = "#38bdf8";
      }
    }
  });
}

document.addEventListener("DOMContentLoaded", () => {
  syncLatestRelease();
  initEnrollmentSimulator();
  initDepthLab();
  initFeedbackForm();
});
