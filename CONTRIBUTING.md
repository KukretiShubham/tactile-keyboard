# Contributing to Tactile

Thanks for helping. This page covers building, testing and the few conventions the code follows.

## Build and run

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

## Conventions

- **No third-party dependencies.** The Mac side uses Apple frameworks only; the page is plain JavaScript modules. This keeps the supply chain empty.
- **One place for each job.** Shared helpers live in `Sources/TactileCore/Support/` (Swift) and `Sources/Tactile/Web/util.js` (JavaScript). Reuse them rather than adding near-copies.
- **Core vs app.** Anything that doesn't draw menu bar UI belongs in `TactileCore`, where the checks can reach it.
- **Security first.** Input from the network is untrusted: validate it, bound it, and fail closed. Never log what is typed, except in a dry run.
- **No personal details** (names, addresses, host names, tailnet names) in code, tests, docs or commit messages. Use placeholders like `your-mac.your-tailnet.ts.net`.
- **Style:** match the surrounding code. Comments explain why, in plain words. UI text follows Apple's Human Interface Guidelines (title-case controls, sentence-case descriptions).

## Pull requests

Keep each pull request to one change, describe what it changes for someone using Tactile, and make sure `swift run tactile-checks` passes.
