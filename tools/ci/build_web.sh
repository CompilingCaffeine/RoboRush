#!/usr/bin/env bash
#
# Builds the one artifact the browser game is published from, and refuses to produce anything it
# cannot describe exactly.
#
#     tools/ci/build_web.sh
#
# Deliberately not tools/release.sh. That script builds four platforms from a signed-off tag, and
# every commit on main needs a Web build — a release wrapper run forty times a week stops being a
# release wrapper. What is shared with it is the part that must not have two answers: what engine,
# what export template and what vendored SDK are pinned, which lives in tools/ci/lib.sh.
#
# What this refuses to do, and why each refusal is worth having:
#
#   - Build with an engine, Web template or Wavedash SDK that is not the pinned one. All three end
#     up inside the artifact and none of them appears in a diff of the game's own source.
#   - Build with the Web preset's threading, GDExtension or PWA settings changed. Those decide
#     whether the game runs at all on a host that does not send cross-origin isolation headers, and
#     a change to them is a requalification, not a build.
#   - Build without running the suite. An artifact nobody has tested is not a build candidate.
#   - Export into a directory that already has files in it. Godot writes the files it produces and
#     leaves everything else alone, so a stale index.wasm from an older export would be uploaded
#     alongside a current index.pck and the two would disagree in the browser.
#   - Write anywhere near the developer's own Godot data. The suite writes user:// saves; run
#     against the real data directory, a build would quietly overwrite the save file of whoever
#     ran it.
#
# Everything it writes goes under build/. build/web is exactly what gets uploaded, matching
# upload_dir in wavedash.toml; build/web-artifact holds the immutable zip, its digest, the
# per-file checksums, and the test log.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TOOL_NAME="build_web"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

PRESET="Web"
WEB_TEMPLATE="web_nothreads_release.zip"
OUTPUT_DIR="build/web"
ARTIFACT_DIR="build/web-artifact"
ZIP_NAME="robo_rush-web.zip"

# Outer timeouts, because the failure being guarded against is not a slow step but a step that
# never ends: an import waiting on a lock, a suite that has stopped making progress, an export
# waiting on a prompt no one will answer. A CI job that hangs costs an hour and reports nothing.
IMPORT_TIMEOUT="${IMPORT_TIMEOUT:-900}"
TEST_TIMEOUT="${TEST_TIMEOUT:-900}"
EXPORT_TIMEOUT="${EXPORT_TIMEOUT:-900}"

# The Web preset settings this build is qualified for. Changing any of them changes what the game
# needs from the host page — thread support requires cross-origin isolation headers Wavedash is not
# documented as sending, GDExtension changes what the template must contain, and a PWA installs a
# service worker that caches an immutable build under a URL meant to serve the next one.
declare -a REQUIRED_PRESET_SETTINGS=(
  'variant/extensions_support=false'
  'variant/thread_support=false'
  'progressive_web_app/enabled=false'
)


# --- Preflight ---------------------------------------------------------------------

## The export presets are checked in, so this is not defending against a typo at the command line.
## It is defending against the settings drifting in the editor — where they are four checkboxes —
## and shipping in a build nobody re-qualified.
verify_preset() {
  local section setting
  section="$(awk '/^name="'"$PRESET"'"$/,/^\[preset\.[0-9]+\]$/' export_presets.cfg)"
  [ -n "$section" ] || die "no '$PRESET' preset in export_presets.cfg"

  for setting in "${REQUIRED_PRESET_SETTINGS[@]}"; do
    grep -qxF "$setting" <<<"$section" || die \
      "the $PRESET preset no longer has $setting. That is a requalification, not a build: test the change in a browser, then update REQUIRED_PRESET_SETTINGS here."
  done

  grep -qxF "export_path=\"$OUTPUT_DIR/index.html\"" <<<"$section" || die \
    "the $PRESET preset's export_path is not $OUTPUT_DIR/index.html, which is the directory wavedash.toml uploads"

  # The one filter that keeps the suite and the build scripts out of the PCK. verify_web.sh checks
  # the result as well, because a filter that silently stops matching is exactly the kind of thing
  # that only shows up in the artifact.
  grep -q '^exclude_filter=.*tests/\*' <<<"$section" || die \
    "the $PRESET preset no longer excludes tests/*"
  grep -q '^exclude_filter=.*tools/\*' <<<"$section" || die \
    "the $PRESET preset no longer excludes tools/*"

  grep -qxF 'renderer/rendering_method="gl_compatibility"' project.godot || die \
    "the project no longer renders with gl_compatibility, which is the only renderer this Web build is qualified for"

  note "$PRESET preset verified (single-threaded, no extensions, no PWA, gl_compatibility)"
}

## A copy of Godot's data directory that belongs to this build and nothing else, holding only the
## template that was just verified.
##
## Two things come from this. The suite's user:// writes land in a directory that is deleted
## afterwards rather than in the save file of whoever ran the build. And the export cannot
## silently use some other template that happens to be installed — the only one reachable is the
## one whose hash was checked.
isolate_godot_data() {
  local source_dir templates_version
  templates_version="$(lock_value templates_version)"
  source_dir="$(template_root)/$templates_version"

  [ -f "$source_dir/$WEB_TEMPLATE" ] || die \
    "export template missing: $source_dir/$WEB_TEMPLATE (see export_presets.cfg for how to install)"

  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roborush-web.XXXXXX")"
  # Armed the moment there is something to clean up, rather than once the build reaches its first
  # long step: everything after this line can die, and a failed build that leaves a copy of the
  # export templates in /tmp is a failed build nobody notices twice.
  trap 'restore_project_file; rm -rf "$WORK_DIR"' EXIT

  export HOME="$WORK_DIR/home"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CACHE_HOME="$HOME/.cache"
  unset GODOT_TEMPLATE_DIR

  local isolated
  isolated="$(template_root "$HOME")/$templates_version"
  mkdir -p "$isolated" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
  cp "$source_dir/$WEB_TEMPLATE" "$isolated/$WEB_TEMPLATE"
  printf '%s\n' "$templates_version" > "$isolated/version.txt"

  # Re-hashed after the copy rather than trusting cp: this is the file that actually gets used.
  verify_template "$WEB_TEMPLATE" "$isolated"
  note "isolated Godot data at $WORK_DIR, holding $WEB_TEMPLATE only"
}


# --- Build steps -------------------------------------------------------------------

## Imports the project the way a fresh clone does. CI checks out a tree with no .godot directory at
## all, so an export there is always preceded by a full import; running it here as its own step
## means an import error is reported as an import error rather than as a mysteriously incomplete
## artifact twenty minutes later.
import_project() {
  note "importing"
  local log="$WORK_DIR/import.log"
  timeout "$IMPORT_TIMEOUT" "$GODOT" --headless --import >"$log" 2>&1 \
    || die "the import failed or exceeded ${IMPORT_TIMEOUT}s. See $log"
  if grep -qE '^(SCRIPT )?ERROR:' "$log"; then
    cp "$log" "$ARTIFACT_DIR/import.log"
    die "the import reported errors. See $ARTIFACT_DIR/import.log"
  fi
}

## The suite, judged the way the runner reports rather than by counting the word ERROR.
##
## Several suites deliberately provoke failures the game is supposed to survive — a corrupt save, a
## refused write, a cloud that answers with nonsense — and each one prints a diagnostic on the way
## past. A build that failed on "ERROR:" would fail on the tests working. What cannot appear is a
## FAIL line, a script error, a leak report, or anything other than exactly one terminal PASS.
run_tests() {
  note "running the suite"
  local log="$ARTIFACT_DIR/test.log"
  local status=0
  timeout "$TEST_TIMEOUT" "$GODOT" --headless --fixed-fps 60 res://tests/test_runner.tscn \
    >"$log" 2>&1 || status=$?

  [ "$status" -eq 124 ] && die "the suite exceeded ${TEST_TIMEOUT}s and was stopped. See $log"
  [ "$status" -eq 0 ] || die "the suite failed (exit $status). See $log"

  local passes
  passes="$(grep -c '^PASS ' "$log" || true)"
  [ "$passes" -eq 1 ] || die \
    "expected exactly one terminal PASS line, found $passes. A run that ended early can exit 0 without reporting. See $log"

  grep -q '^FAIL' "$log" && die "the suite reported a failure. See $log"
  grep -q 'SCRIPT ERROR' "$log" && die "the suite hit a script error. See $log"
  grep -qE '[0-9]+ (ObjectDB instances|resources still in use)' "$log" \
    && die "the run leaked objects. See $log"

  note "$(grep '^PASS ' "$log")"
}

## Writes the build id into the project settings for the duration of the export, so that the
## running game can say which build it is.
##
## A copy of the file is restored afterwards rather than `git checkout --`, because this script is
## allowed to run on a dirty tree and a checkout would throw away work that has nothing to do with
## the build. The setting is read back out of the artifact by verify_web.sh: a build id that says
## it is in the game and is not is worse than no build id at all.
bake_build_id() {
  cp project.godot "$WORK_DIR/project.godot.orig"
  RESTORE_PROJECT_FILE=1
  perl -pi -e 's|^(config/name=.*)$|$1\nconfig/version="'"$BUILD_ID"'"|' project.godot
  grep -qxF "config/version=\"$BUILD_ID\"" project.godot || die "could not write the build id into project.godot"
}

restore_project_file() {
  [ "${RESTORE_PROJECT_FILE:-0}" = "1" ] || return 0
  cp "$WORK_DIR/project.godot.orig" project.godot
  RESTORE_PROJECT_FILE=0
}

## Exports into a directory that is created empty every time. Godot overwrites the files it
## produces and leaves anything else in place, so an export over a previous one is how a file from
# a build nobody remembers ends up in an upload.
export_web() {
  rm -rf "$OUTPUT_DIR"
  mkdir -p "$OUTPUT_DIR"

  note "exporting $PRESET as build $BUILD_ID"
  local log="$WORK_DIR/export.log"
  timeout "$EXPORT_TIMEOUT" "$GODOT" --headless --export-release "$PRESET" \
    "$REPO_ROOT/$OUTPUT_DIR/index.html" >"$log" 2>&1 \
    || { cp "$log" "$ARTIFACT_DIR/export.log"; die "the export failed. See $ARTIFACT_DIR/export.log"; }
  [ -f "$OUTPUT_DIR/index.html" ] || die "the export reported success but produced no index.html"
}

## What the artifact says about itself, shipped inside it. Uploaded along with the game on purpose:
## a hosted build that can be asked which commit it is, over HTTP, is the difference between
## qualifying Build B and believing you are looking at Build B.
write_build_info() {
  python3 - "$OUTPUT_DIR" "$BUILD_ID" "$COMMIT" "$DIRTY" <<'PY'
import hashlib, json, os, re, sys, time

output_dir, build_id, commit, dirty = sys.argv[1:5]


def lock(key):
    with open("tools/engine.lock") as handle:
        for line in handle:
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip()
    return ""


def number(path, pattern):
    """The one number `pattern` captures, from the file that declares it."""
    with open(path) as handle:
        found = re.search(pattern, handle.read(), re.MULTILINE)
    if found is None:
        raise SystemExit("build_web: %s no longer declares %s" % (path, pattern))
    return int(found.group(1))


files = []
for name in sorted(os.listdir(output_dir)):
    path = os.path.join(output_dir, name)
    if not os.path.isfile(path):
        continue
    with open(path, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    files.append({"name": name, "bytes": os.path.getsize(path), "sha256": digest})

info = {
    "build_id": build_id,
    "commit": commit,
    "dirty": dirty == "1",
    "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "engine": lock("engine_version"),
    "export_templates": lock("templates_version"),
    "wavedash_sdk": lock("wavedash_sdk_version"),
    # The two numbers that decide whether a build can read what another build wrote. A rollback
    # compares these before it publishes, which is the whole reason they are in here.
    "save_schema": number("autoload/save_manager.gd", r"^const SAVE_VERSION := (\d+)"),
    "content_version": number("data/runs/main_campaign.tres", r"^content_version = (\d+)"),
    "files": files,
}

with open(os.path.join(output_dir, "build-info.json"), "w") as handle:
    json.dump(info, handle, indent=2)
    handle.write("\n")

print("  build-info.json: save schema %d, content version %d, %d files"
      % (info["save_schema"], info["content_version"], len(files)))
PY
}

## A zip whose bytes depend only on the files in it.
##
## Ordinary zipping records modification times, so the same export zipped twice produces two
## different digests — and a digest that changes without the content changing cannot be used to
## prove that what CI tested is what got uploaded. Names sorted, timestamps fixed, permissions
## normalised: the digest becomes a statement about the game rather than about the clock.
##
## Root-correct, meaning index.html is at the top of the archive rather than inside a directory.
## Wavedash serves what it is given.
##
## Not a claim that two builds of the same commit produce the same digest: build-info.json records
## when the build ran, and that is worth more than the property it costs. What the digest is for is
## the trip between here and the upload — tested, zipped, stored, downloaded, extracted — where the
## question is whether the bytes are still the ones the suite ran against.
write_zip() {
  python3 - "$OUTPUT_DIR" "$ARTIFACT_DIR/$ZIP_NAME" <<'PY'
import os, sys, zipfile

source, target = sys.argv[1:3]

with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name in sorted(os.listdir(source)):
        path = os.path.join(source, name)
        if not os.path.isfile(path):
            continue
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(path, "rb") as handle:
            archive.writestr(info, handle.read())
PY
}


## The flat checksum file, in the format `shasum -c` reads, with paths relative to the upload
## directory. Separate from the digest of the zip: that one identifies the artifact, these say
## which file inside it went wrong when it does not match.
write_checksums() {
  local file
  : > "$ARTIFACT_DIR/SHA256SUMS"
  while IFS= read -r file; do
    printf '%s  %s\n' "$(sha256 "$OUTPUT_DIR/$file")" "$file" >> "$ARTIFACT_DIR/SHA256SUMS"
  done < <(cd "$OUTPUT_DIR" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
}


# --- Main --------------------------------------------------------------------------

main() {
  echo "Robo Rush Web build"

  COMMIT="$(git rev-parse HEAD)"
  DIRTY=0
  BUILD_ID="$(git rev-parse --short HEAD)"
  if [ -n "$(git status --porcelain)" ]; then
    # Allowed, unlike a release: the Web build runs constantly and refusing a dirty tree would make
    # it useless for the iteration it exists to support. Recorded and marked, because a build id
    # that names a commit the artifact does not match is a lie a tester would repeat.
    DIRTY=1
    BUILD_ID="$BUILD_ID-dirty"
    warn "the working tree is dirty; this artifact is marked $BUILD_ID and is not publishable"
  fi

  # Emptied, not added to. The logs and checksums in here describe one build, and a log left over
  # from the last attempt is worse than no log: it is a log that answers questions about a build
  # that no longer exists.
  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"

  verify_engine_version
  verify_wavedash_sdk
  verify_preset
  isolate_godot_data

  # Template verification happens against the isolated copy inside isolate_godot_data, which is the
  # one the export can actually reach.
  import_project
  run_tests

  bake_build_id
  export_web
  restore_project_file

  write_build_info

  # The contract check is a separate script so that CI can run it again after downloading the
  # artifact, against a directory this machine never touched.
  tools/ci/verify_web.sh "$OUTPUT_DIR"

  write_zip
  write_checksums
  sha256 "$ARTIFACT_DIR/$ZIP_NAME" > "$ARTIFACT_DIR/$ZIP_NAME.sha256"

  echo
  echo "Built $BUILD_ID into $OUTPUT_DIR"
  note "upload directory  $OUTPUT_DIR ($(du -sk "$OUTPUT_DIR" | cut -f1) KiB, $(find "$OUTPUT_DIR" -type f | wc -l | tr -d ' ') files)"
  note "artifact          $ARTIFACT_DIR/$ZIP_NAME ($(du -sk "$ARTIFACT_DIR/$ZIP_NAME" | cut -f1) KiB)"
  note "artifact sha256   $(cat "$ARTIFACT_DIR/$ZIP_NAME.sha256")"
  note "commit            $COMMIT"
}

main "$@"
