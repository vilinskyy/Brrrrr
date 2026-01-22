#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH="$ROOT_DIR/Brrrr.xcodeproj"
SCHEME="Brrrrr"
DESTINATION="platform=macOS"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/BrrrrDerivedData}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${TMPDIR:-/tmp}/BrrrrTestResults.xcresult}"

mkdir -p "$DERIVED_DATA_PATH"
mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"

if [[ -e "$RESULT_BUNDLE_PATH" ]]; then
  if [[ "$RESULT_BUNDLE_PATH" == *.xcresult ]]; then
    rm -rf "$RESULT_BUNDLE_PATH"
  else
    echo "Result bundle path must end with .xcresult: $RESULT_BUNDLE_PATH"
    exit 1
  fi
fi

xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  "$@" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
