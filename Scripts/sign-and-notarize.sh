#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RepoBar"
APP_IDENTITY="${APP_IDENTITY:-Developer ID Application: John Larkin (P3Q6VLD666)}"
APP_BUNDLE="RepoBar.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
DSYM_ZIP="${APP_NAME}-${MARKETING_VERSION}.dSYM.zip"

# Notarization credentials: support both APPLE_* and APP_STORE_CONNECT_* env vars.
NOTARY_KEY_PATH=""
NOTARY_KEY_ID=""
NOTARY_ISSUER=""
CLEANUP_KEY_FILE=false

if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY:-}" && -n "${APPLE_ISSUER_ID:-}" ]]; then
  NOTARY_KEY_PATH="$APPLE_API_KEY_PATH"
  NOTARY_KEY_ID="$APPLE_API_KEY"
  NOTARY_ISSUER="$APPLE_ISSUER_ID"
elif [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/repobar-api-key.p8
  NOTARY_KEY_PATH="/tmp/repobar-api-key.p8"
  NOTARY_KEY_ID="$APP_STORE_CONNECT_KEY_ID"
  NOTARY_ISSUER="$APP_STORE_CONNECT_ISSUER_ID"
  CLEANUP_KEY_FILE=true
else
  echo "Missing notarization credentials. Set either APPLE_API_KEY_PATH/APPLE_API_KEY/APPLE_ISSUER_ID or APP_STORE_CONNECT_* env vars." >&2
  exit 1
fi

# Sparkle key is optional for fork builds (no auto-update feed).
SKIP_SPARKLE=false
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE not set — skipping Sparkle signing (fork build)."
  SKIP_SPARKLE=true
elif [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE — skipping Sparkle signing." >&2
  SKIP_SPARKLE=true
else
  key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
  if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
    echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
    exit 1
  fi
fi

cleanup() {
  if [[ "$CLEANUP_KEY_FILE" == "true" ]]; then
    rm -f /tmp/repobar-api-key.p8
  fi
  rm -f "/tmp/${APP_NAME}Notarize.zip"
}
trap cleanup EXIT

# Build universal binary (arm64 + x86_64).
ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
SKIP_BUILD=1 ./Scripts/package_app.sh release

# Resolve the built app bundle and copy to project root for signing/packaging.
BUILT_BUNDLE=""
for candidate in \
  ".build/apple/Products/Release/${APP_NAME}.app" \
  ".build/release/${APP_NAME}.app" \
  ".build/arm64-apple-macosx/release/${APP_NAME}.app" \
  ".build/x86_64-apple-macosx/release/${APP_NAME}.app"; do
  if [[ -d "$candidate" ]]; then
    BUILT_BUNDLE="$candidate"
    break
  fi
done
if [[ -z "$BUILT_BUNDLE" ]]; then
  echo "ERROR: app bundle not found after package_app.sh" >&2
  exit 1
fi
rm -rf "$APP_BUNDLE"
cp -R "$BUILT_BUNDLE" "$APP_BUNDLE"

echo "Signing with $APP_IDENTITY"
# codesign_app.sh handles frameworks, aux binaries, and the main executable.
CODESIGN_IDENTITY="$APP_IDENTITY" ./Scripts/codesign_app.sh "$APP_BUNDLE" "$APP_IDENTITY"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

echo "Submitting for notarization"
xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

# Strip extended attributes that would create AppleDouble files when zipping
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
FIRST_ARCH="${ARCH_LIST[0]}"
PREFERRED_ARCH_DIR=".build/${FIRST_ARCH}-apple-macosx/release"
DSYM_PATH="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
  MERGED_DSYM="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM-universal"
  rm -rf "$MERGED_DSYM"
  cp -R "$DSYM_PATH" "$MERGED_DSYM"
  DWARF_PATH="${MERGED_DSYM}/Contents/Resources/DWARF/${APP_NAME}"
  BINARIES=()
  for ARCH in "${ARCH_LIST[@]}"; do
    ARCH_DSYM=".build/${ARCH}-apple-macosx/release/${APP_NAME}.dSYM/Contents/Resources/DWARF/${APP_NAME}"
    if [[ ! -f "$ARCH_DSYM" ]]; then
      echo "Missing dSYM for ${ARCH} at $ARCH_DSYM" >&2
      exit 1
    fi
    BINARIES+=("$ARCH_DSYM")
  done
  lipo -create "${BINARIES[@]}" -output "$DWARF_PATH"
  DSYM_PATH="$MERGED_DSYM"
fi
"$DITTO_BIN" --norsrc -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
