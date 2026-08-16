# shellcheck shell=bash
#
# What "pinned" means, in one place.
#
# The engine, the export templates and the vendored Wavedash SDK are all part of the artifact: a
# Godot patch release changes the binary, an add-on edit ships inside the PCK, and neither is
# visible in a diff of the game's own source. tools/engine.lock records what they are supposed to
# be, and the functions here are the only thing that reads it.
#
# They live here rather than in tools/release.sh because two tools now need them and a second copy
# of a verification rule is worse than no verification: the copies drift, both keep passing, and
# the one that matters is whichever the build happened to call. Sourced by tools/release.sh, which
# builds every platform from a tag, and by tools/ci/build_web.sh, which builds only the Web export
# and is the one CI runs on every commit.
#
# Nothing here has side effects beyond reading files. Anything that writes the lock file, exports,
# or uploads belongs to the tool that does it.

LOCK_FILE="${LOCK_FILE:-tools/engine.lock}"
GODOT="${GODOT:-godot}"
WAVEDASH_ADDON_DIR="addons/wavedash"

# The vendored Wavedash SDK files, as copied from upstream. The .uid files are tracked but not
# hashed: Godot regenerates them, so pinning them would fail on churn that changes no behaviour.
WAVEDASH_SDK_FILES=(
  "LICENSE"
  "plugin.cfg"
  "README.md"
  "WavedashConstants.gd"
  "WavedashPlugin.gd"
  "WavedashSDK.gd"
)

# Named so a failure says which tool failed. Set by the caller before sourcing, or taken from
# whatever script is running.
TOOL_NAME="${TOOL_NAME:-$(basename "${BASH_SOURCE[1]:-$0}" .sh)}"

die() { printf '\n%s: %s\n' "$TOOL_NAME" "$1" >&2; exit 1; }
note() { printf '  %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1" >&2; }

## Both spellings exist and neither is everywhere: sha256sum is coreutils, shasum is Perl and is
## what macOS ships. The output format is the same, which is the only reason this can be one line.
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi


# --- Where Godot keeps its data ------------------------------------------------------

## The directory Godot reads export templates from, which is also the one it writes user:// data
## into. Per-OS because Godot's own convention is per-OS, and honouring GODOT_TEMPLATE_DIR because
## the Web build runs the whole export against an isolated copy of it.
##
## Takes an optional data root, so a caller can ask where templates *would* live under a different
## HOME without having to know each platform's spelling.
template_root() {
  local home="${1:-$HOME}"
  if [ -n "${GODOT_TEMPLATE_DIR:-}" ] && [ -z "${1:-}" ]; then
    printf '%s' "$GODOT_TEMPLATE_DIR"
    return
  fi
  case "$(uname -s)" in
    Darwin) printf '%s/Library/Application Support/Godot/export_templates' "$home" ;;
    *) printf '%s/godot/export_templates' "${XDG_DATA_HOME:-$home/.local/share}" ;;
  esac
}


# --- Reading the lock ----------------------------------------------------------------

## One key out of the lock file. Everything in it is `key=value`, one per line.
lock_value() {
  [ -f "$LOCK_FILE" ] || die "$LOCK_FILE is missing. Run: tools/release.sh --relock"
  grep "^$1=" "$LOCK_FILE" | head -1 | cut -d= -f2-
}

engine_version() {
  "$GODOT" --version 2>/dev/null | head -1 | tr -d '\n'
}

## The add-on's own declared version, from the manifest Godot reads.
wavedash_sdk_version() {
  grep '^version=' "$WAVEDASH_ADDON_DIR/plugin.cfg" | cut -d= -f2- | tr -d '"'
}

## The Wavedash CLI that uploads builds. Recorded rather than enforced by the build scripts —
## neither of them uploads — so CI has an approved version to compare against before it hands over
## a token.
wavedash_cli_version() {
  command -v wavedash >/dev/null 2>&1 || return 0
  wavedash --version 2>/dev/null | head -1 | tr -d '\n'
}


# --- Verification --------------------------------------------------------------------

## Fails unless the installed engine is the pinned one.
verify_engine_version() {
  local pinned actual
  pinned="$(lock_value engine_version)"
  actual="$(engine_version)"
  [ -n "$actual" ] || die "could not run '$GODOT --version'"
  [ "$actual" = "$pinned" ] || die \
    "engine is '$actual', pinned is '$pinned'. Upgrade deliberately: tools/release.sh --relock"
  note "engine $actual"
}

## Fails unless one export template is byte-for-byte the pinned one. Takes the template's file
## name, and optionally the directory to look in — the Web build points it at an isolated copy.
verify_template() {
  local template="$1"
  local dir="${2:-$(template_root)/$(lock_value templates_version)}"
  local path="$dir/$template"
  [ -f "$path" ] || die "export template missing: $path (see export_presets.cfg for how to install)"
  local expected got
  expected="$(lock_value "template.$template")"
  [ -n "$expected" ] || die "$template is not pinned in $LOCK_FILE"
  got="$(sha256 "$path")"
  [ "$expected" = "$got" ] || die "export template $template does not match the pinned hash"
}

## Fails unless the vendored SDK is byte-for-byte the pinned one. Vendoring already keeps the
## add-on out of the AssetStore's reach, so this catches the other way it drifts: an in-tree edit
## nobody meant to ship, or a copy-in that skipped the lock file.
verify_wavedash_sdk() {
  local pinned_version actual_version
  pinned_version="$(lock_value wavedash_sdk_version)"
  [ -n "$pinned_version" ] || die \
    "no wavedash_sdk_version in $LOCK_FILE. Run: tools/release.sh --relock"
  actual_version="$(wavedash_sdk_version)"

  [ "$actual_version" = "$pinned_version" ] || die \
    "Wavedash SDK is '$actual_version', pinned is '$pinned_version'. Upgrade deliberately: WAVEDASH_SDK_COMMIT=<sha> tools/release.sh --relock"

  local file addon_path expected got
  for file in "${WAVEDASH_SDK_FILES[@]}"; do
    addon_path="$WAVEDASH_ADDON_DIR/$file"
    [ -f "$addon_path" ] || die "Wavedash SDK file missing: $addon_path"
    expected="$(lock_value "wavedash_sdk.$file")"
    got="$(sha256 "$addon_path")"
    [ "$expected" = "$got" ] || die "Wavedash SDK file $file does not match the pinned hash"
  done
  note "Wavedash SDK $pinned_version verified (${#WAVEDASH_SDK_FILES[@]} hashes)"
}
