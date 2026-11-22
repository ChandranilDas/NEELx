<p align="center">
  <img src="website/assets/neelx-logo.png" width="112" height="112" alt="NEELx Official Logo" />
</p>

# NEELx — Fast, Hardened 3D Biometric Face Unlock for macOS

<p align="center">
  <a href="https://github.com/ChandranilDas/NEELx/releases"><img src="https://img.shields.io/github/v/release/ChandranilDas/NEELx?style=flat-square&color=0A84FF&label=Latest%20Release" alt="Latest Release" /></a>
  <a href="https://github.com/ChandranilDas/NEELx/releases"><img src="https://img.shields.io/github/downloads/ChandranilDas/NEELx/total.svg?style=flat-square&color=30D158&label=Total%20Downloads" alt="Total Downloads" /></a>
  <img src="https://hits.sh/github.com/ChandranilDas/NEELx.svg?style=flat-square&label=GitHub%20Visitors&color=64D2FF" alt="GitHub Visitors" />
  <a href="https://chandranildas.github.io/NEELx/"><img src="https://hits.sh/chandranildas.github.io/NEELx.svg?style=flat-square&label=Site%20Visitors&color=BF5AF2" alt="Website Visitors" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-FFD60A.svg?style=flat-square" alt="License: MIT" /></a>
</p>

**NEELx** brings fast, natural, 3D biometric Face Unlock to **macOS** using any standard built-in or USB RGB webcam — **no IR camera required, 100% offline, hardware-encrypted at rest, and open-source (MIT License).**

> **Official Website:** [https://chandranildas.github.io/NEELx/](https://chandranildas.github.io/NEELx/)  
> **Compatibility:** macOS 15+ — Native Universal Binary (`arm64` + `x86_64`) for **Apple Silicon (M1, M2, M3, M4, M5 & all newer chips)** + Intel Macs.

---

## 🎯 About NEELx & Visual Identity

NEELx runs completely offline on your Mac with zero cloud servers and zero telemetry:

- **Notch Face ID**: Expands smoothly out of the MacBook hardware notch with an iPhone/iPad Pro-inspired 80-tick 360° enrollment ring, live Lighting Readiness Meter, emerald checkmark dissolve, and Force Touch haptic feedback.

---

## ✨ Key Features

- **Floating "Welcome Back (Name)!" Unlock Notification**: Shows a sleek, non-intrusive floating glass pill at the top of the screen (`"Welcome Back, <Name>!"`) with a subtle spring entrance and graceful retreat right after successful face authorization (includes settings toggle and 1-click live preview in Settings → General).
- **Smooth 360° Circular Face Enrollment + Live Lighting Readiness Meter**: Slowly roll your head in one natural circle while a live micro-pill (`Ideal Lighting` / `Backlit · HDR Active` / `Low Light · Studio Fill`) guides optimal 512-D ArcFace + **9-zone 3D depth** capture.
- **Face ID for System Touch ID & Password Prompts**: Approves macOS Touch ID & admin password prompts everywhere — System Settings, app/pkg installers, Saved Passwords (Safari, Chrome, Passwords app), Finder, and Keychain — while strictly excluding Apple Pay, payments, and FileVault.
- **Stage 3 Neural 3D Depth + Multi-Frame Temporal Consistency (Apple Neural Engine)**: Runs Apple's Core ML `DepthAnythingV2SmallF16` in FP16 (~22.6 ms on ANE), validating nose protrusion, non-planar surface curvature, head-to-background cliff, and **2 consecutive physically consistent 3D frames**.
- **Backlit Window HDR Shadow Recovery**: GPU Core Image tone mapping (`CIHighlightShadowAdjust`) lifts crushed facial shadows when sitting with a bright sunlit window behind you.
- **Luxury Studio Light Softbox & Spectral Chromatic Rim (with Live Preview)**: Crystal-clear screen center surrounded by a 3800K warm champagne perimeter softbox + softened pastel cyan/magenta reflection check against 4K video replay. Preview anytime via **Settings → General → Preview**.
- **Subtle Spatial Haptic + Optional Soft Glass Sound Cue**: Trackpad `.alignment` haptic + optional muted Glass chime (off by default).
- **iPhone & iPad Pro Continuity Studio (Desk Stand / Studio Optics)**: Seamlessly use your iPhone (iOS 16+) or iPad Pro camera for studio-quality 4K optics, dual-path concurrent unlock, and Bluetooth LE arm's-reach proximity gating (< 1.5m). Works on any standard desk stand, wireless charger, kickstand case, or monitor mount — no proprietary laptop clip required! Includes live hardware cross-checks.
- **Attention & Eye Gaze Verification**: Checks open eyes (`EAR`) and active gaze before unlocking.
- **Hardcoded Zero-Compromise Security**: 3D Neural Depth (ANE), Eye Gaze, and Multi-Frame Anti-Spoofing are hardcoded active so security cannot be accidentally disabled.
- **Silent Adaptive Learning, Encrypted Intruder Log, Walk-Away Auto-Lock & Smart Clamshell Camera**.
- **Auto Local-Cert Signing & 1-Click GitHub Auto-Updater**: Preserves your own free local `Apple Development` certificate on upgrades so macOS Accessibility & Keychain permissions stay intact.

---

## 🚀 Quick Start & Terminal Commands

### Requirements
- **macOS 15.0 (Sequoia)** or later
- **Apple Silicon (M1, M2, M3, M4, M5 & newer)** or **Intel Mac** (no upper chip limit)
- Built-in FaceTime HD / Center Stage camera or external USB / Continuity webcam

### Method 1: 1-Click Terminal Quick Install (Recommended — Zero Gatekeeper Blocks)
Downloads the pre-bundled all-in-one package, automatically clears macOS Gatekeeper quarantine (`xattr -cr`), installs to `/Applications`, and launches automatically:
```bash
curl -fsSL https://chandranildas.github.io/NEELx/install.sh | bash
```

### Method 2: Install via Homebrew Cask
```bash
brew tap ChandranilDas/NEELx https://github.com/ChandranilDas/NEELx
brew install --cask neelx
```

### Method 3: Build Directly from Pure Swift Source
```bash
git clone https://github.com/ChandranilDas/NEELx.git
cd NEELx
chmod +x build.sh
./build.sh --with-depth --install
```

### 📋 Step-by-Step Guide for Mac Users
1. **Install:** Run the 1-click terminal command above (or install via Homebrew). It bypasses browser quarantine automatically so the app opens instantly with zero alerts.
2. **Setup Face & Password:** When prompted, allow camera access. Slowly roll your head in a natural 360° circle while the live meter captures 9 poses and your 3D depth profile. Enter your Mac password once to save it to your local hardware Touch ID Keychain vault.
3. **Instant 3D Unlock:** Press `Cmd + Ctrl + Q` to lock your Mac. Sit in front of your display: NEELx verifies your 3D facial structure in ~25ms on the Neural Engine and unlocks instantly!
4. **Uninstall (if needed):** In the menu bar, click NEELx → **Quit**, then run:
   ```bash
   curl -fsSL https://chandranildas.github.io/NEELx/uninstall.sh | bash
   ```

---

## 🔒 Security Architecture & Threat Model

| Security Layer | macOS 15+ Implementation |
| :--- | :--- |
| **Unlock Visual Language** | Notch Face ID 80-tick circular ring + emerald checkmark |
| **Identity Matching** | 512-D ArcFace Core ML (ANE, `threshold = 0.63`) |
| **3D Neural Depth** | Core ML `DepthAnythingV2SmallF16` (FP16 ANE, ~22.6 ms) |
| **Multi-Frame Guard** | 2 consecutive physically consistent 3D frames + 9-zone profile |
| **Backlit & Dark Rooms** | GPU Core Image HDR shadow lift + 3800K Studio Light & Spectral Rim |
| **Credential Storage** | AES-256-GCM + macOS Keychain (`WhenUnlockedThisDeviceOnly`) + Touch ID |
| **System / Lock Integration** | Lock Screen + System Touch ID & Password Prompts (Apple Pay excluded) |
| **Mobile & Proximity Optics** | iPhone/iPad Desk Stand Continuity Camera + Dual-Path Unlock + BLE Proximity Guard (< 1.5m) |

> **Transparency Note**: Standard webcams capture 2D RGB frames rather than infrared dot projections (TrueDepth / IR). NEELx maximizes security within 2D webcam limits using 512-D ArcFace, Stage 3 monocular 3D Depth, multi-frame temporal depth consistency, eye attention checks, and anti-replay heuristics.

---

## 🛠️ Required OS Permissions

1. **Camera**: Used strictly on-device during enrollment, Lock Screen unlock, and system auth prompts.
2. **Accessibility**: Allows NEELx to securely enter your decrypted password into macOS login and system authorization prompts upon verified 3D Face ID match.

---

## 🗺️ Roadmap

- [x] 360° Circular Notch Face Enrollment + Live Lighting Readiness Meter
- [x] Sub-200ms Unlock Pipeline + 3ms Keystroke Injection
- [x] Eye Gaze & Attention Verification
- [x] Luxury Studio Light Softbox & Spectral Chromatic Rim (with Live Preview)
- [x] Backlit Window HDR Shadow Recovery
- [x] Face ID for System Touch ID & Password Prompts (Apple Pay excluded)
- [x] Stage 3 Neural 3D Depth + Multi-Frame Temporal Consistency (Apple Silicon ANE)
- [x] Subtle Spatial Haptic + Optional Soft Glass Sound Cue
- [x] Universal Binary (Apple Silicon M1–M5+ & Intel), Homebrew Cask & Auto-Updater

---

## 🤝 Contributing & Feedback

Contributions, bug reports, security audits, and test results across **macOS (Apple Silicon M1, M2, M3, M4, M5 & newer, Intel Macs, external webcams)** are very welcome!
- Send feedback directly from the [**Official Website**](https://chandranildas.github.io/NEELx/#feedback), from inside the macOS app via **Menu Bar → Send Feedback…**, or open a [GitHub Issue](https://github.com/ChandranilDas/NEELx/issues).

---

## 📄 License & Credits

Released under the **MIT License** — see [LICENSE](LICENSE).  
NEELx is built upon and heavily evolved from [Glance](https://github.com/jonnyoo/glance) by Jonathan Zhou.
