#version 460 core
/*
 * TON 618 - SUPERMASSIVE BLACK HOLE VISUALIZATION
 * 
 * TON 618 Facts:
 * - Mass: ~66 billion solar masses (6.6 × 10¹⁰ M☉)
 * - Schwarzschild radius: ~1,300 AU (larger than our solar system)
 * - Located 10.4 billion light-years away in a quasar
 * - One of the most massive black holes ever discovered
 */

out vec4 FragColor;
in vec2 TexCoord;

// ============================================================================
// UNIFORMS
// ============================================================================

uniform vec2 resolution;
uniform float time;
uniform vec3 cameraPos;
uniform vec3 cameraTarget;
uniform float cameraFov;

// ============================================================================
// CONSTANTS
// ============================================================================

const float PI = 3.14159265359;
const float TWO_PI = 6.28318530718;

// Black hole parameters (geometric units: G = c = 1)
const vec3 BLACK_HOLE_POS = vec3(0.0);
const float BLACK_HOLE_MASS = 1.0;
const float RS = 2.0 * BLACK_HOLE_MASS;     // Schwarzschild radius
const float PHOTON_SPHERE = 1.5 * RS;        // r = 3.0
const float ISCO = 3.0 * RS;                 // Innermost stable circular orbit

// Integration parameters
const int MAX_STEPS = 500;
const float BASE_STEP_SIZE = 0.06;
const float MAX_DISTANCE = 1000.0;           // Increased significantly
const float HORIZON_EPSILON = 0.02;

// Lensing zone - only use expensive geodesic integration within this radius
// Outside this, spacetime is nearly flat and we can use straight rays
const float LENSING_ZONE = 30.0 * RS;        // Strong lensing within 60 units

// Accretion disk
const float DISK_INNER = ISCO;
const float DISK_OUTER = 25.0 * RS;
const float DISK_HEIGHT = 0.15;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 cartesianToSpherical(vec3 p)
{
    float r = length(p);
    if (r < 0.0001) return vec3(0.0001, PI * 0.5, 0.0);
    
    float theta = acos(clamp(p.y / r, -1.0, 1.0));
    float phi = atan(p.z, p.x);
    
    return vec3(r, theta, phi);
}

vec3 sphericalToCartesian(vec3 sph)
{
    float r = sph.x;
    float theta = sph.y;
    float phi = sph.z;
    
    float sinTheta = sin(theta);
    return vec3(
        r * sinTheta * cos(phi),
        r * cos(theta),
        r * sinTheta * sin(phi)
    );
}

// ============================================================================
// SCENE OBJECTS
// ============================================================================

const int NUM_SPHERES = 3;
const vec4 SPHERES[NUM_SPHERES] = vec4[](
    vec4(80.0, 0.0, 20.0, 5.0),
    vec4(-60.0, 30.0, 50.0, 4.0),
    vec4(20.0, -50.0, 70.0, 6.0)
);

const vec3 SPHERE_COLORS[NUM_SPHERES] = vec3[](
    vec3(1.0, 0.3, 0.1),
    vec3(0.4, 0.6, 1.0),
    vec3(1.0, 0.95, 0.6)
);

const float SPHERE_EMISSION[NUM_SPHERES] = float[](2.0, 3.0, 1.5);

/*
 * Ray-sphere intersection (standard geometric algorithm)
 * 
 * Solves: |rayOrigin + t * rayDir - sphereCenter|² = radius²
 * This is a quadratic equation in t.
 * 
 * Returns: distance t to nearest intersection, or -1 if no hit
 */
float intersectSphere(vec3 ro, vec3 rd, vec3 center, float radius)
{
    vec3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;
    
    if (discriminant < 0.0) return -1.0;
    
    float sqrtD = sqrt(discriminant);
    float t1 = -b - sqrtD;
    float t2 = -b + sqrtD;
    
    // Return nearest positive intersection
    if (t1 > 0.001) return t1;
    if (t2 > 0.001) return t2;
    return -1.0;
}

/*
 * Ray-disk intersection
 * 
 * The disk lies in the y=0 plane, extending from DISK_INNER to DISK_OUTER
 */
float intersectDisk(vec3 ro, vec3 rd, out float diskR, out float diskAngle)
{
    // Find where ray crosses y=0 plane
    if (abs(rd.y) < 0.0001) return -1.0;  // Ray parallel to disk
    
    float t = -ro.y / rd.y;
    if (t < 0.001) return -1.0;  // Intersection behind ray
    
    vec3 hitPoint = ro + rd * t;
    diskR = length(hitPoint.xz);
    
    if (diskR < DISK_INNER || diskR > DISK_OUTER) return -1.0;
    
    diskAngle = atan(hitPoint.z, hitPoint.x);
    return t;
}

vec3 shadeSphere(vec3 hitPoint, vec3 normal, vec3 baseColor, float emission)
{
    vec3 viewDir = normalize(cameraPos - hitPoint);
    float rim = 1.0 - max(0.0, dot(normal, viewDir));
    float limbDarkening = 1.0 - rim * rim * 0.5;
    return baseColor * emission * limbDarkening;
}

// ============================================================================
// ACCRETION DISK
// ============================================================================

vec3 getDiskColor(float radius, float angle)
{
    float normR = (radius - DISK_INNER) / (DISK_OUTER - DISK_INNER);
    float temp = pow(1.0 - normR, 0.75);
    
    vec3 hotColor = vec3(0.8, 0.9, 1.0);
    vec3 warmColor = vec3(1.0, 0.8, 0.4);
    vec3 coolColor = vec3(1.0, 0.4, 0.1);
    
    vec3 diskColor;
    if (temp > 0.5) {
        diskColor = mix(warmColor, hotColor, (temp - 0.5) * 2.0);
    } else {
        diskColor = mix(coolColor, warmColor, temp * 2.0);
    }
    
    // Doppler effect
    float velocity = sqrt(RS / (2.0 * radius));
    float dopplerFactor = sin(angle + time * 0.3) * velocity;
    float dopplerBoost = pow(1.0 + dopplerFactor * 2.0, 3.0);
    dopplerBoost = clamp(dopplerBoost, 0.3, 3.0);
    
    // Gravitational redshift
    float gravRedshift = sqrt(max(0.1, 1.0 - RS / radius));
    
    diskColor *= dopplerBoost * gravRedshift;
    
    // Turbulent structure
    float noise1 = hash(vec2(angle * 20.0 + time * 0.1, radius * 5.0));
    float noise2 = hash(vec2(angle * 8.0 - time * 0.05, radius * 2.0));
    diskColor *= 0.7 + 0.3 * noise1 * noise2;
    
    float brightness = pow(temp, 0.5) * 4.0 + 0.5;
    return diskColor * brightness;
}

// ============================================================================
// STARFIELD
// ============================================================================

vec3 getStarfield(vec3 rd)
{
    vec3 color = vec3(0.0);
    
    float theta = atan(rd.z, rd.x);
    float phi = asin(clamp(rd.y, -1.0, 1.0));
    
    for (int layer = 0; layer < 4; layer++)
    {
        float scale = 30.0 + float(layer) * 20.0;
        vec2 starCoord = vec2(theta, phi) * scale;
        vec2 gridId = floor(starCoord);
        vec2 gridUV = fract(starCoord) - 0.5;
        
        float starRand = hash(gridId + float(layer) * 137.0);
        
        if (starRand > 0.82)
        {
            vec2 offset = vec2(
                hash(gridId * 2.1) - 0.5,
                hash(gridId * 3.7) - 0.5
            ) * 0.6;
            
            float dist = length(gridUV - offset);
            float brightness = (starRand - 0.82) / 0.18;
            brightness = pow(brightness, 1.5) * 2.5;
            
            float starSize = 0.015 + brightness * 0.025;
            float star = smoothstep(starSize, 0.0, dist);
            
            float colorTemp = hash(gridId * 5.3);
            vec3 starColor = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.9, 0.7), colorTemp);
            
            color += starColor * star * brightness;
        }
    }
    
    float galaxyNoise = hash(vec2(theta * 3.0, phi * 3.0));
    color += vec3(0.015, 0.01, 0.025) * (0.5 + galaxyNoise * 0.5);
    
    return color;
}

// ============================================================================
// GEODESIC INTEGRATION
// ============================================================================

void geodesicDerivatives(vec3 pos, vec3 momentum, out vec3 dPos, out vec3 dMom)
{
    float r = pos.x;
    float theta = pos.y;
    
    float p_r = momentum.x;
    float p_theta = momentum.y;
    float p_phi = momentum.z;
    
    float f = max(1.0 - RS / r, 0.001);
    
    float r2 = r * r;
    float r3 = r2 * r;
    float sinTheta = sin(theta);
    float cosTheta = cos(theta);
    float sin2Theta = max(sinTheta * sinTheta, 0.0001);
    
    dPos.x = f * p_r;
    dPos.y = p_theta / r2;
    dPos.z = p_phi / (r2 * sin2Theta);
    
    float dp_r = -RS / (2.0 * r2) * p_r * p_r / f;
    dp_r += (p_theta * p_theta + p_phi * p_phi / sin2Theta) * f / r3;
    dMom.x = dp_r;
    dMom.y = cosTheta * p_phi * p_phi / (r2 * sin2Theta * sinTheta);
    dMom.z = 0.0;
}

void rk4Step(inout vec3 pos, inout vec3 momentum, float h)
{
    vec3 dPos1, dMom1, dPos2, dMom2, dPos3, dMom3, dPos4, dMom4;
    
    geodesicDerivatives(pos, momentum, dPos1, dMom1);
    
    vec3 pos2 = pos + 0.5 * h * dPos1;
    vec3 mom2 = momentum + 0.5 * h * dMom1;
    pos2.x = max(pos2.x, RS * 0.5);
    geodesicDerivatives(pos2, mom2, dPos2, dMom2);
    
    vec3 pos3 = pos + 0.5 * h * dPos2;
    vec3 mom3 = momentum + 0.5 * h * dMom2;
    pos3.x = max(pos3.x, RS * 0.5);
    geodesicDerivatives(pos3, mom3, dPos3, dMom3);
    
    vec3 pos4 = pos + h * dPos3;
    vec3 mom4 = momentum + h * dMom3;
    pos4.x = max(pos4.x, RS * 0.5);
    geodesicDerivatives(pos4, mom4, dPos4, dMom4);
    
    pos += (h / 6.0) * (dPos1 + 2.0 * dPos2 + 2.0 * dPos3 + dPos4);
    momentum += (h / 6.0) * (dMom1 + 2.0 * dMom2 + 2.0 * dMom3 + dMom4);
    
    pos.x = max(pos.x, RS * 0.1);
    pos.y = clamp(pos.y, 0.001, PI - 0.001);
    if (pos.z > PI) pos.z -= TWO_PI;
    if (pos.z < -PI) pos.z += TWO_PI;
}

// ============================================================================
// CAMERA
// ============================================================================

mat3 buildCamera(vec3 position, vec3 target, vec3 worldUp)
{
    vec3 forward = normalize(target - position);
    vec3 right = normalize(cross(forward, worldUp));
    vec3 up = cross(right, forward);
    return mat3(right, up, forward);
}

// ============================================================================
// MAIN
// ============================================================================

void main()
{
    vec2 uv = (gl_FragCoord.xy - 0.5 * resolution) / resolution.y;
    
    // Camera setup
    vec3 worldUp = vec3(0.0, 1.0, 0.0);
    mat3 camera = buildCamera(cameraPos, cameraTarget, worldUp);
    
    float fovScale = tan(radians(cameraFov) * 0.5);
    vec3 rayDir = camera * normalize(vec3(uv * fovScale, 1.0));
    
    vec3 rayOrigin = cameraPos;
    vec3 finalColor = vec3(0.0);
    
    // ========================================================================
    // PHASE 1: Check if ray passes near the black hole (needs geodesic tracing)
    // ========================================================================
    
    /*
     * Calculate closest approach to black hole for this ray
     * 
     * For a ray: P(t) = rayOrigin + t * rayDir
     * Closest point to origin: t = -dot(rayOrigin, rayDir)
     * Distance at closest point: |rayOrigin + t * rayDir|
     * 
     * If this distance > LENSING_ZONE, the ray won't be significantly bent,
     * so we can use fast straight-line intersection tests.
     */
    float tClosest = -dot(rayOrigin, rayDir);
    vec3 closestPoint = rayOrigin + max(tClosest, 0.0) * rayDir;
    float closestDist = length(closestPoint);
    
    bool needsGeodesic = closestDist < LENSING_ZONE;
    
    // ========================================================================
    // PHASE 2: Direct intersection tests (fast path for rays far from BH)
    // ========================================================================
    
    float nearestHit = 1e10;
    int hitType = 0;        // 0=none, 1=sphere, 2=disk, 3=black hole, 4=background
    int hitSphereIdx = -1;
    float hitDiskR, hitDiskAngle;
    
    // Always check direct black hole intersection
    float tBH = intersectSphere(rayOrigin, rayDir, BLACK_HOLE_POS, RS);
    if (tBH > 0.0 && tBH < nearestHit)
    {
        nearestHit = tBH;
        hitType = 3;
    }
    
    // Check direct sphere intersections
    for (int i = 0; i < NUM_SPHERES; i++)
    {
        float t = intersectSphere(rayOrigin, rayDir, SPHERES[i].xyz, SPHERES[i].w);
        if (t > 0.0 && t < nearestHit)
        {
            nearestHit = t;
            hitType = 1;
            hitSphereIdx = i;
        }
    }
    
    // Check direct disk intersection
    float diskR, diskAngle;
    float tDisk = intersectDisk(rayOrigin, rayDir, diskR, diskAngle);
    if (tDisk > 0.0 && tDisk < nearestHit)
    {
        nearestHit = tDisk;
        hitType = 2;
        hitDiskR = diskR;
        hitDiskAngle = diskAngle;
    }
    
    // ========================================================================
    // PHASE 3: If ray passes near black hole, do full geodesic integration
    // ========================================================================
    
    vec3 prevCartesian = rayOrigin;

    if (needsGeodesic)
    {
        // Initialize spherical coordinates
        vec3 relativePos = rayOrigin - BLACK_HOLE_POS;
        vec3 sphericalPos = cartesianToSpherical(relativePos);
        
        float r = sphericalPos.x;
        float theta = sphericalPos.y;
        float phi = sphericalPos.z;
        
        // Spherical basis vectors
        vec3 e_r = normalize(relativePos);
        vec3 e_theta = vec3(cos(theta) * cos(phi), -sin(theta), cos(theta) * sin(phi));
        vec3 e_phi = vec3(-sin(phi), 0.0, cos(phi));
        
        // Initial momentum
        float p_r = dot(rayDir, e_r);
        float p_theta = dot(rayDir, e_theta) * r;
        float p_phi = dot(rayDir, e_phi) * r * sin(theta);
        vec3 momentum = vec3(p_r, p_theta, p_phi);
        
        prevCartesian = relativePos;
        
        for (int step = 0; step < MAX_STEPS; step++)
        {
            float currentR = sphericalPos.x;
            
            // Hit event horizon
            if (currentR < RS + HORIZON_EPSILON)
            {
                hitType = 3;
                break;
            }
            
            // Escaped lensing zone - switch to direct calculation
            if (currentR > LENSING_ZONE && sphericalPos.x > r)  // Moving away
            {
                // Get current direction and do direct intersection from here
                vec3 currentPos = sphericalToCartesian(sphericalPos);
                vec3 currentDir = normalize(currentPos - prevCartesian);
                
                // Check spheres from current position
                for (int i = 0; i < NUM_SPHERES; i++)
                {
                    float t = intersectSphere(currentPos, currentDir, SPHERES[i].xyz, SPHERES[i].w);
                    if (t > 0.0)
                    {
                        hitType = 1;
                        hitSphereIdx = i;
                        nearestHit = t;
                        // Update hit point for shading
                        prevCartesian = currentPos;
                        rayDir = currentDir;
                        break;
                    }
                }
                
                if (hitType == 0)
                {
                    // Check disk
                    float dr, da;
                    float td = intersectDisk(currentPos, currentDir, dr, da);
                    if (td > 0.0)
                    {
                        hitType = 2;
                        hitDiskR = dr;
                        hitDiskAngle = da;
                    }
                    else
                    {
                        // Background
                        hitType = 4;
                        rayDir = currentDir;  // Use bent direction for background
                    }
                }
                break;
            }
            
            // Continue geodesic integration
            vec3 currentCartesian = sphericalToCartesian(sphericalPos);
            
            // Check sphere intersections along geodesic segment
            vec3 segmentDir = currentCartesian - prevCartesian;
            float segmentLen = length(segmentDir);
            if (segmentLen > 0.001)
            {
                segmentDir /= segmentLen;
                
                for (int i = 0; i < NUM_SPHERES; i++)
                {
                    float t = intersectSphere(prevCartesian, segmentDir, SPHERES[i].xyz, SPHERES[i].w);
                    if (t > 0.0 && t < segmentLen)
                    {
                        hitType = 1;
                        hitSphereIdx = i;
                        nearestHit = t;
                        rayDir = segmentDir;
                        // Use prevCartesian as ray origin for hit calculation
                        break;
                    }
                }
                
                if (hitType != 0) break;
                
                // Check disk crossing
                if (prevCartesian.y * currentCartesian.y <= 0.0)
                {
                    float t = abs(prevCartesian.y) / (abs(prevCartesian.y) + abs(currentCartesian.y) + 0.0001);
                    vec3 crossPoint = mix(prevCartesian, currentCartesian, t);
                    float cr = length(crossPoint.xz);
                    
                    if (cr >= DISK_INNER && cr <= DISK_OUTER)
                    {
                        hitType = 2;
                        hitDiskR = cr;
                        hitDiskAngle = atan(crossPoint.z, crossPoint.x);
                        break;
                    }
                }
            }
            
            prevCartesian = currentCartesian;
            
            // Adaptive step size
            float adaptiveStep = BASE_STEP_SIZE * (0.5 + currentR / (4.0 * RS));
            adaptiveStep = clamp(adaptiveStep, 0.02, 0.3);
            
            rk4Step(sphericalPos, momentum, adaptiveStep);
        }
        
        // If we finished the loop without hitting anything
        if (hitType == 0)
        {
            hitType = 4;  // Background
            // Use final direction from geodesic
            vec3 finalDir = sphericalToCartesian(vec3(1.0, sphericalPos.y, sphericalPos.z));
            rayDir = normalize(finalDir);
        }
    }
    else
    {
        // Ray doesn't pass near black hole - use direct test results
        if (hitType == 0)
        {
            hitType = 4;  // Background (no direct hits)
        }
    }
    
    // ========================================================================
    // PHASE 4: Shade based on hit type
    // ========================================================================
    
    if (hitType == 1)  // Sphere
    {
        vec3 hitPoint = (needsGeodesic ? prevCartesian : rayOrigin) + rayDir * nearestHit;
        vec3 normal = normalize(hitPoint - SPHERES[hitSphereIdx].xyz);
        finalColor = shadeSphere(hitPoint, normal, SPHERE_COLORS[hitSphereIdx], SPHERE_EMISSION[hitSphereIdx]);
    }
    else if (hitType == 2)  // Disk
    {
        finalColor = getDiskColor(hitDiskR, hitDiskAngle);
    }
    else if (hitType == 3)  // Black hole
    {
        finalColor = vec3(0.0);
    }
    else  // Background (hitType == 4)
    {
        finalColor = getStarfield(rayDir);
    }
    
    // ========================================================================
    // Post-processing
    // ========================================================================
    
    // Tone mapping
    finalColor = finalColor / (finalColor + vec3(1.0));
    
    // Gamma correction
    finalColor = pow(finalColor, vec3(1.0 / 2.2));
    
    // Vignette
    float vignette = 1.0 - length(uv) * 0.3;
    finalColor *= vignette;
    
    FragColor = vec4(finalColor, 1.0);
}
