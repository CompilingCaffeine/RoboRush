#!/usr/bin/env bash
#
# Puts the pinned engine and the pinned Web export template on a machine that has neither.
#
#     tools/ci/install_godot.sh [--prefix DIR] [--template-dir DIR]
#
# Written for CI runners, which start empty every time. It is safe to run on a developer machine
# too — it verifies before it downloads and does nothing when both are already correct — but the
# README's editor route is the friendlier one for a person.
#
# Two things here are worth more than the convenience.
#
# The first is that both downloads are checked against a hash before anything uses them. A build
# that verifies its engine after installing whatever the network handed it is verifying the
# wrong thing.
#
# The second is that the export templates are not downloaded. Godot publishes them as one 1.28 GB
# bundle covering every platform, of which this build needs a single 10 MB file. The bundle is a
# zip, so its central directory can be read over HTTP range requests and exactly one entry pulled
# out of it. That turns a minute and a quarter of a gigabyte per CI run into about ten megabytes,
# and the extracted file is checked against tools/engine.lock like everything else — if the range
# arithmetic were wrong, the hash would say so.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TOOL_NAME="install_godot"
# shellcheck source=tools/ci/lib.sh
source "$REPO_ROOT/tools/ci/lib.sh"

PREFIX="${PREFIX:-$HOME/.local/bin}"
TEMPLATE_DIR=""
WEB_TEMPLATE="web_nothreads_release.zip"

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
    --template-dir) TEMPLATE_DIR="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done


## The name the Godot project uses for a release, from the version string the lock file pins.
## "4.7.1.stable.official.a13da4feb" is how the engine reports itself; "4.7.1-stable" is how the
## downloads are named. Derived rather than written twice, so an engine upgrade is one edit.
release_tag() {
  local version
  version="$(lock_value engine_version)"
  printf '%s-%s' "$(cut -d. -f1-3 <<<"$version")" "$(cut -d. -f4 <<<"$version")"
}


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


install_web_template() {
  local templates_version target
  templates_version="$(lock_value templates_version)"
  [ -n "$TEMPLATE_DIR" ] || TEMPLATE_DIR="$(template_root)"
  target="$TEMPLATE_DIR/$templates_version"

  if [ -f "$target/$WEB_TEMPLATE" ] \
    && [ "$(sha256 "$target/$WEB_TEMPLATE")" = "$(lock_value "template.$WEB_TEMPLATE")" ]; then
    note "Web template already installed at $target"
    return
  fi

  mkdir -p "$target"
  note "fetching $WEB_TEMPLATE out of the $(release_tag) template bundle"
  python3 - \
    "https://github.com/godotengine/godot/releases/download/$(release_tag)/Godot_v$(release_tag)_export_templates.tpz" \
    "templates/$WEB_TEMPLATE" \
    "$(lock_value "template.$WEB_TEMPLATE")" \
    "$target/$WEB_TEMPLATE" <<'PY'
"""Pull one entry out of a remote zip, using range requests, and verify it."""

import hashlib
import struct
import sys
import urllib.request
import zlib

url, wanted, expected_sha, out = sys.argv[1:5]


def fetch(start, end):
    request = urllib.request.Request(url, headers={"Range": "bytes=%d-%d" % (start, end)})
    with urllib.request.urlopen(request, timeout=180) as response:
        if response.status != 206:
            raise SystemExit(
                "install_godot: the server ignored a range request (HTTP %s). "
                "Fall back to downloading the whole bundle." % response.status
            )
        return response.read()


with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60) as head:
    size = int(head.headers["Content-Length"])

# The end-of-central-directory record lives in the last 64 KiB, and points at the directory that
# says where every entry starts. Two small reads to locate one file in a gigabyte.
tail = fetch(max(0, size - 65536), size - 1)
eocd = tail.rfind(b"PK\x05\x06")
if eocd < 0:
    raise SystemExit("install_godot: no end-of-central-directory record in the bundle")

directory_size, directory_offset = struct.unpack("<II", tail[eocd + 12:eocd + 20])
directory = fetch(directory_offset, directory_offset + directory_size - 1)

at = 0
found = None
while at + 46 <= len(directory) and directory[at:at + 4] == b"PK\x01\x02":
    method, = struct.unpack("<H", directory[at + 10:at + 12])
    compressed, uncompressed = struct.unpack("<II", directory[at + 20:at + 28])
    name_len, extra_len, comment_len = struct.unpack("<HHH", directory[at + 28:at + 34])
    local_offset, = struct.unpack("<I", directory[at + 42:at + 46])
    name = directory[at + 46:at + 46 + name_len].decode("utf-8", "replace")
    if name == wanted:
        found = (method, compressed, uncompressed, local_offset)
        break
    at += 46 + name_len + extra_len + comment_len

if found is None:
    raise SystemExit("install_godot: %s is not in the bundle" % wanted)

method, compressed, uncompressed, local_offset = found
# The local header repeats the name and extra fields, and only it says how long they are here.
header = fetch(local_offset, local_offset + 29)
name_len, extra_len = struct.unpack("<HH", header[26:30])
data_at = local_offset + 30 + name_len + extra_len
blob = fetch(data_at, data_at + compressed - 1)

if method == 8:
    blob = zlib.decompress(blob, -15)
elif method != 0:
    raise SystemExit("install_godot: unexpected compression method %d" % method)

if len(blob) != uncompressed:
    raise SystemExit("install_godot: expected %d bytes, got %d" % (uncompressed, len(blob)))

digest = hashlib.sha256(blob).hexdigest()
if digest != expected_sha:
    raise SystemExit(
        "install_godot: %s hashes to %s, and tools/engine.lock pins %s"
        % (wanted, digest, expected_sha)
    )

with open(out, "wb") as handle:
    handle.write(blob)
PY

  # Godot reads this to decide which version a template directory holds, and refuses the export
  # without it.
  printf '%s\n' "$templates_version" > "$target/version.txt"
  note "Web template installed at $target"
}


main() {
  echo "Installing the pinned Godot toolchain"
  install_editor
  install_web_template
  echo
  echo "Ready. Add $PREFIX to PATH if it is not already there."
}

main "$@"
