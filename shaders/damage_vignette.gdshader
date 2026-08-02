shader_type canvas_item;
// A red bloom around the edges of the screen when the player is hit.
//
// The HUD already says how much integrity is left, but a number the player has to look away
// from the fight to read is a number they do not read. This puts "you were hit" in the part
// of the screen nobody is looking at directly, which is the only place a full-screen effect
// can go without hiding the thing that hit them.
//
// Edges only, and never the middle: the player and whatever is shooting at them are in the
// middle, and tinting that would make the frame after a hit the hardest one to survive.

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.30, 0.24, 1.0);

// How far out the clear area reaches, as a fraction of the distance from centre to edge.
// The first attempt at this used a radial falloff and was unusable: on a 16:9 screen the
// radius to a corner is nearly twice the radius to the top edge, so by the time the corners
// were lit the middle of the screen was already red. A rectangular frame is what "edges
// only" actually means here.
uniform float clear_extent : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	// 0 at the centre, 1 at each edge, independent of aspect.
	vec2 to_edge = abs(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(clear_extent, 1.0, max(to_edge.x, to_edge.y));
	COLOR = vec4(tint.rgb, edge * strength);
}
