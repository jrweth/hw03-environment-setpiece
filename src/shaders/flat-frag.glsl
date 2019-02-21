#version 300 es
precision highp float;

uniform vec3      u_Eye;
uniform vec3      iResolution;           // viewport resolution (in pixels)
uniform float     iTime;                 // shader playback time (in seconds)
uniform float     iTimeDelta;            // render time (in seconds)
uniform int       iFrame;                // shader playback frame
uniform float     iChannelTime[4];       // channel playback time (in seconds)
uniform vec3      iChannelResolution[4]; // channel resolution (in pixels)
uniform vec4      iMouse;                // mouse pixel coords. xy: current (if MLB down), zw: click

//uniform samplerXX iChannel0..3;          // input channel. XX = 2D/Cube
uniform vec4      iDate;                 // (year, month, day, time in seconds)

in vec2 fs_Pos;
out vec4 out_Col;

const float sceneRadius = 100.0;
const float distanceThreshold = 0.001;
const int numFlowers = 5;
const int numObjects = 21; //should be num flowers * 4 + 1
const float timeScale = 0.005;

const float sunOrbit = 80.0;
const float horizon = 0.0;
const float midSky = 15.0;

float sunSpeed = 9.0;
float night;
float noon;
float sunset;
float dawn;
float camChange;


vec3 v3Up = vec3(0.0, 1.0, 0.0);
vec3 v3Ref = vec3(0.0, 0.0, 0.0);
vec3 v3Eye = vec3(0.0, 0.0, 4.0);
vec3 sunPosition = vec3(5.0,10.0,10.0);

// The larger the DISTORTION, the smaller the glow
const float DISTORTION = 12.0;
// The higher GLOW is, the smaller the glow of the subsurface scattering
const float GLOW = 1.0;
// The higher the BSSRDF_SCALE, the brighter the scattered light
const float BSSRDF_SCALE = 1.0;
// Boost the shadowed areas in the subsurface glow with this
const float AMBIENT = 10.0;
// Toggle this to affect how easily the subsurface glow propagates through an object
#define ATTENUATION 0

bool shaderToy = true;


vec3 mainRay;
vec2 v2ScreenPos;
float hour;
float sunBloomDistance;        //the distance of the ray from teh sun in the sky
float pi = 3.14159;
struct sdfParams {
    int sdfType;
    vec3 center;
    float radius;
    vec3 color;
    int extraIntVal;
    vec3 extraVec3Val;
    mat3 rotation;
};


sdfParams sdfs[numObjects];

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Random/Noise Functions ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float random1( vec2 p , vec2 seed) {
  return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}

float random1( vec3 p , vec3 seed) {
  return fract(sin(dot(p + seed, vec3(987.654, 123.456, 531.975))) * 85734.3545);
}

vec2 random2( vec2 p , vec2 seed) {
  return fract(sin(vec2(dot(p + seed, vec2(311.7, 127.1)), dot(p + seed, vec2(269.5, 183.3)))) * 85734.3545);
}



float interpNoiseRandom2to1(vec2 p, vec2 seed) {
    float fractX = fract(p.x);
    float x1 = floor(p.x);
    float x2 = x1 + 1.0;

    float fractY = fract(p.y);
    float y1 = floor(p.y);
    float y2 = y1 + 1.0;

    float v1 = random1(vec2(x1, y1), seed);
    float v2 = random1(vec2(x2, y1), seed);
    float v3 = random1(vec2(x1, y2), seed);
    float v4 = random1(vec2(x2, y2), seed);

    float i1 = mix(v1, v2, fractX);
    float i2 = mix(v3, v4, fractX);

//    return smoothstep(i1, i2, fractY);
    return mix(i1, i2, fractY);

}

float fbm2to1(vec2 p, vec2 seed) {
    float total  = 0.0;
    float persistence = 0.5;
    float octaves = 8.0;

    for(float i = 0.0; i < octaves; i++) {
        float freq = pow(2.0, i);
        float amp = pow(persistence, i+1.0);
        total = total + interpNoiseRandom2to1(p * freq, seed) * amp;
    }
    return total;
}

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Utilities ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
vec2 pixelToScreenPos(vec2 pixelPos) {
    return (2.0 * vec2(pixelPos.x / iResolution.x, pixelPos.y/iResolution.y)) - vec2(1.0);
}

vec2 screenToPixelPos(vec2 pixelPos) {
    return iResolution.xy * (pixelPos + vec2(1.0)) / 2.0;
}

//  Function to calculate the ray based upn the up, eye, ref, aspect ration and screen position
vec3 getRay(vec3 up, vec3 eye, vec3 ref, float aspect, vec2 screenPos) {
    vec3 right = normalize(cross( up - eye, up));  //right vector
    float len = length(ref - eye);   //length
    vec3 vert = up * len * 0.5; //normally this would also be based upon FOV tan(FOV) but we are constraing to the box
    vec3 horiz = right * aspect * len * 0.5; //normally this would also be based upon FOV tan(FOV) but we are constraining to the box
    vec3 point = ref + (screenPos.x * horiz) + screenPos.y * vert;

    //calculate the ray
    return normalize(point - eye);

}

mat3 rotateX(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat3(1.0, 0.0, 0.0,
                0.0, c, -s,
                0.0, s, c);
}


mat3 rotateY(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat3(c, 0.0, -s,
                0.0, 1.0, 0.0,
                s, 0.0, c);
}

mat3 rotateZ(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat3(c, -s, 0.0,
                s, c, 0.0,
                0.0, 0.0, 1.0);
}







////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SDF Utilities ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float sdfSubtract( float d1, float d2 ) { return max(-d1,d2); }

float sdfUnion( float d1, float d2 ) { return min(d1,d2); }

float sdfEllipsoid( in vec3 p, in vec3 r )
{
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

//adjust y to bend around around z axis
vec3 opCheapBendYZ(in vec3 p )
{
    const float k = 1.0; // or some other amount
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c,-s,s,c);
    vec2 xz = m*p.xz;
    vec3  q = vec3(xz[0], p.y,xz[1]);
    return q;
}

//adjust z to bend around x axis
vec3 opCheapBendZX(in vec3 p )
{
    const float k = 10.0; // or some other amount
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c, -s, s, c);
    vec3  q = vec3(p.x, m*p.yz);
    return q;
}

//adjust z to bend around x axis
vec3 opCheapBendZY(in vec3 p )
{
    const float k = 10.0; // or some other amount
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c, -s, s, c);
    vec2 xz = m*p.xz;
    vec3  q = vec3(xz.x,p.y, xz.y);
    return q;
}



////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Background  ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float horizonHeight() {
    vec2 adjustedPos = vec2(v2ScreenPos.x - camChange*0.5, 0.0);
    float displacement = fbm2to1(adjustedPos, vec2(3.33, 3.2343))*1.3 - .75;
    return displacement;
}

vec3 skyColor() {

      vec3 color;
      vec3 horizonColor;
      vec3 midColor;
      vec3 zenithColor;

      vec3 nightHorizon = vec3(0.107, 0.127, 0.468);
      vec3 nightMid = vec3(0.030, 0.031, 0.3);
      vec3 nightZenith = vec3(0.002, 0.005, 0.2);

      vec3 noonHorizon = vec3(0.137, 0.227, 0.568);
      vec3 noonMid = vec3(0.050, 0.071, 0.7);
      vec3 noonZenith = vec3(0.007, 0.009, 1.0);

      vec3 sunsetHorizon = vec3(0.823, 0.325, 0.227);
      vec3 sunsetMid = vec3(0.909, 0.450, 0.262);
      vec3 sunsetZenith = vec3(0.007, 0.009, 0.3);

      vec3 dawnHorizon = vec3(0.323, 0.225, 0.127);
      vec3 dawnMid = vec3(0.209, 0.150, 0.262);
      vec3 dawnZenith = vec3(0.007, 0.009, 0.3);
      float blend;


      horizonColor = nightHorizon  * night
                   + dawnHorizon   * dawn
                   + noonHorizon   * noon
                   + sunsetHorizon * sunset;

      midColor     = nightMid  * night
                   + dawnMid   * dawn
                   + noonMid   * noon
                   + sunsetMid * sunset;

      zenithColor  = nightZenith  * night
                   + dawnZenith   * dawn
                   + noonZenith  * noon
                   + sunsetZenith* sunset;



      if(mainRay.y < 0.25) {
          color = mix(horizonColor, midColor, mainRay.y * 4.0);
      }
      else {
          color = mix(midColor, zenithColor, (mainRay.y - 0.25) *1.333);
      }
      return color;

}


vec3 landColor() {

    vec2 adjustedPos = v2ScreenPos;
    adjustedPos.x -= camChange*0.5;
    float noise = fbm2to1(adjustedPos*70.0, vec2(1.0,2.0));
    float noise2= fbm2to1(adjustedPos*5.0, vec2(1.0,2.0));
    vec3 grass = vec3(0.180, 0.356, 0.039);
    vec3 dirt = vec3(0.878, 0.733, 0.141);
    vec3 base = mix(grass, dirt, noise) * noise2;

    float noonIntensity = 1.5;
    float sunsetIntensity = 0.5;
    float nightIntensity = 0.03;
    float dawnIntensity = 0.5;


    return noise * base * (
        noon * noonIntensity
        + sunset * sunsetIntensity
        + night * nightIntensity
        + dawn * dawnIntensity
    );

}

vec3 backgroundColor() {


    if(v2ScreenPos.y < horizonHeight()) {
        return landColor();
    }
    return skyColor();

}

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SUN  ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float sunSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    return length(p) - params.radius;
}

vec3 sunColor(sdfParams params, vec3 point) {
    if(v2ScreenPos.y < horizonHeight()) {
        return backgroundColor();
    }
    return params.color;
}


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// PETALS  ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float flatPetal( vec3 p, vec3 b, float r )
{
  b.y = b.y * smoothstep(0.0, 0.4, clamp(0.0, 1.0, b.x-p.x));
  vec3 d = abs(p) - b;
  return length(max(d,0.0)) - r
         + min(
            max(d.x,max(d.y,d.z)),0.0); // remove this line for an only partially signed sdf
}

float petalSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    p = params.rotation * p;

    ///add some noise to the y vector
    p.y += sin(p.x*4.0 + (random1(params.center.xy, params.center.xz) -0.5)*4.0) * 0.05;
    vec3 q = p;
    q = opCheapBendZX(p);
    //q = opCheapBendZY(q);
    return flatPetal(q, params.extraVec3Val, 0.03);

}

float petalsSDF(sdfParams params, vec3 point) {

    vec3 p = params.rotation * (point - params.center);
    float petalMin = 9999.0;
    int numPetals = 12;
    sdfParams params2 = params;

    for(int i = 0; i < numPetals; i++) {
       //get random value for adjusting placement/length
       float adjust = random1(vec3(float(i), params.center.zy), vec3(1,2,3)) - 0.5;
       float angle = float(i) * 2.0*pi/float(numPetals) + adjust*0.15;
       params2.center.x = cos(angle)*0.7;
       params2.center.y = sin(angle)*0.7;
       params2.center.z = 0.0;
       params2.rotation = rotateZ(angle);
       //adjust the petal length
       params2.extraVec3Val.x += (random1(params2.center, vec3(1,2,3))-0.5)*0.2;
       params2.extraVec3Val.y += (random1(params2.center, vec3(1,2,3))-0.5)*0.04;
       petalMin = min(petalMin, petalSDF(params2, p));
    }
    return petalMin;

}


vec3 petalColor(sdfParams params, vec3 point) {
    vec3 color;
    vec3 color1 = vec3(0.384, 0.082, 0.047);
    vec3 color2 = vec3(0.635, 0.184, 0.035);
    vec3 color3 = vec3(0.996, 0.862, 0.141);
    vec3 color4 = vec3(1.0, 1.0, 0.4);


    vec2 p = normalize(point.xy - params.center.xy);
    float percent = (length(point - params.center) - 0.5) - random1(params.center.xy, vec2(1.0, 2.0)) * 0.2;// / params.extraVec3Val.x;
    vec3 stripedColor = mix(color2, color4, abs(sin(400.0*acos(p.x)/pi)));
    if(percent < 0.1) {
        color = mix(color1, color2, percent * 10.0);
    }
    else if(percent < 0.2) {
        color = mix(color2, color3, (percent - 0.1) * 10.0);
        color = mix(color, stripedColor, pow(percent, 2.0));
    }
    else if(percent < 0.4)  {
        color = mix(color3, color4, (percent - 0.2) * 5.0);
        color = mix(color, stripedColor, pow(percent, 2.0));
    }
    else {
        color = color4;
    }

    return  color;
}





////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SEEDS ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float seedHeightOffset(sdfParams params, vec3 point) {

    float g = 80.0;
    float dist = (0.5 - length(point.xy)) * 2.0;
    mat3 rot = mat3(cos(-dist), -sin(-dist), 0.0,
                    sin(-dist), cos(dist),  0.0,
                    0.0,       0.0,        1.0);
    point = rot * point;
    return (2.0 + abs(sin(point.y * g))+abs(cos(point.x * g)))/4.0;
}

float hemisphere(sdfParams params, vec3 point) {
    return point.z-0.95;
}

float seedsSDF(sdfParams params, vec3 point) {
    vec3 p = params.rotation * (point - params.center);
    //vec3 p = point - params.center;
    p.z += 0.83;

    float height = seedHeightOffset(params, p) / 25.0;

    return max(-hemisphere(params, p), length(p) - (params.radius + height));
}



vec3 sphereNormal(sdfParams params, vec3 point) {
    return normalize(point - params.center);
}


vec3 seedColor(sdfParams params, vec3 point) {
    vec3 p = params.rotation * (point - params.center);
    //vec3 p = point - params.center;
    p.z += 0.95;
    float height = seedHeightOffset(params, p);
    return vec3(1.0, 1.0, 0.0); //* height;
}

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Stem ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float stemSDF(sdfParams params, vec3 point) {
   vec3 p = params.rotation * (point - params.center);

   //adjust a bit
   p.x +=  params.radius * sin(p.y ) * 2.0;

   vec2 np = normalize(p.xz);

   float displacement = params.radius * abs(cos(np.x * 2.0 * pi));
   return max(p.y, length(p.xz) - params.radius - displacement);

}

vec3 stemColor(sdfParams params, vec3 point) {
    return vec3(0.1, 0.5, 0.1);
}


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Ray Functions ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float objectDistance(sdfParams params, vec3 point, float maxDistance) {
    //get distance from point on the ray to the object
    switch(params.sdfType) {
        case 0: return sunSDF    (params, point);
        case 1: return seedsSDF  (params, point);
        case 2: return petalsSDF (params, point);
        case 3: return stemSDF   (params, point);
    }
    return maxDistance;

}


float rayMarch(
    sdfParams params,
    vec3 ray,
    vec3 origin,
    int maxIterations,
    float minT,
    float maxT,
    out float closestDistance,
    out float closestT
) {
    float t = minT;
    vec3 rayPos;
    float distance;
    int iterations = 0;
    closestDistance = sceneRadius;
    while (t < maxT && iterations <= maxIterations) {

        rayPos = origin + t * ray;

        //get distance from point on the ray to the object
        distance = objectDistance(params, rayPos, maxT);

        if(distance < closestDistance) {
             closestDistance = distance;
             closestT = t;
        }

        //if distance < some epsilon we are done
        if(distance < distanceThreshold) {
            closestDistance = t;
            closestT = t;
            return t;
        }

        t += distance;
        iterations++;
    }
    if(iterations >= maxIterations) return maxT;

    return t;
}



void rayMarchWorld(
    vec3 origin,
    vec3 ray,
    float minT,
    float maxT,
    int excludeSdfIndex,
    int excludeSdfForClosest,
    out float t,
    out float minClosestDistance,
    out float minClosestT,
    out int sdfIndex
) {

    int maxIterations = 100;
    float cDistance;
    float cT;

    t = maxT;
    minClosestDistance = sceneRadius * 2.0;
    sdfParams params;

    for(int i = 0; i < numObjects; i++) {
        if(i == excludeSdfIndex) continue;
        params = sdfs[i];
        float objectT = rayMarch(params, ray, origin, maxIterations, minT, t, cDistance, cT);
        if( objectT < t) { //must have hit an object closer than the previous
            sdfIndex = i;
            t = objectT;
        }
        if(cDistance < minClosestDistance && i != excludeSdfForClosest) {
            minClosestDistance = cDistance;
            minClosestT = cT;
        }
        if(i == 0 && origin == v3Eye) {
            sunBloomDistance = cDistance;
        }
    }
}






vec3 getNormalFromRays(sdfParams params, vec2 fragCoord) {
    float aspect = iResolution.x / iResolution.y;
    float closestDistance;
    float closestT;
    //calculate the points for 4 surrounding rays
    vec3 ray1 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2(-0.001,  0.0));
    vec3 ray2 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.001,  0.0));
    vec3 ray3 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.00, -0.001));
    vec3 ray4 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.00,  0.001));

    float t1 =  rayMarch(params, ray1, v3Eye, 100, 0.0, sceneRadius, closestDistance, closestT);
    float t2 =  rayMarch(params, ray2, v3Eye, 100, 0.0, sceneRadius, closestDistance, closestT);
    float t3 =  rayMarch(params, ray3, v3Eye, 100, 0.0, sceneRadius, closestDistance, closestT);
    float t4 =  rayMarch(params, ray4, v3Eye, 100, 0.0, sceneRadius, closestDistance, closestT);

    vec3 p1 = v3Eye + ray1 * t1;
    vec3 p2 = v3Eye + ray2 * t2;
    vec3 p3 = v3Eye + ray3 * t3;
    vec3 p4 = v3Eye + ray4 * t4;

    return normalize(cross(p4-p3, p1-p2));
}




////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Shadwos   ////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float sunShadow(vec3 point, float k, int sdfIndex) {
    vec3 ray = normalize(sunPosition - point);
    float sunDistance = length(sunPosition - point) / 2.0;
    float minClosestDistance;
    float t;
    float minT = 0.05;
    float minClosestT;
    int shadowingSdfIndex;

    rayMarchWorld(point, ray, minT, sunDistance, -1, -1, t, minClosestDistance, minClosestT, shadowingSdfIndex);
    if( t < sunDistance ) return 0.0;

    if(sdfIndex == 0) return 1.0;


    //add soft shadow
    return k * minClosestDistance / minClosestT;

}



float subsurface(vec3 lightDir, vec3 normal, vec3 viewVec, float thinness) {
    vec3 scatteredLightDir = lightDir + normal * DISTORTION;
    float lightReachingEye = pow(clamp(dot(viewVec, -scatteredLightDir), 0.0, 1.0), GLOW) * BSSRDF_SCALE;
	float totalLight = lightReachingEye;// * thinness;


    return totalLight;
}


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// normal/color operations ////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
vec3 getNormal(sdfParams params, vec3 point, vec2 fragCoord) {
    switch(params.sdfType) {
        case 0: return sphereNormal            (params, point);
        //case 1: return vec3(1.0,1.0,1.0);
        default: return getNormalFromRays      (params, fragCoord);
    }
    return vec3(0.0, 0.1, 0.0);
}


//get the color of the texture at a particular point
vec3 getTextureColor(sdfParams params, vec3 point) {

    switch(params.sdfType) {
        case 0: return sunColor(params, point);
        case 1: return seedColor(params, point);
        case 2: return petalColor(params, point);
        case 3: return stemColor(params, point);
    }
    return params.color;
}


void adjustColorForLights(inout vec3 color, vec3 normal, vec3 point, int sdfIndex) {
    vec3 direction;
    vec3 lightColor;
    vec3 sunDirection = normalize(sunPosition - point);
    vec3 sunColor = vec3(1.5, 1.25, 1.0);
    vec3 skyColor = vec3(0.08,0.10,0.14);
    vec3 indirectColor = vec3(0.04, 0.028, 0.020);


    //get the soft shadow and subsurface amounts
    float shadow = sunShadow(point, 3.0, sdfIndex);
    float sunIntensity;


    if(dot(normal, sunDirection) >= 0.0) {
        sunIntensity = clamp(dot(normal, sunDirection), 0.0, 1.0) * shadow;
    }
    else {
        //get the glow for the petals
        if(sdfs[sdfIndex].sdfType == 2 ) {
            sunIntensity = subsurface(-sunDirection, normal, normalize(point - v3Eye), 0.01);

            //make subsurface only apply in in evening
            sunIntensity = sunIntensity * clamp(-sunPosition.z/sunOrbit, 0.0, 1.0);

            //account for the shadows
            sunIntensity = sunIntensity * shadow;
        }
        else {
            sunIntensity = 0.0;
        }
    }


    //make sun brighter at noon
    sunIntensity = sunIntensity * clamp(sunPosition.y/80.0, 0.0, 1.0);

    //
    float skyIntensity = clamp(0.5 + 0.5*normal.y, 0.0, 1.0);

    //decrease skyintesity at night
    if(hour > 17.0) {
        skyIntensity = clamp(pow((1.0 - (hour - 17.0)/7.0), 4.0), 0.1, 1.0)  * skyIntensity;
    }
    if(hour < 6.0) {
        skyIntensity = clamp(pow((1.0 - (6.0-hour)/6.0), 4.0), 0.1, 1.0)  * skyIntensity;
    }


    float indirectIntensity = clamp(dot(normal, normalize(sunDirection * vec3(-1.0, 0.0, -1.0))), 0.0, 1.0);

    //diminish indrect intensity at noon/midnight
    indirectIntensity = pow(mix(indirectIntensity, 0.0, abs(6.0 - mod(hour, 12.0))/6.0), 3.0);

    //make sun redder at sunrise/sunset
    sunColor.r = max(sunColor.r * 3.0 * (dawn*0.8 + sunset), sunColor.r);
    if(hour < 5.0) {
       sunIntensity = 0.0;
    }

    vec3 intensity = sunIntensity*sunColor
                    + skyIntensity * skyColor
                    + indirectIntensity * indirectColor;


    color = color * intensity;

}





////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Initilaization ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
void initSdfs() {
    //earth
    float pi = 3.14159;

    //sun
    sdfs[0].sdfType = 0;
    sdfs[0].center = sunPosition;
    sdfs[0].radius = 6.0;
    sdfs[0].color = vec3(1.0, 1.0, 0.5);

    sdfs[1].sdfType = 3;
    sdfs[1].center = vec3(0.0, 0.0, 0.0);
    sdfs[1].radius = 0.3;
    sdfs[1].color = vec3(1.0, 1.0, 0.5);

    vec3 flowerCenter;
    mat3 flowerRotation;
    for(int i = 0; i < numFlowers; i++) {
        switch (i) {
            case 0:
                flowerCenter = vec3(0.7, -0.5, 1.0);
                flowerRotation = rotateY(pi/8.0);
                break;
            case 1:
                 flowerCenter = vec3(-2.0, -0.0, -2.0);
                 flowerRotation = rotateY(-pi/6.0);
                break;
            case 2:
                flowerCenter = vec3(-1.1, 2.0, -3.0);
                flowerRotation = rotateY(0.0);
                break;
            case 3:
                flowerCenter = vec3(2.3, 0.0, 0.0);
                flowerRotation = rotateY(pi/5.0);
                break;
            case 4:
                flowerCenter = vec3(-2.3, -0.5, 0.2);
                flowerRotation = rotateY(-pi/4.0);
                break;
        }


        //seeds
        sdfs[i*4 + 1].sdfType = 1;
        sdfs[i*4 + 1].center = flowerCenter;
        sdfs[i*4 + 1].radius = 1.0;
        sdfs[i*4 + 1].color = vec3(0.0, 0.0, 1.0);
        sdfs[i*4 + 1].rotation = flowerRotation;


        //row of petals
        sdfs[i*4 + 2].sdfType = 2;
        sdfs[i*4 + 2].center = flowerCenter;
        sdfs[i*4 + 2].radius = 1.0;
        sdfs[i*4 + 2].color = vec3(1.0, 1.0, 0.0);
        sdfs[i*4 + 2].extraVec3Val = vec3(0.5,0.1,0.005);
        sdfs[i*4 + 2].rotation = flowerRotation;

        //2nd row of petals
        sdfs[i*4 + 3].sdfType = 2;
        sdfs[i*4 + 3].center = flowerCenter + flowerRotation * vec3(0.0, 0.0, -0.1);
        sdfs[i*4 + 3].radius = 1.0;
        sdfs[i*4 + 3].color = vec3(1.0, 1.0, 0.0);
        sdfs[i*4 + 3].extraVec3Val = vec3(0.5,0.1,0.005);
        sdfs[i*4 + 3].rotation = rotateZ(pi/4.0) * flowerRotation;

        //stem
        sdfs[i*4 + 4].sdfType = 3;
        sdfs[i*4 + 4].center = flowerCenter + vec3(0.0, 0.0, -0.2);
        sdfs[i*4 + 4].radius = 0.05;
        sdfs[i*4 + 4].color = vec3(0.0, 0.0, 1.0);
        sdfs[i*4 + 4].rotation = flowerRotation;
    }
}



////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Lighting ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
void initTiming() {
    float time = 372.0;
    //time = 300.0;
    time = iTime;
    hour = mod(6.0 + 12.0 * time * sunSpeed * timeScale / pi, 24.0);
    sunPosition = sunOrbit * vec3(cos(time * sunSpeed *timeScale)/3.9,
                       sin(time * sunSpeed * timeScale),
                       cos(time * sunSpeed * timeScale)/2.0);
    ///night
    if(hour >= 19.0 || hour < 5.0) {
        night  = 1.0;
        dawn   = 0.0;
        noon   = 0.0;
        sunset = 0.0;
   }
   //night to dawn
    if(hour >= 5.0 && hour < 7.0) {
        night  = (7.0 - hour) / 2.0;
        dawn   = (hour - 5.0) / 2.0;
        noon   = 0.0;
        sunset = 0.0;
    }
   //dawn to noo
    if(hour >= 7.0 && hour < 10.0) {
        night  = 0.0;
        dawn   = (10.0 - hour) / 3.0;
        noon   = (hour - 7.0) / 3.0;
        sunset = 0.0;
    }
    //noon
    if(hour >= 10.0 && hour < 15.0) {
        night  = 0.0;
        dawn   = 0.0;
        noon   = 1.0;
        sunset = 0.0;
   }
   //noon to sunset
    if(hour >= 15.0 && hour < 17.0) {
        night  = 0.0;
        dawn   = 0.0;
        noon   = (17.0 - hour) / 2.0;
        sunset = (hour - 15.0) / 2.0;
    }
    //sunset to evening
    if(hour >= 17.0 && hour < 19.0) {
        night  = (hour - 17.0) / 2.0;
        dawn   = 0.0;
        noon   = 0.0;
        sunset = (19.0 - hour) / 2.0;
    }

}





void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    v2ScreenPos = pixelToScreenPos(fragCoord);
    initTiming();


    //adjust camera position
    camChange = smoothstep(0.0, 1.0, abs(12.0-(mod(hour+3.0, 24.0)))/12.0);
    v3Eye.z = 4.0 - camChange;
    v3Eye.x = camChange;

    v3Ref = mix(vec3(0,0,0), vec3(-1.0,0.0,-1.0), camChange *0.5);


    //set up
    initSdfs();

    vec3 normal;
    float minClosestDistance;
    float minClosestT;
    float t;
    int sdfIndex;
    vec3 point;


    mainRay= getRay(v3Up, v3Eye, v3Ref, iResolution.x/iResolution.y, v2ScreenPos) ;
    rayMarchWorld(v3Eye, mainRay, 0.1, sceneRadius, -1, -1, t, minClosestDistance, minClosestT, sdfIndex);
    point = v3Eye + mainRay * t;

    vec3 color = backgroundColor();

    //go get the color
    if(t < sceneRadius) {
        color = getTextureColor(sdfs[sdfIndex], point);
        normal = getNormal(sdfs[sdfIndex], point, v2ScreenPos);
        if(sdfIndex > 0) {
            adjustColorForLights(color, normal, point, sdfIndex);
        }
    }


    //gamma correction
    color = max(color, 0.0);
    color = pow(color, vec3(1.0/2.2));

    if(shaderToy) {
        //get the sun bloom
        float sunClosestDistance;
        float sunT = rayMarch(sdfs[0], mainRay, v3Eye, 100, 0.0, sunOrbit, sunClosestDistance, minClosestT);
        float sunBloom = 0.0;
        if(sunT < sunOrbit || sunClosestDistance < 0.1) {
            sunBloom = 1000.0;
        }
        fragColor = vec4(color, t + sunBloom);
    }
    else {
        fragColor = vec4(color, 1.0);
    }


}

void main() {
    //need to convert to pixel dimesions
    shaderToy = false;
    sunSpeed = 3.0;
    vec2 fragCoord = screenToPixelPos(fs_Pos);
    v3Eye = u_Eye;
    mainImage(out_Col, fragCoord);
}

