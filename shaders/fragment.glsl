#version 430 core

out vec4 FragColor;
in vec2 TexCoord;

uniform vec2 resolution;
uniform float time;
uniform vec3 cameraPos;
uniform vec3 cameraTarget;
uniform float cameraFov;

const float PI = 3.14159265359;

// Black hole
const float RS = 15.0;
const float DISK_INNER = 3.0 * RS;
const float DISK_OUTER = 20.0 * RS;

// Grid parameters
const float GRID_EXTENT = 1200.0;
const float GRID_SPACING = 40.0;          // Square grid spacing
const float GRID_LINE_WIDTH = 0.8;
const float GRID_HOLE_RADIUS = RS * 1.1;  // Just slightly larger than event horizon

// Deformation - scales the embedding diagram
const float DEFORM_SCALE = 8.0;

// ============================================================================
// UTILITIES
// ============================================================================

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

mat3 lookAt(vec3 eye, vec3 target) {
    vec3 f = normalize(target - eye);
    vec3 r = normalize(cross(f, vec3(0.0, 1.0, 0.0)));
    if (length(cross(f, vec3(0.0, 1.0, 0.0))) < 0.001) {
        r = vec3(1.0, 0.0, 0.0);
    }
    vec3 u = cross(r, f);
    return mat3(r, u, f);
}

// ============================================================================
// GRAVITATIONAL GRID - CORRECT SCHWARZSCHILD EMBEDDING
// ============================================================================

/*
 * Schwarzschild Embedding Diagram
 *
 * The proper embedding of Schwarzschild geometry into 3D Euclidean space:
 * z = 2 * sqrt(RS * (r - RS))  for r >= RS
 *
 * This means:
 * - At r = RS (event horizon): z = 0 (deepest point)
 * - As r increases: z increases (surface rises, becomes flatter)
 * - The slope dz/dr = sqrt(RS / (r - RS)) is INFINITE at r = RS
 *   (vertical walls at the event horizon!)
 *
 * We flip this upside down for visualization (negative Y = deeper)
 */
float getGravityDepth(float r) {
    // Inside event horizon - no grid
    if (r < GRID_HOLE_RADIUS) return -9999.0;

    // Schwarzschild embedding: z = 2 * sqrt(RS * (r - RS))
    // We negate it so the funnel goes DOWN
    float embedding = 2.0 * sqrt(RS * (r - RS));

    // Scale for visualization and shift so flat part is at y=0
    // Far away (large r) should be at y ≈ 0
    // Near RS should be deep negative
    float farValue = 2.0 * sqrt(RS * (GRID_EXTENT - RS));
    float depth = (embedding - farValue) * DEFORM_SCALE;

    return depth;
}

/*
 * Square/Cartesian grid pattern
 * Simple X and Z axis-aligned lines
 */
float getGridLine(float x, float z) {
    // Distance to nearest X-aligned line
    float distX = abs(mod(x + GRID_SPACING * 0.5, GRID_SPACING) - GRID_SPACING * 0.5);

    // Distance to nearest Z-aligned line
    float distZ = abs(mod(z + GRID_SPACING * 0.5, GRID_SPACING) - GRID_SPACING * 0.5);

    // Minimum distance to any line
    float dist = min(distX, distZ);

    // Smooth line
    return 1.0 - smoothstep(0.0, GRID_LINE_WIDTH, dist);
}

/*
 * Get grid surface Y position at given X, Z
 */
float getGridSurfaceY(float x, float z) {
    float r = sqrt(x * x + z * z);
    return getGravityDepth(r);
}

/*
 * Ray-grid surface intersection
 */
bool intersectGrid(vec3 ro, vec3 rd, out vec3 hitPoint, out vec3 hitNormal, out float gridIntensity) {
    float t = 0.0;
    float maxT = 3000.0;
    float lastDist = 1000.0;

    for (int i = 0; i < 400; i++) {
        vec3 p = ro + rd * t;

        // Check bounds
        float r = length(p.xz);
        if (r > GRID_EXTENT) {
            t += 40.0;
            if (t > maxT) return false;
            continue;
        }

        // Skip inside hole
        if (r < GRID_HOLE_RADIUS * 0.9) {
            t += 5.0;
            continue;
        }

        // Get surface Y
        float surfaceY = getGridSurfaceY(p.x, p.z);

        if (surfaceY < -9000.0) {
            t += 5.0;
            continue;
        }

        float dist = p.y - surfaceY;

        // Detect surface crossing
        if (abs(dist) < 2.0 || (lastDist > 0.0 && dist < 0.0)) {
            hitPoint = vec3(p.x, surfaceY, p.z);

            // Normal via finite differences
            float eps = 2.0;
            float hL = getGridSurfaceY(p.x - eps, p.z);
            float hR = getGridSurfaceY(p.x + eps, p.z);
            float hD = getGridSurfaceY(p.x, p.z - eps);
            float hU = getGridSurfaceY(p.x, p.z + eps);

            if (hL < -9000.0) hL = surfaceY;
            if (hR < -9000.0) hR = surfaceY;
            if (hD < -9000.0) hD = surfaceY;
            if (hU < -9000.0) hU = surfaceY;

            hitNormal = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
            gridIntensity = getGridLine(p.x, p.z);

            return true;
        }

        lastDist = dist;
        float step = max(1.5, abs(dist) * 0.3);
        t += step;

        if (t > maxT) return false;
    }

    return false;
}

/*
 * Grid color based on depth
 */
vec3 getGridColor(vec3 hitPoint, vec3 normal, float lineIntensity) {
    float r = length(hitPoint.xz);
    float depth = -hitPoint.y;

    // Proximity to event horizon (0 = far, 1 = at RS)
    float proximity = 1.0 - smoothstep(RS, RS * 20.0, r);

    // Colors
    vec3 farColor = vec3(0.02, 0.06, 0.12);      // Dark blue (flat region)
    vec3 midColor = vec3(0.05, 0.25, 0.4);       // Medium blue
    vec3 nearColor = vec3(0.15, 0.5, 0.7);       // Cyan (curved region)
    vec3 hotColor = vec3(0.4, 0.85, 1.0);        // Bright cyan (event horizon)

    vec3 baseColor;
    if (proximity > 0.7) {
        baseColor = mix(nearColor, hotColor, (proximity - 0.7) / 0.3);
    } else if (proximity > 0.3) {
        baseColor = mix(midColor, nearColor, (proximity - 0.3) / 0.4);
    } else {
        baseColor = mix(farColor, midColor, proximity / 0.3);
    }

    // Lines brighter than base
    vec3 lineColor = baseColor * 1.8 + vec3(0.1, 0.15, 0.2);

    // Mix
    vec3 color = mix(baseColor * 0.25, lineColor, lineIntensity);

    // Lighting
    vec3 lightDir = normalize(vec3(0.2, 1.0, 0.3));
    float diffuse = max(0.35, dot(normal, lightDir));
    color *= diffuse;

    // Glow at event horizon edge
    float rimDist = r - GRID_HOLE_RADIUS;
    if (rimDist > 0.0 && rimDist < RS * 2.0) {
        float rimGlow = 1.0 - rimDist / (RS * 2.0);
        color += vec3(0.3, 0.7, 0.9) * rimGlow * rimGlow * 0.8;
    }

    // Edge fade
    float edgeFade = 1.0 - smoothstep(GRID_EXTENT * 0.7, GRID_EXTENT, r);
    color *= edgeFade;

    return color;
}

// ============================================================================
// ACCRETION DISK
// ============================================================================

vec3 getDiskColor(float r, float angle) {
    float normR = (r - DISK_INNER) / (DISK_OUTER - DISK_INNER);
    float temp = pow(clamp(1.0 - normR, 0.0, 1.0), 0.7);

    vec3 hot = vec3(1.0, 0.95, 0.8);
    vec3 mid = vec3(1.0, 0.6, 0.2);
    vec3 cool = vec3(0.8, 0.2, 0.05);

    vec3 col;
    if (temp > 0.5) {
        col = mix(mid, hot, (temp - 0.5) * 2.0);
    } else {
        col = mix(cool, mid, temp * 2.0);
    }

    float velocity = sqrt(RS / (2.0 * r));
    float doppler = 1.0 + sin(angle + time * 0.1) * velocity * 2.0;
    doppler = clamp(doppler, 0.4, 2.0);

    float spiral = sin(angle * 4.0 - r * 0.03 + time * 0.05) * 0.5 + 0.5;
    float noise = hash(vec2(angle * 5.0, r * 0.1));

    return col * doppler * (temp * 2.0 + 0.3) * (0.6 + 0.4 * spiral * noise) * 1.5;
}

// ============================================================================
// SPHERES
// ============================================================================

const int NUM_SPHERES = 4;
const vec4 SPHERES[4] = vec4[](
    vec4(0.0, 20.0, -250.0, 35.0),
    vec4(180.0, 40.0, -150.0, 25.0),
    vec4(-160.0, -30.0, -180.0, 30.0),
    vec4(80.0, 25.0, 150.0, 28.0)
);
const vec3 SPHERE_COLORS[4] = vec3[](
    vec3(0.2, 0.4, 1.0),
    vec3(1.0, 0.3, 0.1),
    vec3(1.0, 0.85, 0.2),
    vec3(0.2, 0.9, 0.3)
);

float hitSphere(vec3 ro, vec3 rd, vec3 center, float radius) {
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;

    if (discriminant < 0.0) return -1.0;

    float sqrtD = sqrt(discriminant);
    float t1 = -b - sqrtD;
    float t2 = -b + sqrtD;

    if (t1 > 0.01) return t1;
    if (t2 > 0.01) return t2;
    return -1.0;
}

vec3 shadeSphere(vec3 hitPoint, vec3 center, vec3 baseColor) {
    vec3 normal = normalize(hitPoint - center);
    vec3 viewDir = normalize(cameraPos - hitPoint);
    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.5));

    float diff = max(0.0, dot(normal, lightDir));
    vec3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(0.0, dot(normal, halfDir)), 32.0);
    float fresnel = pow(1.0 - max(0.0, dot(normal, viewDir)), 3.0);

    vec3 color = baseColor * (0.15 + diff * 0.7) + vec3(1.0) * spec * 0.3;
    color += baseColor * fresnel * 0.3;

    return color;
}

// ============================================================================
// STARFIELD
// ============================================================================

vec3 getStars(vec3 rd) {
    vec3 col = vec3(0.0);
    float theta = atan(rd.z, rd.x);
    float phi = asin(clamp(rd.y, -1.0, 1.0));

    for (int layer = 0; layer < 3; layer++) {
        float scale = 50.0 + float(layer) * 30.0;
        vec2 uv = vec2(theta, phi) * scale;
        vec2 id = floor(uv);
        vec2 f = fract(uv) - 0.5;

        float rand = hash(id + float(layer) * 100.0);
        if (rand > 0.88) {
            vec2 offset = (vec2(hash(id * 2.0), hash(id * 3.0)) - 0.5) * 0.6;
            float dist = length(f - offset);
            float brightness = (rand - 0.88) * 8.0;
            float star = smoothstep(0.04, 0.0, dist);
            col += vec3(0.9, 0.92, 1.0) * star * brightness;
        }
    }
    return col + vec3(0.005, 0.005, 0.01);
}

// ============================================================================
// MAIN
// ============================================================================

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * resolution) / resolution.y;

    mat3 cam = lookAt(cameraPos, cameraTarget);
    float fovFactor = tan(radians(cameraFov) * 0.5);
    vec3 rayDir = cam * normalize(vec3(uv * fovFactor, 1.0));

    vec3 pos = cameraPos;
    vec3 dir = rayDir;
    float prevY = pos.y;

    vec3 color = vec3(0.0);
    float hitDist = 1e10;
    int hitType = 0;

    // Grid intersection
    vec3 gridHitPoint, gridNormal;
    float gridIntensity;
    bool hitGrid = intersectGrid(cameraPos, rayDir, gridHitPoint, gridNormal, gridIntensity);
    float gridDist = hitGrid ? length(gridHitPoint - cameraPos) : 1e10;
    vec3 gridColor = hitGrid ? getGridColor(gridHitPoint, gridNormal, gridIntensity) : vec3(0.0);

    // Direct sphere hits
    for (int s = 0; s < NUM_SPHERES; s++) {
        float t = hitSphere(cameraPos, rayDir, SPHERES[s].xyz, SPHERES[s].w);
        if (t > 0.0 && t < hitDist) {
            hitDist = t;
            vec3 hp = cameraPos + rayDir * t;
            color = shadeSphere(hp, SPHERES[s].xyz, SPHERE_COLORS[s]);
            hitType = 3;
        }
    }

    // Ray march with lensing
    for (int i = 0; i < 400; i++) {
        float r = length(pos);

        if (r < RS * 1.02) {
            float dist = length(pos - cameraPos);
            if (dist < hitDist) {
                color = vec3(0.0);
                hitDist = dist;
                hitType = 1;
            }
            break;
        }

        if (r > 3000.0) {
            if (hitType == 0) {
                color = getStars(dir);
                hitType = 5;
            }
            break;
        }

        float curY = pos.y;
        if (prevY * curY < 0.0) {
            float cylR = length(pos.xz);
            if (cylR > DISK_INNER && cylR < DISK_OUTER) {
                float dist = length(pos - cameraPos);
                if (dist < hitDist) {
                    float angle = atan(pos.z, pos.x);
                    color = getDiskColor(cylR, angle);
                    hitDist = dist;
                    hitType = 2;
                }
            }
        }
        prevY = curY;

        for (int s = 0; s < NUM_SPHERES; s++) {
            float t = hitSphere(pos, dir, SPHERES[s].xyz, SPHERES[s].w);
            if (t > 0.0 && t < 15.0) {
                vec3 hp = pos + dir * t;
                float dist = length(hp - cameraPos);
                if (dist < hitDist) {
                    color = shadeSphere(hp, SPHERES[s].xyz, SPHERE_COLORS[s]);
                    hitDist = dist;
                    hitType = 3;
                }
            }
        }

        vec3 toCenter = -normalize(pos);
        float bendStrength = (RS * RS) / (r * r) * 0.8;
        if (r < 3.0 * RS) bendStrength *= 2.5;
        dir = normalize(dir + toCenter * bendStrength);

        float stepSize = max(0.5, min(r * 0.02, 8.0));
        pos += dir * stepSize;
    }

    if (hitType == 0) {
        color = getStars(dir);
        hitType = 5;
    }

    // Blend grid
    if (hitGrid) {
        float gridAlpha = 0.0;

        if (hitType == 1) {
            gridAlpha = 0.05;
        } else if (gridDist < hitDist) {
            gridAlpha = 0.85;
        } else {
            gridAlpha = 0.45;
        }

        gridAlpha *= 1.0 - smoothstep(900.0, 1400.0, gridDist);
        gridAlpha *= (0.25 + gridIntensity * 0.75);

        color = mix(color, gridColor, gridAlpha);
    }

    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));

    FragColor = vec4(color, 1.0);
}
