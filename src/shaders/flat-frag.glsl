#version 300 es
precision highp float;

uniform vec2 u_Dimensions;
uniform float u_Time;
uniform vec3 iResolution;           // viewport resolution (in pixels)
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
const int numObjects = 1;

vec3 v3Up = vec3(0.0, 1.0, 0.0);
vec3 v3Ref = vec3(0.0, 0.0, 0.0);
vec3 v3Eye = vec3(0.0, 0.0, -10.0);
vec3 v3ScreenPos;

struct sdfParams {
    int sdfType;
    vec3 center;
    float radius;
    vec3 color;
    int extraIntVal;
    int extraVec3Val;
};

sdfParams sdfs[numObjects];

float sphereSDF(sdfParams params, vec3 point) {
    return length(point - params.center) - params.radius;
}


vec3 sphereNormal(sdfParams params, vec3 point) {
    return normalize(point - params.center);
}

float rayMarch(sdfParams params, vec3 ray, int maxIterations, float maxT) {
    float t = 0.0;
    vec3 rayPos;
    float distance;
    int iterations = 0;
    while (t < maxT && iterations <= maxIterations) {

        rayPos = v3Eye + t * ray;

        //get distance from point on the ray to the object
        switch(params.sdfType) {
            case 0: distance = sphereSDF           (params, rayPos); break;
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

vec3 getNormalFromRays(sdfParams params) {
    float aspect = u_Dimensions.x / u_Dimensions.y;
    //calculate the points for 4 surrounding rays
    vec3 ray1 = getRay(v3Up, v3Eye, v3Ref, aspect, fs_Pos + vec2(-0.001,  0.0));
    vec3 ray2 = getRay(v3Up, v3Eye, v3Ref, aspect, fs_Pos + vec2( 0.001,  0.0));
    vec3 ray3 = getRay(v3Up, v3Eye, v3Ref, aspect, fs_Pos + vec2( 0.00, -0.001));
    vec3 ray4 = getRay(v3Up, v3Eye, v3Ref, aspect, fs_Pos + vec2( 0.00,  0.001));

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

vec3 getNormal(sdfParams params, vec3 point) {
    switch(params.sdfType) {
        case 0: return sphereNormal            (params, point);
        default: return getNormalFromRays      (params);
    }
    return vec3(0.0, 0.1, 0.0);
}

vec4 getTextureColor(sdfParams params, vec3 point) {
    vec3 normal;
    vec3 lightDirection = normalize(sunPosition - point);
    float intensity;

    switch(params.sdfType) {
        ///flat lambert
        case 0:
            normal = getNormal(params, point);
            intensity = dot(normal, lightDirection) * 0.9;
            return vec4(params.color * intensity, 1.0);
    }
    return vec4(params.color, 1.0);
}



void initSdfs() {
    //earth
    float pi = 3.14159;

    sdfs[0].sdfType = 0;
    sdfs[0].center = vec3(0,0,0);
    sdfs[0].radius = 1.5;
    sdfs[0].color = vec3(0.0, 0.0, 1.0);

}

vec2 pixelToScreenPos(vec2 pixelPos) {
    return (2.0 * pixelPos / iResolution.xy) - vec2(1.0);
}

vec2 screenToPixelPos(vec2 pixelPos) {
    return iResolution.xy * (pixelPos + vec2(1.0)) / 2.0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);

    //set up
    initSdfs();
    vec3 ray = getRay(v3Up, v3Eye, v3Ref, u_Dimensions.x/u_Dimensions.y, fs_Pos) ;

    float maxT = 100.0;
    int maxIterations = 100;
    float t;

     for(int i = 0; i < numObjects; i++) {
        t = rayMarch(sdfs[i], ray, maxIterations, maxT);
        if( t < maxT) {
            //get the diffuse term
            fragColor = getTextureColor(sdfs[i], v3Eye + ray*t);
            maxT = t;
        }
    }
}

void main() {
    //need to convert to pixel dimesions
    vec2 fragCoord = screenToPixelPos(fs_Pos);
    mainImage(out_Col, fs_Pos);
}

