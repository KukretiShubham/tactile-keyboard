# Changelog

What changed in each release of Tactile. Each release's download is on the [releases page](https://github.com/KukretiShubham/tactile-keyboard/releases).

## Unreleased

- **Send right after you talk:** Esc, Delete and **Send** (Return) now sit right under the Voice Typing key, so you can dictate and send with one hand. In Trackpad only they're the first Return, Delete and Esc on screen.
- **Cancel:** while Granola listens, Esc becomes **Cancel**. Slide off the Voice Typing key onto it to throw the words away instead of pasting them. Any Esc now stops the key showing hands-free.
- **Keyboard only** at its Fit size gets a shelf under the keys in landscape: Voice Typing and Send on the left, your shortcuts in the middle, and app hotkeys on the right, which used to need the trackpad. Put the keyboard in the middle to keep the old look.
- The Voice Typing key names the app your words will go into, and stays put when you switch to Granola's tab.
- Fix: with Rest Fingers on Keys, a slow Return, Tab or Esc no longer gets ignored.

## 1.2.0

- **Granola:** a hotkey pack with a Voice Typing key that holds Granola's dictation key for you (hold to talk, double-tap for hands-free), in Granola's own colors. It also sits beside the general shortcuts, so you can dictate into any app. If you changed Granola's key from fn, tap **Change** on the Granola tab (or use Settings) and press yours.
- **Trackpad only:** in landscape, the trackpad-only layout keeps the shortcut keys and app hotkeys on either side of the trackpad.
- **One-command install:** `curl -fsSL https://raw.githubusercontent.com/KukretiShubham/tactile-keyboard/main/install.sh | sh` downloads, verifies and installs the latest release.
- The Mac can now hold fn, for apps that use it as a shortcut.

## 1.1.0

- **App hotkeys.** Keys beside the trackpad for Claude Code, Codex, VS Code, Zed, Xcode, JetBrains IDEs and browsers, shown with each app's own icon from your Mac. They follow the app in front, tapping a tab brings that app forward, and you can hide the ones you don't use.
- **Claude Code and Codex:** tabs bring back the desktop app or terminal window you used last; **Start** runs them in a new terminal window.
- **Two-tap toggles:** a second tap closes the panel or palette a hotkey opened, and switched-on keys light up.
- **Your own hotkeys:** record a key combination on Tactile's keyboard, or send text, for one app or all.
- **Safer pairing:** the pairing code only travels in HTTPS links. With Tailscale one scan still pairs; on Wi-Fi only you type the code once.
- **Faster start:** Tactile works on Wi-Fi straight away and adds the Tailscale address when its certificate arrives, instead of waiting for it.
- Hotkey labels fit any key height; the status and buttons share a row on the left.
- Fixes: a device you disconnected from the menu now sees "Disconnected by your Mac" instead of "Mac not reachable"; Tactile now starts on Macs with very long names (certificate names were over OpenSSL's 64-character limit).

## 1.0.0

The first release: a full Mac keyboard with key sounds and skins, a trackpad with gestures, a MacBook-style layout with shortcut keys, adaptive typing, Tailscale or Wi-Fi with TLS, and a menu bar app.
