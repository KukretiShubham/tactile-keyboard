const status = document.getElementById('status');
const openButton = document.getElementById('openButton');

const info = await fetch('/setup.json', { cache: 'no-store' }).then((response) => response.json());
const appURL = `https://${location.hostname}:${info.appPort}/`;
document.getElementById('fingerprint').textContent = info.fingerprint;
document.getElementById('caName').textContent = info.caName;
openButton.href = appURL;

// An opaque request succeeds only if the TLS handshake does, which tells us
// whether this iPad already trusts the Mac's certificate.
async function trusted() {
  try {
    await fetch(`${appURL}config.json`, { mode: 'no-cors', cache: 'no-store' });
    return true;
  } catch {
    return false;
  }
}

let ready = false;
async function check() {
  if (ready || document.hidden) return;
  if (!(await trusted())) return;
  ready = true;
  status.textContent = 'This iPad trusts your Mac. You’re all set.';
  status.classList.add('done');
  openButton.removeAttribute('aria-disabled');
  document.getElementById('finalStep').classList.add('done');
}

// Already trusted (a returning iPad): go straight to the keyboard.
if (await trusted()) location.replace(appURL);

setInterval(check, 2000);
document.addEventListener('visibilitychange', check);
