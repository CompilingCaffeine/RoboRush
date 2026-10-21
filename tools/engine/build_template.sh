#!/usr/bin/env bash
#
# Builds the engine Robo Rush's Web export runs on, from source, with every feature the game does
# not use switched off.
#
#     tools/engine/build_template.sh web           # build/engine/web/web_nothreads_release.zip
#     tools/engine/build_template.sh native        # build/engine/native/godot
#     tools/engine/build_template.sh --recipe-key  # the key the two builds are stamped with
#
# The stock Web template is 39.5 MB of WebAssembly, 6.9 MB on the wire with brotli, and it was most
# of what a player downloaded. Built with tools/engine/profile.py it is 22.9 MB, and 3.7 MB with
# brotli. Same engine version, same commit and same compiler as the official template: only the
# feature set differs.
#
# Two builds, from one profile:
#
#   - web is the export template the Web build ships. tools/ci/build_web.sh and tools/release.sh
#     export the Web preset with it and with nothing else.
#   - native is the same feature set compiled for the machine running this, as a debug template.
#     The suite runs on it a second time, after the editor run, because the editor has every class
#     and so cannot notice the game reaching for one the profile removed. That is the one way a
#     stripped engine breaks, and without this it breaks in a browser instead of in a test.
#
# The recipe is the Godot commit and Emscripten version in tools/engine.lock, the profile, and this
# script. Each build writes the key of the recipe it came from beside what it built, and
# verify_engine_build in tools/ci/lib.sh refuses an engine whose key is not the current one, so an
# engine built before an edit to any of them cannot be exported with afterwards. CI caches the
# builds under the same key: a commit that leaves the recipe alone reuses them, and one that changes
# it gets a fresh build of exactly what it changed to.
#
# Sources, toolchain and objects go in $ENGINE_WORK_DIR (build/engine/work by default) and are kept,
# so the next build is incremental. build/ is ignored by Godot (.gdignore) and by git, so none of it
# is ever imported, exported or committed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TOOL_NAME="build_template"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

WORK_DIR="${ENGINE_WORK_DIR:-$ENGINE_DIR/work}"
PROFILE="$REPO_ROOT/tools/engine/profile.py"

# SCons only drives the compiler, but it is a dependency like any other, so it is pinned like one.
SCONS_VERSION="4.11.1"

GODOT_REPOSITORY="https://github.com/godotengine/godot.git"
EMSDK_REPOSITORY="https://github.com/emscripten-core/emsdk.git"


cpu_count() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2
}


# --- Sources and toolchain ---------------------------------------------------------

## The Godot source at exactly the commit the lock names. The tag is only how it is found: the
## commit is what is checked, so a tag that had moved would be refused rather than built.
fetch_source() {
  local commit tag source="$WORK_DIR/godot"
  commit="$(lock_value engine_source_commit || true)"
  [ -n "$commit" ] || die "no engine_source_commit in $LOCK_FILE"
  tag="$(release_tag)"

  if [ -d "$source/.git" ] && [ "$(git -C "$source" rev-parse HEAD)" = "$commit" ]; then
    note "Godot $tag source already checked out"
    return
  fi

  rm -rf "$source"
  note "fetching the Godot $tag source"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$GODOT_REPOSITORY" "$source" \
    || die "could not clone $tag from $GODOT_REPOSITORY"
  local fetched
  fetched="$(git -C "$source" rev-parse HEAD)"
  [ "$fetched" = "$commit" ] || die "$tag is $fetched, but $LOCK_FILE pins $commit. Refusing to build it."
}

## SCons at the pinned version, in an environment of its own rather than whatever the machine has.
install_scons() {
  local venv="$WORK_DIR/venv" installed=""
  if [ -x "$venv/bin/python" ]; then
    installed="$("$venv/bin/python" -c 'import SCons; print(SCons.__version__)' 2>/dev/null || true)"
  fi
  if [ "$installed" != "$SCONS_VERSION" ]; then
    rm -rf "$venv"
    python3 -m venv "$venv" || die "could not create a Python environment at $venv"
    "$venv/bin/pip" install --quiet "scons==$SCONS_VERSION" || die "could not install SCons $SCONS_VERSION"
  fi
  SCONS="$venv/bin/scons"
  note "SCons $SCONS_VERSION"
}

## Emscripten at the version the lock names, from the emsdk tag of the same name. The template is
## compiled C++, so the compiler is part of what it is: the official 4.7.1 template reports
## Emscripten 4.0.20 in its startup banner, and the lock pins the same.
install_emscripten() {
  local version emsdk="$WORK_DIR/emsdk"
  version="$(lock_value emscripten_version || true)"
  [ -n "$version" ] || die "no emscripten_version in $LOCK_FILE"

  if [ ! -d "$emsdk/.git" ] || [ "$(git -C "$emsdk" describe --tags --exact-match 2>/dev/null || true)" != "$version" ]; then
    rm -rf "$emsdk"
    note "fetching emsdk $version"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" "$EMSDK_REPOSITORY" "$emsdk" \
      || die "could not clone emsdk $version from $EMSDK_REPOSITORY"
  fi
  # Logged rather than shown: emsdk draws a download progress bar that runs to tens of kilobytes of
  # carriage returns in a CI log.
  local log="$WORK_DIR/emsdk.log"
  "$emsdk/emsdk" install "$version" >"$log" 2>&1 || {
    tail -20 "$log" >&2
    die "emsdk could not install Emscripten $version. Full log: $log"
  }
  "$emsdk/emsdk" activate "$version" >>"$log" 2>&1 || {
    tail -20 "$log" >&2
    die "emsdk could not activate Emscripten $version. Full log: $log"
  }

  # emsdk's environment script reads variables it does not set, which `set -u` would turn into an
  # abort halfway through putting emcc on PATH.
  set +u
  # shellcheck source=/dev/null
  source "$emsdk/emsdk_env.sh" >/dev/null 2>&1
  set -u

  local banner
  banner="$(emcc --version 2>/dev/null | head -1 || true)"
  grep -qF " $version " <<<"$banner" || die "emcc reports '$banner', expected Emscripten $version"
  note "Emscripten $version"
}


# --- Builds ------------------------------------------------------------------------

## Runs SCons in the source tree with the profile, logging to a file and showing the end of it if
## the build fails. Everything else on the command line is the caller's.
scons_build() {
  local log="$WORK_DIR/$1.log"
  shift
  (cd "$WORK_DIR/godot" && "$SCONS" profile="$PROFILE" -j"$(cpu_count)" "$@") >"$log" 2>&1 || {
    tail -40 "$log" >&2
    die "the build failed. Full log: $log"
  }
}

## The export template. threads=no because the Web preset is single-threaded: the host sends no
## cross-origin isolation headers, so a threaded build would not start. Everything else is the
## profile.
build_web() {
  install_emscripten
  note "building the Web template (a few minutes on a warm machine, longer from cold)"
  scons_build web platform=web target=template_release threads=no
  install_output "$WORK_DIR/godot/bin/godot.web.template_release.wasm32.nothreads.zip" "$ENGINE_WEB_TEMPLATE"
}

## The same feature set for this machine, as a debug template the suite can run on. It never
## ships, so the options here are about running headless on a bare CI runner: nothing to link for
## a display, audio or the desktop, no link-time optimisation to wait for, and path overrides left
## on so the suite can be pointed at the project with --path. None of them decides which classes
## exist, which is the only thing this build is for.
build_native() {
  local platform arch
  local -a options
  # In Godot's spelling, which is what the binary is named after: Linux calls the same machine
  # aarch64 that Godot and macOS call arm64.
  arch="$(uname -m)"
  case "$arch" in
    aarch64) arch="arm64" ;;
    amd64) arch="x86_64" ;;
  esac
  case "$(uname -s)" in
    Darwin)
      platform="macos"
      options=(vulkan=no metal=no accesskit=no)
      ;;
    Linux)
      platform="linuxbsd"
      options=(vulkan=no accesskit=no sdl=no x11=no wayland=no alsa=no pulseaudio=no dbus=no
        speechd=no fontconfig=no udev=no)
      ;;
    *) die "there is no native build for $(uname -s)" ;;
  esac

  note "building the native $platform engine the suite runs on"
  scons_build native platform="$platform" arch="$arch" target=template_debug production=no \
    disable_path_overrides=no "${options[@]}"
  install_output "$WORK_DIR/godot/bin/godot.$platform.template_debug.$arch" "$ENGINE_NATIVE"
}

## Puts a build where the tools look for it, with the key of the recipe it came from beside it. The
## key is written last, so an interrupted copy leaves an engine with no key, which
## verify_engine_build refuses, rather than a key vouching for half a file.
install_output() {
  local built="$1" target="$2" stamp
  stamp="$(dirname "$target")/recipe"
  [ -f "$built" ] || die "the build reported success but produced no $built"
  mkdir -p "$(dirname "$target")"
  rm -f "$stamp"
  cp "$built" "$target"
  engine_recipe_key > "$stamp"
  note "$target: $(wc -c < "$target" | tr -d ' ') bytes, recipe $(cut -c1-12 "$stamp")"
}


main() {
  case "${1:-}" in
    --recipe-key)
      engine_recipe_key
      return
      ;;
    web | native) ;;
    *) die "usage: tools/engine/build_template.sh web|native|--recipe-key" ;;
  esac

  echo "Robo Rush engine: $1"
  mkdir -p "$WORK_DIR"
  # Absolute from here on, because SCons runs from inside the source tree and every relative path
  # into the work directory would resolve against that instead.
  WORK_DIR="$(cd "$WORK_DIR" && pwd)"
  fetch_source
  install_scons
  "build_$1"
}

main "$@"
