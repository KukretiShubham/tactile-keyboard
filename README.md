# Tactile

Turn an iPad into a Magic Keyboard–style keyboard and trackpad for your Mac, over Wi-Fi.

- **Full Mac keyboard**: function row with media keys, number row, modifiers, fn layer, inverted-T arrows. Every row lines up like the real keyboard.
- **Feels like typing**: each key plays a synthesized key sound (Soft, Crisp or Thock). iPads have no vibration motor, so sound is the main feedback; vibration is used on devices that support it.
- **Skins**: Midnight Glow (dark keys with glowing edges, eight glow colors), Space Black, Silver, Frosted Glass, or Automatic (follows the iPad's light/dark setting).
- **Trackpad gestures**: tap to click, two-finger tap for secondary click, two-finger scroll with momentum, hold-then-move to drag, three-finger swipes for Spaces, Mission Control and App Exposé.
- **No dependencies**: the Mac side uses only Apple frameworks. The iPad side is plain HTML, CSS and JavaScript, so there are no packages to keep patched.

## Run it

Requires macOS 14 or later and the Swift toolchain (Xcode or Command Line Tools).

```bash
swift run -c release Tactile
```

The Terminal shows a QR code, the address to open and a six-digit pairing code. On the iPad:

1. Scan the QR code (or type the address) to open it in Safari.
2. Enter the pairing code. The iPad is remembered after that.
3. Optional: Share → **Add to Home Screen** to get a full-screen app without Safari's toolbar.

The first run asks for **Accessibility** access. Allow the app you started Tactile from (for example Terminal) in System Settings → Privacy & Security → Accessibility, then restart Tactile. macOS needs this permission before any app can send keyboard and mouse input.

### Options

| Flag | Effect |
|---|---|
| `--port 8420` | Port for the web page. The socket uses the next port. |
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
iPad Safari ── WebSocket (JSON) ──▶ Tactile (Swift) ──▶ CGEvent ──▶ macOS
```

- `Sources/Tactile/HTTPServer.swift` serves the web app from memory. Only the bundled files can be requested.
- `Sources/Tactile/SocketServer.swift` handles pairing and input. It accepts sockets only from this Mac's own page, and every iPad gets its own input session, so keys are released if it disconnects.
- `Sources/Tactile/InputSession.swift` turns messages into real key, mouse, scroll and media-key events.
- `Sources/Tactile/Web/` is the iPad app: `keyboard.js` (layout and modifiers), `trackpad.js` (gestures), `feedback.js` (Web Audio key sounds), `styles.css` (skins).

## Security

- Pairing uses a random six-digit code that changes on every launch. Five wrong tries lock that address out for a minute.
- Paired iPads keep a random 256-bit token. The Mac stores only SHA-256 hashes of these tokens, in `~/Library/Application Support/Tactile/`.
- Traffic is plain HTTP and WebSocket on your local network and is **not encrypted**, so anyone on the same network who can see the traffic could read what you type. Use it only on networks you trust.
