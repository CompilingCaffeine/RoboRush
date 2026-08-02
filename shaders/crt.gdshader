shader_type canvas_item;
// The cabinet the game is pretending to be inside. Spec section 20 asks for CRT glow;
// section 21 insists it stays subtle and optional.
//
// Deliberately does not sample the screen. A real CRT emulation warps, blooms, and bleeds
// colour sideways, all of which need the framebuffer and all of which fight the one thing
// this game's art depends on: every pixel being a crisp square. This draws two things over
// the top instead — scanlines and a vignette — which is the part of the look that reads at a
// glance and the part that cannot smear a 5-pixel-wide glyph.
//
// Scanlines are spaced in *game* pixels, not screen pixels. The game renders at 480x270 and
// is magnified whole, so a line every other screen pixel would be invisible at 1x and moire
// at 3x; a line every other game pixel scales with everything else, which is what a cabinet
// actually looked like.

uniform vec2 game_resolution = vec2(480.0, 270.0);

// How dark a scanline gets. Above roughly 0.25 the game starts to look broken rather than
// old, and the HUD's 8-pixel text is the first thing to suffer.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.16;

// How far the corners fall off.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.40;

// Where the vignette starts and ends, as a fraction of the distance from centre to corner.
uniform float vignette_inner : hint_range(0.0, 1.5) = 0.55;
uniform float vignette_outer : hint_range(0.0, 1.5) = 1.05;

void fragment() {
	float row = floor(UV.y * game_resolution.y);
	float scanline = mod(row, 2.0) < 1.0 ? scanline_strength : 0.0;

	// Corrected for aspect, or the vignette is an ellipse on a 16:9 screen and reads as a
	// smudge on the left and right edges rather than as corners falling away.
	vec2 centred = (UV - vec2(0.5)) * vec2(game_resolution.x / game_resolution.y, 1.0);
	float falloff = smoothstep(vignette_inner, vignette_outer, length(centred) * 2.0);

	COLOR = vec4(0.0, 0.0, 0.0, clamp(scanline + falloff * vignette_strength, 0.0, 1.0));
}
