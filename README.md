# Tactile

Turn an iPad into a Magic Keyboard–style keyboard and trackpad for your Mac, over Wi-Fi or Tailscale.

- **Full Mac keyboard:** function row with media keys, number row, modifiers, fn layer and inverted-T arrows. Every row lines up like the real keyboard, and the keys can show your Mac's own layout (AZERTY, QWERTZ and others).
- **Feels like typing:** each key plays a synthesized key sound (Soft, Crisp or Thock). iPads have no vibration motor, so sound is the main feedback; vibration is used on devices that have one.
- **Learns your aim:** with **Adapt to My Typing**, each key's touch area drifts toward where you actually press it.
- **Skins:** Midnight Glow (dark keys with glowing edges, eight glow colors), Space Black, Silver, Frosted Glass, or Automatic (follows the iPad's light and dark setting).
- **Trackpad gestures:** tap to click, two-finger tap for secondary click, two-finger scroll with momentum, pinch to zoom, hold-then-move to drag (or three-finger drag), and three-finger swipes for Spaces, Mission Control and App Exposé.
- **Shortcut bar:** one tap for Undo, Redo, Copy, Paste, Switch App, Screenshot, Mission Control, Spotlight and more. You choose which.
- **No dependencies:** the Mac side uses only Apple frameworks. The iPad side is plain HTML, CSS and JavaScript modules, so there are no packages to keep patched.

## Requirements

- A Mac with macOS 15 or later, and the Swift 6 toolchain (Xcode, or the Command Line Tools: `xcode-select --install`).
- An iPad (or any device with a modern browser) on the same network as the Mac, or on the same [Tailscale](https://tailscale.com) tailnet.

## Getting started

1. Double-click `start-tactile.command`. It builds **Tactile.app** (only when the code has changed) and opens it. Tactile lives in the menu bar; there's no Dock icon. You can also move `build/Tactile.app` to Applications.
2. The first time, macOS asks for **Accessibility** access for **Tactile**. macOS needs it before any app can type or move the pointer.
3. Click the Tactile icon in the menu bar and choose **Pair a Device…**. Scan the QR code with the iPad's camera. Each code works once, and a new one appears after every pairing.

**Keep the Accessibility permission across rebuilds:** run `scripts/create-signing-certificate.sh` once. It adds a self-signed "Tactile Local Signing" code-signing certificate to your login keychain, and `scripts/build-app.sh` signs with it from then on. Without it, the app is signed ad hoc and macOS asks for Accessibility again after every rebuild. The first build after creating the certificate still needs approving once: run `tccutil reset Accessibility app.tactile.mac`, open Tactile, and switch it on.

To run it from a terminal instead (for development), use `swift run -c release Tactile`. It prints the QR code and pairing code there.

### With Tailscale (no certificate setup)

If the Mac and iPad both use Tailscale, Tactile uses a real, publicly trusted HTTPS certificate for the Mac's tailnet name, so there's nothing to install on the iPad.

1. In the Tailscale admin console, turn on **MagicDNS** and **HTTPS Certificates**. This is a one-time step.
2. Start Tactile. It asks Tailscale for a certificate at launch, and the QR code points at an address like `https://your-mac.your-tailnet.ts.net:8423`.
3. On the iPad, with Tailscale on, scan the QR code.

This works away from home too. Public certificates are recorded in public Certificate Transparency logs, so your Mac's tailnet name becomes publicly visible.

### Without Tailscale: trust the Mac's certificate once

1. Scan the QR code to open the setup page in Safari.
2. **Once per iPad**, the setup page walks you through trusting your Mac's certificate:
   - download it
   - install the profile in Settings, and check that its SHA-256 fingerprint matches the one in Tactile's menu (hold ⌥ while opening it)
   - turn on full trust under General → About → Certificate Trust Settings
3. Open Tactile and enter the pairing code. The iPad is remembered after that.

Tip: on the keyboard page, tap Share → **Add to Home Screen** for a full-screen app without Safari's toolbar.

## Using it

| On the iPad | On the Mac |
|---|---|
| Tap a modifier (⇧ ⌃ ⌥ ⌘ fn) | Applies to the next key, like the iPad keyboard |
| Double-tap a modifier | Locks it until tapped again |
| Hold a modifier and tap a key | Normal shortcut (⌘-Tab stays open while held) |
| fn + delete / arrows | Forward delete, Page Up/Down, Home/End |
| fn + top row | F1–F12 instead of media keys |
| Compose button (top right) | Type with the iPad's own keyboard, so dictation, emoji and autocorrect work |

A hardware keyboard attached to the iPad is passed through to the Mac too.

### Settings on the iPad

Tap the settings button (top right).

- **Keyboard:**
  - **Rest Fingers on Keys** (on by default): keys type when you lift your finger, so fingers resting on the keys don't type. Rolled keys still come out in the order you pressed them. Delete and the arrow keys still repeat when held.
  - **Key Popups:** letters and symbols appear in a bubble above your finger.
  - **Adapt to My Typing** (on by default): learns where you press each key and shifts its touch area to match. A key you delete straight away doesn't count. What it learns stays on the iPad; **Reset Typing Learning** starts over.
  - **Match Mac Layout** (on by default): labels the keys for the keyboard layout your Mac is using, and updates when you switch layouts.
- **Shortcut Bar:** shows one-tap shortcuts between the status and the buttons. Choose which ones appear. Letter shortcuts follow your Mac's layout, so ⌘Z is still ⌘Z on AZERTY.
- **Feedback:** key sounds (Soft, Crisp or Thock), volume, Sound in Silent Mode, and vibration where the device has it. Sounds are synthesized from short bursts of filtered noise, come from the side of the keyboard the key is on, and the trackpad has its own click. Safari only allows sound after a tap; if sound hasn't started, a "Tap to enable key sounds" button appears.
- **Trackpad:** tracking speed, scrolling speed, natural scrolling, **Pinch to Zoom** (zooms the app you're using, like ⌘+ and ⌘−) and **Three-Finger Drag** (swipes between Spaces then take four fingers).
- **Layout:**
  - **Show** the keyboard, the trackpad, or both. In landscape with both, the controls float over the trackpad's top corners so the keys get the whole height.
  - **Keyboard Position:** Top or Bottom with the trackpad; Middle too in keyboard-only layout.
  - **Keyboard Size** (keyboard-only layout): **Expanded** makes keys taller. **Floating** works like the iPad's floating keyboard: drag the handle to move it, drag the corner grip to resize it, double-tap the handle to reset.
  - **Keep Screen Awake:** the iPad stays on while you use Tactile, and sleeps as usual after 10 minutes without a touch.

### The menu bar

Click the Tactile icon to open its panel. The icon shows the state at a glance: a filled keyboard while a device is connected, a pause icon while input is paused, and a warning when Accessibility access is missing.

- **Devices:** a card for each paired device with its route (Tailscale or Wi-Fi) and, while connected, its connection quality. Hover over a card to **Disconnect** it (it stays off until you choose **Reconnect**) or **Revoke** it.
- **Options:** Pause Input (also **⌃⌥⌘P** from any app), Pause While Mac Is Locked, Use Tailscale, Only My Devices on Tailscale, Notify When a Device Connects, and Open at Login.
- **Pair a Device…** (⌘P) shows the QR code. **Copy Tailscale Link** copies the address.
- **Hold ⌥** to see details: addresses, ports, the certificate fingerprint, the Tailscale certificate's expiry, and Show Log.

### Command-line options

| Option | Effect |
|---|---|
| `--port 8420` | Setup page port (plain HTTP). The app uses the next two ports with the local certificate, and the two after with the Tailscale certificate. |
| `--dry-run` | Logs input instead of sending it to the Mac, and also serves a plain-HTTP copy of the page at `http://127.0.0.1:<port + 5>`, reachable only from this Mac, for trying UI changes in a desktop browser. |
| `--no-tailscale` | Don't ask Tailscale for a certificate. |
| `--forget-devices` | Removes every paired device. |

## How it works

```
iPad Safari ── HTTPS + secure WebSocket (JSON) ──▶ Tactile ──▶ CGEvent ──▶ macOS
```

| Folder | What's there |
|---|---|
| `Sources/TactileCore/` | Everything except the menu bar UI, as a library the app and the checks share. |
| `  Security/` | Pairing codes and remembered devices (`Pairing`), the local certificate authority and Tailscale certificates (`TLS`, `Tailscale`), and the Tailscale owner check (`TailnetGate`). |
| `  Network/` | `HTTPServer` serves the page from memory, so only bundled files can be requested. `SocketServer` handles pairing and input, and accepts sockets only from the Mac's own page. |
| `  Input/` | `InputSession` turns messages into real key, pointer, scroll and media-key events. `KeyMap` maps key names to Mac key codes; `KeyboardLayout` reads the Mac's current layout. |
| `  Support/` | Small shared helpers: paths, logging, running tools, hashing and random codes, host names. |
| `  TactileService.swift` | Owns the servers and pairing; the menu bar and terminal mode both drive it. |
| `Sources/Tactile/` | The menu bar app (`MenuBar/`), notifications, the global hot key, and `main.swift`. |
| `Sources/Tactile/Web/` | The iPad page. `keys.js` (layout and drawing), `keyboard.js` (typing), `typing-model.js` (learned touch areas), `trackpad.js` (gestures), `shortcuts.js`, `feedback.js` (sounds), `connection.js`, `settings.js`, `sheets.js` (settings UI), `wake-lock.js` and `util.js`. |
| `Tests/` | `TactileChecks/` (Swift checks) and `Web/` (tests for the page). See [CONTRIBUTING.md](CONTRIBUTING.md). |
| `scripts/`, `Packaging/` | Build and sign `Tactile.app`. |

## Security

- **Encrypted:** everything you type travels over TLS 1.2 or later. The keyboard page and its socket refuse plain HTTP, and the socket only accepts connections from the Mac's own page.
- **Limited certificate authority:** the local CA lives in `~/Library/Application Support/Tactile/tls/` (private key readable only by you). It is *name-constrained* to `.local` names and private IPv4 ranges, so even though the iPad trusts it, it can't be used to impersonate websites.
- **Pairing:** a random six-digit code that works once. Five wrong tries lock that address out for a minute; 20 wrong tries from anywhere within 10 minutes also replace the code and pause all pairing for a minute.
- **Remembered devices:** each keeps a random 256-bit token. The Mac stores only SHA-256 hashes of these tokens, with each device's name and when it was last used. Devices unused for 90 days must pair again. Revoking a device disconnects it at once.
- **Only your devices over Tailscale** (on by default): before a device can even try to pair over Tailscale, Tactile asks Tailscale who owns it (`tailscale whois`). Devices shared into your tailnet by someone else, tagged devices, and devices Tailscale can't vouch for are refused.
- **Its own permission:** Tactile.app holds the Accessibility permission itself, so other programs don't inherit the ability to control the Mac.
- **Starting over:** delete the `tls` folder to replace the CA, and remove the old profile on the iPad under Settings → General → VPN & Device Management.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Contributing

Bug reports and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build, run the checks and find your way around.

## License

[MIT](LICENSE)
