#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Resourcio"
ARCHIVE_PATH="$ROOT_DIR/dist/${APP_NAME}.xcarchive"
EXPORT_PATH="$ROOT_DIR/dist/export"
DMG_PATH="$ROOT_DIR/dist/${APP_NAME}.dmg"
STAGE_PATH="$ROOT_DIR/dist/dmg-stage"
PROJECT_FILE="$ROOT_DIR/${APP_NAME}.xcodeproj"
EXPORT_PLIST_TMP="$ROOT_DIR/dist/exportOptions.plist"

command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun is required"; exit 1; }

SIGNED_RELEASE=1
if [[ -z "${APPLE_ID:-}" ]] || [[ -z "${APPLE_TEAM_ID:-}" ]] || [[ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] || [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  SIGNED_RELEASE=0
fi

if [[ "$SIGNED_RELEASE" -eq 1 ]]; then
  echo "Running release preflight checks (signed mode)..."
  "$ROOT_DIR/scripts/preflight_release.sh" signed
else
  echo "Signing secrets not fully present. Falling back to unsigned release."
  echo "Running release preflight checks (unsigned mode)..."
  "$ROOT_DIR/scripts/preflight_release.sh" unsigned
fi

rm -rf "$ROOT_DIR/dist"
mkdir -p "$ROOT_DIR/dist"

if command -v xcodegen >/dev/null 2>&1; then
  echo "Generating Xcode project..."
  xcodegen generate
else
  if [[ -d "$PROJECT_FILE" ]]; then
    echo "xcodegen not found; using existing project at $PROJECT_FILE"
  else
    echo "xcodegen is required when $PROJECT_FILE does not exist." >&2
    exit 1
  fi
fi

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Expected project not found: $PROJECT_FILE" >&2
  exit 1
fi

APP_PATH=""

if [[ "$SIGNED_RELEASE" -eq 1 ]]; then
  sed "s/__TEAM_ID__/${APPLE_TEAM_ID}/g" "$ROOT_DIR/config/exportOptions.plist" > "$EXPORT_PLIST_TMP"

  echo "Archiving app..."
  xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic

  echo "Exporting signed app..."
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST_TMP"

  APP_PATH="$EXPORT_PATH/${APP_NAME}.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Exported app not found: $APP_PATH" >&2
    exit 1
  fi

  echo "Ensuring Developer ID signature..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"

  echo "Submitting app for notarization..."
  xcrun notarytool submit "$APP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  echo "Stapling app..."
  xcrun stapler staple "$APP_PATH"
else
  echo "Building unsigned app..."
  xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$ROOT_DIR/dist/DerivedData" \
    build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

  APP_PATH="$ROOT_DIR/dist/DerivedData/Build/Products/Release/${APP_NAME}.app"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Unsigned app not found: $APP_PATH" >&2
    exit 1
  fi
fi

echo "Building DMG..."
rm -rf "$STAGE_PATH"
mkdir -p "$STAGE_PATH"
cp -R "$APP_PATH" "$STAGE_PATH/"
ln -s /Applications "$STAGE_PATH/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGNED_RELEASE" -eq 1 ]]; then
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  echo "Stapling DMG..."
  xcrun stapler staple "$DMG_PATH"
else
  echo "Skipping notarization/stapling for unsigned DMG."
fi

echo "Done."
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
if [[ "$SIGNED_RELEASE" -eq 0 ]]; then
  echo "Release mode: UNSIGNED"
else
  echo "Release mode: SIGNED + NOTARIZED"
fi
