# Changelog

What changed in each release of Tactile. Each release's download is on the [releases page](https://github.com/KukretiShubham/tactile-keyboard/releases).

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
