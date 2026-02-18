#!/usr/bin/env bash
# Template generation + lint validation (Tier 1.5).
#
# Generates every code template from every plugin, then runs language-specific
# linters and (optionally) type checkers on the generated output.
#
# Tier 1 (test-templates.sh): py_compile / ruby -c / bun build — syntax only
# Tier 1.5 (this script):     ruff / rubocop / biome + pyright / tsc — lint + types
# Tier 3 (test-examples.yml): full example app integration tests
#
# POSIX-compatible (macOS bash 3.2 safe).
#
# Requires TASKER_CTL env var pointing to the tasker-ctl binary.
#
# Usage:
#   TASKER_CTL=path/to/tasker-ctl ./scripts/lint-templates.sh
#   TASKER_CTL=path/to/tasker-ctl ./scripts/lint-templates.sh --plugin tasker-contrib-python
#   TASKER_CTL=path/to/tasker-ctl ./scripts/lint-templates.sh --no-types

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FILTER_PLUGIN=""
SKIP_TYPES=0
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
    --no-types)
      SKIP_TYPES=1
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--plugin <plugin-name>] [--no-types]"
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

# Resolve to absolute path (critical — script cd's to other dirs)
TASKER_CTL="$(cd "$(dirname "$TASKER_CTL")" && pwd)/$(basename "$TASKER_CTL")"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT_TARGETS="$REPO_ROOT/tests/lint-targets"
TASKER_CORE_PATH="${TASKER_CORE_PATH:-$REPO_ROOT/../tasker-core}"

# Resolve TASKER_CORE_PATH to absolute
if [ -d "$TASKER_CORE_PATH" ]; then
  TASKER_CORE_PATH="$(cd "$TASKER_CORE_PATH" && pwd)"
fi

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
has_tool() { command -v "$1" >/dev/null 2>&1; }

HAVE_RUFF=0;    has_tool ruff    && HAVE_RUFF=1
HAVE_RUBOCOP=0; has_tool rubocop && HAVE_RUBOCOP=1
HAVE_BIOME=0;   has_tool biome   && HAVE_BIOME=1
HAVE_PYRIGHT=0; has_tool pyright && HAVE_PYRIGHT=1
HAVE_TSC=0;     has_tool tsc     && HAVE_TSC=1

check_mark() { if [ "$1" -eq 1 ]; then echo "yes"; else echo "no"; fi; }

echo "========================================="
echo "Template Lint (Tier 1.5)"
echo "========================================="
echo "  Linters:  ruff=$(check_mark $HAVE_RUFF)  rubocop=$(check_mark $HAVE_RUBOCOP)  biome=$(check_mark $HAVE_BIOME)"
echo "  Types:    pyright=$(check_mark $HAVE_PYRIGHT)  tsc=$(check_mark $HAVE_TSC)"
if [ "$SKIP_TYPES" -eq 1 ]; then
  echo "  (type checking disabled via --no-types)"
fi
if [ -d "$TASKER_CORE_PATH/workers" ]; then
  echo "  SDK path: $TASKER_CORE_PATH/workers/"
else
  echo "  SDK path: not found (type checking will be skipped)"
fi
echo ""

# ---------------------------------------------------------------------------
# Test parameters per template name (must match test-templates.sh)
# ---------------------------------------------------------------------------
params_for_template() {
  local tmpl_name="$1"
  case "$tmpl_name" in
    step_handler)          echo "name=TestProcessor" ;;
    step_handler_api)      echo "name=FetchUser" ;;
    step_handler_decision) echo "name=RouteOrder" ;;
    step_handler_batchable) echo "name=ProcessBatch" ;;
    task_template)         echo "name=ProcessOrder handler_callable=Handlers::ProcessOrderHandler" ;;
    docker_compose)        echo "name=myapp" ;;
    config)                echo "" ;;
    *)                     echo "name=Test" ;;
  esac
}

# ---------------------------------------------------------------------------
# Setup: working directory for tasker-ctl
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR" "$LINT_TARGETS/python/generated" "$LINT_TARGETS/typescript/generated" "$LINT_TARGETS/ruby/generated" "$LINT_TARGETS/python/pyrightconfig.json" "$LINT_TARGETS/typescript/tsconfig.json"' EXIT

cat > "$WORK_DIR/.tasker-ctl.toml" <<EOF
plugin-paths = ["$REPO_ROOT"]
EOF

# ---------------------------------------------------------------------------
# Phase 1: Generate all templates into lint-target dirs
# ---------------------------------------------------------------------------
echo "--- Phase 1: Generating templates ---"
echo ""

gen_total=0
gen_passed=0

for plugin_dir in "$REPO_ROOT"/*/tasker-cli-plugin; do
  [ -d "$plugin_dir" ] || continue
  [ -f "$plugin_dir/tasker-plugin.toml" ] || continue

  # Extract plugin name and language from manifest
  plugin_name=""
  plugin_lang=""
  while IFS= read -r line; do
    case "$line" in
      *name\ =\ *)
        if [ -z "$plugin_name" ]; then
          plugin_name="$(echo "$line" | sed 's/.*name *= *"\([^"]*\)".*/\1/')"
        fi
        ;;
      *language\ =\ *)
        plugin_lang="$(echo "$line" | sed 's/.*language *= *"\([^"]*\)".*/\1/')"
        ;;
    esac
  done < "$plugin_dir/tasker-plugin.toml"

  [ -z "$plugin_name" ] && continue

  # Apply plugin filter
  if [ -n "$FILTER_PLUGIN" ] && [ "$plugin_name" != "$FILTER_PLUGIN" ]; then
    continue
  fi

  # Skip non-code languages
  case "$plugin_lang" in
    python|ruby|typescript) ;;
    *) continue ;;
  esac

  echo "  $plugin_name ($plugin_lang)"

  # Extract template names
  template_names=""
  in_templates=0
  while IFS= read -r line; do
    case "$line" in
      "[[templates]]"*) in_templates=1 ;;
      "["*)
        if [ "$in_templates" -eq 1 ]; then in_templates=0; fi
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

  # Generate each template
  for tmpl_name in $template_names; do
    gen_total=$((gen_total + 1))

    out_dir="$LINT_TARGETS/$plugin_lang/generated/$plugin_name/$tmpl_name"
    mkdir -p "$out_dir"

    # Build param flags
    param_str="$(params_for_template "$tmpl_name")"
    param_flags=""
    for kv in $param_str; do
      param_flags="$param_flags --param $kv"
    done

    # shellcheck disable=SC2086
    if (cd "$WORK_DIR" && "$TASKER_CTL" template generate "$tmpl_name" \
        --plugin "$plugin_name" \
        $param_flags \
        --output "$out_dir") >/dev/null 2>&1; then

      file_count="$(find "$out_dir" -type f | wc -l | tr -d ' ')"
      if [ "$file_count" -gt 0 ]; then
        echo "    $tmpl_name ($file_count files)"
        gen_passed=$((gen_passed + 1))
      else
        echo "    $tmpl_name — no output"
      fi
    else
      echo "    $tmpl_name — generation failed"
    fi
  done
done

echo ""
echo "  Generated: $gen_passed/$gen_total"
echo ""

# ---------------------------------------------------------------------------
# Phase 2: Lint
# ---------------------------------------------------------------------------
echo "--- Phase 2: Linting ---"

lint_total=0
lint_passed=0
lint_skipped=0
lint_failed=0
failed_list=""

# --- Python: ruff ---
py_dir="$LINT_TARGETS/python/generated"
if [ -d "$py_dir" ]; then
  py_count="$(find "$py_dir" -name "*.py" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$py_count" -gt 0 ]; then
    echo ""
    echo "  Python ($py_count .py files)"

    lint_total=$((lint_total + 1))
    if [ "$HAVE_RUFF" -eq 1 ]; then
      echo -n "    ruff check: "
      ruff_output=""
      if ruff_output=$(ruff check --config "$LINT_TARGETS/python/ruff.toml" "$py_dir" 2>&1); then
        echo "passed"
        lint_passed=$((lint_passed + 1))
      else
        echo "FAILED"
        echo "$ruff_output" | sed 's/^/      /'
        lint_failed=$((lint_failed + 1))
        failed_list="$failed_list  - python/ruff\n"
      fi
    else
      echo "    ruff: skipped (not installed: pip install ruff)"
      lint_skipped=$((lint_skipped + 1))
    fi
  fi
fi

# --- Python: pyright (type checking) ---
py_sdk="$TASKER_CORE_PATH/workers/python/python"
if [ -d "$py_dir" ] && [ "$py_count" -gt 0 ] && [ "$SKIP_TYPES" -eq 0 ]; then
  lint_total=$((lint_total + 1))
  if [ "$HAVE_PYRIGHT" -eq 1 ] && [ -d "$py_sdk" ]; then
    # Write pyrightconfig.json with resolved SDK path
    cat > "$LINT_TARGETS/python/pyrightconfig.json" <<EOF
{
  "extraPaths": ["$py_sdk"],
  "pythonVersion": "3.11",
  "typeCheckingMode": "basic",
  "include": ["generated"],
  "reportMissingModuleSource": false,
  "reportMissingTypeStubs": false
}
EOF
    echo -n "    pyright: "
    pyright_output=""
    if pyright_output=$(cd "$LINT_TARGETS/python" && pyright 2>&1); then
      echo "passed"
      lint_passed=$((lint_passed + 1))
    else
      echo "FAILED"
      # Show only error lines, not the full project summary
      echo "$pyright_output" | grep -E '(error|Error)' | head -20 | sed 's/^/      /'
      lint_failed=$((lint_failed + 1))
      failed_list="$failed_list  - python/pyright\n"
    fi
  else
    if [ "$HAVE_PYRIGHT" -eq 0 ]; then
      echo "    pyright: skipped (not installed: pip install pyright)"
    else
      echo "    pyright: skipped (SDK source not found at $py_sdk)"
    fi
    lint_skipped=$((lint_skipped + 1))
  fi
fi

# --- Ruby: rubocop ---
rb_dir="$LINT_TARGETS/ruby/generated"
if [ -d "$rb_dir" ]; then
  rb_count="$(find "$rb_dir" -name "*.rb" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rb_count" -gt 0 ]; then
    echo ""
    echo "  Ruby ($rb_count .rb files)"

    lint_total=$((lint_total + 1))
    if [ "$HAVE_RUBOCOP" -eq 1 ]; then
      echo -n "    rubocop: "
      rubocop_output=""
      if rubocop_output=$(rubocop --config "$LINT_TARGETS/ruby/.rubocop.yml" "$rb_dir" --format simple 2>&1); then
        echo "passed"
        lint_passed=$((lint_passed + 1))
      else
        echo "FAILED"
        echo "$rubocop_output" | head -30 | sed 's/^/      /'
        lint_failed=$((lint_failed + 1))
        failed_list="$failed_list  - ruby/rubocop\n"
      fi
    else
      echo "    rubocop: skipped (not installed: gem install rubocop)"
      lint_skipped=$((lint_skipped + 1))
    fi
  fi
fi

# --- TypeScript: biome ---
ts_dir="$LINT_TARGETS/typescript/generated"
if [ -d "$ts_dir" ]; then
  ts_count="$(find "$ts_dir" -name "*.ts" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$ts_count" -gt 0 ]; then
    echo ""
    echo "  TypeScript ($ts_count .ts files)"

    lint_total=$((lint_total + 1))
    if [ "$HAVE_BIOME" -eq 1 ]; then
      echo -n "    biome check: "
      biome_output=""
      if biome_output=$(biome check "$ts_dir" 2>&1); then
        echo "passed"
        lint_passed=$((lint_passed + 1))
      else
        echo "FAILED"
        echo "$biome_output" | head -20 | sed 's/^/      /'
        lint_failed=$((lint_failed + 1))
        failed_list="$failed_list  - typescript/biome\n"
      fi
    else
      echo "    biome: skipped (not installed: bun add -g @biomejs/biome)"
      lint_skipped=$((lint_skipped + 1))
    fi
  fi
fi

# --- TypeScript: tsc (type checking) ---
ts_sdk="$TASKER_CORE_PATH/workers/typescript/src"
if [ -d "$ts_dir" ] && [ "$ts_count" -gt 0 ] && [ "$SKIP_TYPES" -eq 0 ]; then
  lint_total=$((lint_total + 1))
  if [ "$HAVE_TSC" -eq 1 ] && [ -d "$ts_sdk" ]; then
    # Write tsconfig.json with resolved SDK path
    cat > "$LINT_TARGETS/typescript/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "paths": {
      "@tasker-systems/tasker": ["$ts_sdk/index.ts"]
    }
  },
  "include": ["generated/**/*.ts"]
}
EOF
    echo -n "    tsc --noEmit: "
    tsc_output=""
    if tsc_output=$(cd "$LINT_TARGETS/typescript" && tsc --noEmit 2>&1); then
      echo "passed"
      lint_passed=$((lint_passed + 1))
    else
      echo "FAILED"
      echo "$tsc_output" | head -20 | sed 's/^/      /'
      lint_failed=$((lint_failed + 1))
      failed_list="$failed_list  - typescript/tsc\n"
    fi
  else
    if [ "$HAVE_TSC" -eq 0 ]; then
      echo "    tsc: skipped (not installed: bun add -g typescript)"
    else
      echo "    tsc: skipped (SDK source not found at $ts_sdk)"
    fi
    lint_skipped=$((lint_skipped + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "Lint Summary"
echo "========================================="
echo "  Generated: $gen_passed/$gen_total templates"
echo "  Lint checks: $lint_passed passed, $lint_failed failed, $lint_skipped skipped"

if [ "$lint_failed" -gt 0 ]; then
  echo ""
  echo "  Failed:"
  printf "%b" "$failed_list"
  exit 1
fi

if [ "$lint_passed" -eq 0 ] && [ "$lint_skipped" -gt 0 ]; then
  echo ""
  echo "  No linters ran. Install at least one:"
  echo "    pip install ruff        # Python"
  echo "    gem install rubocop     # Ruby"
  echo "    bun add -g @biomejs/biome  # TypeScript"
  exit 1
fi

echo ""
echo "All lint checks passed."
