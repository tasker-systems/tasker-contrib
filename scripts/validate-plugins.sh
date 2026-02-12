#!/usr/bin/env bash
# Validate all plugin manifests in the repository.
#
# Requires TASKER_CTL env var pointing to the tasker-ctl binary.
#
# Usage:
#   TASKER_CTL=path/to/tasker-ctl ./scripts/validate-plugins.sh

set -euo pipefail

if [ -z "${TASKER_CTL:-}" ]; then
  echo "ERROR: TASKER_CTL not set. Build tasker-ctl first:"
  echo "  cargo make build-ctl"
  exit 1
fi

if [ ! -x "$TASKER_CTL" ]; then
  echo "ERROR: $TASKER_CTL is not executable"
  exit 1
fi

# Resolve to absolute path
TASKER_CTL="$(cd "$(dirname "$TASKER_CTL")" && pwd)/$(basename "$TASKER_CTL")"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

passed=0
failed=0
errors=""

for plugin_dir in "$REPO_ROOT"/*/tasker-cli-plugin; do
  [ -d "$plugin_dir" ] || continue
  [ -f "$plugin_dir/tasker-plugin.toml" ] || continue

  plugin_name="$(basename "$(dirname "$plugin_dir")")"
  echo "Validating: $plugin_name ($plugin_dir)"

  if "$TASKER_CTL" plugin validate "$plugin_dir" 2>&1; then
    passed=$((passed + 1))
    echo ""
  else
    failed=$((failed + 1))
    errors="$errors  - $plugin_name\n"
    echo ""
  fi
done

echo "========================================="
echo "Plugin Validation Summary"
echo "========================================="
echo "  Passed: $passed"
echo "  Failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo ""
  echo "Failed plugins:"
  printf "%b" "$errors"
  exit 1
fi

echo ""
echo "All plugins valid."
