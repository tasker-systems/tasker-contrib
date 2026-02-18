#!/usr/bin/env bash
# Template generation and syntax validation (Tier 1).
#
# Generates every template from every plugin and syntax-checks all output files.
# POSIX-compatible (macOS bash 3.2 safe).
#
# Requires TASKER_CTL env var pointing to the tasker-ctl binary.
#
# Usage:
#   TASKER_CTL=path/to/tasker-ctl ./scripts/test-templates.sh
#   TASKER_CTL=path/to/tasker-ctl ./scripts/test-templates.sh --plugin tasker-contrib-rails

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FILTER_PLUGIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)
      FILTER_PLUGIN="$2"
      shift 2
      ;;
    --plugin=*)
      FILTER_PLUGIN="${1#--plugin=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--plugin <plugin-name>]"
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Prereqs
# ---------------------------------------------------------------------------
if [ -z "${TASKER_CTL:-}" ]; then
  echo "ERROR: TASKER_CTL not set. Build tasker-ctl first:"
  echo "  cargo make build-ctl"
  exit 1
fi

if [ ! -x "$TASKER_CTL" ]; then
  echo "ERROR: $TASKER_CTL is not executable"
  exit 1
fi

# Resolve to absolute path (critical — script cd's to temp dirs)
TASKER_CTL="$(cd "$(dirname "$TASKER_CTL")" && pwd)/$(basename "$TASKER_CTL")"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Activate Python venv if present (provides PyYAML for YAML/TOML checks)
if [ -f "$REPO_ROOT/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.venv/bin/activate"
fi

# ---------------------------------------------------------------------------
# Test parameters per template name
# ---------------------------------------------------------------------------
params_for_template() {
  local tmpl_name="$1"
  case "$tmpl_name" in
    step_handler)        echo "name=TestProcessor" ;;
    step_handler_api)    echo "name=FetchUser" ;;
    step_handler_decision) echo "name=RouteOrder" ;;
    step_handler_batchable) echo "name=ProcessBatch" ;;
    task_template)       echo "name=ProcessOrder handler_callable=Handlers::ProcessOrderHandler" ;;
    docker_compose)      echo "name=myapp" ;;
    config)              echo "" ;;
    *)                   echo "name=Test" ;;
  esac
}

# ---------------------------------------------------------------------------
# Syntax checkers by extension
# ---------------------------------------------------------------------------
check_syntax() {
  local filepath="$1"
  local ext="${filepath##*.}"

  case "$ext" in
    rb)
      if command -v ruby >/dev/null 2>&1; then
        ruby -c "$filepath" >/dev/null 2>&1
        return $?
      fi
      echo "  SKIP: ruby not available for $filepath"
      return 0
      ;;
    py)
      if command -v python3 >/dev/null 2>&1; then
        python3 -m py_compile "$filepath" 2>&1
        return $?
      fi
      echo "  SKIP: python3 not available for $filepath"
      return 0
      ;;
    ts)
      if command -v bun >/dev/null 2>&1; then
        # Use --outfile instead of --outdir to work around bun ENOENT bug
        # (bun build --no-bundle --outdir fails with 'failed to write file ""')
        local ts_outfile
        ts_outfile="$(mktemp /tmp/bun-syntax-XXXXXX.js)"
        bun build --no-bundle "$filepath" --outfile "$ts_outfile" >/dev/null 2>&1
        local ts_rc=$?
        rm -f "$ts_outfile"
        return $ts_rc
      fi
      echo "  SKIP: bun not available for $filepath"
      return 0
      ;;
    rs)
      if command -v rustfmt >/dev/null 2>&1; then
        rustfmt --edition 2021 --check "$filepath" >/dev/null 2>&1
        return $?
      fi
      echo "  SKIP: rustfmt not available for $filepath"
      return 0
      ;;
    yaml|yml)
      if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, yaml
yaml.safe_load(open(sys.argv[1]))
" "$filepath" 2>&1
        return $?
      fi
      echo "  SKIP: python3 not available for YAML check on $filepath"
      return 0
      ;;
    toml)
      if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], 'rb') as f:
    tomllib.load(f)
" "$filepath" 2>&1
        return $?
      fi
      echo "  SKIP: python3 not available for TOML check on $filepath"
      return 0
      ;;
    *)
      # No syntax checker for this extension — count as pass
      return 0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Create working directory
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Write a .tasker-ctl.toml pointing at the repo root
cat > "$WORK_DIR/.tasker-ctl.toml" <<EOF
plugin-paths = ["$REPO_ROOT"]
EOF

total=0
passed=0
failed=0
failed_list=""

# ---------------------------------------------------------------------------
# Iterate plugins
# ---------------------------------------------------------------------------
for plugin_dir in "$REPO_ROOT"/*/tasker-cli-plugin; do
  [ -d "$plugin_dir" ] || continue
  [ -f "$plugin_dir/tasker-plugin.toml" ] || continue

  # Extract plugin name from manifest
  plugin_name=""
  while IFS= read -r line; do
    case "$line" in
      *name\ =\ *)
        # Extract the quoted value after name =
        plugin_name="$(echo "$line" | sed 's/.*name *= *"\([^"]*\)".*/\1/')"
        break
        ;;
    esac
  done < "$plugin_dir/tasker-plugin.toml"

  if [ -z "$plugin_name" ]; then
    echo "WARNING: Could not extract plugin name from $plugin_dir/tasker-plugin.toml"
    continue
  fi

  # Apply plugin filter
  if [ -n "$FILTER_PLUGIN" ] && [ "$plugin_name" != "$FILTER_PLUGIN" ]; then
    continue
  fi

  echo "========================================="
  echo "Plugin: $plugin_name"
  echo "========================================="

  # First validate the plugin
  echo "  Validating manifest..."
  if ! (cd "$WORK_DIR" && "$TASKER_CTL" plugin validate "$plugin_dir") >/dev/null 2>&1; then
    echo "  FAIL: Plugin validation failed"
    failed=$((failed + 1))
    total=$((total + 1))
    failed_list="$failed_list  - $plugin_name (validation)\n"
    continue
  fi
  echo "  Manifest valid."
  echo ""

  # Extract template names from [[templates]] sections
  template_names=""
  in_templates=0
  while IFS= read -r line; do
    case "$line" in
      "[[templates]]"*)
        in_templates=1
        ;;
      "["*)
        if [ "$in_templates" -eq 1 ]; then
          in_templates=0
        fi
        ;;
    esac
    if [ "$in_templates" -eq 1 ]; then
      case "$line" in
        *name\ =\ *)
          tname="$(echo "$line" | sed 's/.*name *= *"\([^"]*\)".*/\1/')"
          template_names="$template_names $tname"
          in_templates=0
          ;;
      esac
    fi
  done < "$plugin_dir/tasker-plugin.toml"

  for tmpl_name in $template_names; do
    total=$((total + 1))
    echo "  Template: $tmpl_name"

    # Create output directory for this template
    out_dir="$WORK_DIR/output/${plugin_name}/${tmpl_name}"
    mkdir -p "$out_dir"

    # Build --param flags
    param_str="$(params_for_template "$tmpl_name")"
    param_flags=""
    for kv in $param_str; do
      param_flags="$param_flags --param $kv"
    done

    # Generate template
    # shellcheck disable=SC2086
    if ! (cd "$WORK_DIR" && "$TASKER_CTL" template generate "$tmpl_name" \
        --plugin "$plugin_name" \
        $param_flags \
        --output "$out_dir") 2>&1; then
      echo "    FAIL: Generation failed"
      failed=$((failed + 1))
      failed_list="$failed_list  - $plugin_name/$tmpl_name (generation)\n"
      echo ""
      continue
    fi

    # Verify output is non-empty
    file_count="$(find "$out_dir" -type f | wc -l | tr -d ' ')"
    if [ "$file_count" -eq 0 ]; then
      echo "    FAIL: No files generated"
      failed=$((failed + 1))
      failed_list="$failed_list  - $plugin_name/$tmpl_name (no output)\n"
      echo ""
      continue
    fi

    # Syntax check each generated file
    syntax_ok=1
    while IFS= read -r gen_file; do
      [ -f "$gen_file" ] || continue
      rel_path="${gen_file#"$out_dir"/}"
      if ! check_syntax "$gen_file"; then
        echo "    FAIL: Syntax check failed for $rel_path"
        syntax_ok=0
      else
        echo "    OK: $rel_path"
      fi
    done <<EOF
$(find "$out_dir" -type f)
EOF

    if [ "$syntax_ok" -eq 1 ]; then
      passed=$((passed + 1))
      echo "    PASS ($file_count file(s))"
    else
      failed=$((failed + 1))
      failed_list="$failed_list  - $plugin_name/$tmpl_name (syntax)\n"
    fi
    echo ""
  done
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "========================================="
echo "Template Test Summary"
echo "========================================="
echo "  Total:  $total"
echo "  Passed: $passed"
echo "  Failed: $failed"

if [ "$failed" -gt 0 ]; then
  echo ""
  echo "Failed:"
  printf "%b" "$failed_list"
  exit 1
fi

echo ""
echo "All templates passed."
