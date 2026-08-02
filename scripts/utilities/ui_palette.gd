class_name UIPalette
## The interface's colours, in one place.
##
## Not a Resource and never instantiated — the same shape as `Teams`. These are not tunable
## content, they are the game's palette, and a designer moving them at runtime would only be
## able to make the HUD unreadable.
##
## The values are the ones the sprites already use (see tools/generate_art.py), so the
## interface and the game are visibly the same machine rather than two things that happen to
## be on screen together. `data/ui/theme.tres` repeats a few of them because a Theme resource
## cannot reference a constant; those two are kept in step by hand, and there are deliberately
## only a few.
##
## Named by role rather than by colour. "CYAN" would have to be renamed to change the accent;
## `ACCENT` does not, and every caller already says what it means.

## The screen behind everything. Matches the project's clear colour.
const VOID := Color("0b0d12")

## Window and panel fill, and the line around them.
const PANEL := Color("0e1118")
const PANEL_BORDER := Color("2a3446")

## Body text, and the dimmer label text beside it.
const TEXT := Color("d8e2ec")
const TEXT_DIM := Color("7c8a99")
const TEXT_FAINT := Color("4a5666")

## The system is working. Integrity, room clear, victory, focus rings.
const ACCENT := Color("58f0c8")

## The system wants something. Scrap, items, dash, pause.
const WARN := Color("f2a13c")

## The system is failing. Damage, low integrity, the boss, game over.
const DANGER := Color("ff6b5a")

## Base label size. Everything is a multiple of it, because the font is a bitmap face and a
## non-integer multiple is a blurred one.
const FONT_SIZE := 8
const FONT_SIZE_TITLE := 24
const FONT_SIZE_HEADING := 16


## Styles a label in one call. Used by screens that build their rows in code, which is most
## of them: the row *set* changes with the run, so the alternative is a scene file full of
## placeholder labels.
static func style(label: Label, color: Color, size := FONT_SIZE) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)


## Builds a styled label, for the common case of one that did not exist a moment ago.
static func make_label(text: String, color := TEXT, size := FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style(label, color, size)
	return label
