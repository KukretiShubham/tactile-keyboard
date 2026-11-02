#!/bin/zsh
# Creates "Tactile Release Signing", the certificate every release is signed
# with, once per project, and stores it in the repository's secrets for the
# release workflow. Installed copies of Tactile update only to apps signed
# with it, and macOS keeps Accessibility allowed across those updates.
#
# Usage: scripts/create-release-certificate.sh <backup.p12>
#
# Nothing goes into your keychain. A copy is saved to <backup.p12>: keep it,
# and the password this prints, somewhere safe (a password manager). A new
# certificate would mean everyone installing the next release by hand.
set -euo pipefail

BACKUP="${1:?Usage: scripts/create-release-certificate.sh <backup.p12>}"
[[ -e "$BACKUP" ]] && { echo "$BACKUP already exists; not replacing it." >&2; exit 1; }
command -v gh >/dev/null || { echo "This needs the GitHub CLI (gh), signed in to the repository." >&2; exit 1; }

NAME="Tactile Release Signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CONF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -hex 24)"
# macOS's keychain only reads these older PKCS#12 ciphers.
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASSWORD" -out "$WORK/identity.p12"

install -m 600 "$WORK/identity.p12" "$BACKUP"
base64 -i "$WORK/identity.p12" | gh secret set TACTILE_SIGNING_CERTIFICATE
print -rn -- "$PASSWORD" | gh secret set TACTILE_SIGNING_PASSWORD

echo "Created \"$NAME\" and stored it in the repository's secrets."
echo "Backup: $BACKUP"
echo "Password (save it with the backup): $PASSWORD"
