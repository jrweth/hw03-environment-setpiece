#version 300 es
precision highp float;

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

const vec3 sunPosition = vec3(100.0,100.0,0.0);
const float distanceThreshold = 0.001;
const int numObjects = 2;

vec3 v3Up = vec3(0.0, 1.0, 0.0);
vec3 v3Ref = vec3(0.0, 0.0, 0.0);
vec3 v3Eye = vec3(0.0, 0.5, 1.5);
vec2 v2ScreenPos;

struct sdfParams {
    int sdfType;
    vec3 center;
    float radius;
    vec3 color;
    int extraIntVal;
    int extraVec3Val;
};

sdfParams sdfs[numObjects];


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Utilities ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
vec2 pixelToScreenPos(vec2 pixelPos) {
    return (2.0 * vec2(pixelPos.x / iResolution.x, pixelPos.y/iResolution.y)) - vec2(1.0);
}

vec2 screenToPixelPos(vec2 pixelPos) {
    return iResolution.xy * (pixelPos + vec2(1.0)) / 2.0;
}


////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SDF Utilities ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float sdfSubtract( float d1, float d2 ) { return max(-d1,d2); }

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// PETALS  ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float sdfEllipsoid( in vec3 p, in vec3 r )
{
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

float flatPetal( vec3 p, vec3 b, float r )
{
  b.y = b.y * smoothstep(0.0, 1.0, clamp(0.0, 1.0, b.x-p.x));
  vec3 d = abs(p) - b;
  return length(max(d,0.0)) - r
         + min(
            max(d.x,max(d.y,d.z)),0.0); // remove this line for an only partially signed sdf
}

float petalSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    return flatPetal(p, vec3(1.0,0.2,0.01), 0.0);
    vec3 r = vec3(params.radius, params.radius/2.0, params.radius/3.0);
    vec3 p2 = p + vec3(0.0, 0.0,-0.4);

    return sdfSubtract(sdfEllipsoid(p,r), sdfEllipsoid(p2,r));//length(p) - params.radius;

}



////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SEEDS ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float seedHeightOffset(sdfParams params, vec3 point) {
    vec3 p = point - params.center;

    float g = 100.0;
    float dist = (0.5 - length(point.xy)) * 2.0;
    mat3 rot = mat3(cos(-dist), -sin(-dist), 0.0,
                    sin(-dist), cos(dist),  0.0,
                    0.0,       0.0,        1.0);
    p = rot * p;
    return (2.0 + abs(sin(p.y * g))+abs(cos(p.x * g)))/4.0;
}
float hemisphere(sdfParams params, vec3 point) {
    return -point.z-0.94;
}

float seedsSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;

    float height = seedHeightOffset(params, point) / 25.0;

    return max(-hemisphere(params, point), length(p) - (params.radius + height));
}

vec4 seedColor(sdfParams params, vec3 point) {
    float height = seedHeightOffset(params, point);
    return vec4(vec3(1.0, 1.0, 0.0) * height, 1.0);
}


vec3 sphereNormal(sdfParams params, vec3 point) {
    return normalize(point - params.center);
}





////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Ray Functions ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float rayMarch(sdfParams params, vec3 ray, int maxIterations, float maxT) {
    float t = 0.0;
    vec3 rayPos;
    float distance;
    int iterations = 0;
    while (t < maxT && iterations <= maxIterations) {

        rayPos = v3Eye + t * ray;

        //get distance from point on the ray to the object
        switch(params.sdfType) {
            case 0: distance = seedsSDF (params, rayPos); break;
            case 1: distance = petalSDF (params, rayPos); break;
            default: distance = maxT;
        }

        //if distance < some epsilon we are done
        if(distance < distanceThreshold) {
            return t;
        }

        t += distance;
        iterations++;
    }
    if(iterations >= maxIterations) return maxT;

    return t;
}



//  Function to calculate the ray based upn the up, eye, ref, aspect ration and screen position
vec3 getRay(vec3 up, vec3 eye, vec3 ref, float aspect, vec2 screenPos) {
    vec3 right = normalize(cross( up - eye, up));  //right vector
    float len = length(ref - eye);   //length
    vec3 vert = up * len; //normally this would also be based upon FOV tan(FOV) but we are constraing to the box
    vec3 horiz = right * aspect * len; //normally this would also be based upon FOV tan(FOV) but we are constraining to the box
    vec3 point = ref + (screenPos.x * horiz) + screenPos.y * vert;

    //calculate the ray
    return normalize(point - eye);

}



vec3 getNormalFromRays(sdfParams params, vec2 fragCoord) {
    float aspect = iResolution.x / iResolution.y;
    //calculate the points for 4 surrounding rays
    vec3 ray1 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2(-0.001,  0.0));
    vec3 ray2 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.001,  0.0));
    vec3 ray3 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.00, -0.001));
    vec3 ray4 = getRay(v3Up, v3Eye, v3Ref, aspect, fragCoord + vec2( 0.00,  0.001));

    float t1 =  rayMarch(params, ray1, 100, 100.0);
    float t2 =  rayMarch(params, ray2, 100, 100.0);
    float t3 =  rayMarch(params, ray3, 100, 100.0);
    float t4 =  rayMarch(params, ray4, 100, 100.0);

    vec3 p1 = v3Eye + ray1 * t1;
    vec3 p2 = v3Eye + ray2 * t2;
    vec3 p3 = v3Eye + ray3 * t3;
    vec3 p4 = v3Eye + ray4 * t4;

    return normalize(cross(p4-p3, p1-p2));
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



vec4 getTextureColor(sdfParams params, vec3 point, vec2 fragCoord) {
    vec3 normal;
    vec3 lightDirection = normalize(sunPosition - point);
    float intensity;

    switch(params.sdfType) {
        ///flat lambert
        case 0:
            normal = getNormal(params, point, fragCoord);
            intensity = dot(normal, lightDirection) * 0.9;
            return seedColor(params, point);

        case 1:
            normal = getNormal(params, point, fragCoord);
            intensity = dot(normal, lightDirection) * 0.5 + 0.5;
            return vec4(params.color*intensity, 1.0);
    }
    return vec4(params.color, 1.0);
}




////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Initilaization ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
void initSdfs() {
    //earth
    float pi = 3.14159;

    //seeds
    sdfs[0].sdfType = 0;
    sdfs[0].center = vec3(-1.0,0,0);
    sdfs[0].radius = 1.0;
    sdfs[0].color = vec3(0.0, 0.0, 1.0);


    //petals
    sdfs[1].sdfType = 1;
    sdfs[1].center = vec3(0.5,0,0);
    sdfs[1].radius = 1.0;
    sdfs[1].color = vec3(0.0, 0.0, 1.0);

}



void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);

    v2ScreenPos = pixelToScreenPos(fragCoord);
    //set up
    initSdfs();
    vec3 ray= getRay(v3Up, v3Eye, v3Ref, iResolution.x/iResolution.y, v2ScreenPos) ;

    float maxT = 100.0;
    int maxIterations = 100;
    float t;

     for(int i = 0; i < numObjects; i++) {
        t = rayMarch(sdfs[i], ray, maxIterations, maxT);
        if( t < maxT) {
            //get the diffuse term
            fragColor = getTextureColor(sdfs[i], v3Eye + ray*t, v2ScreenPos);
            maxT = t;
        }
    }

}

void main() {
    //need to convert to pixel dimesions
    vec2 fragCoord = screenToPixelPos(fs_Pos);
    mainImage(out_Col, fragCoord);
}

