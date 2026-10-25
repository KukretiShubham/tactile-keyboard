<h1 align="center">Tactile</h1>

<p align="center">
  <b>Turn your iPad into a Magic Keyboard and trackpad for your Mac.</b><br>
  Full Mac layout, real key sounds, trackpad gestures. No app to install on the iPad, no accounts, no dependencies.
</p>

<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="macOS 15 or later" src="https://img.shields.io/badge/macOS-15%2B-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="No dependencies" src="https://img.shields.io/badge/dependencies-none-brightgreen">
</p>

<p align="center">
  <img src="docs/images/midnight.jpg" alt="Tactile on an iPad in landscape: a full Mac keyboard with glowing blue key edges above a trackpad, with a shortcut bar of Mac shortcuts" width="900">
</p>

Put your Mac on a stand, keep the iPad in front of you, and type and point with it like a laptop. Tactile is a tiny menu bar app for the Mac and a web page for the iPad. Scan a QR code and you're typing; there's nothing to install from the App Store.

## Why Tactile

- **It's a real Mac keyboard.** Function row with media keys, the number row, ⌃ ⌥ ⌘ and fn, inverted-T arrows, rows that line up like a Magic Keyboard. Keys show your Mac's own layout (AZERTY, QWERTZ and others) and switch when you do.
- **It feels like typing.** iPads have no vibration motor, so every key plays a synthesized key sound (Soft, Crisp or Thock), coming from the side of the keyboard the key is on. Letters pop up above your finger, like on the iPhone.
- **It learns your aim.** Glass has no edges to feel, so Tactile quietly learns where you actually press each key and shifts its touch area to match.
- **Rest your fingers.** Fingers resting on the keys don't type; keys type when you lift. Rolled keys still come out in the right order.
- **A proper trackpad.** Tap to click, two-finger click, two-finger scroll with momentum, pinch to zoom, drag, three-finger drag, and swipes for Spaces, Mission Control and App Exposé.
- **Shortcuts in one tap.** A shortcut bar for Undo, Redo, Copy, Paste, Switch App, Screenshot, Mission Control, Spotlight and more. You pick which.
- **Private and secure.** Everything stays between your iPad and your Mac, encrypted with TLS. Pairing takes a one-time code, and over Tailscale only your own devices can connect.
- **Nothing to patch.** No third-party packages on either side: Apple frameworks on the Mac, plain HTML, CSS and JavaScript on the iPad.

## Screenshots

| | |
|---|---|
| ![Silver skin: white keys with a key popup showing the letter a](docs/images/silver.jpg) | ![Frosted Glass skin: translucent keys over a colorful background, keyboard only](docs/images/frosted.jpg) |
| **Silver**, with a key popup | **Frosted Glass**, keyboard only and expanded |
| ![Floating keyboard in Space Black, smaller and centered with a drag handle](docs/images/floating.jpg) | ![Settings sheet with keyboard skins and glow colors](docs/images/settings.jpg) |
| **Floating** keyboard: drag the handle to move it, the corner to resize it | **Settings**: skins, glow colors, sounds, trackpad and layout |

Midnight Glow comes in eight glow colors:

<p align="center"><img src="docs/images/glow-colors.jpg" alt="Midnight Glow skin with purple glowing key edges" width="700"></p>

## Getting started

You need a Mac with **macOS 15 or later** and Apple's free developer tools, plus an iPad (any device with a modern browser works) on the same Wi-Fi network or the same [Tailscale](https://tailscale.com) network.

1. **Install the developer tools**, if you don't have Xcode:
   ```sh
   xcode-select --install
   ```
2. **Download Tactile:**
   ```sh
   git clone https://github.com/KukretiShubham/tactile-keyboard.git
   cd tactile-keyboard
   ```
3. **Build and open it:** double-click `start-tactile.command` (or run `./start-tactile.command`). It builds **Tactile.app** and opens it in your menu bar. The first build takes a few minutes. You can move `build/Tactile.app` to Applications afterwards.
4. **Allow Accessibility:** macOS asks you to allow Tactile in System Settings → Privacy & Security → Accessibility. Every app that types or moves the pointer needs this.
5. **Pair your iPad:** click the Tactile icon in the menu bar, choose **Pair a Device…**, and scan the QR code with the iPad's camera.

Then tap Share → **Add to Home Screen** on the iPad for a full-screen app without Safari's toolbar.

### Connecting over Tailscale (recommended)

With [Tailscale](https://tailscale.com) on both devices, Tactile gets a real HTTPS certificate for your Mac, so there's nothing to install on the iPad, and it works away from home too.

1. In the Tailscale admin console, turn on **MagicDNS** and **HTTPS Certificates** (a one-time step).
2. Open Tactile. The QR code points at your Mac's Tailscale address, such as `https://your-mac.your-tailnet.ts.net:8423`.

Public certificates are listed in public Certificate Transparency logs, so your Mac's Tailscale name becomes publicly visible.

### Connecting over Wi-Fi only

Without Tailscale, Tactile uses its own certificate, which each iPad trusts once:

1. Scan the QR code to open the setup page in Safari.
2. Follow the steps there: download the certificate, install the profile in Settings (check that its SHA-256 fingerprint matches the one in Tactile's menu; hold ⌥ while opening it), and turn on full trust under General → About → Certificate Trust Settings.
3. Open Tactile and enter the pairing code. The iPad is remembered from then on.

### Keep Accessibility allowed when you rebuild

macOS ties the Accessibility permission to the app's signature. To avoid approving Tactile again after every update, run this once:

```sh
scripts/create-signing-certificate.sh
```

It creates a self-signed "Tactile Local Signing" certificate in your login keychain, and every build is signed with it from then on. After creating it, approve Tactile once more: run `tccutil reset Accessibility app.tactile.mac`, open Tactile, and switch it on. If macOS asks whether `codesign` may use the key, enter your password and choose **Always Allow**.

## Using it

| On the iPad | On the Mac |
|---|---|
| Tap a modifier (⇧ ⌃ ⌥ ⌘ fn) | Applies to the next key, like the iPad keyboard |
| Double-tap a modifier | Locks it until you tap it again |
| Hold a modifier and tap a key | A normal shortcut (⌘-Tab stays open while held) |
| fn + delete / arrows | Forward delete, Page Up/Down, Home/End |
| fn + top row | F1–F12 instead of media keys |
| Compose button (top right) | Type with the iPad's own keyboard, for dictation, emoji and autocorrect |

| On the trackpad | |
|---|---|
| Tap / two-finger tap | Click / secondary click |
| Two fingers | Scroll, with momentum |
| Pinch | Zoom in or out in the app you're using |
| Hold, then move | Drag (or three fingers, with Three-Finger Drag on) |
| Three fingers left, right, up, down | Switch Spaces, Mission Control, App Exposé |

A hardware keyboard attached to the iPad is passed through to the Mac too.

### Settings on the iPad

Tap the settings button (top right):

- **Keyboard skin:** Midnight Glow (eight glow colors), Space Black, Silver, Frosted Glass, or Automatic.
- **Keyboard:** Key Height, Function Row, Rest Fingers on Keys, Key Popups, **Adapt to My Typing** (with Reset Typing Learning), and **Match Mac Layout**.
- **Shortcut Bar:** turn it on or off and choose its shortcuts. Letter shortcuts follow your Mac's layout, so ⌘Z is still ⌘Z on AZERTY.
- **Feedback:** key sounds, Soft, Crisp or Thock, volume, Sound in Silent Mode, and vibration on devices that have it.
- **Trackpad:** tracking speed, scrolling speed, natural scrolling, Pinch to Zoom, Three-Finger Drag.
- **Layout:** keyboard, trackpad or both; keyboard at the top, middle or bottom; **Expanded** or **Floating** keyboard; **Keep Screen Awake** (the iPad stays on while you use it, and sleeps normally after 10 idle minutes).

### The menu bar

Click the Tactile icon in the menu bar to see connected devices with their connection quality, and to:

- **Pause Input** (also **⌃⌥⌘P** from any app), or pause automatically while the Mac is locked
- **Disconnect**, **Reconnect** or **Revoke** a device
- turn Tailscale, **Only My Devices on Tailscale**, connection notifications and **Open at Login** on or off
- **Pair a Device…** (⌘P) or **Copy Tailscale Link**

Hold ⌥ while opening it for details: addresses, ports, certificate fingerprint and the log.

## Security and privacy

Tactile can type on your Mac, so it's built to be careful:

- **Encrypted:** everything travels over TLS. The keyboard page and its connection refuse plain HTTP, and only the Mac's own page may connect.
- **Paired, not open:** a new device needs a six-digit code that works once. Wrong guesses lock out quickly. Remembered devices hold a random 256-bit token that the Mac stores only as a hash, and expire after 90 days unused.
- **Only your devices on Tailscale:** Tactile asks Tailscale who owns each device and refuses anything not signed in as you, before it can even try to pair.
- **A limited certificate:** the local certificate authority can only vouch for `.local` names and private addresses, so it can't be used to impersonate websites.
- **Nothing leaves your network:** no accounts, no analytics, no cloud service. What Adapt to My Typing learns stays on the iPad.

Found a security problem? Please report it privately, as described in [SECURITY.md](SECURITY.md).

## FAQ

**Do I need to install anything on the iPad?**
No. Tactile runs in Safari. Add it to the Home Screen for a full-screen app.

**Does it work with an iPhone, an Android tablet, or another computer's browser?**
Yes, anything with a modern browser can connect. The layout is designed for iPads in landscape.

**Why sounds instead of vibration?**
iPads don't have a vibration motor. Devices that do vibrate on each key.

**Does it work with Windows or Linux?**
Not yet. The Mac side uses macOS APIs to send keystrokes and pointer movement.

**Does it slow down my Mac or drain the iPad?**
The Mac app idles in the menu bar. On the iPad, the screen is allowed to sleep after 10 minutes without a touch.

## For developers

```sh
swift build                      # build everything
swift run tactile-checks         # Swift checks, plus the web tests in WebKit
swift run -c release Tactile     # run in a terminal (prints the QR code)
swift run Tactile --dry-run      # log input instead of controlling the Mac
swift run Tactile --help         # other options: --port, --no-tailscale, --forget-devices
```

| Folder | What's there |
|---|---|
| `Sources/TactileCore/` | Everything but the menu bar UI: pairing and certificates (`Security/`), the web and WebSocket servers (`Network/`), turning messages into keystrokes and pointer events (`Input/`), and shared helpers (`Support/`). |
| `Sources/Tactile/` | The menu bar app. `Web/` is the iPad page: `keys.js` (layout), `keyboard.js` (typing), `typing-model.js` (learned touch areas), `trackpad.js`, `shortcuts.js`, `feedback.js` (sounds) and more. |
| `Tests/` | `TactileChecks/` (Swift checks) and `Web/` (tests for the page). |
| `scripts/`, `Packaging/` | Building and signing `Tactile.app`. |

```
iPad Safari ── HTTPS + secure WebSocket ──▶ Tactile (menu bar app) ──▶ macOS keyboard and pointer events
```

See [CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## Contributing

Bug reports, ideas and pull requests are welcome. If Tactile is useful to you, a ⭐ helps others find it.

## License

[MIT](LICENSE). Not affiliated with Apple. Mac, iPad, Magic Keyboard and Safari are trademarks of Apple Inc.
