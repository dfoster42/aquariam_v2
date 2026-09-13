shader_type canvas_item;
// Makes plants wave without the simulation knowing anything about it.
//
// The bend is done by offsetting the texture lookup rather than by moving vertices: a
// Sprite2D is a four-vertex quad, so displacing its corners shears the whole sprite
// instead of bending it. Sampling along a curve gives a real bend from the same quad.
//
// Each plant's phase comes from its own world position, read in vertex() from
// MODEL_MATRIX. That matters for cost: every plant can share one material — so they
// still batch into one draw call — while no two sway together. The alternative, a
// duplicated material per plant carrying a random phase, breaks batching for nothing.
//
// Cost is one sin() per fragment and no per-frame CPU work at all.

uniform float sway_strength : hint_range(0.0, 0.25) = 0.055;
uniform float sway_speed : hint_range(0.0, 4.0) = 0.85;
// How sharply the bend concentrates toward the tip. 1.0 leans the whole plant like a
// plank; higher values keep the base planted and move the fronds.
uniform float bend_power : hint_range(0.5, 5.0) = 2.2;
// A slower, smaller second wave so the motion does not read as a metronome.
uniform float drift_speed : hint_range(0.0, 2.0) = 0.31;

varying float phase;

void vertex() {
	vec2 world = MODEL_MATRIX[3].xy;
	// Irrational-ish multipliers so plants on a grid do not fall into step.
	phase = world.x * 0.0131 + world.y * 0.0217;
}

void fragment() {
	// UV.y is 0 at the top of the texture; plants are drawn rooted at the bottom.
	float height = 1.0 - UV.y;
	float bend = pow(height, bend_power);
	float wave = sin(TIME * sway_speed + phase) + 0.35 * sin(TIME * drift_speed + phase * 1.7);
	vec2 uv = UV + vec2(wave * sway_strength * bend, 0.0);

	// Sampling past the edge would smear the border pixels across the sprite. The
	// textures carry transparent padding to sway into, and this covers the rest.
	if (uv.x < 0.0 || uv.x > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, uv);
	}
}
