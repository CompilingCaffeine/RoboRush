#!/usr/bin/env bash
#
# Says whether a directory is a Robo Rush web build worth uploading.
#
#     tools/ci/verify_web.sh [directory]     # defaults to build/web
#
# Run by tools/ci/build_web.sh on what it just exported, and again by CI on the artifact after it
# has been downloaded and extracted — the second run is the point. Between the two there is a zip,
# an upload, a download and an extraction, and the whole reason the artifact is immutable is that
# nobody can say afterwards which of those a missing file went missing in.
#
# It checks the artifact rather than the build, so it needs no engine, no templates and no
# repository state: given a directory, it can be run anywhere, including against an upload
# directory prepared by a machine that never saw this source tree.
#
# What it is looking for, in order of how badly each one ends:
#
#   - A file the game needs at runtime is missing, so the build is a blank page.
#   - index.html and the binaries came from different exports, so the browser downloads a PCK the
#     engine cannot read. The exporter writes the sizes it saw into the page, which makes this
#     detectable rather than a mystery about caching.
#   - The build id in the page is not the one the artifact claims, so a tester's bug report names
#     a build nobody can reproduce.
#   - Source, tests or tooling are in the upload, which publishes the repository to anyone who
#     opens the network tab.
#   - The artifact has grown in a way nobody intended, which is a five-second wait for a player on
#     a mobile connection that nobody chose to spend.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_NAME="verify_web"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

TARGET="${1:-build/web}"

# Godot's Web export writes exactly these, plus the build-info.json this project adds. Anything
# else is either a leak or a change nobody wrote down, and both are worth stopping for.
EXPECTED_FILES=(
  "build-info.json"
  "index.apple-touch-icon.png"
  "index.audio.position.worklet.js"
  "index.audio.worklet.js"
  "index.html"
  "index.icon.png"
  "index.js"
  "index.pck"
  "index.png"
  "index.wasm"
)

# Without any one of these the build does not run at all.
REQUIRED_FILES=("index.html" "index.js" "index.wasm" "index.pck" "build-info.json")

# Wavedash accepts a folder or zip up to 1 GB. This is the only hard external limit involved, and
# it is nowhere near the current 41 MB, which is exactly why it is worth asserting: the failure it
# guards against is not today's build, it is the one that accidentally includes uncompressed audio.
HARD_LIMIT_BYTES=$((1024 * 1024 * 1024))

# What the build weighed when this was written. Growth is not a failure — content is supposed to
# arrive — but growth nobody predicted is worth a line in the log, because the alternative is
# finding out from a player on a phone.
BASELINE_TOTAL_BYTES=41500000
BASELINE_WASM_BYTES=39513091
GROWTH_WARNING_PERCENT=10

failures=0

fail() { printf '  x %s\n' "$1" >&2; failures=$((failures + 1)); }
pass() { printf '  . %s\n' "$1"; }

file_bytes() { wc -c < "$1" | tr -d ' '; }


# --- The files themselves -----------------------------------------------------------

check_files_present() {
  local name
  for name in "${REQUIRED_FILES[@]}"; do
    if [ -f "$TARGET/$name" ] && [ -s "$TARGET/$name" ]; then
      continue
    fi
    fail "$name is missing or empty"
  done

  # Flat on purpose. The export produces no directories, so one here means something was copied in.
  local directories
  directories="$(find "$TARGET" -mindepth 1 -type d | head -5)"
  [ -z "$directories" ] || fail "the upload directory has subdirectories: $(tr '\n' ' ' <<<"$directories")"
}

## Anything present that the export does not produce. This is the leak check, and it is a
## whitelist rather than a search for suspicious extensions: a list of what is allowed catches the
## file nobody thought to look for.
check_no_extra_files() {
  local name allowed
  while IFS= read -r name; do
    allowed=0
    for expected in "${EXPECTED_FILES[@]}"; do
      [ "$name" = "$expected" ] && allowed=1 && break
    done
    [ "$allowed" -eq 1 ] || fail "unexpected file in the upload: $name"
  done < <(cd "$TARGET" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}

## The PCK is the one file whose contents nobody reads by eye, so the exclude filters are checked
## against it rather than against the preset that is supposed to apply them. Resource paths are
## stored in the pack's directory as plain strings, which is what makes this possible at all.
check_no_source_leakage() {
  local pattern
  for pattern in "res://tests/" "res://tools/" ".gd.uid" "robo_rush_build_spec"; do
    if LC_ALL=C grep -qaF "$pattern" "$TARGET/index.pck"; then
      fail "the PCK contains $pattern, which the export is supposed to exclude"
    fi
  done

  # The scripts themselves are compiled into .gdc and remapped, so a readable script body in the
  # pack means an export that did not compile them.
  if LC_ALL=C grep -qaF "extends TestCase" "$TARGET/index.pck"; then
    fail "the PCK contains test script source"
  fi
}


# --- Whether the pieces belong together ---------------------------------------------

## The page names the files it will fetch, and records the size it saw for the two big ones. Both
## are checked, because the way this breaks in practice is an index.html left over from a previous
## export beside a freshly written PCK — a combination that looks completely normal in a directory
## listing and fails in the browser with a progress bar that never fills.
check_references() {
  local name
  for name in index.js index.wasm index.pck; do
    LC_ALL=C grep -qF "$name" "$TARGET/index.html" \
      || fail "index.html does not reference $name"
  done

  local declared actual
  for name in index.pck index.wasm; do
    declared="$(grep -o "\"$name\":[0-9]*" "$TARGET/index.html" | head -1 | cut -d: -f2)"
    actual="$(file_bytes "$TARGET/$name")"
    if [ -z "$declared" ]; then
      fail "index.html declares no size for $name"
    elif [ "$declared" != "$actual" ]; then
      fail "index.html says $name is $declared bytes; it is $actual. The page and the binaries are from different exports."
    fi
  done
}

## The build id has to survive into the artifact, or Phase 7's whole qualification — open Build B,
## confirm it is Build B — is somebody reading a number off a page and hoping.
check_build_id() {
  local id
  id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build_id"])' \
    "$TARGET/build-info.json" 2>/dev/null || true)"
  [ -n "$id" ] || { fail "build-info.json has no readable build_id"; return; }

  LC_ALL=C grep -qaF "$id" "$TARGET/index.pck" \
    || fail "build $id is not baked into the PCK, so the running game cannot say which build it is"
  pass "build id $id, in build-info.json and in the PCK"
}

check_build_info() {
  python3 - "$TARGET/build-info.json" <<'PY'
import json, sys

required = ["build_id", "commit", "built", "engine", "export_templates",
            "wavedash_sdk", "save_schema", "content_version", "files"]
try:
    info = json.load(open(sys.argv[1]))
except Exception as error:
    print("  x build-info.json is not readable JSON: %s" % error)
    raise SystemExit(1)

missing = [key for key in required if key not in info]
if missing:
    print("  x build-info.json is missing %s" % ", ".join(missing))
    raise SystemExit(1)

print("  . build-info.json: commit %s, engine %s, save schema %s, content version %s"
      % (info["commit"][:7], info["engine"], info["save_schema"], info["content_version"]))
PY
}


# --- Weight --------------------------------------------------------------------------

check_size() {
  local total wasm growth
  total="$(find "$TARGET" -type f -exec cat {} + | wc -c | tr -d ' ')"
  wasm="$(file_bytes "$TARGET/index.wasm")"

  if [ "$total" -gt "$HARD_LIMIT_BYTES" ]; then
    fail "the upload is $total bytes, over Wavedash's 1 GB limit"
  fi

  growth=$(((total - BASELINE_TOTAL_BYTES) * 100 / BASELINE_TOTAL_BYTES))
  if [ "$growth" -gt "$GROWTH_WARNING_PERCENT" ]; then
    warn "the upload is ${growth}% larger than the ${BASELINE_TOTAL_BYTES}-byte baseline. Deliberate? Update BASELINE_TOTAL_BYTES."
  fi

  growth=$(((wasm - BASELINE_WASM_BYTES) * 100 / BASELINE_WASM_BYTES))
  if [ "$growth" -gt "$GROWTH_WARNING_PERCENT" ]; then
    # The engine binary changing size without the engine changing version means the export settings
    # changed — a different renderer, threads turned on, extensions enabled.
    warn "index.wasm is ${growth}% larger than the pinned engine's ${BASELINE_WASM_BYTES}-byte baseline"
  fi

  pass "$(printf '%s bytes across %s files, %s in index.wasm' \
    "$total" "$(find "$TARGET" -type f | wc -l | tr -d ' ')" "$wasm")"
}

## Every file, its size and its hash. Printed rather than compared: this is the record CI keeps of
## what a given build actually consisted of, and the thing a person compares two builds with when
## one of them boots and the other does not.
print_inventory() {
  local name
  while IFS= read -r name; do
    printf '    %-34s %10s  %s\n' "$name" "$(file_bytes "$TARGET/$name")" "$(sha256 "$TARGET/$name")"
  done < <(cd "$TARGET" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}


main() {
  [ -d "$TARGET" ] || die "$TARGET is not a directory"
  echo "Verifying $TARGET"

  check_files_present
  # Everything after this reads the files, so there is no point asking whether the PCK excludes the
  # tests when there is no PCK.
  [ "$failures" -eq 0 ] || die "$failures problem(s); the artifact is incomplete"

  check_no_extra_files
  check_no_source_leakage
  check_references
  check_build_info || fail "build-info.json is not usable"
  check_build_id
  check_size
  print_inventory

  [ "$failures" -eq 0 ] || die "$failures problem(s) with $TARGET"
  echo "  OK"
}

main "$@"
