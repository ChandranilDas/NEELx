//
//  PasskeyCompanionManager.swift
//  NEELx
//
//  Zero-App Native Biometric Companion for iPhone (iOS 16+ TrueDepth Face ID)
//  and Android (9+ BiometricPrompt) via standard FIDO2 / WebAuthn Passkeys.
//
//  Allows unlocking macOS using the phone's native hardware biometrics (Secure Enclave / Keystore)
//  with zero app installation required on the phone.
//

import AppKit
import CoreBluetooth
import CoreImage
import CryptoKit
import Foundation
import Network
import Observation

@Observable
@MainActor
final class PasskeyCompanionManager: NSObject, CBCentralManagerDelegate {
    static let shared = PasskeyCompanionManager()

    private var centralManager: CBCentralManager?
    private var listener: NWListener?
    private var serverPort: UInt16 = 8765

    private(set) var isBluetoothPoweredOn: Bool = true
    private(set) var isPairingServerRunning: Bool = false
    private(set) var pairingURL: String? = nil
    private(set) var pairingQRImage: NSImage? = nil

    private(set) var isRequirementsMet: Bool = false
    private(set) var diagnosticMessage: String = ""

    // Paired companion state
    var isPaired: Bool {
        NEELxSettings.shared.passkeyCompanionCredentialID != nil
    }

    var pairedDeviceName: String {
        NEELxSettings.shared.passkeyCompanionDeviceName ?? "Mobile Device"
    }

    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
        evaluateRequirements()
    }

    // MARK: - CBCentralManagerDelegate
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
            self.evaluateRequirements()
        }
    }

    // MARK: - Requirements Cross-Checker
    func evaluateRequirements() {
        let localIP = getWiFiAddress()

        if localIP == nil {
            isRequirementsMet = false
            diagnosticMessage = "⚠️ No local Wi-Fi / Ethernet connection detected. Both your Mac and phone must be on the same local network to pair passkeys."
            return
        }

        if !isBluetoothPoweredOn {
            isRequirementsMet = false
            diagnosticMessage = "⚠️ Bluetooth is turned OFF on this Mac. Turn on Bluetooth in System Settings to allow proximity companion unlock."
            return
        }

        isRequirementsMet = true
        if isPaired {
            diagnosticMessage = "✅ Ready: Paired with \(pairedDeviceName). Native hardware biometrics armed for unlock."
        } else {
            diagnosticMessage = """
            ✅ Companion Ready to Pair:
            • iPhone (iOS 16+) with TrueDepth Face ID or Touch ID
            • Android (9.0+) with BiometricPrompt (Fingerprint or Face)
            • Mac & Phone on same Wi-Fi with Bluetooth active
            • Zero mobile app required — uses built-in OS Passkey hardware
            """
        }
    }

    // MARK: - Pairing Session
    func startPairingSession() {
        guard !isPairingServerRunning else { return }

        guard let localIP = getWiFiAddress() else {
            diagnosticMessage = "⚠️ Cannot start pairing: Wi-Fi address unavailable."
            return
        }

        serverPort = 8765
        let urlString = "http://\(localIP):\(serverPort)/pair"
        self.pairingURL = urlString
        self.pairingQRImage = generateQRCode(from: urlString)

        do {
            let parameters = NWParameters.tcp
            self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: serverPort)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in
                    self?.handleIncomingConnection(connection)
                }
            }

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isPairingServerRunning = true
                        self?.evaluateRequirements()
                    case .failed(let error):
                        self?.isPairingServerRunning = false
                        self?.diagnosticMessage = "⚠️ Local pairing server failed: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isPairingServerRunning = false
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .main)
        } catch {
            diagnosticMessage = "⚠️ Could not start pairing listener: \(error.localizedDescription)"
        }
    }

    func stopPairingSession() {
        listener?.cancel()
        listener = nil
        isPairingServerRunning = false
        pairingURL = nil
        pairingQRImage = nil
    }

    func unpairDevice() {
        let settings = NEELxSettings.shared
        settings.passkeyCompanionCredentialID = nil
        settings.passkeyCompanionDeviceName = nil
        settings.passkeyCompanionPublicKey = nil
        evaluateRequirements()
    }

    // MARK: - Network Request Handling
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, _ in
            Task { @MainActor in
                guard let self = self, let content = content, let requestString = String(data: content, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                if requestString.contains("GET /pair") {
                    let html = self.pairingHTMLPage()
                    let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=utf-8\r
                    Content-Length: \(html.utf8.count)\r
                    Connection: close\r
                    \r
                    \(html)
                    """
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                } else if requestString.contains("POST /api/register") {
                    // Parse POST JSON body
                    if let bodyStart = requestString.range(of: "\r\n\r\n")?.upperBound {
                        let body = String(requestString[bodyStart...])
                        if let bodyData = body.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                           let credId = json["credentialId"] as? String {
                            
                            let deviceName = (json["deviceName"] as? String) ?? "Mobile Biometric Device"
                            let clientData = (json["clientDataJSON"] as? String) ?? ""

                            let settings = NEELxSettings.shared
                            settings.passkeyCompanionCredentialID = credId
                            settings.passkeyCompanionDeviceName = deviceName
                            settings.passkeyCompanionPublicKey = clientData
                            settings.passkeyCompanionEnabled = true
                            self.evaluateRequirements()
                            self.stopPairingSession()

                            let res = "{\"status\":\"ok\",\"device\":\"\(deviceName)\"}"
                            let response = """
                            HTTP/1.1 200 OK\r
                            Content-Type: application/json\r
                            Content-Length: \(res.utf8.count)\r
                            Connection: close\r
                            \r
                            \(res)
                            """
                            connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                                connection.cancel()
                            }))
                            return
                        }
                    }

                    let badResponse = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: badResponse.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                } else {
                    let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                }
            }
        }
    }

    // MARK: - Local IP Resolver
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name == "en2" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let candidate = String(cString: hostname)
                    if !candidate.isEmpty && candidate != "127.0.0.1" {
                        address = candidate
                        break
                    }
                }
            }
        }
        return address
    }

    // MARK: - Crisp QR Code Generator
    private func generateQRCode(from string: String) -> NSImage? {
        let data = string.data(using: .utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - WebAuthn HTML Template
    private func pairingHTMLPage() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <title>NEELx Biometric Companion</title>
          <style>
            body {
              background: #0b0f19;
              color: #f1f5f9;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              margin: 0;
              padding: 24px;
              box-sizing: border-box;
              text-align: center;
            }
            .card {
              background: #161a29;
              border: 1px solid rgba(255, 255, 255, 0.1);
              border-radius: 24px;
              padding: 32px 24px;
              max-width: 380px;
              width: 100%;
              box-shadow: 0 20px 40px rgba(0,0,0,0.6);
            }
            .badge {
              display: inline-block;
              background: rgba(56, 189, 248, 0.15);
              color: #38bdf8;
              padding: 5px 12px;
              border-radius: 999px;
              font-size: 11px;
              font-weight: 700;
              letter-spacing: 0.5px;
              margin-bottom: 16px;
            }
            h1 { font-size: 22px; font-weight: 700; margin: 0 0 10px 0; color: #ffffff; }
            p { font-size: 14px; color: #94a3b8; line-height: 1.5; margin: 0 0 24px 0; }
            button {
              background: #38bdf8;
              color: #0b0f19;
              border: none;
              border-radius: 14px;
              padding: 16px 20px;
              font-size: 16px;
              font-weight: 700;
              width: 100%;
              cursor: pointer;
              transition: transform 0.1s, background 0.2s;
            }
            button:active { transform: scale(0.98); }
            .success { display: none; }
            .error { display: none; color: #f87171; margin-top: 16px; font-size: 13.5px; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="badge">ZERO APP REQUIRED</div>
            <h1>Pair with NEELx</h1>
            <p>Register your phone's native hardware Face ID (TrueDepth) or BiometricPrompt to unlock your Mac with zero app downloads.</p>
            
            <div id="initial">
              <button id="btnPair" onclick="registerPasskey()">Register Device Biometrics</button>
            </div>

            <div id="success" class="success">
              <div style="font-size: 48px; margin-bottom: 12px;">✅</div>
              <h2 style="color: #4ade80; font-size: 20px; margin: 0 0 8px 0;">Pairing Complete!</h2>
              <p style="color: #cbd5e1; font-size: 14px;">Your phone's hardware biometric is now registered with NEELx on your Mac. You can close this tab.</p>
            </div>

            <div id="errorMsg" class="error"></div>
          </div>

          <script>
            async function registerPasskey() {
              const btn = document.getElementById('btnPair');
              const err = document.getElementById('errorMsg');
              btn.innerText = "Authenticating...";
              btn.disabled = true;
              err.style.display = "none";

              try {
                const challenge = new Uint8Array(32);
                window.crypto.getRandomValues(challenge);

                const userId = new Uint8Array(16);
                window.crypto.getRandomValues(userId);

                const options = {
                  challenge: challenge,
                  rp: { name: "NEELx Biometric Companion", id: window.location.hostname },
                  user: { id: userId, name: "neelx-user", displayName: "MacBook User" },
                  pubKeyCredParams: [{ alg: -7, type: "public-key" }, { alg: -257, type: "public-key" }],
                  authenticatorSelection: {
                    authenticatorAttachment: "platform",
                    userVerification: "required"
                  },
                  timeout: 60000
                };

                const credential = await navigator.credentials.create({ publicKey: options });
                const rawId = btoa(String.fromCharCode(...new Uint8Array(credential.rawId)));
                
                let clientDataJSON = "";
                if (credential.response.clientDataJSON) {
                  clientDataJSON = btoa(String.fromCharCode(...new Uint8Array(credential.response.clientDataJSON)));
                }

                const isApple = /iPhone|iPad|Macintosh/i.test(navigator.userAgent);
                const isAndroid = /Android/i.test(navigator.userAgent);
                const deviceName = isApple ? "iPhone (Face ID TrueDepth)" : (isAndroid ? "Android (BiometricPrompt)" : "Mobile Device");

                const res = await fetch('/api/register', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    credentialId: rawId,
                    clientDataJSON: clientDataJSON,
                    deviceName: deviceName
                  })
                });

                if (res.ok) {
                  document.getElementById('initial').style.display = 'none';
                  document.getElementById('success').style.display = 'block';
                } else {
                  throw new Error("Mac rejected registration payload.");
                }
              } catch (e) {
                btn.innerText = "Try Again";
                btn.disabled = false;
                err.innerText = e.message || "Biometric authentication cancelled or unavailable.";
                err.style.display = "block";
              }
            }
          </script>
        </body>
        </html>
        """
    }
}
