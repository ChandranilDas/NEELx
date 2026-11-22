# Security Policy

NEELx is designed with a **zero-trust, 100% offline biometric architecture** for macOS. Because NEELx integrates directly with macOS authentication, Keychain storage, and on-device camera pipelines, we take security, cryptographic integrity, and biometric robustness with the utmost seriousness.

---

## Supported Versions

Only the latest active release series receives proactive security fixes and patches.

| Version | Supported          | Security Maintenance Status |
| :------ | :----------------- | :-------------------------- |
| `2.0.x` | :white_check_mark: | Actively supported          |
| `< 2.0` | :x:                | Unsupported                 |

---

## Reporting a Security Vulnerability

If you discover a security vulnerability, biometric bypass, or cryptographic weakness in NEELx, **please do NOT report it via a public GitHub issue or discussion.**

Instead, please report it privately through one of the following channels:

1. **GitHub Private Vulnerability Reporting (Recommended)**:
   * Navigate to the [NEELx Security Advisories](https://github.com/ChandranilDas/NEELx/security/advisories) tab.
   * Click **Report a vulnerability** to submit a confidential report directly to the repository maintainer.
2. **Direct Confidential Email**:
   * Email: **`chandranildas925@gmail.com`**
   * Subject line: `[NEELx Security Disclosure] <Short Description>`

---

## Information to Include in Your Report

To help us triage and patch the issue as quickly as possible, please include:

* A detailed description of the vulnerability (e.g. anti-spoofing evasion, Keychain privilege escalation, timing attack, IPC boundary bypass).
* Step-by-step reproduction instructions or a minimal Proof of Concept (PoC).
* Your test environment: macOS version (e.g. macOS 15.1 Sequoia), hardware architecture (Apple Silicon M1–M4 or Intel), and NEELx version tag.
* Impact assessment: what an attacker with or without physical access could achieve.

---

## Response & Disclosure Timeline

We adhere to coordinated vulnerability disclosure:

* **Initial Acknowledgment**: Within **24–48 hours** of receiving your report.
* **Triage & Reproduction**: Within **3–5 business days**.
* **Remediation & Patch**: A fix will be developed, tested, and shipped in a new GitHub release tag (e.g. `v2.0.0-beta.x` or hotfix release).
* **Public Disclosure / Credit**: We will coordinate the public disclosure date with you and proudly credit your contribution in the official release notes and CHANGELOG.

---

## Security Architecture Guarantees

NEELx upholds the following strict non-negotiable security guarantees:

1. **100% Offline Biometrics**: Zero biometric face vectors, camera frames, or telemetry ever touch the internet. All inference runs locally on the Apple Neural Engine (ANE) via Core ML.
2. **Hardware-Backed Keyring**: Passwords and encryption keys are stored in the macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and optional Touch ID ACL gating.
3. **Audit Vault Privacy**: Security audit logs and failed intruder snapshots are stored encrypted with AES-256-GCM and guarded by Touch ID / system biometric authentication.
4. **Isolated Memory**: Biometric frames and decrypted secrets are purged from RAM immediately following verification.
