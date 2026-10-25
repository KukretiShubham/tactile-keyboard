# Security policy

Tactile can type and move the pointer on your Mac, so security problems matter. Thank you for reporting them responsibly.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: on the repository's **Security** tab, choose **Report a vulnerability**. Don't open a public issue for a security problem.

Include what an attacker could do, the steps to reproduce it, and the Tactile version or commit. You'll get a reply as soon as possible, and credit in the fix's release notes if you'd like.

## Supported versions

Only the latest release (and `main`) receives security fixes.

## What Tactile defends against

- **Other devices on the network:** they can't send input without pairing, pairing codes are single-use and rate-limited, and remembered devices hold 256-bit tokens that the Mac stores only as hashes.
- **Eavesdropping:** all keyboard and trackpad traffic uses TLS. The local certificate authority is name-constrained to `.local` names and private addresses, so it can't impersonate public websites.
- **Other websites in the iPad's browser:** the socket only accepts connections from Tactile's own page.
- **Other people on a shared tailnet:** with "Only My Devices on Tailscale", devices not signed in as the Mac's owner are refused before they can try to pair.

Out of scope: someone with access to your unlocked Mac or iPad, and malware already running as your user.
