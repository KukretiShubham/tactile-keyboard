# Contributing to Tactile

Thanks for helping. This page covers building, testing and the few conventions the code follows.

## Build and run

You need macOS 15 and Xcode 16, or the Command Line Tools 16 or later (`xcode-select --install`), for the Swift 6 toolchain. There's nothing else to install.

```sh
swift build                      # everything
swift run -c release Tactile     # run in a terminal (QR code and logs print there)
scripts/build-app.sh             # build and sign build/Tactile.app
```

`swift run Tactile --dry-run` logs input instead of controlling the Mac, and serves a plain-HTTP copy of the page at `http://127.0.0.1:8425` for trying UI changes in a desktop browser. To keep a dry run from touching your real paired devices, give it a throwaway home folder:

```sh
CFFIXED_USER_HOME="$(mktemp -d)" swift run Tactile --dry-run
```

## Checks

```sh
swift run tactile-checks             # Swift checks, then the web tests in WebKit
swift run tactile-checks --no-web    # Swift checks only
```

The Command Line Tools ship neither XCTest nor Swift Testing, so the checks are a small executable (`Tests/TactileChecks`) that works with any Swift toolchain. It covers pairing, the Tailscale owner check, key maps, the web server and the WebSocket protocol, and then runs `Tests/Web` in a WebKit view and reports each web test.

To work on the web tests in a browser, serve the repository root and open the test page:

```sh
python3 -m http.server 8490 --bind 127.0.0.1
open http://127.0.0.1:8490/Tests/Web/index.html
```

Add a test with every bug fix: a test that fails before the fix and passes after.

- **Swift checks** live in `Tests/TactileChecks/`, grouped by area (`SecurityChecks.swift`, `NetworkChecks.swift`, …). Add a `checks.run("…") { … }` to the right file.
- **Web tests** live in `Tests/Web/*.test.js`. A new test file must also be added to the list in `Tests/Web/index.html`, since a browser can't list a folder.

## Conventions

- **No third-party dependencies.** The Mac side uses Apple frameworks only; the page is plain JavaScript modules. This keeps the supply chain empty.
- **One place for each job.** Shared helpers live in `Sources/TactileCore/Support/` (Swift) and `Sources/Tactile/Web/util.js` (JavaScript). Reuse them rather than adding near-copies.
- **Core vs app.** Anything that doesn't draw menu bar UI belongs in `TactileCore`, where the checks can reach it.
- **Security first.** Input from the network is untrusted: validate it, bound it, and fail closed. Never log what is typed, except in a dry run.
- **No personal details** (names, addresses, host names, tailnet names) in code, tests, docs or commit messages. Use placeholders like `your-mac.your-tailnet.ts.net`.
- **Style:** match the surrounding code (`.editorconfig` sets the indentation: 4 spaces for Swift, 2 for everything else). Comments explain why, in plain words. UI text follows Apple's Human Interface Guidelines (title-case controls, sentence-case descriptions).

## Pull requests

Keep each pull request to one change, describe what it changes for someone using Tactile, and make sure `swift run tactile-checks` passes. Add a line to [CHANGELOG.md](CHANGELOG.md) for anything people will notice. To add hotkeys for another app, see [docs/app-hotkeys.md](docs/app-hotkeys.md).

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Releasing

1. Set the new version in `Packaging/Info.plist` (`CFBundleShortVersionString`, e.g. `1.1.0`), give it a heading in `CHANGELOG.md`, and commit both.
2. Tag the commit with release notes as the tag message, and push the tag:
   ```sh
   git tag -s v1.1.0
   git push origin v1.1.0
   ```
3. The **Release** workflow runs the checks, builds a universal `Tactile.app`, and publishes it with a checksum (and, for public repositories, a build provenance attestation). It refuses a tag that doesn't match the version in `Info.plist`.
