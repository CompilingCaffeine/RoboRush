#!/usr/bin/env bash
#
# Builds every distributable artifact from a clean tag, into an empty versioned directory, and
# writes a manifest that says exactly what was built and from what.
#
# The point is not convenience. A release built by hand is a release nobody can reproduce: the
# version in the binary comes from whatever was last typed into export_presets.cfg, the engine is
# whatever `godot` happens to resolve to today, the output lands beside the previous build so
# stale files ship with it, and nothing records which commit any of it came from. Every one of
# those is silent, and every one of them is only discovered by somebody holding the wrong build.
#
#     tools/release.sh v0.3.0        # build that tag
#     tools/release.sh --relock      # re-record the engine, template and SDK hashes
#
# What it refuses to do, and why each refusal is worth having:
#
#   - Build from a dirty tree. The manifest names a commit; if the tree has uncommitted changes
#     that commit does not describe what shipped.
#   - Build from a tag that does not exist, or a commit that is not that tag. A version number
#     that is not anchored to a tag is a version number that can be reused.
#   - Build with an engine or export templates that differ from the pinned ones, or export the Web
#     preset with an engine not built from the pinned recipe (tools/engine/). The engine is part of
#     the artifact — a Godot patch release changes the binary — so an unpinned engine makes
#     "reproducible" untrue in the one way nobody checks.
#   - Sign nothing while claiming to. See the signing section: without credentials it says so and
#     marks the artifacts unsigned rather than shipping them as if they were not.
#
# Everything it writes goes under build/<version>/, which must not already exist.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# What "pinned" means, the lock file, and the hashing that checks it. Shared with the Web build so
# that there is one definition of it rather than one per tool.
TOOL_NAME="release"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

# The presets, and the file each one produces. Names must match export_presets.cfg exactly —
# `--export-release` takes the preset's name and fails loudly on a typo, which is the behaviour
# wanted here.
PRESETS=("macOS" "Windows" "Linux" "Web")
OUTPUTS=("robo_rush.zip" "robo_rush.exe" "robo_rush.x86_64" "index.html")

# The stock release templates the desktop presets consume. Hashed and pinned, because they are as
# much a part of the artifact as the project's own source is. The Web preset is not here: it is
# exported with the stripped engine tools/engine/build_template.sh builds, which is pinned by its
# recipe instead (see verify_engine_build in tools/ci/lib.sh).
TEMPLATES=(
  "macos.zip"
  "windows_release_x86_64.exe"
  "linux_release.x86_64"
)

# --- Engine and template pinning ---------------------------------------------------

## Writes the lock file from whatever is installed now. Run deliberately, when the engine is
## upgraded on purpose, so that an upgrade is a reviewable diff rather than a silent change in
## what the next release is built with.
relock() {
  local version templates_version sdk_version sdk_commit cli_version pinned_cli_version cli_installer template_dir
  local source_commit emscripten
  template_dir="$(template_root)"
  version="$(engine_version)"
  # The `|| true` is load-bearing, for the same reason it is on the greps further down: with no
  # templates installed the glob matches nothing, cat fails, `2>/dev/null` hides why, and
  # `set -o pipefail` turns that into a silent abort of the entire relock — exit 1, no output, and
  # nothing to suggest the templates are what is missing. The lock file survives that, because it
  # is only written below, but the operator is told nothing at all.
  templates_version="$(cat "$template_dir"/*/version.txt 2>/dev/null | head -1 || true)"
  [ -n "$version" ] || die "could not run '$GODOT --version'"
  [ -n "$templates_version" ] || die \
    "no export templates installed in $template_dir (see export_presets.cfg for how to install)"

  sdk_version="$(wavedash_sdk_version)"
  [ -n "$sdk_version" ] || die "no version= in $WAVEDASH_ADDON_DIR/plugin.cfg"

  # Carried across when the CLI is not installed here, the way the SDK commit is. This line is the
  # approval the upload workflow gates on before it exposes WAVEDASH_TOKEN, and the machine that
  # relocks is usually not the machine that uploads — a relock from a dev box without the CLI used
  # to drop the line entirely, silently retiring an approval nobody meant to withdraw. The gate
  # then compared its installed CLI against an empty string, so it failed closed but said something
  # confusing about it.
  #
  # Deliberately no environment override to go with it: approving a version reviewed elsewhere —
  # the Linux binary CI installs, reviewed from a macOS dev box, which is the usual case — stays a
  # hand edit, so what was reviewed gets written down in the commit rather than typed into a
  # variable that leaves no trace of anyone having looked.
  # The `|| true` is load-bearing: finding nothing is a normal outcome here (a lock written before
  # the pin existed, or no lock at all on a first relock), but grep says so with exit 1 and
  # `set -o pipefail` would turn that into a silent abort of the whole relock.
  cli_version="$(wavedash_cli_version)"
  pinned_cli_version="$(grep '^wavedash_cli_version=' "$LOCK_FILE" 2>/dev/null | cut -d= -f2- || true)"
  if [ -z "$cli_version" ]; then
    cli_version="$pinned_cli_version"
    if [ -n "$cli_version" ]; then
      note "Wavedash CLI not installed here; kept the recorded '$cli_version'"
    else
      warn "no Wavedash CLI installed and none recorded: the upload workflow's version gate has nothing to compare against"
    fi
  fi
  # The hash of the installer the upload workflow runs for that version. Nothing installed here
  # can produce it, so it is only ever carried across, and the approval that changes the version
  # changes it in the same hand edit. Same `|| true`, same reason.
  cli_installer="$(grep '^wavedash_cli_installer=' "$LOCK_FILE" 2>/dev/null | cut -d= -f2- || true)"
  if [ -n "$pinned_cli_version" ] && [ "$cli_version" != "$pinned_cli_version" ]; then
    warn "recorded the installed Wavedash CLI '$cli_version' over the approved '$pinned_cli_version'. wavedash_cli_installer still pins the old installer, so uploads stop until it is updated to match."
  fi

  # Upstream publishes no tags, so the commit the vendored tree came from exists nowhere in the
  # files themselves. It has to be carried across a relock, or supplied when the SDK is upgraded.
  # Same `|| true`, for the same reason: without it a lock with no commit in it aborts the relock
  # silently on grep's exit status, and the message below — the one written to explain exactly that
  # situation and how to get out of it — never prints.
  sdk_commit="${WAVEDASH_SDK_COMMIT:-$(grep '^wavedash_sdk_commit=' "$LOCK_FILE" 2>/dev/null | cut -d= -f2- || true)}"
  [ -n "$sdk_commit" ] || die \
    "no wavedash_sdk_commit in $LOCK_FILE. Re-run with: WAVEDASH_SDK_COMMIT=<sha> tools/release.sh --relock"

  # The stripped Web engine's recipe. Neither half can be read off anything installed here — the
  # engine names only the first nine characters of its commit, and nothing on this machine has to
  # have Emscripten — so both are carried across a relock the way the SDK commit is, or supplied
  # when the engine is upgraded. Same `|| true`, same reason.
  source_commit="${ENGINE_SOURCE_COMMIT:-$(grep '^engine_source_commit=' "$LOCK_FILE" 2>/dev/null | cut -d= -f2- || true)}"
  emscripten="${EMSCRIPTEN_VERSION:-$(grep '^emscripten_version=' "$LOCK_FILE" 2>/dev/null | cut -d= -f2- || true)}"
  [ -n "$source_commit" ] || die \
    "no engine_source_commit in $LOCK_FILE. Re-run with: ENGINE_SOURCE_COMMIT=<full commit of the engine's release tag> tools/release.sh --relock"
  [ -n "$emscripten" ] || die \
    "no emscripten_version in $LOCK_FILE. Re-run with: EMSCRIPTEN_VERSION=<the version the stock Web template's banner reports> tools/release.sh --relock"
  # An upgrade that forgot ENGINE_SOURCE_COMMIT would otherwise carry the old commit forward and pin
  # a Web engine built from a different Godot than everything else in the release.
  case "$source_commit" in
    "${version##*.}"*) ;;
    *) die "engine_source_commit $source_commit is not the commit of the installed engine (${version##*.}). Re-run with: ENGINE_SOURCE_COMMIT=<full commit of the engine's release tag> tools/release.sh --relock" ;;
  esac

  # Built beside the lock file and moved over it only once every hash has been taken. Writing
  # straight to the lock file truncates it the moment the redirection opens, so a relock run
  # anywhere the full template set is not installed — a machine set up only for the Web build,
  # say — used to fail on the first missing file and leave the pins it had not reached yet gone.
  # The failure is fine; destroying the record of what the last release was built with is not.
  # Not `local`: the cleanup trap below runs after this function has returned, when a local would
  # be out of scope and `set -u` would turn the cleanup itself into the error.
  RELOCK_TMP="$(mktemp "$LOCK_FILE.XXXXXX")" || die "could not create a temporary file beside $LOCK_FILE"
  trap 'rm -f "${RELOCK_TMP:-}"' EXIT

  {
    echo "# Generated by tools/release.sh --relock. Do not edit by hand."
    echo "# The engine and export templates a release is built with are part of the artifact:"
    echo "# a Godot patch release changes the binary, so an unpinned engine makes a build"
    echo "# reproducible only by accident."
    echo "engine_version=$version"
    echo "templates_version=$templates_version"
    for template in "${TEMPLATES[@]}"; do
      local path="$template_dir/$templates_version/$template"
      [ -f "$path" ] || die "export template missing: $path"
      echo "template.$template=$(sha256 "$path")"
    done
    echo
    echo "# The Web preset runs on an engine compiled for this game (tools/engine/) rather than on"
    echo "# the stock Web template. tools/engine/build_template.sh builds it from this commit of the"
    echo "# engine source, with this Emscripten; together with tools/engine/ they are its recipe."
    echo "engine_source_commit=$source_commit"
    echo "emscripten_version=$emscripten"
    echo
    echo "# The vendored Wavedash SDK ships inside the web build, so it is part of the artifact"
    echo "# too. Upstream has no tags: the commit is the only durable name for what was copied."
    echo "wavedash_sdk_version=$sdk_version"
    echo "wavedash_sdk_commit=$sdk_commit"
    for file in "${WAVEDASH_SDK_FILES[@]}"; do
      local addon_path="$WAVEDASH_ADDON_DIR/$file"
      [ -f "$addon_path" ] || die "Wavedash SDK file missing: $addon_path"
      echo "wavedash_sdk.$file=$(sha256 "$addon_path")"
    done
    if [ -n "$cli_version" ]; then
      echo
      echo "# The Wavedash CLI the upload workflow installs: this version, from the installer with this"
      echo "# sha256. Approving a new one is a hand edit to both lines, made after reviewing it."
      echo "wavedash_cli_version=$cli_version"
      if [ -n "$cli_installer" ]; then
        echo "wavedash_cli_installer=$cli_installer"
      fi
    fi
  } > "$RELOCK_TMP"

  # Same directory, so this is a rename rather than a copy: the lock file is either the old one
  # or the new one, never half of either.
  mv "$RELOCK_TMP" "$LOCK_FILE" || die "could not move $RELOCK_TMP into place as $LOCK_FILE"
  trap - EXIT

  echo "Wrote $LOCK_FILE:"
  sed 's/^/  /' "$LOCK_FILE"
}

## Fails unless the installed engine, every stock export template and the vendored SDK are
## byte-for-byte the pinned ones, and the stripped engine — the Web template and the native copy
## the suite runs on — was built from the pinned recipe. A release builds all four platforms, so it
## verifies everything all four use; the Web build verifies only what it uses.
verify_engine() {
  verify_engine_version

  local templates_version template
  templates_version="$(lock_value templates_version)"
  for template in "${TEMPLATES[@]}"; do
    verify_template "$template"
  done
  note "export templates $templates_version verified (${#TEMPLATES[@]} hashes)"

  verify_engine_build web "$ENGINE_WEB_TEMPLATE"
  verify_engine_build native "$ENGINE_NATIVE"
  verify_wavedash_sdk
}


# --- Version, from the tag ----------------------------------------------------------

## Rewrites the version fields in export_presets.cfg from the tag, so the number inside the binary
## and the number on the release are the same by construction rather than by somebody remembering.
## Restored afterwards by the trap in main, because the working file is not the release artifact.
apply_version() {
  local semver="$1"
  local windows_version="${semver}.0"

  # macOS wants a dotted version; Windows wants four components. Both presets are rewritten in
  # place, and both are put back before this script exits.
  perl -pi -e "s|^application/short_version=.*|application/short_version=\"$semver\"|" export_presets.cfg
  perl -pi -e "s|^application/version=.*|application/version=\"$semver\"|" export_presets.cfg
  perl -pi -e "s|^application/product_version=.*|application/product_version=\"$windows_version\"|" export_presets.cfg
  perl -pi -e "s|^application/file_version=.*|application/file_version=\"$windows_version\"|" export_presets.cfg
  note "version $semver written into the export presets"
}

## Points the Web preset at the stripped engine for the length of the release. Godot would
## otherwise export it with the stock template from the export templates directory, which is
## 39.5 MB of engine against the stripped one's 22.9. Put back by the same trap as the version.
apply_web_template() {
  local template="$REPO_ROOT/$ENGINE_WEB_TEMPLATE"
  # Through the environment rather than spliced into the expression, so a path with a space or a
  # character Perl means something by cannot change what the substitution does.
  WEB_TEMPLATE_PATH="$template" perl -0pi -e \
    's|(name="Web"\n(?:.*\n)*?\[preset\.\d+\.options\]\n)|$1custom_template/release="$ENV{WEB_TEMPLATE_PATH}"\n|' \
    export_presets.cfg
  grep -qxF "custom_template/release=\"$template\"" export_presets.cfg || die \
    "could not point the Web preset at $template"
  note "Web preset exported with the stripped engine"
}


# --- Signing ------------------------------------------------------------------------

## macOS signing and notarisation, when there are credentials to do it with.
##
## Deliberately not silent when there are none. An unsigned macOS build is not a broken build, it
## is a build Gatekeeper refuses to open without the user right-clicking — which is a fine state
## for a test build and a bad surprise for a public one. The manifest records which it is, so the
## difference is visible to whoever publishes rather than to whoever downloads.
sign_macos() {
  local artifact="$1"
  if [ -z "${MACOS_SIGNING_IDENTITY:-}" ]; then
    note "macOS: unsigned (set MACOS_SIGNING_IDENTITY to a Developer ID to sign)"
    echo "unsigned"
    return
  fi

  codesign --force --timestamp --options runtime \
    --sign "$MACOS_SIGNING_IDENTITY" "$artifact" >/dev/null 2>&1 \
    || die "codesign failed for $artifact"

  if [ -z "${MACOS_NOTARY_PROFILE:-}" ]; then
    note "macOS: signed, not notarised (set MACOS_NOTARY_PROFILE for notarytool)"
    echo "signed"
    return
  fi

  xcrun notarytool submit "$artifact" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait \
    || die "notarisation failed for $artifact"
  xcrun stapler staple "$artifact" || die "stapling failed for $artifact"
  note "macOS: signed and notarised"
  echo "notarised"
}

sign_windows() {
  local artifact="$1"
  if [ -z "${WINDOWS_SIGNING_PFX:-}" ]; then
    note "Windows: unsigned (set WINDOWS_SIGNING_PFX and WINDOWS_SIGNING_PASSWORD to sign)"
    echo "unsigned"
    return
  fi
  command -v osslsigncode >/dev/null || die "osslsigncode is needed to sign Windows artifacts"
  osslsigncode sign -pkcs12 "$WINDOWS_SIGNING_PFX" -pass "${WINDOWS_SIGNING_PASSWORD:-}" \
    -t http://timestamp.digicert.com -in "$artifact" -out "$artifact.signed" >/dev/null \
    || die "osslsigncode failed for $artifact"
  mv "$artifact.signed" "$artifact"
  echo "signed"
}


# --- Main ---------------------------------------------------------------------------

main() {
  if [ "${1:-}" = "--relock" ]; then
    relock
    return
  fi

  local tag="${1:-}"
  [ -n "$tag" ] || die "usage: tools/release.sh <tag>   (or --relock)"

  echo "Robo Rush release $tag"

  # A clean tree, or the commit in the manifest is a lie about what was built.
  [ -z "$(git status --porcelain)" ] || die "the working tree is dirty; commit or stash first"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag '$tag' does not exist"
  [ "$(git rev-parse "$tag^{commit}")" = "$(git rev-parse HEAD)" ] \
    || die "HEAD is not tag '$tag'; check it out first"

  local commit semver output
  commit="$(git rev-parse HEAD)"
  semver="${tag#v}"
  output="build/$semver"

  # Empty and versioned. Building into a directory that already has files in it is how a stale
  # artifact from a previous version ends up inside a release.
  [ ! -e "$output" ] || die "$output already exists; remove it or pick another tag"

  verify_engine

  # The suite is part of the release gate: an artifact nobody has tested is not a release
  # candidate, it is a build. Twice, as in the Web build: the editor has every class, so only the
  # stripped engine can say the Web export still has everything the game uses. Its run leaves out
  # the timing suite, for the reason given beside ENGINE_NATIVE_SUITE_ARGS.
  note "running the test suite"
  "$GODOT" --headless --fixed-fps 60 res://tests/test_runner.tscn >/dev/null 2>&1 \
    || die "the test suite failed; nothing was built"
  note "running the test suite on the stripped engine"
  "$REPO_ROOT/$ENGINE_NATIVE" --headless --fixed-fps 60 --path "$REPO_ROOT" res://tests/test_runner.tscn \
    "${ENGINE_NATIVE_SUITE_ARGS[@]}" >/dev/null 2>&1 \
    || die "the test suite failed on the stripped engine; nothing was built"

  # The presets are edited in place and put back however this exits, including on failure. The
  # working file is not the artifact, and a release that left a rewritten version behind would
  # make the next developer's diff start with a change they did not make.
  trap 'git checkout -- export_presets.cfg 2>/dev/null || true' EXIT
  apply_version "$semver"
  apply_web_template

  mkdir -p "$output"
  local manifest="$output/manifest.json"
  echo "{" > "$manifest"
  echo "  \"version\": \"$semver\"," >> "$manifest"
  echo "  \"tag\": \"$tag\"," >> "$manifest"
  echo "  \"commit\": \"$commit\"," >> "$manifest"
  echo "  \"engine\": \"$(engine_version)\"," >> "$manifest"
  echo "  \"web_engine_recipe\": \"$(engine_recipe_key)\"," >> "$manifest"
  echo "  \"built\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$manifest"
  echo "  \"artifacts\": [" >> "$manifest"

  local index=0
  for preset in "${PRESETS[@]}"; do
    local lower
    lower="$(printf '%s' "$preset" | tr '[:upper:]' '[:lower:]')"
    local target_dir="$output/$lower"
    mkdir -p "$target_dir"
    local artifact="$target_dir/${OUTPUTS[$index]}"

    note "exporting $preset"
    "$GODOT" --headless --export-release "$preset" "$artifact" >/dev/null 2>&1 \
      || die "export failed for $preset"
    [ -f "$artifact" ] || die "$preset reported success but produced no file"

    local signing="not applicable"
    case "$preset" in
      macOS) signing="$(sign_macos "$artifact" | tail -1)" ;;
      Windows) signing="$(sign_windows "$artifact" | tail -1)" ;;
    esac

    # Size is the whole target directory for Web, which is many files, and the single artifact
    # otherwise. Both are what somebody downloading it actually receives.
    local size
    size="$(du -sk "$target_dir" | cut -f1)"

    [ $index -eq 0 ] || echo "    }," >> "$manifest"
    {
      echo "    {"
      echo "      \"target\": \"$preset\","
      echo "      \"path\": \"$lower/${OUTPUTS[$index]}\","
      echo "      \"sha256\": \"$(sha256 "$artifact")\","
      echo "      \"kilobytes\": $size,"
      echo "      \"signing\": \"$signing\""
    } >> "$manifest"

    index=$((index + 1))
  done

  echo "    }" >> "$manifest"
  echo "  ]" >> "$manifest"
  echo "}" >> "$manifest"

  # A flat checksum file as well as the manifest, because that is what a download page publishes
  # and what `shasum -c` consumes.
  (cd "$output" && find . -type f ! -name SHA256SUMS ! -name manifest.json -exec shasum -a 256 {} + > SHA256SUMS)

  echo
  echo "Built $tag into $output"
  sed 's/^/  /' "$manifest"
}

main "$@"
