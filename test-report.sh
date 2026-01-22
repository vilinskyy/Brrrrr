#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-${TMPDIR:-/tmp}/BrrrrTestResults.xcresult}"

SKIP_RUN="false"
if [[ "${1:-}" == "--skip-run" ]]; then
  SKIP_RUN="true"
  shift
fi

if [[ "$SKIP_RUN" != "true" ]]; then
  bash "$ROOT_DIR/run-tests.sh" "$@"
fi

if [[ ! -d "$RESULT_BUNDLE_PATH" ]]; then
  echo "Result bundle not found at: $RESULT_BUNDLE_PATH"
  echo "Run tests first or set RESULT_BUNDLE_PATH."
  exit 1
fi

RESULT_BUNDLE_PATH="$RESULT_BUNDLE_PATH" python3 - <<'PY'
import json
import os
import subprocess
import sys

result_path = os.environ.get("RESULT_BUNDLE_PATH")
if not result_path:
    print("RESULT_BUNDLE_PATH is not set.")
    sys.exit(1)

def xcresult_get(extra_args):
    cmd = [
        "xcrun",
        "xcresulttool",
        "get",
        "object",
        "--format",
        "json",
        "--path",
        result_path,
        "--legacy",
    ] + extra_args
    output = subprocess.check_output(cmd)
    return json.loads(output)

def values(obj):
    if isinstance(obj, dict) and "_values" in obj:
        return obj["_values"]
    if isinstance(obj, list):
        return obj
    return []

def unwrap(obj):
    if isinstance(obj, dict) and "_value" in obj:
        return obj["_value"]
    return obj

data = xcresult_get([])

tests_ref_id = None
actions = values(data.get("actions", []))
for action in actions:
    action_result = action.get("actionResult") or {}
    tests_ref = action_result.get("testsRef") or {}
    ref_id = unwrap(tests_ref.get("id"))
    if ref_id:
        tests_ref_id = ref_id
        break

if not tests_ref_id:
    print("Unable to find testsRef in result bundle.")
    sys.exit(1)

data = xcresult_get(["--id", tests_ref_id])

def find_testables(node):
    if isinstance(node, dict):
        if "testableSummaries" in node:
            return values(node["testableSummaries"])
        for value in node.values():
            found = find_testables(value)
            if found:
                return found
    elif isinstance(node, list):
        for item in node:
            found = find_testables(item)
            if found:
                return found
    return []

def iter_tests(node, path):
    name = unwrap(node.get("name", ""))
    subtests = values(node.get("subtests", []))
    if subtests:
        next_path = path + ([name] if name and name != "All tests" else [])
        for sub in subtests:
            yield from iter_tests(sub, next_path)
        return

    status = unwrap(node.get("testStatus", ""))
    duration = unwrap(node.get("duration", ""))
    if status:
        group = ".".join(path)
        full_name = f"{group}/{name}" if group else name
        yield full_name, status, duration

def normalize_status(status):
    lowered = str(status).lower()
    if "success" in lowered or "passed" in lowered:
        return "PASS"
    if "failure" in lowered or "failed" in lowered:
        return "FAIL"
    if "skipped" in lowered:
        return "SKIP"
    return str(status) if status else "UNKNOWN"

testables = find_testables(data)
rows = []
for testable in testables:
    root_name = unwrap(testable.get("name", ""))
    tests = values(testable.get("tests", []))
    path = [root_name] if root_name else []
    for group in tests:
        rows.extend(iter_tests(group, path))

if not rows:
    print("No test cases found in result bundle.")
    sys.exit(1)

print("| Test | Status | Duration (s) |")
print("| --- | --- | --- |")

passed = failed = skipped = 0
for name, status, duration in rows:
    norm = normalize_status(status)
    if norm == "PASS":
        passed += 1
    elif norm == "FAIL":
        failed += 1
    elif norm == "SKIP":
        skipped += 1

    try:
        duration_value = float(duration)
        duration_text = f"{duration_value:.3f}"
    except Exception:
        duration_text = ""

    print(f"| {name} | {norm} | {duration_text} |")

print("")
print(f"Summary: {passed} passed, {failed} failed, {skipped} skipped")
print("Status: GREEN" if failed == 0 else "Status: NOT GREEN")
PY
