# Tactile

Turn an iPad into a Magic Keyboard–style keyboard and trackpad for your Mac, over Wi-Fi.

- **Full Mac keyboard**: function row with media keys, number row, modifiers, fn layer, inverted-T arrows. Every row lines up like the real keyboard.
- **Feels like typing**: each key plays a synthesized key sound (Soft, Crisp or Thock). iPads have no vibration motor, so sound is the main feedback; vibration is used on devices that support it.
- **Skins**: Midnight Glow (dark keys with glowing edges, eight glow colors), Space Black, Silver, Frosted Glass, or Automatic (follows the iPad's light/dark setting).
- **Trackpad gestures**: tap to click, two-finger tap for secondary click, two-finger scroll with momentum, hold-then-move to drag, three-finger swipes for Spaces, Mission Control and App Exposé.
- **No dependencies**: the Mac side uses only Apple frameworks. The iPad side is plain HTML, CSS and JavaScript, so there are no packages to keep patched.

## Run it

Requires macOS 15 or later and the Swift toolchain (Xcode or Command Line Tools).

```bash
swift run -c release Tactile
```

Or double-click `start-tactile.command`. Terminal shows a QR code, the setup address, a six-digit pairing code and the certificate fingerprint. On the iPad:

1. Scan the QR code, or type the address, to open the setup page in Safari.
2. **Once per iPad**, the setup page walks you through trusting your Mac's certificate:
   - download it
   - install the profile in Settings (check that its SHA-256 fingerprint matches Terminal)
   - turn on full trust under General → About → Certificate Trust Settings
3. Open Tactile and enter the pairing code. The iPad is remembered after that, and the setup address goes straight to the keyboard.
4. Optional: on the keyboard page, tap Share → **Add to Home Screen** for a full-screen app without Safari's toolbar.

The first run asks for **Accessibility** access. Allow the app you started Tactile from (for example Terminal) in System Settings → Privacy & Security → Accessibility, then restart Tactile. macOS needs this permission before any app can send keyboard and mouse input.

### Options

| Flag | Effect |
|---|---|
| `--port 8420` | Setup page port (plain HTTP). The app uses the next port (HTTPS) and the one after that (secure WebSocket). |
| `--dry-run` | Prints input instead of sending it to the Mac. Useful while working on the UI. |
| `--forget-devices` | Removes every paired iPad. |

## Using it

| On the iPad | On the Mac |
|---|---|
| Tap a modifier (⇧ ⌃ ⌥ ⌘ fn) | Applies to the next key, like the iPad keyboard |
| Double-tap a modifier | Locks it until tapped again |
| Hold a modifier with one finger and tap a key | Normal shortcut (⌘-Tab works and stays open while held) |
| fn + delete / arrows | Forward delete, Page Up/Down, Home/End |
| fn + top row | F1–F12 instead of media keys |
| Compose button (top right) | Type with the iPad's own keyboard, so dictation, emoji and autocorrect work |

A hardware keyboard attached to the iPad is passed through to the Mac too.

## How it works

```
iPad Safari ── TLS: HTTPS + secure WebSocket (JSON) ──▶ Tactile (Swift) ──▶ CGEvent ──▶ macOS
```

- `Sources/Tactile/TLSIdentity.swift` keeps this Mac's private certificate authority (CA) and issues a fresh HTTPS certificate on every launch for the Mac's current name and addresses.
- `Sources/Tactile/HTTPServer.swift` serves files from memory, so only the bundled files can be requested. The app is served over HTTPS; plain HTTP serves only the setup page (`Web/setup/`) and the CA certificate.
- `Sources/Tactile/SocketServer.swift` handles pairing and input. It accepts sockets only from this Mac's own page, and every iPad gets its own input session, so keys are released if it disconnects.
- `Sources/Tactile/InputSession.swift` turns messages into real key, mouse, scroll and media-key events.
- `Sources/Tactile/Web/` is the iPad app: `keyboard.js` (layout and modifiers), `trackpad.js` (gestures), `feedback.js` (Web Audio key sounds), `styles.css` (skins).

## Security

- **Encrypted:** everything you type travels over TLS 1.2 or later. The keyboard page and its socket refuse plain HTTP, and only accept connections from this Mac's own HTTPS page.
- **Limited certificate authority:** the CA lives in `~/Library/Application Support/Tactile/tls/` (private key readable only by you). It is *name-constrained* to `.local` names and private IPv4 ranges (10/8, 172.16/12, 192.168/16, 100.64/10, 127/8). So even though the iPad trusts it, it cannot be used to impersonate websites on the internet.
- **Verify before trusting:** the setup page itself is plain HTTP. Before turning on trust, check that the profile's SHA-256 fingerprint matches the one in Terminal.
- **Pairing:** a random six-digit code that changes on every launch. Five wrong tries lock that address out for a minute.
- **Remembered iPads:** each keeps a random 256-bit token. The Mac stores only SHA-256 hashes of these tokens. Tokens issued before encryption existed were discarded, so iPads pair again once.
- **Starting over:** delete the `tls` folder to replace the CA, and remove the old profile on the iPad under Settings → General → VPN & Device Management.
