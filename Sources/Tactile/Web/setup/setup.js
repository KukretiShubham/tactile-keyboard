const status = document.getElementById('status');
const openButton = document.getElementById('openButton');

const info = await fetch('/setup.json', { cache: 'no-store' }).then((response) => response.json());
const localURL = `https://${location.hostname}:${info.appPort}/`;
document.getElementById('fingerprint').textContent = info.fingerprint;
document.getElementById('caName').textContent = info.caName;
document.getElementById('tailscaleNote').hidden = !info.tailscaleURL;
openButton.href = localURL;

// An opaque request succeeds only if the TLS handshake does, so it tells us
// whether this iPad can use an address. Tailscale wins when it works: it
// needs no setup and works away from home too.
async function reachable(url) {
  try {
    await fetch(`${url}config.json`, { mode: 'no-cors', cache: 'no-store' });
    return true;
  } catch {
    return false;
  }
}

async function bestAddress() {
  if (info.tailscaleURL && (await reachable(info.tailscaleURL))) return info.tailscaleURL;
  if (await reachable(localURL)) return localURL;
  return null;
}

let ready = false;
async function check() {
  if (ready || document.hidden) return;
  const url = await bestAddress();
  if (!url) return;
  ready = true;
  openButton.href = url;
  status.textContent = url === info.tailscaleURL
    ? 'Connected through Tailscale. You’re all set.'
    : 'This iPad trusts your Mac. You’re all set.';
  status.classList.add('done');
  openButton.removeAttribute('aria-disabled');
  document.getElementById('finalStep').classList.add('done');
}

// A returning iPad (or one on Tailscale) goes straight to the keyboard.
const url = await bestAddress();
if (url) location.replace(url);

setInterval(check, 2000);
document.addEventListener('visibilitychange', check);
