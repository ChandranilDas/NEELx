# NEELx — Fast, Hardened Biometric Face Unlock for macOS

**NEELx** brings fast, natural, iPhone-style Face Unlock to macOS using your Mac's built-in camera and Apple Neural Engine — **100% offline, encrypted at rest, and open-source.**

> **Official Website:** [https://chandranildas.github.io/NEELx/](https://chandranildas.github.io/NEELx/)  
> Built for **macOS 15+ (Apple Silicon M1 & newer — M1, M2, M3, M4, M5+, plus Intel)** and **Windows 11 (`windows/` Edition)**. Runs 100% offline on-device with zero telemetry and hardware-backed encryption.

---

## ✨ Key Features

- **Smooth 360° Circular Face Enrollment + Live Lighting Readiness Meter**: Guided notch onboarding just like Face ID on iPhone and iPad Pro — slowly roll your head in one natural circle while a live lighting meter (`Ideal Lighting` / `Backlit · HDR Active` / `Low Light · Studio Fill`) guides optimal capture of your 512-D ArcFace template and **9-zone 3D facial depth profile**.
- **Face ID for System Touch ID & Password Prompts**: Automatically replaces macOS password/Touch ID authorization prompts (System Settings Privacy & Security toggles, Keychain/Saved Passwords, App Store/Installer auth, and standard admin sheets) with hands-free 3D Face ID — while strictly excluding Apple Pay, payments, FileVault, and sensitive financial dialogs.
- **Stage 3 Neural 3D Depth + Multi-Frame Temporal Consistency (Apple Neural Engine)**: Powered by Apple's Core ML `DepthAnythingV2SmallF16` running in FP16 (~22ms on Apple Silicon ANE). Validates **3D nose protrusion**, **non-planar facial curvature**, **head-to-background depth cliff**, and requires **2 consecutive physically consistent 3D depth frames** — rejecting flat photos, phone/tablet screens, and transient OLED glare.
- **Backlit Window HDR Shadow Recovery**: Detects silhouetted backlit scenes (bright window behind your head, dark face in front) and applies GPU `CIHighlightShadowAdjust` shadow lift before face detection — seamlessly recovering darkened faces without waiting for dark-room mode.
- **Luxury Studio Light & Spectral Chromatic Rim (with Live Preview)**: Redesigned dark-room softbox fills your display perimeter with an even 3800K warm champagne frame while keeping the center crystal clear, paired with a refined pastel-blended cyan/magenta reflection check against 4K video replays. Test it anytime via **Settings → General → Preview**.
- **Subtle Spatial Haptic + Optional Soft Glass Sound Cue**: Crisp Force Touch trackpad `.alignment` haptic and optional whisper-soft unlock chime synced with the Face ID emerald checkmark dissolve.
- **Attention & Eye Gaze Verification**: "Require Attention for Face ID" — checks Eye Aspect Ratio (`EAR`) and head orientation before unlocking.
- **Silent Adaptive Learning**: Automatically adapts to gradual changes (glasses, beard, lighting drift) from high-confidence 3D-verified unlocks.
- **Encrypted Intruder & Security Audit Log**: Records unlock attempts and AES-256-GCM encrypted snapshots of blocked intruders/spoofs strictly offline under your Touch ID key.
- **Walk-Away Auto-Lock (Presence Lock)**: Optional zero-drain idle presence check that locks your Mac automatically when you step away.
- **Smart Clamshell / Multi-Camera Auto-Switching**: Automatically switches to an external webcam or iPhone Continuity Camera when your MacBook lid is closed.
- **Windows 11 Edition (`windows/`) — Fluent Prism Horizon**: Native `.NET 8` WPF + **ONNX Runtime DirectML** + **Windows DPAPI** + `ICredentialProvider` lock-screen architecture for Windows 11 laptops and desktops with standard RGB webcams, featuring a bespoke Windows-native **Fluent Prism Horizon** faceted diamond-iris & laser sweep animation (intentionally distinct from macOS/iPhone's circular Face ID).
- **Zero-Cloud Privacy & Local Signing**:
  - Touch ID (`LocalAuthentication`) gates access to your session key.
  - 256-bit AES-GCM key in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) encrypts credentials, embeddings, and audit logs.
  - Auto-preserves your own free local `Apple Development` certificate on updates so macOS Accessibility permissions survive seamlessly.

---

## 🚀 Quick Start (Build & Install in 1 Command)

### Requirements
- **macOS 15.0 (Sequoia)** or later
- **Xcode** (for `swiftc`, `coremlc`, and `actool`)
- Built-in FaceTime HD / Center Stage camera or external USB webcam

### Install via Homebrew Cask (Recommended)

```bash
brew tap ChandranilDas/NEELx https://github.com/ChandranilDas/NEELx
brew install --cask neelx
```

### Or Download the DMG Directly

Download `NEELx-v2.0.0-beta.5-universal-lite.dmg` (Universal Apple Silicon M1 & newer + Intel, 1-click in-app 3D Depth download) or the full offline DMG from the [**Official Website**](https://chandranildas.github.io/NEELx/) or [**GitHub Releases**](https://github.com/ChandranilDas/NEELx/releases), drag **NEELx.app** into **Applications**, and launch! NEELx includes a built-in **GitHub Releases Auto-Updater** (**Menu Bar → Check for Updates…**) so future beta updates install and relaunch in one click while keeping your enrolled face and Keychain credentials intact.

### Windows 11 Edition (`windows/`)

See [`windows/README.md`](windows/README.md) for the native `.NET 8` WPF + DirectML GPU/NPU + DPAPI + WinLogon `ICredentialProvider` implementation featuring the bespoke **Fluent Prism Horizon** unlock blade.

### Or Build From Source

```bash
git clone https://github.com/ChandranilDas/NEELx.git
cd NEELx
chmod +x build.sh
./build.sh --with-depth --install
```

This script automatically:
1. Downloads Apple's official Core ML `DepthAnythingV2SmallF16.mlpackage` (when `--with-depth` is passed) and compiles both `ArcFace.mlpackage` and `DepthAnythingV2SmallF16.mlpackage` plus the asset catalog from pure source.
2. Compiles all Swift sources with `-O -whole-module-optimization` for your Mac's native architecture (`arm64` or `x86_64`).
3. Ad-hoc signs `NEELx.app` with camera entitlements (no paid Apple Developer account required).
4. Installs to `/Applications/NEELx.app`, registers with LaunchServices/Spotlight, and launches the guided notch onboarding flow.

---

## 🔒 Security Architecture & Threat Model

| Security Layer | Implementation |
|---|---|
| **Identity Matching** | 512-D ArcFace embeddings with 5-point Vision landmark alignment (`threshold = 0.63`) |
| **3D Neural Depth (ANE)** | Apple Core ML `DepthAnythingV2SmallF16` — 3D nose protrusion + least-squares plane-fit residual |
| **Attention Check** | Eye Aspect Ratio (`EAR ≥ 0.14`) + Head Pose (`|yaw| ≤ 0.35`, `|pitch| ≤ 0.35`) |
| **Spoof Defense** | 3D flat-plane spoof detector + specular screen glare cue + rectangular device bezel detector |
| **Credential Storage** | AES-256-GCM encryption via Touch ID-gated session key (`LocalAuthentication` + Keychain) |
| **Lockout Guard** | Auto-locks session on consecutive failures or idle timeout; requires Touch ID / Mac password |
| **Lock Verification** | Authoritative `CGSessionCopyCurrentDictionary` check prevents accidental typing when unlocked |

> **Transparency Note**: Standard Mac webcams capture 2D RGB images rather than infrared dot projections (TrueDepth). NEELx maximizes security within 2D camera hardware limits using ArcFace, Stage 3 Neural 3D Depth (Depth Anything V2 on ANE), eye attention verification, and anti-spoofing heuristics, and is designed as a fast, hardened convenience unlock alongside Touch ID.

---

## 🛠️ Required macOS Permissions

During onboarding, NEELx requests two standard macOS permissions:
1. **Camera**: Used strictly on-device while the lock screen is active or while enrolling your face in Settings.
2. **Accessibility**: Allows NEELx to securely enter your decrypted password into the macOS lock screen login field upon a verified biometric match.

---

## 🗺️ Roadmap

- [x] 360° Circular Face Enrollment + Live Lighting Readiness Meter
- [x] Sub-200ms Unlock Pipeline + 3ms Keystroke Injection
- [x] Eye Gaze & Attention Verification
- [x] Luxury Studio Light Softbox & Spectral Chromatic Rim (with Live Preview)
- [x] Backlit Window HDR Shadow Recovery
- [x] Face ID for System Touch ID & Password Prompts
- [x] **Stage 3 Neural Depth + Multi-Frame Temporal Consistency** (Core ML *Depth Anything V2 Small* on Apple Silicon ANE)
- [x] Subtle Spatial Haptic + Optional Soft Glass Sound Cue
- [x] **NEELx for Windows 11 (`windows/`)** — Fluent Prism Horizon UI + DirectML + DPAPI

---

## 🤝 Contributing & Feedback

Contributions, bug reports, security audits, and test results across all Mac models (**Apple Silicon M1, M2, M3, M4, M5 & newer**, Intel Macs, Studio Display, external webcams) and Windows 11 laptops are very welcome!
1. Fork the repository
2. Run `./build.sh` to verify your local build
3. Open a Pull Request or Issue with your Mac model, macOS version, and feedback

---

## 📄 License & Credits

Released under the **MIT License** — see [LICENSE](LICENSE).  
NEELx is built upon and heavily evolved from [Glance](https://github.com/jonnyoo/glance) by Jonathan Zhou.
