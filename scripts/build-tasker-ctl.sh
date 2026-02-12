#!/usr/bin/env bash
# Build tasker-ctl from tasker-core source and install to local bin/.
#
# Usage:
#   TASKER_CORE_PATH=../tasker-core ./scripts/build-tasker-ctl.sh
#
# Copies the binary to bin/tasker-ctl (absolute path, always works).
# Skips rebuild if source binary is newer than Cargo.lock.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKER_CORE_PATH="${TASKER_CORE_PATH:-../tasker-core}"

# Resolve to absolute path
TASKER_CORE_PATH="$(cd "$TASKER_CORE_PATH" 2>/dev/null && pwd)" || {
  echo "ERROR: tasker-core not found at ${TASKER_CORE_PATH}"
  echo "Set TASKER_CORE_PATH to the tasker-core checkout directory."
  exit 1
}

LOCAL_BIN="$REPO_ROOT/bin"
LOCAL_BINARY="$LOCAL_BIN/tasker-ctl"
CARGO_LOCK="$TASKER_CORE_PATH/Cargo.lock"
DEBUG_BINARY="$TASKER_CORE_PATH/target/debug/tasker-ctl"
RELEASE_BINARY="$TASKER_CORE_PATH/target/release/tasker-ctl"

# Pick the best source binary (release preferred)
pick_source() {
  if [ -f "$RELEASE_BINARY" ] && [ -f "$CARGO_LOCK" ] && [ "$RELEASE_BINARY" -nt "$CARGO_LOCK" ]; then
    echo "$RELEASE_BINARY"
  elif [ -f "$DEBUG_BINARY" ] && [ -f "$CARGO_LOCK" ] && [ "$DEBUG_BINARY" -nt "$CARGO_LOCK" ]; then
    echo "$DEBUG_BINARY"
  fi
}

SOURCE="$(pick_source)"

# Skip rebuild if local binary exists and is up-to-date with source
if [ -n "$SOURCE" ] && [ -f "$LOCAL_BINARY" ] && [ "$LOCAL_BINARY" -nt "$SOURCE" ]; then
  echo "bin/tasker-ctl is up-to-date."
  exit 0
fi

# Build if no fresh source binary
if [ -z "$SOURCE" ]; then
  echo "Building tasker-ctl from $TASKER_CORE_PATH ..."
  (cd "$TASKER_CORE_PATH" && SQLX_OFFLINE=true cargo build --package tasker-ctl --bin tasker-ctl)

  if [ ! -f "$DEBUG_BINARY" ]; then
    echo "ERROR: Build succeeded but binary not found at $DEBUG_BINARY"
    exit 1
  fi
  SOURCE="$DEBUG_BINARY"
fi

# Copy to local bin/
mkdir -p "$LOCAL_BIN"
cp "$SOURCE" "$LOCAL_BINARY"
chmod +x "$LOCAL_BINARY"
echo "Installed: bin/tasker-ctl (from $SOURCE)"
