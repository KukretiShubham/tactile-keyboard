// The pairing sheet: the six-digit code from the Mac, typed on the iPad.
import { closeSheet, openSheet } from './util.js';

export function createPairingSheet(connection) {
  const sheet = document.getElementById('pairSheet');
  const code = document.getElementById('pairCode');
  const error = document.getElementById('pairError');

  const submit = () => {
    const digits = code.value.replace(/\D/g, '');
    if (digits.length !== 6) {
      error.textContent = 'The code has six digits.';
      return;
    }
    error.textContent = '';
    connection.pair(digits);
  };
  code.addEventListener('input', () => {
    code.value = code.value.replace(/\D/g, '').slice(0, 6);
    if (code.value.length === 6) submit();
  });
  code.addEventListener('keydown', (event) => { if (event.key === 'Enter') submit(); });
  document.getElementById('pairButton').addEventListener('click', submit);

  return {
    show() {
      if (!sheet.hidden) return;
      code.value = '';
      error.textContent = '';
      openSheet(sheet);
      code.focus();
    },
    hide() {
      if (sheet.hidden) return;
      code.blur();
      closeSheet(sheet);
    },
    /** The Mac refused a code: `locked` (too many tries), `expired` or wrong. */
    denied(reason) {
      code.value = '';
      error.textContent = {
        locked: 'Too many tries. Wait a minute, then try again.',
        expired: 'That QR code has expired. Enter the code your Mac shows now.',
      }[reason] ?? "That code didn't match. Check the code in Tactile's menu on your Mac.";
    },
  };
}
