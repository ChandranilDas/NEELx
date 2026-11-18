# NEELx for Windows 11 (Fluent Prism Edition)

**100% offline 3D biometric Face Unlock for Windows 11 laptops and desktops with any standard RGB webcam — no Windows Hello IR camera required.**

Unlike macOS (which uses an iPhone/iPad Pro-inspired circular notch Face ID animation), **NEELx for Windows 11** features a completely original **Fluent Prism Horizon** experience built specifically for Windows 11 Mica/Acrylic glass: a razor-thin frosted horizon blade with a rotating **faceted diamond-iris aperture** and **luminous horizontal laser sweep**.

---

## Architecture

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Desktop & Overlay UI** | `.NET 8` + `WPF` (Fluent Dark Mica) | Settings dashboard, enrollment wizard, and bespoke **Prism Horizon** top-edge unlock blade |
| **3D Depth & Recognition** | `ONNX Runtime DirectML` (`Microsoft.ML.OnnxRuntime.DirectML`) | Runs `ArcFace` (512-D identity) + `DepthAnythingV2Small` (3D anti-spoofing) on any DirectX 12 GPU or Copilot+ NPU |
| **Backlit HDR Recovery** | Real-time luminance & gamma shadow lift | Recovers darkened faces sitting with a bright window behind them |
| **Multi-Frame Depth Guard** | Rolling temporal 3D buffer | Requires 2 consecutive consistent 3D geometry frames (nose protrusion + head-to-background cliff) |
| **Credential & Template Vault** | Windows `DPAPI` (`ProtectedData`) + `AES-256-GCM` | Encrypts biometric vectors and unlock tokens offline under `DataProtectionScope.CurrentUser` |
| **Lock Screen Integration** | Windows `ICredentialProvider` COM DLL (`NEELx.CredentialProvider`) | Native Windows 11 WinLogon lock-screen tile communicating over ACL-protected named pipe `\\.\pipe\NEELxBiometricUnlock` |

---

## System Requirements

- **OS**: Windows 11 (22H2 or newer, x64 or ARM64)
- **Hardware**: Any built-in or USB webcam (720p+ recommended)
- **Accelerator**: Any DirectX 12 GPU (Intel Iris Xe/Arc, AMD Radeon, NVIDIA RTX/GTX) or Windows NPU via DirectML (CPU fallback supported)
- **Build Toolchain**: [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

---

## Quick Build (Windows 11)

```powershell
cd windows
dotnet restore NEELx.Windows.sln
dotnet build NEELx.Windows.sln -c Release
dotnet run --project src/NEELx.App/NEELx.App.csproj -c Release
```

## Lock Screen Credential Provider Setup (Optional)

The `src/NEELx.CredentialProvider` directory defines the native C++ WinLogon `ICredentialProvider` contract (`NEELxCredentialProvider.h`) that pairs with `NEELx.App`'s local named-pipe biometric daemon (`\\.\pipe\NEELxBiometricUnlock`, restricted to `SYSTEM` + current user SID).

1. Build the WinLogon Credential Provider DLL with Visual Studio 2022 (`Desktop development with C++`).
2. Register the COM CLSID under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers`.
3. Launch `NEELx.App`, enroll your 3D facial signature, and enable **Lock Screen Biometric Unlock**.
