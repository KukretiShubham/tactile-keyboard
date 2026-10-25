#!/bin/zsh
# Creates the "Tactile Local Signing" code-signing certificate in your login
# keychain, once. build-app.sh then signs Tactile.app with it, so macOS keeps
# Tactile's Accessibility permission across rebuilds.
#
# It's self-signed and only used to sign apps you build on this Mac; it isn't
# trusted for anything else and changes no trust settings.
set -euo pipefail

NAME="Tactile Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists in your keychain. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
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
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASSWORD" -out "$WORK/identity.p12"

# -T lets codesign use the key without asking each time.
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASSWORD" -T /usr/bin/codesign

echo "Created \"$NAME\". Now run ./build-app.sh (or double-click start-tactile.command)."
echo "If macOS asks whether codesign may use the key, choose Always Allow."
