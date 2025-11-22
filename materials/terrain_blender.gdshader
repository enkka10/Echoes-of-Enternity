shader_type spatial;

uniform sampler2D grass_texture : source_color;
uniform sampler2D sand_texture : source_color;
uniform sampler2D rock_texture : source_color;
uniform sampler2D snow_texture : source_color;

uniform float height_blend_steepness : hint_range(0.0, 20.0) = 5.0;
uniform float rock_blend_steepness : hint_range(0.0, 20.0) = 5.0;

varying float vertex_y;
varying float normal_y;

void vertex() {
	vertex_y = VERTEX.y;
	normal_y = NORMAL.y;
}

void fragment() {
	vec3 grass_albedo = texture(grass_texture, UV).rgb;
	vec3 sand_albedo = texture(sand_texture, UV).rgb;
	vec3 rock_albedo = texture(rock_texture, UV).rgb;
	vec3 snow_albedo = texture(snow_texture, UV).rgb;
	
	// Base is grass
	vec3 final_albedo = grass_albedo;
	
	// Blend Sand (Low height)
	float sand_factor = clamp(1.0 - (vertex_y - 2.0) / 3.0, 0.0, 1.0); // Fade out above y=5
	// Reduce sand on steep slopes (keep rock there)
	sand_factor *= clamp((normal_y - 0.7) * 5.0, 0.0, 1.0); 
	final_albedo = mix(final_albedo, sand_albedo, sand_factor);
	
	// Blend Rock (Steep slopes)
	// normal.y is 1.0 for flat up, 0.0 for vertical wall
	float rock_factor = clamp((0.7 - normal_y) * rock_blend_steepness, 0.0, 1.0);
	final_albedo = mix(final_albedo, rock_albedo, rock_factor);
	
	// Blend Snow (High peaks)
	float snow_factor = clamp((vertex_y - 12.0) / 5.0, 0.0, 1.0);
	// Snow sticks to flatter surfaces more than vertical cliffs? Or covers everything?
	// Let's say snow covers everything high up
	final_albedo = mix(final_albedo, snow_albedo, snow_factor);
	
	ALBEDO = final_albedo;
}
