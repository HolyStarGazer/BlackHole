#version 460 core

out vec4 FragColor;
in vec2 TexCoord;

uniform vec2 resolution;
uniform float time;

void main()
{
    // Aspect-ratio corrected coordinates
    // Dividing by resolution.y keeps aspect ratio correct
    // Subtracting 0.5 * resolution centers the origin at screen center
    vec2 uv = (gl_FragCoord.xy - 0.5 * resolution) / resolution.y;
    
    // Now center is at (0, 0), and coordinates scale uniformly
    vec2 center = vec2(0.3 * sin(time), 0.3 * cos(time));
    float dist = length(uv - center);
    
    // Black circle (our "black hole") - now a perfect circle
    float blackHole = smoothstep(0.1, 0.12, dist);
    
    // Colorful background (adjusted for centered coords)
    vec3 bg = vec3(uv.x + 0.5, 0.3, uv.y + 0.5);
    
    vec3 color = bg * blackHole;
    
    FragColor = vec4(color, 1.0);
}
