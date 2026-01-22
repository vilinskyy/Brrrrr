#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WATCH_MODE="false"
if [[ "${1:-}" == "--watch" ]]; then
  WATCH_MODE="true"
  shift
fi

run_tests() {
  if bash "$ROOT_DIR/run-tests.sh" "$@"; then
    echo "Tests passed."
  else
    echo "Tests failed."
  fi
}

if [[ "$WATCH_MODE" == "true" ]]; then
  if ! command -v fswatch >/dev/null 2>&1; then
    echo "fswatch is required for watch mode."
    echo "Install it with: brew install fswatch"
    exit 1
  fi

  echo "Starting TDD watch mode."
  run_tests "$@"

  fswatch -o \
    "$ROOT_DIR/Brrrr" \
    "$ROOT_DIR/BrrrrTests" \
    | while read -r _; do
      echo "Change detected. Running tests..."
      run_tests "$@"
    done
else
  run_tests "$@"
fi
