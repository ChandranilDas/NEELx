# NEELx — Fast, Hardened Biometric Face Unlock for macOS

**NEELx** brings fast, natural, iPhone-style Face Unlock to macOS using your Mac's built-in camera and Apple Neural Engine — **100% offline, encrypted at rest, and open-source.**

> Built for macOS 15+ (Apple Silicon & Intel). Runs entirely on-device with zero network connections, zero telemetry, and hardware-backed macOS Keychain protection.

---

## ✨ Key Features

- **Smooth 360° Circular Face Enrollment + 3D Depth Profile**: Just like Face ID on iPhone and iPad Pro — slowly roll your head in a single natural circle to capture all 8 compass sectors, 512-D ArcFace embeddings, and your personal **9-zone 3D facial depth profile** in 1–2 seconds.
- **Instant Sub-200ms Unlock**: Strict ArcFace cosine-similarity matching (`≥ 0.63` threshold) accelerated on the Apple Neural Engine (ANE) paired with ultra-fast 3ms keystroke dispatch.
- **Stage 3 Neural 3D Depth Anti-Spoofing (Apple Neural Engine)**: Powered by Apple's official Core ML `DepthAnythingV2SmallF16` running in FP16 (~22ms on Apple Silicon ANE). Validates **3D nose protrusion**, **non-planar facial curvature**, and your enrolled **9-zone 3D depth profile** — rejecting flat photos and phone/tablet screens.
- **Active Chromatic Flash Challenge (Anti-4K Video Replay)**: Optional randomized ~110ms cyan/amber reflection challenge that verifies live skin color shift in real time — defeating pre-recorded video replay attacks.
- **Attention & Eye Gaze Verification**: "Require Attention for Face ID" — checks that your eyes are open (Eye Aspect Ratio) and you are actively facing the screen before unlocking.
- **Closed-Loop Adaptive Dark-Room Illumination**: Dynamically steps up both your MacBook's real display backlight and a warm TrueTone soft-box glow until your face is clearly visible (during both enrollment and lock-screen unlock), then immediately restores your original screen brightness.
- **Silent Adaptive Learning**: Automatically adapts to gradual changes (glasses, beard, lighting drift) from high-confidence 3D-verified unlocks.
- **Encrypted Intruder & Security Audit Log**: Records unlock attempts and AES-256-GCM encrypted snapshots of blocked intruders/spoofs strictly offline under your Touch ID key.
- **Walk-Away Auto-Lock (Presence Lock)**: Optional zero-drain idle presence check that locks your Mac automatically if you step away from your desk.
- **Smart Clamshell / Multi-Camera Auto-Switching**: Automatically switches to an external webcam or iPhone Continuity Camera when your MacBook lid is closed.
- **Live 3D Depth Heatmap in Face Lab & 1-Click Diagnostics**: Inspect live Inferno-colorized 3D depth maps in Face Lab (tap the icon 5× in About) and copy privacy-scrubbed diagnostics for GitHub Issues in one click.
- **Zero-Cloud Privacy & Hardware Encryption**:
  - Touch ID (`LocalAuthentication`) gates access to your session key.
  - A 256-bit AES-GCM symmetric key stored in macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) encrypts your login credential, face embeddings, and audit log.
  - Plaintext password buffers are explicitly zeroed in memory immediately after unlock.

---

## 🚀 Quick Start (Build & Install in 1 Command)

### Requirements
- **macOS 15.0 (Sequoia)** or later
- **Xcode** (for `swiftc`, `coremlc`, and `actool`)
- Built-in FaceTime HD / Center Stage camera or external USB webcam

### Build & Install

```bash
git clone https://github.com/ChandranilDas/NEELx.git
cd NEELx
chmod +x build.sh
./build.sh --with-depth --install
```

> **Prefer a pre-built installer?** Download the complete all-in-one universal DMG `NEELx-v2.0.0-beta.9-universal.dmg` from [**GitHub Releases**](https://github.com/ChandranilDas/NEELx/releases) (or install in 1 click via `curl -fsSL https://chandranildas.github.io/NEELx/install.sh | bash`). It pre-bundles Apple's 3D neural depth engine and ArcFace so zero extra downloads are required! NEELx also includes a built-in **GitHub Releases Auto-Updater** (**Menu Bar → Check for Updates…**) so future updates install and relaunch in one click while keeping your enrolled face and Keychain credentials intact.

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

- [x] 360° Circular Face Enrollment (iPhone/iPad Pro style)
- [x] Sub-200ms Unlock Pipeline + 3ms Keystroke Injection
- [x] Eye Gaze & Attention Verification
- [x] Adaptive TrueTone Low-Light Illumination
- [x] Ad-hoc Open-Source Build without Paid Developer Entitlements
- [x] **Stage 3 Neural Depth**: Core ML *Depth Anything V2 Small* monocular 3D curvature & nose protrusion validation on Apple Silicon ANE
- [ ] **Apple Watch & Continuity Proximity** secondary factor

---

## 🤝 Contributing & Feedback

Contributions, bug reports, security audits, and test results across different Mac models (M1/M2/M3/M4, Intel, Studio Display, external webcams) are very welcome!
1. Fork the repository
2. Run `./build.sh` to verify your local build
3. Open a Pull Request or Issue with your Mac model, macOS version, and feedback

---

## 📄 License & Credits

Released under the **MIT License** — see [LICENSE](LICENSE).  
NEELx is built upon and heavily evolved from [Glance](https://github.com/jonnyoo/glance) by Jonathan Zhou.
