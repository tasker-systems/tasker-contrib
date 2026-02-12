#!/usr/bin/env bash
# Remove .keep files from populated template directories.
#
# Only removes .keep files where sibling .tera or template.toml files exist.
# Removes entirely empty directories that only had a .keep file.
#
# Usage:
#   ./scripts/cleanup-keep-files.sh
#   ./scripts/cleanup-keep-files.sh --dry-run

set -euo pipefail

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

removed=0

while IFS= read -r keep_file; do
  [ -z "$keep_file" ] && continue
  dir="$(dirname "$keep_file")"

  # Check for sibling .tera or template.toml
  has_content=0
  for f in "$dir"/*.tera "$dir"/template.toml; do
    if [ -f "$f" ]; then
      has_content=1
      break
    fi
  done

  if [ "$has_content" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "WOULD REMOVE: $keep_file"
    else
      rm "$keep_file"
      echo "REMOVED: $keep_file"
    fi
    removed=$((removed + 1))
  else
    # Empty dir with only .keep — remove the whole directory
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "WOULD REMOVE DIR: $dir"
    else
      rm -rf "$dir"
      echo "REMOVED DIR: $dir"
    fi
    removed=$((removed + 1))
  fi
done <<EOF
$(find "$REPO_ROOT" -name '.keep' -path '*/tasker-cli-plugin/templates/*')
EOF

echo ""
echo "Removed: $removed"
echo "Done."
