# Tactile

Turn an iPad into a Magic Keyboard–style keyboard and trackpad for your Mac, over Wi-Fi.

- **Full Mac keyboard**: function row with media keys, number row, modifiers, fn layer, inverted-T arrows. Every row lines up like the real keyboard.
- **Feels like typing**: each key plays a synthesized key sound (Soft, Crisp or Thock). iPads have no vibration motor, so sound is the main feedback; vibration is used on devices that support it.
- **Skins**: Midnight Glow (dark keys with glowing edges, eight glow colors), Space Black, Silver, Frosted Glass, or Automatic (follows the iPad's light/dark setting).
- **Trackpad gestures**: tap to click, two-finger tap for secondary click, two-finger scroll with momentum, hold-then-move to drag, three-finger swipes for Spaces, Mission Control and App Exposé.
- **No dependencies**: the Mac side uses only Apple frameworks. The iPad side is plain HTML, CSS and JavaScript, so there are no packages to keep patched.

## Run it

Requires macOS 15 or later and the Swift toolchain (Xcode or Command Line Tools).

Double-click `start-tactile.command`. It builds **Tactile.app** (only when the code has changed) and opens it. Tactile lives in the menu bar, next to Wi-Fi; there's no Dock icon or Terminal window. You can also move `build/Tactile.app` to Applications and open it from there.

The first time, macOS asks for **Accessibility** access for **Tactile**. macOS needs it before any app can type or move the pointer. If you used an earlier version that ran in Terminal, you can now switch Terminal off in that list.

Developers can still run it in Terminal with `swift run -c release Tactile`, which prints the QR code and pairing code there.

### The menu bar

Click the Tactile icon in the menu bar to open its panel (styled like the Wi-Fi menu; click elsewhere or press Esc to close). Hover over the icon to see the status. The icon itself shows the state at a glance: a filled keyboard when a device is connected, a pause icon when input is paused, and a warning when Accessibility access is missing.

- **Header:** the status ("Connected · input flowing" while you type) and an on/off switch for Tactile itself.
- **Devices:** a card for each paired device with its route (Tailscale or Wi-Fi). Connected devices also show connection quality, for example "Excellent · 14 ms" with signal bars. Hover over a card to:
  - **Disconnect** it: it stays off until you choose **Reconnect**, because an iPad would otherwise reconnect straight away.
  - **Revoke** it: click once more to confirm.
- **Options:**
  - **Pause Input** (also **⌃⌥⌘P** from any app)
  - **Pause While Mac Is Locked**: also pauses during the screen saver
  - **Use Tailscale**
  - **Notify When a Device Connects**
  - **Open at Login**
- **Pair a Device…** (⌘P) opens the QR code window. **Copy Tailscale Link** copies the address.
- **Hold ⌥** while opening the panel (or while it's open) to see details: setup address, ports, certificate fingerprint, Tailscale certificate expiry, and Show Log.

Tactile sends a macOS notification when a new device pairs, and when a device connects after being away for a while.

**Keep the Accessibility permission across rebuilds:** run `./create-signing-certificate.sh` once. It adds a self-signed "Tactile Local Signing" code-signing certificate to your login keychain, and `build-app.sh` signs with it from then on. Without it, the app is signed ad-hoc and macOS asks for Accessibility again after every rebuild. The first build after creating the certificate still needs approving once: run `tccutil reset Accessibility app.tactile.mac`, open Tactile, and switch it on.

### Fastest: Tailscale (no certificate setup)

If the Mac and iPad are both on [Tailscale](https://tailscale.com), Tactile uses a real, publicly trusted HTTPS certificate for the Mac's tailnet name, so there's nothing to install on the iPad.

1. In the Tailscale admin console, turn on **MagicDNS** and **HTTPS Certificates** (https://login.tailscale.com/admin/dns). This is a one-time step.
2. Start Tactile. It asks Tailscale for a certificate at launch and prints a **With Tailscale** address, for example `https://your-mac.your-tailnet.ts.net:8423`.
3. On the iPad, with Tailscale on, open that address (or the setup page, which redirects there) and enter the pairing code.

This works away from home too. Note that public certificates are recorded in public Certificate Transparency logs, so your Mac's tailnet name becomes publicly visible.

### Without Tailscale: trust the Mac's certificate once

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
| `--port 8420` | Setup page port (plain HTTP). The app uses +1/+2 with the local certificate and +3/+4 with the Tailscale certificate (HTTPS page and secure WebSocket). |
| `--dry-run` | Prints input instead of sending it to the Mac. Also serves a plain-HTTP copy of the app at `http://127.0.0.1:<port+5>`, reachable only from this Mac, for trying UI changes in a desktop browser. |
| `--no-tailscale` | Don't ask Tailscale for a certificate. |
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

Other settings (gear button, top right):

- **Pairing:** scanning the QR code in Terminal also pairs the iPad, so there's no code to type. Each code works once; Terminal shows a new QR and code after every pairing.
- **Rest Fingers on Keys** (on by default): keys type when you lift your finger, so fingers resting on the keys don't type. If you roll from one key to the next, the letters still come out in the order you pressed them. Delete and the arrow keys still repeat when held.
- **Landscape:** with the trackpad showing, the status and buttons float over the trackpad's top corners, so the keyboard and trackpad get the whole height. Keys are square like a Mac keyboard's. Tactile is tuned for iPads in landscape. Add it to the Home Screen for the most room, since Safari's toolbar takes about 60 pt.
- **Keyboard Position:** Top or Bottom with the trackpad (Bottom docks the keys like the iPad's own keyboard). In keyboard-only layout, Middle is also available.
- **Keyboard Size** (keyboard-only layout):
  - **Expanded** makes the keys taller to fill the screen.
  - **Floating** works like the iPad's floating keyboard. Drag the handle under it to move it; it snaps to the centre and to the top and bottom edges. Drag the corner grip to resize it, down to keys of about 40 pt. Double-tap the handle to reset. The size and position are remembered separately for portrait and landscape. Only the handle and grip move it, so typing never does.
- **Keep Screen Awake** (on by default): the iPad doesn't dim or sleep while Tactile is open.
- **Key Popups** (on by default): letters and symbols appear in a bubble above your finger, like the iPhone keyboard.
- **Key sounds:** synthesized from short bursts of filtered noise, with no pitched tones: a tick, a brief keycap resonance and a dull bottom-out, like a real key. Each click comes from the side of the keyboard the key is on, and keys make a quieter sound coming back up. The trackpad has its own short, dry click. Safari only allows sound after a tap, so the first keystroke turns sound on. If it hasn't, a "Tap to enable key sounds" button appears at the top. **Test Sound** in Settings plays a sample. **Sound in Silent Mode** plays sounds even when the iPad is muted, but pauses any music playing on the iPad.

## How it works

```
iPad Safari ── TLS: HTTPS + secure WebSocket (JSON) ──▶ Tactile (Swift) ──▶ CGEvent ──▶ macOS
```

- `Sources/Tactile/MenuBarController.swift`, `PairingWindow.swift` and `Notifier.swift` are the menu bar app. `TactileService.swift` owns the servers and pairing, and both the menu and Terminal mode drive it.
- `Sources/Tactile/Pairing.swift` handles pairing codes, the paired-device list, expiry and wrong-code limits.
- `build-app.sh` and `Packaging/` build and sign `Tactile.app`.
- `Sources/Tactile/Tailscale.swift` asks Tailscale for a Let's Encrypt certificate for the Mac's tailnet name, when HTTPS certificates are enabled for the tailnet.
- `Sources/Tactile/TLSIdentity.swift` keeps this Mac's private certificate authority (CA), the fallback, and issues a fresh HTTPS certificate on every launch for the Mac's current name and addresses.
- `Sources/Tactile/HTTPServer.swift` serves files from memory, so only the bundled files can be requested. The app is served over HTTPS; plain HTTP serves only the setup page (`Web/setup/`) and the CA certificate.
- `Sources/Tactile/SocketServer.swift` handles pairing and input. It accepts sockets only from this Mac's own page, and every iPad gets its own input session, so keys are released if it disconnects.
- `Sources/Tactile/InputSession.swift` turns messages into real key, mouse, scroll and media-key events.
- `Sources/Tactile/Web/` is the iPad app: `keyboard.js` (layout and modifiers), `trackpad.js` (gestures), `feedback.js` (Web Audio key sounds), `styles.css` (skins).

## Security

- **Encrypted:** everything you type travels over TLS 1.2 or later. The keyboard page and its socket refuse plain HTTP, and only accept connections from this Mac's own HTTPS page.
- **Limited certificate authority:** the CA lives in `~/Library/Application Support/Tactile/tls/` (private key readable only by you). It is *name-constrained* to `.local` names and private IPv4 ranges (10/8, 172.16/12, 192.168/16, 100.64/10, 127/8). So even though the iPad trusts it, it cannot be used to impersonate websites on the internet.
- **Verify before trusting:** the setup page itself is plain HTTP. Before turning on trust, check that the profile's SHA-256 fingerprint matches the one in Terminal.
- **Pairing:** a random six-digit code that works once; a new one is issued after every pairing. Five wrong tries lock that address out for a minute. Because an attacker could switch addresses, 20 wrong tries from anywhere within 10 minutes also replaces the code and pauses all pairing for a minute.
- **Remembered devices:** each keeps a random 256-bit token. The Mac stores only SHA-256 hashes of these tokens, with each device's name and when it was last used. Devices unused for 90 days must pair again. Revoking a device in the menu disconnects it at once.
- **Visibility:** the menu bar always shows whether a device is connected, and macOS notifications announce new pairings.
- **Only your devices over Tailscale** (on by default; switch in the menu panel): before a device can even try to pair over Tailscale, Tactile asks Tailscale who owns it (`tailscale whois`). Only devices signed in as the Mac's owner get in. Devices shared into your tailnet by someone else, tagged devices, and devices Tailscale can't vouch for are refused. Device cards also show the Tailscale name, such as "iPad Air 13".
- **Its own permission:** Tactile.app holds the Accessibility permission itself, so other programs run from Terminal don't inherit the ability to control the Mac.
- **Starting over:** delete the `tls` folder to replace the CA, and remove the old profile on the iPad under Settings → General → VPN & Device Management.
