#version 430 core

out vec4 FragColor;
in vec2 TexCoord;

uniform vec2 resolution;
uniform float time;
uniform vec3 cameraPos;
uniform vec3 cameraTarget;
uniform float cameraFov;

// =============================================================================
// BLACK HOLE PARAMETERS - TON 618 Scale
// =============================================================================
const float RS = 15.0;                    // Schwarzschild radius (event horizon)
const float PHOTON_SPHERE = 1.5 * RS;     // Photon sphere at 1.5 Rs
const float ISCO = 3.0 * RS;              // Innermost stable circular orbit

// =============================================================================
// ACCRETION DISK PARAMETERS
// =============================================================================
const float DISK_INNER = ISCO;            // Inner edge at ISCO (45 units)
const float DISK_OUTER = 20.0 * RS;       // Outer edge (300 units)
const float DISK_HEIGHT = 0.5;            // Thin disk approximation

// =============================================================================
// RAY TRACING PARAMETERS
// =============================================================================
const int MAX_STEPS = 300;
const float MAX_DISTANCE = 2000.0;
const float STEP_SIZE = 0.5;

// =============================================================================
// GRAVITATIONAL GRID PARAMETERS
// =============================================================================
const float GRID_EXTENT = 800.0;          // How far the grid extends
const float GRID_Y_BASE = -80.0;          // Base Y position of grid (below BH)
const float GRID_SPACING = 30.0;          // Grid line spacing
const float GRID_LINE_WIDTH = 0.8;        // Width of grid lines
const float GRID_HOLE_RADIUS = RS * 1.2;  // Cutout around event horizon
const float DEFORM_SCALE = 25.0;          // Depth of gravity well visualization

// =============================================================================
// STATIC SPHERES (planets/stars for reference)
// =============================================================================
struct Sphere {
    vec3 center;
    float radius;
    vec3 color;
};

const int NUM_SPHERES = 5;

Sphere getSphere(int i) {
    if (i == 0) return Sphere(vec3(200.0, 50.0, 0.0), 15.0, vec3(1.0, 0.3, 0.1));      // Red giant
    if (i == 1) return Sphere(vec3(-180.0, -30.0, 150.0), 12.0, vec3(0.2, 0.5, 1.0));  // Blue star
    if (i == 2) return Sphere(vec3(100.0, -40.0, -200.0), 18.0, vec3(1.0, 0.9, 0.3));  // Yellow star
    if (i == 3) return Sphere(vec3(-250.0, 80.0, -100.0), 10.0, vec3(0.8, 0.4, 0.9));  // Purple planet
    return Sphere(vec3(0.0, 100.0, 280.0), 20.0, vec3(0.3, 1.0, 0.5));                 // Green gas giant
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// =============================================================================
// STARFIELD BACKGROUND
// =============================================================================

vec3 getStarfield(vec3 rd) {
    vec3 col = vec3(0.0);

    // Multiple star layers
    for (int layer = 0; layer < 3; layer++) {
        float scale = 200.0 + float(layer) * 150.0;
        vec2 uv = rd.xy / (rd.z + 1.0001) * scale + float(layer) * 100.0;

        vec2 cell = floor(uv);
        vec2 cellUV = fract(uv);

        float h = hash(cell + float(layer) * 50.0);

        if (h > 0.97) {
            vec2 starPos = vec2(hash(cell * 1.1), hash(cell * 2.3)) * 0.6 + 0.2;
            float d = length(cellUV - starPos);
            float brightness = (1.0 - h) * 30.0 + 0.5;
            float star = exp(-d * 15.0) * brightness;

            vec3 starColor = vec3(1.0);
            float colorHash = hash(cell * 3.7);
            if (colorHash > 0.7) starColor = vec3(1.0, 0.8, 0.6);
            else if (colorHash > 0.4) starColor = vec3(0.8, 0.9, 1.0);

            col += starColor * star * (0.3 + 0.7 / float(layer + 1));
        }
    }

    // Subtle nebula colors
    float nebula = noise(rd.xy * 3.0 + rd.z) * 0.5 + 0.5;
    nebula *= noise(rd.xz * 2.0) * 0.5 + 0.5;
    col += vec3(0.02, 0.01, 0.04) * nebula * 0.5;

    return col;
}

// =============================================================================
// SCHWARZSCHILD GRAVITY - Compute gravitational deflection
// =============================================================================

// Get gravitational acceleration at position p
vec3 getGravity(vec3 p) {
    vec3 toCenter = -p;
    float r = length(toCenter);

    if (r < RS * 0.5) return vec3(0.0);

    vec3 dir = toCenter / r;

    // Schwarzschild gravity: a = -GM/r^2 = -0.5 * RS / r^2 (in geometric units)
    float strength = 1.5 * RS / (r * r);

    return dir * strength;
}

// =============================================================================
// RAY-SPHERE INTERSECTION
// =============================================================================

float intersectSphere(vec3 ro, vec3 rd, vec3 center, float radius) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;

    if (h < 0.0) return -1.0;

    float t = -b - sqrt(h);
    if (t < 0.0) t = -b + sqrt(h);

    return t;
}

// =============================================================================
// ACCRETION DISK
// =============================================================================

vec4 getAccretionDisk(vec3 pos) {
    float r = length(pos.xz);

    if (r < DISK_INNER || r > DISK_OUTER) return vec4(0.0);
    if (abs(pos.y) > DISK_HEIGHT * (1.0 + (r - DISK_INNER) / DISK_OUTER)) return vec4(0.0);

    // Temperature profile: T ~ r^(-3/4)
    float temp = pow(DISK_INNER / r, 0.75);

    // Color from temperature (blackbody approximation)
    vec3 hotColor = vec3(1.0, 0.9, 0.7);   // Inner: white-yellow
    vec3 warmColor = vec3(1.0, 0.5, 0.1);  // Mid: orange
    vec3 coolColor = vec3(0.8, 0.2, 0.05); // Outer: red

    vec3 diskColor;
    if (temp > 0.6) {
        diskColor = mix(warmColor, hotColor, (temp - 0.6) / 0.4);
    } else {
        diskColor = mix(coolColor, warmColor, temp / 0.6);
    }

    // Spiral structure
    float angle = atan(pos.z, pos.x);
    float spiral = sin(angle * 3.0 - r * 0.1 + time * 0.5) * 0.5 + 0.5;

    // Turbulence
    float turb = noise(vec2(r * 0.1, angle * 2.0 + time * 0.2)) * 0.3 + 0.7;

    // Doppler effect (approaching side brighter)
    float doppler = 1.0 + 0.3 * sin(angle + time * 0.3);

    // Intensity
    float radialFade = smoothstep(DISK_INNER, DISK_INNER + 20.0, r) *
                       smoothstep(DISK_OUTER, DISK_OUTER - 50.0, r);
    float intensity = temp * radialFade * turb * spiral * doppler;

    // Add glow
    diskColor += vec3(0.3, 0.1, 0.0) * temp;

    return vec4(diskColor * intensity * 2.0, intensity);
}

// =============================================================================
// GRAVITATIONAL GRID (2D Rubber Sheet Visualization)
// =============================================================================

// Calculate the depth of the gravity well at distance r from center
// Using Schwarzschild embedding: z = 2 * sqrt(Rs * (r - Rs))
float getGravityWellDepth(float r) {
    if (r <= RS) return -DEFORM_SCALE * 4.0; // Below event horizon

    // Schwarzschild embedding formula (Flamm's paraboloid)
    float depth = 2.0 * sqrt(RS * (r - RS));

    // The embedding gives depth that increases as you approach Rs
    // We want the well to go DOWN, and be deepest at the event horizon
    // At r = RS: depth = 0 (but we're at the horizon)
    // As r increases: depth increases
    // So we invert: deeper near RS, shallower far away

    float maxDepth = 2.0 * sqrt(RS * (GRID_EXTENT - RS));
    float wellDepth = (maxDepth - depth) / maxDepth * DEFORM_SCALE;

    return -wellDepth;
}

// Check if point is on a grid line
float getGridPattern(vec2 xz) {
    // Square grid pattern
    vec2 gridPos = mod(xz + GRID_SPACING * 0.5, GRID_SPACING) - GRID_SPACING * 0.5;
    float distToLineX = abs(gridPos.x);
    float distToLineZ = abs(gridPos.y);
    float distToLine = min(distToLineX, distToLineZ);

    return 1.0 - smoothstep(0.0, GRID_LINE_WIDTH, distToLine);
}

// Intersect ray with the deformed grid surface
vec4 intersectGrid(vec3 ro, vec3 rd) {
    // Only trace if ray might hit the grid plane
    if (rd.y >= 0.0 && ro.y >= GRID_Y_BASE) return vec4(0.0);
    if (rd.y <= 0.0 && ro.y <= GRID_Y_BASE - DEFORM_SCALE * 4.0) return vec4(0.0);

    // March along ray to find grid surface intersection
    float t = 0.0;
    float lastY = ro.y;
    float lastSurfaceY = 0.0;

    for (int i = 0; i < 200; i++) {
        t += 2.0;
        if (t > MAX_DISTANCE) break;

        vec3 p = ro + rd * t;

        // Check XZ bounds
        if (abs(p.x) > GRID_EXTENT || abs(p.z) > GRID_EXTENT) continue;

        // Distance from black hole center (in XZ plane)
        float r = length(p.xz);

        // Skip if inside the hole cutout
        if (r < GRID_HOLE_RADIUS) continue;

        // Calculate surface Y at this XZ position
        float surfaceY = GRID_Y_BASE + getGravityWellDepth(r);

        // Check if we crossed the surface
        if ((lastY > surfaceY && p.y <= surfaceY) ||
            (lastY < surfaceY && p.y >= surfaceY)) {

            // Binary search for exact intersection
            float t0 = t - 2.0;
            float t1 = t;
            for (int j = 0; j < 8; j++) {
                float tm = (t0 + t1) * 0.5;
                vec3 pm = ro + rd * tm;
                float rm = length(pm.xz);
                float sm = GRID_Y_BASE + getGravityWellDepth(rm);
                if (pm.y > sm) t0 = tm;
                else t1 = tm;
            }

            t = (t0 + t1) * 0.5;
            vec3 hitPos = ro + rd * t;
            float hitR = length(hitPos.xz);

            if (hitR < GRID_HOLE_RADIUS) return vec4(0.0);

            // Get grid pattern
            float grid = getGridPattern(hitPos.xz);

            if (grid > 0.01) {
                // Color based on distance from center
                float distFactor = hitR / GRID_EXTENT;
                vec3 gridColor = mix(
                    vec3(0.0, 0.8, 1.0),  // Cyan near center
                    vec3(0.0, 0.3, 0.6),  // Dark blue at edges
                    distFactor
                );

                // Add glow near the black hole
                if (hitR < RS * 5.0) {
                    float glow = 1.0 - (hitR - GRID_HOLE_RADIUS) / (RS * 5.0 - GRID_HOLE_RADIUS);
                    gridColor += vec3(0.5, 0.2, 0.0) * glow;
                }

                // Fade with distance from camera
                float fade = exp(-t * 0.001);

                return vec4(gridColor * grid, grid * fade * 0.8);
            }

            return vec4(0.0);
        }

        lastY = p.y;
        lastSurfaceY = surfaceY;
    }

    return vec4(0.0);
}

// =============================================================================
// MAIN RAY TRACING WITH GRAVITATIONAL LENSING
// =============================================================================

vec4 traceRay(vec3 ro, vec3 rd) {
    vec3 pos = ro;
    vec3 vel = rd;

    vec3 accumColor = vec3(0.0);
    float accumAlpha = 0.0;

    vec3 sphereColor = vec3(0.0);
    float sphereAlpha = 0.0;
    bool hitSphere = false;

    // Track previous position for disk intersection
    vec3 prevPos = pos;

    for (int step = 0; step < MAX_STEPS; step++) {
        float r = length(pos);

        // Check if fallen into black hole
        if (r < RS) {
            return vec4(accumColor, 1.0);
        }

        // Check if escaped
        if (r > MAX_DISTANCE) {
            break;
        }

        // Adaptive step size
        float stepSize = STEP_SIZE;
        if (r < PHOTON_SPHERE * 2.0) {
            stepSize *= 0.3;  // Smaller steps near photon sphere
        } else if (r > 100.0) {
            stepSize *= 2.0;  // Larger steps far away
        }

        // Apply gravitational deflection (RK4-style)
        vec3 k1 = getGravity(pos);
        vec3 k2 = getGravity(pos + vel * stepSize * 0.5);
        vec3 k3 = getGravity(pos + vel * stepSize * 0.5 + k1 * stepSize * 0.25);
        vec3 k4 = getGravity(pos + vel * stepSize + k2 * stepSize * 0.5);

        vec3 accel = (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0;

        vel += accel * stepSize;
        vel = normalize(vel);  // Keep as direction

        prevPos = pos;
        pos += vel * stepSize;

        // Check accretion disk crossing
        if ((prevPos.y > 0.0 && pos.y <= 0.0) || (prevPos.y < 0.0 && pos.y >= 0.0)) {
            float t = -prevPos.y / (pos.y - prevPos.y);
            vec3 diskHit = prevPos + (pos - prevPos) * t;

            vec4 disk = getAccretionDisk(diskHit);
            if (disk.a > 0.0) {
                accumColor = mix(accumColor, disk.rgb, disk.a * (1.0 - accumAlpha));
                accumAlpha += disk.a * (1.0 - accumAlpha);
            }
        }

        // Check sphere intersections
        if (!hitSphere) {
            for (int i = 0; i < NUM_SPHERES; i++) {
                Sphere s = getSphere(i);
                float t = intersectSphere(prevPos, normalize(pos - prevPos), s.center, s.radius);

                if (t > 0.0 && t < length(pos - prevPos)) {
                    vec3 hitPoint = prevPos + normalize(pos - prevPos) * t;
                    vec3 normal = normalize(hitPoint - s.center);

                    // Simple lighting
                    vec3 lightDir = normalize(vec3(1.0, 1.0, 0.5));
                    float diff = max(dot(normal, lightDir), 0.0);
                    float amb = 0.2;

                    sphereColor = s.color * (amb + diff * 0.8);
                    sphereAlpha = 1.0;
                    hitSphere = true;
                    break;
                }
            }
        }
    }

    // Get background
    vec3 bg = getStarfield(vel);

    // Combine: sphere over accretion disk over background
    vec3 finalColor = bg;

    if (accumAlpha > 0.0) {
        finalColor = mix(bg, accumColor, accumAlpha);
    }

    if (hitSphere) {
        finalColor = mix(finalColor, sphereColor, sphereAlpha);
    }

    return vec4(finalColor, 1.0);
}

// =============================================================================
// MAIN
// =============================================================================

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * resolution) / resolution.y;

    // Use uniforms for camera, with fallbacks
    vec3 camPos = cameraPos;
    vec3 camTarget = cameraTarget;
    float fov = cameraFov;

    // Fallback if uniforms not set
    if (length(camPos) < 0.001) {
        camPos = vec3(0.0, 50.0, 200.0);
    }
    if (fov < 1.0) {
        fov = 60.0;
    }

    // Build camera matrix
    vec3 forward = normalize(camTarget - camPos);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);

    // Ray direction
    float fovRad = fov * 3.14159 / 180.0;
    vec3 rd = normalize(forward + uv.x * right * tan(fovRad * 0.5) + uv.y * up * tan(fovRad * 0.5));

    // Trace the main scene
    vec4 sceneColor = traceRay(camPos, rd);

    // Trace the gravity grid
    vec4 gridColor = intersectGrid(camPos, rd);

    // Blend grid with scene (grid is semi-transparent overlay)
    vec3 finalColor = sceneColor.rgb;
    if (gridColor.a > 0.0) {
        finalColor = mix(finalColor, gridColor.rgb, gridColor.a * 0.7);
    }

    // Add gravitational lensing glow near photon sphere (visual effect)
    float distToCenter = length(camPos);
    vec2 screenCenter = vec2(0.0);
    float screenDist = length(uv - screenCenter);

    // Event horizon visual
    vec3 toCenterDir = normalize(-camPos);
    float dotToCenter = dot(rd, toCenterDir);
    if (dotToCenter > 0.99) {
        float ring = smoothstep(0.995, 0.999, dotToCenter);
        finalColor += vec3(0.2, 0.1, 0.0) * ring;
    }

    // Tone mapping
    finalColor = finalColor / (finalColor + vec3(1.0));
    finalColor = pow(finalColor, vec3(1.0 / 2.2));

    FragColor = vec4(finalColor, 1.0);
}
