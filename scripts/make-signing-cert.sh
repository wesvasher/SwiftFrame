#!/bin/zsh
# Makes a self-signed code signing certificate for building SwiftFrame on this
# Mac, and writes Config/Local.xcconfig to use it.
#
# Why: ad-hoc builds look like a new app to macOS every time, so it asks
# again for camera access after each build. Signing every build with the
# same certificate lets macOS remember. No Apple account is needed; the
# certificate only works on this Mac and isn't used for releases.
#
# Usage: scripts/make-signing-cert.sh   (does nothing if the certificate exists)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="SwiftFrame Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
LOCAL="Config/Local.xcconfig"

existing=$(security find-identity -p codesigning "$KEYCHAIN" | awk -v n="\"$NAME\"" 'index($0, n) { print $2; exit }')
if [[ -n "$existing" ]]; then
  echo "“$NAME” is already in your keychain ($existing)."
  hash="$existing"
else
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  cat > "$work/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  pass="$(openssl rand -hex 16)"
  openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$NAME" \
    -out "$work/id.p12" -passout "pass:$pass"
  # -T lets codesign use the key without asking each build.
  security import "$work/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  hash=$(openssl x509 -in "$work/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
  echo "Made “$NAME” ($hash), valid for 10 years, in your login keychain."
fi

if [[ -f "$LOCAL" ]] && grep -q "^CODE_SIGN_IDENTITY *= *$hash" "$LOCAL"; then
  echo "$LOCAL already uses it."
  exit 0
fi
if [[ -f "$LOCAL" ]]; then
  cp "$LOCAL" "$LOCAL.bak"
  echo "Saved the old $LOCAL as $LOCAL.bak."
fi
cat > "$LOCAL" <<EOF
// This Mac only (gitignored). Written by scripts/make-signing-cert.sh.
// Signs local builds with "$NAME", a self-signed certificate in the login
// keychain, so macOS remembers camera access across rebuilds. Release DMGs are still built by GitHub Actions.
CODE_SIGN_IDENTITY = $hash
DEVELOPMENT_TEAM =
// Hardened runtime only loads code signed by Apple or the same Apple team,
// and a self-signed certificate has no team, so debug builds and tests
// couldn't load their own libraries. Release DMGs keep it on.
ENABLE_HARDENED_RUNTIME = NO
EOF
echo "Wrote $LOCAL. Allow camera access once more after the next build; then it stays allowed."
