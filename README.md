# Resourcio

Native macOS menu bar app that shows the top 5 consumer apps currently impacting user experience, scored as a weighted percentage out of 100.

## What It Does

- Tracks running GUI apps and ranks the top 5 by impact.
- Shows each app on one line with total impact %, CPU %, and memory %.
- Adds badges: `SPIKE`, `TABS`, `AI`.
- Updates every `500ms`.
- On mouseover, shows a quick explanation of why that app is using resources.

## Scoring (High Level)

- `60%` CPU impact
- `30%` memory impact
- `10%` foreground (active app) boost
- `+12` for sustained CPU spike
- `+8` for tab-like memory pressure

## Run

```bash
swift build
swift run
```

## Requirements

- macOS 13+
- Swift 6.2 toolchain

## Packaging And Release

Local signed/notarized release:

```bash
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID1234"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID1234)"

./scripts/preflight_release.sh
./scripts/release_local.sh
```

If signing secrets are missing, `release_local.sh` automatically falls back to an unsigned `.app` + unsigned `.dmg` build.

GitHub release automation:

- Tag push `v*` triggers `.github/workflows/release.yml`.
- Required repo secrets:
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `SIGNING_CERT_BASE64` (Developer ID Application `.p12`, base64-encoded)
- `SIGNING_CERT_PASSWORD`
- `KEYCHAIN_PASSWORD`
