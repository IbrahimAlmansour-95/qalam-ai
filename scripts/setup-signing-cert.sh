#!/usr/bin/env bash
#
# Creates a STABLE self-signed code-signing identity in the login keychain.
#
# Why: ad-hoc signing (`codesign -s -`) gives the app a new code identity on
# every build (the cdhash changes), so macOS TCC drops the Accessibility grant
# after each update and autocomplete stops working until the user re-grants.
# Signing with a stable self-signed certificate keeps the app's *designated
# requirement* (identifier + certificate) constant across rebuilds, so the
# Accessibility (and Input Monitoring, etc.) grant survives updates.
#
# This is a LOCAL developer convenience — it is NOT a Developer ID and does
# nothing for Gatekeeper on other people's Macs (they still right-click→Open,
# same as ad-hoc). It only stabilizes permissions on machines where the cert
# is installed.
#
# Idempotent: if the identity already exists, it does nothing.
#
# Usage: bash scripts/setup-signing-cert.sh

set -euo pipefail

CERT_NAME="QalamAI Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# ── Step 2 (defined first so it runs whether or not the cert already exists) ──
# Let `codesign` use the private key without a GUI prompt on every build by
# adding it to the key's partition list. This needs YOUR login/keychain
# password — the script reads it silently and passes it straight to `security`;
# it is never printed, stored, or visible to anyone else.
configure_partition_list() {
    echo
    echo "→ Allowing codesign to use the key without prompting on every build."
    echo "  Enter your Mac login password (keychain password). It is not shown"
    echo "  or saved. Press Return to skip (you'll instead click \"Always Allow\""
    echo "  once on the first build)."
    printf "  Login password: "
    read -rs KCPW
    echo
    if [[ -z "$KCPW" ]]; then
        echo "  Skipped — the first signed build will prompt once; click \"Always Allow\"."
        return 0
    fi
    if security set-key-partition-list \
        -S apple-tool:,apple:,codesign: -s \
        -k "$KCPW" "$KEYCHAIN" >/dev/null 2>&1; then
        echo "  ✓ codesign can now use the key silently."
    else
        echo "  ⚠︎ Couldn't set the partition list (wrong password?). The first build"
        echo "    will prompt once — click \"Always Allow\" and you're set."
    fi
    unset KCPW
}

# Already present? Skip creation, but still (re)configure the partition list.
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ Signing identity \"$CERT_NAME\" already exists."
    configure_partition_list
    exit 0
fi

echo "→ Creating self-signed code-signing certificate \"$CERT_NAME\"…"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# OpenSSL config: a self-signed leaf with the Code Signing extended key usage.
cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = v3_codesign
prompt             = no

[ dn ]
CN = QalamAI Self-Signed

[ v3_codesign ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# Bundle into a PKCS#12 for keychain import.
openssl pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/qalamai.p12" -name "$CERT_NAME" \
    -passout pass:qalamai >/dev/null 2>&1

# Import the cert + private key into the login keychain, granting codesign
# access so it can use the key (the first build will still ask once — see note).
security import "$TMP/qalamai.p12" \
    -k "$KEYCHAIN" -P qalamai \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1

# Trust the cert for code signing in the *user's* trust settings so
# `codesign --sign` accepts it. This is scoped to the login keychain (no admin
# password needed for the user trust domain).
security add-trusted-cert \
    -p codeSign \
    -k "$KEYCHAIN" "$TMP/cert.pem" >/dev/null 2>&1 || true

echo "✓ Created \"$CERT_NAME\" in the login keychain."
echo
echo "  Note: the FIRST build that signs with it may pop a one-time prompt:"
echo "        \"codesign wants to sign using key … in your keychain\"."
echo "        Click **Always Allow** (no password) and it won't ask again."
echo
security find-identity -v -p codesigning | grep "$CERT_NAME" || \
    echo "  (Identity not yet listed as valid — build.sh will fall back to ad-hoc if codesign can't use it.)"
