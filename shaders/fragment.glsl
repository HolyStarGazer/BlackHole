#version 430 core

out vec4 FragColor;
in vec2 TexCoord;

uniform vec2 resolution;
uniform float time;

// Camera parameters
const vec3 cameraPos = vec3(0.0, 0.0, 5.0);
const float fov = 60.0;

// Black hole parameters
const vec3 blackHolePos = vec3(0.0, 0.0, 0.0);
const float blackHoleRadius = 1.0;  // Schwarzschild radius (event horizon)

// Ray marching parameters
const int MAX_STEPS = 100;
const float MAX_DIST = 100.0;
const float EPSILON = 0.001;

// Simple sphere SDF (Signed Distance Function)
float sphereSDF(vec3 p, vec3 center, float radius)
{
    return length(p - center) - radius;
}

// Scene SDF - for now just the black hole event horizon
float sceneSDF(vec3 p)
{
    return sphereSDF(p, blackHolePos, blackHoleRadius);
}

// Basic ray marching (without gravity bending yet)
float rayMarch(vec3 ro, vec3 rd)
{
    float totalDist = 0.0;
    
    for (int i = 0; i < MAX_STEPS; i++)
    {
        vec3 currentPos = ro + rd * totalDist;
        float dist = sceneSDF(currentPos);
        
        if (dist < EPSILON)
        {
            return totalDist;  // Hit!
        }
        
        if (totalDist > MAX_DIST)
        {
            break;  // Too far, stop
        }
        
        totalDist += dist;
    }
    
    return -1.0;  // No hit
}

// Calculate normal at surface point
vec3 calcNormal(vec3 p)
{
    vec2 e = vec2(EPSILON, 0.0);
    return normalize(vec3(
        sceneSDF(p + e.xyy) - sceneSDF(p - e.xyy),
        sceneSDF(p + e.yxy) - sceneSDF(p - e.yxy),
        sceneSDF(p + e.yyx) - sceneSDF(p - e.yyx)
    ));
}

// Simple background gradient (will be replaced with skybox later)
vec3 getBackground(vec3 rd)
{
    float t = 0.5 * (rd