#!/usr/bin/env bash
#
# Puts the pinned engine on a machine that does not have it.
#
#     tools/ci/install_godot.sh [--prefix DIR]
#
# Written for CI runners, which start empty every time. It is safe to run on a developer machine
# too — it verifies before it installs and does nothing when the engine is already correct — but
# the README's editor route is the friendlier one for a person.
#
# The download is checked against a hash before anything uses it. A build that verifies its engine
# after installing whatever the network handed it is verifying the wrong thing.
#
# There is no export template to install. The Web preset is exported with the stripped engine that
# tools/engine/build_template.sh compiles from source, not with Godot's stock Web template, so the
# only thing this fetches is the editor that does the importing, testing and exporting.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TOOL_NAME="install_godot"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

PREFIX="${PREFIX:-$HOME/.local/bin}"

# The editor archive this script is allowed to install, by hash. Recorded here rather than in
# tools/engine.lock because that file is generated from what is installed, and this is the file
# that does the installing — it cannot take its authority from the thing it produces.
#
# Only the Linux x86_64 build is pinned: this exists for CI, which is Linux, and a developer on
# another platform installs the editor the way they installed the one they already have.
EDITOR_SHA256="c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done


install_editor() {
  local tag archive url work
  tag="$(release_tag)"
  archive="Godot_v${tag}_linux.x86_64.zip"
  url="https://github.com/godotengine/godot/releases/download/$tag/$archive"

  if [ -x "$PREFIX/godot" ] && [ "$("$PREFIX/godot" --version 2>/dev/null | head -1)" = "$(lock_value engine_version)" ]; then
    note "engine already installed at $PREFIX/godot"
    return
  fi

  [ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || die \
    "only the Linux x86_64 editor is pinned here. Install $tag by hand (see the README) and re-run the build."

  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN

  note "downloading $archive"
  curl -fsSL --retry 3 -o "$work/$archive" "$url" || die "could not download $url"

  local got
  got="$(sha256 "$work/$archive")"
  [ "$got" = "$EDITOR_SHA256" ] || die \
    "$archive hashes to $got, expected $EDITOR_SHA256. Refusing to install it."

  unzip -q "$work/$archive" -d "$work"
  mkdir -p "$PREFIX"
  mv "$work/Godot_v${tag}_linux.x86_64" "$PREFIX/godot"
  chmod +x "$PREFIX/godot"

  GODOT="$PREFIX/godot" verify_engine_version
  note "engine installed at $PREFIX/godot"
}


main() {
  echo "Installing the pinned Godot editor"
  install_editor
  echo
  echo "Ready. Add $PREFIX to PATH if it is not already there."
}

main "$@"
