#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Resourcio"
MODE="${1:-auto}" # auto | signed | unsigned
PROJECT_FILE="$APP_NAME.xcodeproj"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

has_errors=0
has_warnings=0

check_ok() {
  echo -e "${GREEN}OK${NC}  $1"
}

check_warn() {
  has_warnings=1
  echo -e "${YELLOW}WARN${NC} $1"
}

check_fail() {
  has_errors=1
  echo -e "${RED}FAIL${NC} $1"
}

require_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    check_ok "Command found: $cmd"
  else
    check_fail "Missing command: $cmd"
  fi
}

check_xcodegen_or_project() {
  if command -v xcodegen >/dev/null 2>&1; then
    check_ok "Command found: xcodegen"
    return
  fi

  if [[ -d "$PROJECT_FILE" ]]; then
    check_warn "xcodegen missing, but existing project found: $PROJECT_FILE"
  else
    check_fail "Missing xcodegen and no existing project found ($PROJECT_FILE)."
  fi
}

check_xcode_full() {
  local devdir
  devdir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -z "$devdir" ]]; then
    check_fail "xcode-select has no active developer directory."
    return
  fi

  if [[ "$devdir" == *"CommandLineTools"* ]]; then
    check_fail "Active developer directory points to CommandLineTools, not full Xcode."
    echo "      Fix: sudo xcode-select -s /Applications/Xcode.app"
    return
  fi

  if xcodebuild -version >/dev/null 2>&1; then
    check_ok "Full Xcode is active: $devdir"
  else
    check_fail "xcodebuild unavailable even though developer directory is set."
  fi
}

check_signing_identities() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if echo "$identities" | rg -q "Developer ID Application"; then
    check_ok "Developer ID Application signing identity found."
  else
    check_fail "No Developer ID Application identity found in keychain."
  fi
}

has_signing_env() {
  [[ -n "${APPLE_ID:-}" ]] &&
    [[ -n "${APPLE_TEAM_ID:-}" ]] &&
    [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] &&
    [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]
}

check_env_var() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    check_ok "Env var set: $name"
  else
    check_fail "Missing env var: $name"
  fi
}

check_optional_env_var() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    check_ok "Env var set: $name"
  else
    check_warn "Optional env var not set: $name"
  fi
}

echo "Preflight checks for $APP_NAME release"
echo

require_command rg
check_xcodegen_or_project
require_command xcodebuild
require_command xcrun
require_command hdiutil
require_command sed

effective_mode="$MODE"
if [[ "$MODE" == "auto" ]]; then
  if has_signing_env; then
    effective_mode="signed"
  else
    effective_mode="unsigned"
  fi
fi

if [[ "$effective_mode" == "signed" ]]; then
  check_xcode_full
  require_command codesign
  require_command security
  check_signing_identities
else
  check_warn "Unsigned mode selected. App will not be notarized/stapled."
fi

echo
if [[ "$effective_mode" == "signed" ]]; then
  echo "Required environment variables (signed mode):"
  check_env_var APPLE_ID
  check_env_var APPLE_TEAM_ID
  check_env_var APPLE_APP_SPECIFIC_PASSWORD
  check_env_var DEVELOPER_ID_APPLICATION
else
  echo "Environment variables:"
  check_optional_env_var APPLE_ID
  check_optional_env_var APPLE_TEAM_ID
  check_optional_env_var APPLE_APP_SPECIFIC_PASSWORD
  check_optional_env_var DEVELOPER_ID_APPLICATION
fi

echo
echo "Optional environment variables:"
check_optional_env_var APP_VERSION

echo
if [[ "$has_errors" -ne 0 ]]; then
  echo -e "${RED}Preflight failed.${NC} Fix the FAIL items above."
  exit 1
fi

if [[ "$has_warnings" -ne 0 ]]; then
  echo -e "${YELLOW}Preflight passed with warnings.${NC}"
else
  echo -e "${GREEN}Preflight passed.${NC}"
fi
