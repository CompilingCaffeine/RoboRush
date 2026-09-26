#!/usr/bin/env python3
"""Fails if a Godot text resource or scene carries a `;` comment.

    tools/ci/check_design_notes.py [root]     # defaults to the repository root

Godot's text-resource saver regenerates a `.tres` or `.tscn` from the loaded object, and a comment
is not part of the object: one save in the inspector deletes every comment in the file, silently,
in a diff that looks like a routine property change. The project's design rationale used to live in
exactly those comments, over a hundred files of it.

It lives in `metadata/design_notes` now, which is part of the object, survives every save, and shows
in the inspector's Metadata section. A note is written on the section it describes: the
`[resource]` or root node for the file as a whole, a `[node]` or `[sub_resource]` for one part of
it, and prefixed with a property name (`weight: ...`) when it explains one value.

This check exists so a comment added out of habit is caught in review rather than by the next
person who happens to open the file in the editor.
"""

import pathlib
import sys

SUFFIXES = (".tres", ".tscn")
SKIPPED_DIRS = {".git", ".godot", "build", "addons"}


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2])
    problems = []
    for path in sorted(root.rglob("*")):
        if path.suffix not in SUFFIXES or SKIPPED_DIRS.intersection(path.relative_to(root).parts):
            continue
        # Line-based on purpose: a multi-line string value can contain a line starting with `;`,
        # but none in this project does, and a false positive here costs a rewording while a
        # false negative costs the note.
        for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
            if line.startswith(";"):
                problems.append(f"{path.relative_to(root)}:{number}")
                break

    if problems:
        print("These files have `;` comments, which the Godot editor deletes on the next save:")
        for problem in problems:
            print(f"  {problem}")
        print('Move each into `metadata/design_notes = "..."` on the section it describes.')
        return 1
    print("check_design_notes: no comments in Godot text resources")
    return 0


if __name__ == "__main__":
    sys.exit(main())
