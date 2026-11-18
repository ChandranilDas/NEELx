# NEELx.CredentialProvider (WinLogon ICredentialProvider)

This directory contains the WinLogon `ICredentialProvider` interface (`NEELxCredentialProvider.h`) for native Windows 11 Lock Screen unlock.

## Security Model
- `NEELx.App` runs in the user/service biometric verification layer using DirectML (`ArcFace` + `DepthAnythingV2Small` + multi-frame temporal consistency).
- Only after 3D liveness and identity verification pass does `DpapiCredentialVault` transmit a single-use nonce over `\\.\pipe\NEELxBiometricUnlock` (restricted via Windows DACL to `NT AUTHORITY\SYSTEM` and the active user SID).
- Credentials remain encrypted at rest under Windows DPAPI and never leave the device.
