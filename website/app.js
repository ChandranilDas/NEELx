// NEELx Official Website — Multi-Tab Interactive Engine
// Features:
//  - Smooth animated multi-tab navigation + URL hash sync
//  - Proper sculpted 3D vector human face rotating in true 3D perspective inside the 80-tick enrollment ring
//  - Interactive Backlit HDR Shadow Recovery before/after split demo
//  - Interactive Studio Light & Chromatic Prism Rim simulator
//  - Interactive Stage 3 Neural 3D Depth Inferno heatmap + cross-section
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
      activateTab(el.getAttribute("data-go-tab"));
    });
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

    if (macAsset) {
      const mb = (macAsset.size / (1024 * 1024)).toFixed(1);
      const macBtn = document.getElementById("btnDownloadMac") || document.getElementById("btnDownloadFull");
      const macSize = document.getElementById("macSize") || document.getElementById("fullSize");
      if (macBtn) macBtn.href = macAsset.browser_download_url;
      if (macSize) macSize.textContent = `${mb} MB · Universal`;
    }
  } catch {
    // Keep pre-populated links seamlessly
  }
}

// ---------------------------------------------------------------------------
// Shared Sculpted 3D Human Face Renderer (used across macOS & Depth Lab)
// ---------------------------------------------------------------------------
function renderSculptedHumanFace(ctx, opts) {
  const {
    cx,
    cy,
    scale = 1,
    yaw = 0,
    pitch = 0,
    blinkPhase = 0,
    isComplete = false,
    strokeMain = null,
    strokeSoft = null,
    fillTop = null,
    fillMid = null,
    fillEdge = null,
    pupilColor = null,
    showShoulders = true,
    showMeridians = true,
    showEars = true,
    smileBoost = 0,
    lineWidthScale = 1,
    shadowGlow = null,
  } = opts;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(scale, scale);

  if (shadowGlow) {
    ctx.shadowColor = shadowGlow;
    ctx.shadowBlur = 12;
  }

  // 3D Perspective Projection Engine (True anatomical 3D projection)
  const FOV = 320;
  function p3d(x, y, z) {
    const thetaY = yaw * 0.62;
    const thetaX = pitch * 0.48;
    const cosY = Math.cos(thetaY), sinY = Math.sin(thetaY);
    const cosX = Math.cos(thetaX), sinX = Math.sin(thetaX);

    // Rotate Y (yaw)
    const x1 = x * cosY + z * sinY;
    const z1 = -x * sinY + z * cosY;

    // Rotate X (pitch) - aligned with screen coordinate space (+Y is down)
    const y2 = y * cosX + z1 * sinX;
    const z2 = -y * sinX + z1 * cosX;

    const p = FOV / (FOV - z2);
    return { x: x1 * p, y: y2 * p, z: z2, p };
  }

  // Key light vector tracking cursor/pose
  const lightPt = p3d(-26, -38, 32);
  const lightX = lightPt.x;
  const lightY = lightPt.y;

  // Neck & Shoulders (anatomical base)
  if (showShoulders) {
    const neckBase = p3d(0, 52, -5);
    const neckTop = p3d(0, 32, -2);

    // Trapezius / shoulders
    ctx.fillStyle = isComplete ? "rgba(48, 209, 88, 0.08)" : "rgba(255, 255, 255, 0.06)";
    ctx.beginPath();
    ctx.ellipse(neckBase.x * 0.6, 58 + neckBase.y * 0.35, 46, 22, 0, Math.PI, Math.PI * 2);
    ctx.fill();

    // Cylindrical neck with throat shadow
    const neckGrad = ctx.createLinearGradient(neckTop.x - 14, neckTop.y, neckTop.x + 14, neckTop.y);
    neckGrad.addColorStop(0, "rgba(22, 26, 36, 0.75)");
    neckGrad.addColorStop(0.45, "rgba(85, 92, 108, 0.45)");
    neckGrad.addColorStop(1, "rgba(18, 20, 28, 0.85)");
    ctx.fillStyle = neckGrad;
    ctx.beginPath();
    ctx.moveTo(neckTop.x - 15, neckTop.y);
    ctx.lineTo(neckBase.x - 20, 56);
    ctx.lineTo(neckBase.x + 20, 56);
    ctx.lineTo(neckTop.x + 15, neckTop.y);
    ctx.closePath();
    ctx.fill();
  }

  // 3D Ears with realistic parallax occlusion (rear ear hides behind skull, front ear expands)
  if (showEars) {
    const earL = p3d(-31.5, -3, -10);
    const earR = p3d(31.5, -3, -10);

    function drawEar(pt, isLeft) {
      if ((isLeft && yaw > 0.45) || (!isLeft && yaw < -0.45)) return;
      ctx.save();
      const earGrad = ctx.createRadialGradient(pt.x, pt.y, 2, pt.x, pt.y, 11);
      earGrad.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.3)" : "rgba(165, 172, 188, 0.28)");
      earGrad.addColorStop(1, "rgba(18, 22, 30, 0.65)");
      ctx.fillStyle = earGrad;
      ctx.strokeStyle = strokeSoft || (isComplete ? "rgba(48, 209, 88, 0.45)" : "rgba(255, 255, 255, 0.28)");
      ctx.lineWidth = 1.1 * lineWidthScale;
      ctx.beginPath();
      const dir = isLeft ? -1 : 1;
      ctx.ellipse(pt.x, pt.y, 5.5 * pt.p, 11.5 * pt.p, dir * 0.15, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();

      // Inner helix curve
      ctx.beginPath();
      ctx.arc(pt.x - dir * 1.5, pt.y - 1.5, 3.2, 0, Math.PI);
      ctx.stroke();
      ctx.restore();
    }

    if (yaw >= 0) {
      drawEar(earL, true);
      drawEar(earR, false);
    } else {
      drawEar(earR, false);
      drawEar(earL, true);
    }
  }

  // Cranium Top & Jawline Boundary (projected 3D points)
  const topForehead = p3d(0, -36, 12);
  const leftTemple = p3d(-26, -24, 6);
  const rightTemple = p3d(26, -24, 6);
  const leftCheek = p3d(-29, 2, 8);
  const rightCheek = p3d(29, 2, 8);
  const leftJaw = p3d(-23, 23, 7);
  const rightJaw = p3d(23, 23, 7);
  const chin = p3d(0, 39, 15);

  // Volumetric Head Shading Gradient (Reacts dynamically to virtual key light!)
  const faceGrad = ctx.createRadialGradient(
    lightX, lightY, 6,
    p3d(0, 0, 5).x, p3d(0, 0, 5).y, 48 * topForehead.p
  );
  if (isComplete) {
    faceGrad.addColorStop(0, "rgba(48, 209, 88, 0.38)");
    faceGrad.addColorStop(0.35, "rgba(35, 160, 68, 0.22)");
    faceGrad.addColorStop(0.72, "rgba(18, 70, 32, 0.28)");
    faceGrad.addColorStop(1, "rgba(8, 24, 14, 0.65)");
  } else {
    faceGrad.addColorStop(0, fillTop || "rgba(240, 243, 252, 0.32)");
    faceGrad.addColorStop(0.32, fillMid || "rgba(145, 154, 172, 0.18)");
    faceGrad.addColorStop(0.72, "rgba(45, 52, 68, 0.25)");
    faceGrad.addColorStop(1, fillEdge || "rgba(14, 18, 26, 0.65)");
  }

  // Sculpted anatomical head shape
  ctx.fillStyle = faceGrad;
  ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
  ctx.lineWidth = 1.65 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(topForehead.x, topForehead.y);
  ctx.bezierCurveTo(rightTemple.x, rightTemple.y - 10, rightCheek.x + 3, rightCheek.y - 8, rightCheek.x, rightCheek.y);
  ctx.bezierCurveTo(rightCheek.x - 2, rightCheek.y + 16, rightJaw.x + 2, rightJaw.y + 4, rightJaw.x, rightJaw.y);
  ctx.bezierCurveTo(rightJaw.x - 7, rightJaw.y + 12, chin.x + 12, chin.y + 2, chin.x, chin.y);
  ctx.bezierCurveTo(chin.x - 12, chin.y + 2, leftJaw.x + 7, leftJaw.y + 12, leftJaw.x, leftJaw.y);
  ctx.bezierCurveTo(leftJaw.x - 2, leftJaw.y + 4, leftCheek.x + 2, leftCheek.y + 16, leftCheek.x, leftCheek.y);
  ctx.bezierCurveTo(leftCheek.x - 3, leftCheek.y - 8, leftTemple.x, leftTemple.y - 10, topForehead.x, topForehead.y);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Cheekbone Specular Highlights (Zygomatic Prominences)
  const cheekL = p3d(-20, 2, 16);
  const cheekR = p3d(20, 2, 16);
  const cheekGlowL = ctx.createRadialGradient(cheekL.x, cheekL.y, 1, cheekL.x, cheekL.y, 10);
  cheekGlowL.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.22)" : "rgba(255, 255, 255, 0.18)");
  cheekGlowL.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = cheekGlowL;
  ctx.beginPath();
  ctx.arc(cheekL.x, cheekL.y, 10, 0, Math.PI * 2);
  ctx.fill();

  const cheekGlowR = ctx.createRadialGradient(cheekR.x, cheekR.y, 1, cheekR.x, cheekR.y, 10);
  cheekGlowR.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.22)" : "rgba(255, 255, 255, 0.18)");
  cheekGlowR.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = cheekGlowR;
  ctx.beginPath();
  ctx.arc(cheekR.x, cheekR.y, 10, 0, Math.PI * 2);
  ctx.fill();

  // 3D Apple Face ID Structured-Light Topographic Contours (Meridians & Latitudes)
  if (showMeridians) {
    ctx.strokeStyle = strokeSoft || (isComplete ? "rgba(48, 209, 88, 0.38)" : "rgba(255, 255, 255, 0.22)");
    ctx.lineWidth = 0.85 * lineWidthScale;

    // Vertical median contour (follows nose bridge & chin in true 3D)
    const noseBridgeTop = p3d(0, -12, 16);
    const noseTip = p3d(0, 7.5, 28);
    const subNose = p3d(0, 12, 20);
    const mouthCenter = p3d(0, 20 + smileBoost, 18);

    ctx.beginPath();
    ctx.moveTo(topForehead.x, topForehead.y);
    ctx.quadraticCurveTo(p3d(0, -24, 16).x, p3d(0, -24, 16).y, noseBridgeTop.x, noseBridgeTop.y);
    ctx.lineTo(noseTip.x, noseTip.y);
    ctx.lineTo(subNose.x, subNose.y);
    ctx.lineTo(mouthCenter.x, mouthCenter.y);
    ctx.quadraticCurveTo(p3d(0, 28, 17).x, p3d(0, 28, 17).y, chin.x, chin.y);
    ctx.stroke();

    // Horizontal latitude contours (curving around 3D skull, brow, cheeks, and chin)
    const latitudes = [
      [-22, -18, 14], // forehead
      [-8, -5, 16],   // eye socket level
      [14, 12, 20],   // upper lip level
      [27, 24, 16],   // chin groove level
    ];
    for (const [yLev, yMid, zLev] of latitudes) {
      const pL = p3d(-24, yLev, 8);
      const pM = p3d(0, yMid, zLev);
      const pR = p3d(24, yLev, 8);
      ctx.beginPath();
      ctx.moveTo(pL.x, pL.y);
      ctx.quadraticCurveTo(pM.x, pM.y, pR.x, pR.y);
      ctx.stroke();
    }
  }

  // Eye Sockets (Recessed Orbital Cavities with Depth Ambient Shadow)
  const eyeL_center = p3d(-12.5, -6.5, 12);
  const eyeR_center = p3d(12.5, -6.5, 12);

  for (const center of [eyeL_center, eyeR_center]) {
    const socketGrad = ctx.createRadialGradient(center.x, center.y, 1, center.x, center.y, 11);
    socketGrad.addColorStop(0, "rgba(8, 10, 16, 0.45)");
    socketGrad.addColorStop(1, "rgba(8, 10, 16, 0)");
    ctx.fillStyle = socketGrad;
    ctx.beginPath();
    ctx.arc(center.x, center.y, 11, 0, Math.PI * 2);
    ctx.fill();
  }

  // Sculpted Eyebrows (Realistic feathered arch)
  ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
  ctx.lineWidth = 1.95 * lineWidthScale;
  ctx.lineCap = "round";

  const browL_inner = p3d(-4.5, -14, 16);
  const browL_arch = p3d(-12.5, -17, 14);
  const browL_outer = p3d(-20.5, -13, 10);
  ctx.beginPath();
  ctx.moveTo(browL_inner.x, browL_inner.y);
  ctx.quadraticCurveTo(browL_arch.x, browL_arch.y, browL_outer.x, browL_outer.y);
  ctx.stroke();

  const browR_inner = p3d(4.5, -14, 16);
  const browR_arch = p3d(12.5, -17, 14);
  const browR_outer = p3d(20.5, -13, 10);
  ctx.beginPath();
  ctx.moveTo(browR_inner.x, browR_inner.y);
  ctx.quadraticCurveTo(browR_arch.x, browR_arch.y, browR_outer.x, browR_outer.y);
  ctx.stroke();

  // Natural Eyelid Blinking Mechanics (Cosine curve easing: sweeps upper lid smoothly down & up)
  let eyeAperture = 1.0;
  if (blinkPhase > 0.92) {
    const tBlink = (blinkPhase - 0.92) / 0.08;
    eyeAperture = Math.max(0.08, Math.abs(Math.cos(tBlink * Math.PI)));
  }

  // Realistic Eyes (Sclera + Iris + Pupil + Specular Catchlight + Gaze Tracking)
  const gazeX = yaw * 1.5;
  const gazeY = pitch * 1.1;

  for (const [side, center] of [[-1, eyeL_center], [1, eyeR_center]]) {
    const eyeW = 6.2 * center.p;
    const eyeH = 3.6 * center.p * eyeAperture;

    // Eyeball Sclera (Almond shape aperture)
    ctx.save();
    ctx.beginPath();
    ctx.ellipse(center.x, center.y, eyeW, eyeH, side * 0.05, 0, Math.PI * 2);
    ctx.clip();

    // 3D Spherical Sclera Shading (Soft upper eyelid shadow)
    const scleraGrad = ctx.createLinearGradient(center.x, center.y - eyeH, center.x, center.y + eyeH);
    scleraGrad.addColorStop(0, "rgba(140, 148, 165, 0.85)");
    scleraGrad.addColorStop(0.35, "rgba(235, 238, 246, 0.95)");
    scleraGrad.addColorStop(1, "rgba(200, 206, 218, 0.90)");
    ctx.fillStyle = scleraGrad;
    ctx.fillRect(center.x - eyeW - 2, center.y - eyeH - 2, (eyeW + 2) * 2, (eyeH + 2) * 2);

    if (eyeAperture > 0.28) {
      const irisX = center.x + gazeX * center.p;
      const irisY = center.y + gazeY * center.p;
      const irisR = 2.8 * center.p;

      // Iris Limbal Ring & Body
      const irisGrad = ctx.createRadialGradient(irisX, irisY, 0.6, irisX, irisY, irisR);
      if (isComplete) {
        irisGrad.addColorStop(0, "#5ee984");
        irisGrad.addColorStop(0.65, "#30d158");
        irisGrad.addColorStop(1, "#0d451e");
      } else {
        irisGrad.addColorStop(0, pupilColor || "#8898b2");
        irisGrad.addColorStop(0.65, "#3e4859");
        irisGrad.addColorStop(1, "#121720");
      }
      ctx.fillStyle = irisGrad;
      ctx.beginPath();
      ctx.arc(irisX, irisY, irisR, 0, Math.PI * 2);
      ctx.fill();

      // Pupil (Deep obsidian black)
      ctx.fillStyle = "#040608";
      ctx.beginPath();
      ctx.arc(irisX, irisY, 1.35 * center.p, 0, Math.PI * 2);
      ctx.fill();

      // Specular Corneal Catchlight (Crisp white reflection dot toward key light)
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(irisX - 0.7 * center.p, irisY - 0.7 * center.p, 0.65 * center.p, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    // Upper & Lower Eyelid Outline
    ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
    ctx.lineWidth = 1.35 * lineWidthScale;
    ctx.beginPath();
    ctx.ellipse(center.x, center.y, eyeW, eyeH, side * 0.05, 0, Math.PI * 2);
    ctx.stroke();

    // Supratarsal Upper Eyelid Crease
    if (eyeAperture > 0.5) {
      ctx.strokeStyle = strokeSoft || (isComplete ? "rgba(48, 209, 88, 0.35)" : "rgba(255, 255, 255, 0.24)");
      ctx.lineWidth = 0.9 * lineWidthScale;
      ctx.beginPath();
      ctx.arc(center.x, center.y - 3.2 * center.p, eyeW * 0.9, Math.PI * 1.1, Math.PI * 1.9);
      ctx.stroke();
    }
  }

  // Sculpted 3D Nose (Dorsum bridge, lobule tip, alar wings, nostrils)
  const nasion = p3d(0, -9, 16);
  const rhinion = p3d(0, 0, 21);
  const noseTip = p3d(0, 7.5, 28); // Peaks farthest forward for authentic 3D parallax!
  const alarL = p3d(-6.2, 7.8, 20);
  const alarR = p3d(6.2, 7.8, 20);
  const subNose = p3d(0, 10.5, 20);

  // Dorsum Bridge Highlight
  const bridgeGrad = ctx.createLinearGradient(nasion.x, nasion.y, noseTip.x, noseTip.y);
  bridgeGrad.addColorStop(0, strokeSoft || (isComplete ? "rgba(48, 209, 88, 0.45)" : "rgba(255, 255, 255, 0.35)"));
  bridgeGrad.addColorStop(1, strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.95)"));
  ctx.strokeStyle = bridgeGrad;
  ctx.lineWidth = 1.65 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(nasion.x, nasion.y);
  ctx.lineTo(rhinion.x, rhinion.y);
  ctx.lineTo(noseTip.x, noseTip.y);
  ctx.stroke();

  // Nasal Tip Specular Highlight Bulb
  const tipGlow = ctx.createRadialGradient(noseTip.x - 1, noseTip.y - 1, 0.5, noseTip.x, noseTip.y, 4 * noseTip.p);
  tipGlow.addColorStop(0, isComplete ? "#5ee984" : "#ffffff");
  tipGlow.addColorStop(0.5, isComplete ? "rgba(48, 209, 88, 0.35)" : "rgba(255, 255, 255, 0.25)");
  tipGlow.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = tipGlow;
  ctx.beginPath();
  ctx.arc(noseTip.x, noseTip.y, 4 * noseTip.p, 0, Math.PI * 2);
  ctx.fill();

  // Alar Wings (Left & Right curved nostrils)
  ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
  ctx.lineWidth = 1.35 * lineWidthScale;
  ctx.beginPath();
  // Left nostril wing
  ctx.moveTo(noseTip.x, noseTip.y);
  ctx.bezierCurveTo(noseTip.x - 3.5, noseTip.y + 2.2, alarL.x, alarL.y + 1.8, alarL.x, alarL.y);
  // Right nostril wing
  ctx.moveTo(noseTip.x, noseTip.y);
  ctx.bezierCurveTo(noseTip.x + 3.5, noseTip.y + 2.2, alarR.x, alarR.y + 1.8, alarR.x, alarR.y);
  ctx.stroke();

  // Subnasal shadow
  ctx.fillStyle = "rgba(10, 12, 18, 0.55)";
  ctx.beginPath();
  ctx.ellipse(subNose.x, subNose.y, 4.2 * subNose.p, 1.4 * subNose.p, 0, 0, Math.PI * 2);
  ctx.fill();

  // Sculpted Lips & Philtrum (Cupid's Bow, Vermilion Border, Full Lower Lip)
  const cupidPeakL = p3d(-3.8, 17, 18);
  const cupidPeakR = p3d(3.8, 17, 18);
  const cupidDip = p3d(0, 17.8, 18);
  const lipCornerL = p3d(-9.8, 19 + smileBoost * 0.4, 14);
  const lipCornerR = p3d(9.8, 19 + smileBoost * 0.4, 14);
  const lowerLipBottom = p3d(0, 24 + smileBoost, 17);

  // Philtrum column indentations
  ctx.strokeStyle = strokeSoft || (isComplete ? "rgba(48, 209, 88, 0.35)" : "rgba(255, 255, 255, 0.2)");
  ctx.lineWidth = 0.85 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(subNose.x - 1.8, subNose.y);
  ctx.lineTo(cupidPeakL.x, cupidPeakL.y);
  ctx.moveTo(subNose.x + 1.8, subNose.y);
  ctx.lineTo(cupidPeakR.x, cupidPeakR.y);
  ctx.stroke();

  // Upper Lip (Cupid's bow vermilion contour)
  ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
  ctx.lineWidth = 1.45 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(lipCornerL.x, lipCornerL.y);
  ctx.quadraticCurveTo(cupidPeakL.x - 1, cupidPeakL.y, cupidPeakL.x, cupidPeakL.y);
  ctx.quadraticCurveTo(cupidDip.x, cupidDip.y, cupidPeakR.x, cupidPeakR.y);
  ctx.quadraticCurveTo(cupidPeakR.x + 1, cupidPeakR.y, lipCornerR.x, lipCornerR.y);
  ctx.stroke();

  // Oral Fissure (Center parting line between lips)
  ctx.strokeStyle = isComplete ? "#30d158" : "rgba(18, 22, 30, 0.85)";
  ctx.lineWidth = 1.6 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(lipCornerL.x, lipCornerL.y);
  ctx.quadraticCurveTo(cupidDip.x, cupidDip.y + 1.2, lipCornerR.x, lipCornerR.y);
  ctx.stroke();

  // Full Lower Lip (Volumetric contour + central light catch)
  ctx.strokeStyle = strokeMain || (isComplete ? "rgba(48, 209, 88, 0.95)" : "rgba(245, 245, 247, 0.92)");
  ctx.lineWidth = 1.4 * lineWidthScale;
  ctx.beginPath();
  ctx.moveTo(lipCornerL.x + 1.2, lipCornerL.y);
  ctx.quadraticCurveTo(lowerLipBottom.x, lowerLipBottom.y, lipCornerR.x - 1.2, lipCornerR.y);
  ctx.stroke();

  // Soft specular catchlight on lower lip
  const lipGlow = ctx.createRadialGradient(lowerLipBottom.x, lowerLipBottom.y - 1.5, 0.5, lowerLipBottom.x, lowerLipBottom.y - 1.5, 5);
  lipGlow.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.35)" : "rgba(255, 255, 255, 0.28)");
  lipGlow.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = lipGlow;
  ctx.beginPath();
  ctx.ellipse(lowerLipBottom.x, lowerLipBottom.y - 1.5, 4.5, 1.8, 0, 0, Math.PI * 2);
  ctx.fill();

  // Sublabial groove shadow + Chin Highlight (Mental Protuberance)
  const chinCenter = p3d(0, 33, 16);
  ctx.fillStyle = "rgba(10, 12, 18, 0.35)";
  ctx.beginPath();
  ctx.ellipse(p3d(0, 27, 14).x, p3d(0, 27, 14).y, 6.5, 2.2, 0, 0, Math.PI * 2);
  ctx.fill();

  const chinGlow = ctx.createRadialGradient(chinCenter.x, chinCenter.y, 1, chinCenter.x, chinCenter.y, 8);
  chinGlow.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.25)" : "rgba(255, 255, 255, 0.22)");
  chinGlow.addColorStop(1, "rgba(255, 255, 255, 0)");
  ctx.fillStyle = chinGlow;
  ctx.beginPath();
  ctx.arc(chinCenter.x, chinCenter.y, 8, 0, Math.PI * 2);
  ctx.fill();

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

    // Subtle dark-glass camera vignette lens circle behind the face
    const bgGrad = ctx.createRadialGradient(yaw * 12, pitch * 10 - 8, 6, 0, 0, 64);
    bgGrad.addColorStop(0, isComplete ? "rgba(48, 209, 88, 0.18)" : "rgba(255, 255, 255, 0.08)");
    bgGrad.addColorStop(0.7, isComplete ? "rgba(20, 80, 40, 0.22)" : "rgba(18, 22, 32, 0.65)");
    bgGrad.addColorStop(1, "rgba(6, 8, 12, 0.95)");
    ctx.fillStyle = bgGrad;
    ctx.beginPath();
    ctx.arc(0, 0, 63, 0, Math.PI * 2);
    ctx.fill();

    // Clip to camera lens circle
    ctx.beginPath();
    ctx.arc(0, 0, 62, 0, Math.PI * 2);
    ctx.clip();

    ctx.restore();

    // Subtle procedural breathing micro-motion
    const breath = Math.sin(Date.now() * 0.0025) * 0.02;

    // Render realistic 3D sculpted human head with natural blinking & tracking
    renderSculptedHumanFace(ctx, {
      cx,
      cy,
      scale: 1.0 + breath,
      yaw,
      pitch,
      blinkPhase,
      isComplete,
      showShoulders: true,
      showMeridians: true,
      showEars: true,
      smileBoost: isComplete ? 2.5 : 0,
      shadowGlow: isComplete ? "rgba(48, 209, 88, 0.45)" : null,
    });
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

function detectBasicBrowserEnv() {
  const ua = navigator.userAgent || "";
  const os = /Mac OS X/i.test(ua)
    ? "macOS"
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


// ---------------------------------------------------------------------------
// 8. Interactive 3D Card Perspective Tilt & Dynamic Glare Engine
// ---------------------------------------------------------------------------
function init3DCardTilt() {
  const cards = document.querySelectorAll(
    ".feature-card, .spec-tile, .notch-stage, .download-card, .demo-card, .card, .step-card"
  );

  cards.forEach((card) => {
    if (card.dataset.tiltInitialized) return;
    card.dataset.tiltInitialized = "true";
    card.classList.add("tilt-3d");

    let glare = card.querySelector(".card-3d-glare");
    if (!glare) {
      glare = document.createElement("div");
      glare.className = "card-3d-glare";
      card.appendChild(glare);
    }

    let rafId = null;

    card.addEventListener("mousemove", (e) => {
      const rect = card.getBoundingClientRect();
      const x = (e.clientX - rect.left) / rect.width;
      const y = (e.clientY - rect.top) / rect.height;

      const tiltX = (0.5 - y) * 11;
      const tiltY = (x - 0.5) * 11;

      if (rafId) cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        card.style.transform = `perspective(1000px) rotateX(${tiltX.toFixed(2)}deg) rotateY(${tiltY.toFixed(2)}deg) translateZ(6px) scale3d(1.015, 1.015, 1.015)`;
        card.style.boxShadow = `${(-tiltY * 1.5).toFixed(1)}px ${(tiltX * 1.5 + 14).toFixed(1)}px 32px rgba(0, 0, 0, 0.45)`;
        glare.style.opacity = "1";
        glare.style.background = `radial-gradient(circle at ${(x * 100).toFixed(1)}% ${(y * 100).toFixed(1)}%, rgba(255, 255, 255, 0.14) 0%, rgba(255, 255, 255, 0.03) 45%, transparent 75%)`;
      });
    });

    card.addEventListener("mouseleave", () => {
      if (rafId) cancelAnimationFrame(rafId);
      card.style.transition = "transform 0.45s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.45s cubic-bezier(0.16, 1, 0.3, 1)";
      card.style.transform = "perspective(1000px) rotateX(0deg) rotateY(0deg) translateZ(0px) scale3d(1, 1, 1)";
      card.style.boxShadow = "";
      glare.style.opacity = "0";
      setTimeout(() => {
        card.style.transition = "";
      }, 450);
    });

    card.addEventListener("mouseenter", () => {
      card.style.transition = "transform 0.1s ease-out, box-shadow 0.1s ease-out";
    });
  });
}

document.addEventListener("DOMContentLoaded", () => {
  initTabs();
  initCopyButtons();
  syncLatestRelease();
  initEnrollmentSimulator();
  initHowItWorksDemos();
  initDepthLab();
  initMacNotchArchCanvas();
  initFeedbackForm();
  init3DCardTilt();
});
