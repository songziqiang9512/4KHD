#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/artifact output.json [log.json]" >&2
  exit 2
fi

artifact_path="$1"
output_json="$2"
log_json="${3:-${output_json%.json}.log.json}"

for name in APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing environment variable: $name" >&2
    exit 1
  fi
done

xcrun notarytool submit "$artifact_path" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --timeout 20m \
  --output-format json > "$output_json"

status="$(/usr/bin/python3 - "$output_json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
print(data.get("status", ""))
PY
)"

submission_id="$(/usr/bin/python3 - "$output_json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
print(data.get("id", ""))
PY
)"

if [[ "$status" != "Accepted" ]]; then
  echo "Notarization failed for $artifact_path with status: $status" >&2
  cat "$output_json" >&2
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --output-format json > "$log_json" || true
    if [[ -f "$log_json" ]]; then
      cat "$log_json" >&2
    fi
  fi
  exit 1
fi
