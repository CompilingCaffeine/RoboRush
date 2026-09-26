#!/usr/bin/env bash
#
# Every static check the project runs, in one place. Needs no engine, so it runs in seconds.
#
#     tools/ci/lint.sh
#
# Tools, at the versions CI installs (see .github/workflows/lint.yml):
#
#     python3 -m pip install gdtoolkit==4.5.0 ruff==0.15.8 shellcheck-py==0.11.0.1
#
# What each check is for:
#
#   - Design notes: no `;` comments in .tres/.tscn, because the Godot editor deletes them on save.
#   - Script UIDs: every tracked .gd has its .uid tracked beside it. Godot 4 generates one on import
#     and refers to scripts by it; an untracked .uid is regenerated differently on every fresh
#     clone, so any scene or resource that saved the reference breaks on someone else's machine.
#   - gdlint: GDScript naming, unused arguments, line length and the rest (see gdlintrc).
#   - ruff: the Python tooling under tools/ (see ruff.toml).
#   - shellcheck: the shell tooling, at warning severity and above.
#
# Runs every check even after one fails, so a single run reports everything.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

failed=()

run() {
  local name="$1"
  shift
  printf '\n== %s\n' "$name"
  if "$@"; then
    printf '   ok\n'
  else
    failed+=("$name")
  fi
}

check_script_uids() {
  local missing
  missing="$(comm -23 <(git ls-files '*.gd' | sed 's/$/.uid/' | sort) <(git ls-files '*.gd.uid' | sort))"
  if [ -n "$missing" ]; then
    printf 'These scripts have no tracked .uid. Import the project once (godot --headless --import)\n'
    printf 'and commit the generated files:\n'
    while IFS= read -r path; do printf '  %s\n' "$path"; done <<<"$missing"
    return 1
  fi
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'lint: %s is not installed. See the top of tools/ci/lint.sh.\n' "$1" >&2
    exit 2
  }
}

for tool in gdlint ruff shellcheck; do
  require_tool "$tool"
done

run "design notes" python3 tools/ci/check_design_notes.py
run "script uids" check_script_uids
run "gdlint" gdlint .
run "ruff" ruff check tools/
# shellcheck disable=SC2046  # word splitting of the file list is the point
run "shellcheck" shellcheck --severity=warning -x $(git ls-files '*.sh')

if [ ${#failed[@]} -gt 0 ]; then
  printf '\nFAIL  %s\n' "${failed[*]}"
  exit 1
fi
printf '\nPASS  all static checks\n'
