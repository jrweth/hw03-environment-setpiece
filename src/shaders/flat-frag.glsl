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

const float distanceThreshold = 0.001;
const int numObjects = 4;

float sunSpeed = 1.0;
vec3 v3Up = vec3(0.0, 1.0, 0.0);
vec3 v3Ref = vec3(0.0, 0.0, 0.0);
vec3 v3Eye = vec3(0.0, 0.0, 1.5);
vec2 v2ScreenPos;
vec3 sunPosition = vec3(5.0,10.0,10.0);
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
     return 0.2;
}

vec4 skyColor() {

      vec4 dawn = vec4(0.1, 0.1, 0.2, 1.0);
      vec4 noon = vec4(0.02, 0.02, 0.8, 1.0);
      vec4 dusk = vec4(0.1, 0.1, 0.2, 1.0);
      vec4 night = vec4(0, 0, 0.05, 1.0);


      //night
      if(sunPosition.y < -4.0) return night;
      //noon
      if(sunPosition.y > 4.) return noon;

      //transition to dawn
      if(sunPosition.x < 0.0 && sunPosition.y < 0.0) {
          return mix(dawn, night, -sunPosition.y / 4.0);
      }
      //transition to noon
      if(sunPosition.x < 0.0 && sunPosition.y > 0.0) {
          return mix(dawn, noon, sunPosition.y / 4.0);
      }
      //transition to dusk;
      if(sunPosition.x > 0.0 && sunPosition.y > 0.0) {
          return mix(dawn, noon, sunPosition.y / 4.0);
      }
      //transition to dusk;
      if(sunPosition.x > 0.0 && sunPosition.y < 0.0) {
          return mix(dawn, night,  -sunPosition.y / 4.0);
      }

}

vec4 landColor() {

    vec4 dawn = vec4(0.0, 0.1, 0.0, 1.0);
    vec4 noon = vec4(0.0, 0.2, 0.0, 1.0);
    vec4 dusk = vec4(0.0, 0.1, 0.0, 1.0);
    vec4 night = vec4(0.0, 0.05, 0.0, 1.0);


    //night
    if(sunPosition.y < 0.0) return night;
    //noon
    if(sunPosition.y > 8.0) return noon;

    //transition to dawn
    if(sunPosition.x < 0.0 && sunPosition.y < 0.4) {
        return mix(dawn, night, -sunPosition.y / 4.0);
    }
    //transition to noon
    if(sunPosition.x < 0.0 && sunPosition.y > 0.4) {
        return mix(dawn, noon, (sunPosition.y-4.0) / 4.0);
    }
    //transition to dusk;
    if(sunPosition.x > 0.0 && sunPosition.y > 1.0) {
        return mix(dusk, noon, (sunPosition.y-1.0) / 7.0);
    }
    //transition to dusk;
    if(sunPosition.x > 0.0 && sunPosition.y < 1.0) {
        return mix(dawn, night,  -sunPosition.y);
    }
}

vec4 backgroundColor() {

    if(v2ScreenPos.y < horizonHeight()) {
        return landColor();
    }
    return skyColor();

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
       float adjust = random1(params2.center, vec3(1,2,3))-0.5;
       float angle = float(i) * 2.0*pi/float(numPetals) + adjust*0.15;
       params2.center.x = params.center.x + cos(angle)*0.7;
       params2.center.y = params.center.y + sin(angle)*0.7;;
       params2.rotation = rotateZ(angle);
       //adjust the petal length
       params2.extraVec3Val.x += (random1(params2.center, vec3(1,2,3))-0.5)*0.2;
       params2.extraVec3Val.y += (random1(params2.center, vec3(1,2,3))-0.5)*0.05;
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
    float percent = (length(point - params.center) - 0.5);// / params.extraVec3Val.x;
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
////////////////////////////////////////// SUN  ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

float sunSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    return length(p) - params.radius;
}

vec4 sunColor(sdfParams params) {
    if(v2ScreenPos.y < horizonHeight()) {
        return backgroundColor();
    }
    return vec4(params.color, 1.0);
}




////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// SEEDS ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
float seedHeightOffset(sdfParams params, vec3 point) {
    vec3 p = point - params.center;

    float g = 80.0;
    float dist = (0.5 - length(point.xy)) * 2.0;
    mat3 rot = mat3(cos(-dist), -sin(-dist), 0.0,
                    sin(-dist), cos(dist),  0.0,
                    0.0,       0.0,        1.0);
    p = rot * p;
    return (2.0 + abs(sin(p.y * g))+abs(cos(p.x * g)))/4.0;
}
float hemisphere(sdfParams params, vec3 point) {
    return point.z-0.97;
}

float seedsSDF(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    p.z += .97;

    float height = seedHeightOffset(params, p) / 25.0;

    return max(-hemisphere(params, p), length(p) - (params.radius + height));
}

vec4 seedColor(sdfParams params, vec3 point) {
    vec3 p = point - params.center;
    float height = seedHeightOffset(params, p);
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
            case 0: distance = sunSDF (params, rayPos); break;
            case 1: distance = seedsSDF (params, rayPos); break;
            case 2: distance = petalsSDF (params, rayPos); break;
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
    vec3 color;
    vec3 lightDirection = normalize(sunPosition - point);
    float intensity;

    switch(params.sdfType) {
        case 0: //sun
            return sunColor(params);

        ///flat lambert
        case 1:   //seeds
            normal = sphereNormal(params, point);
            intensity = dot(normal, lightDirection) * 0.9;
            return seedColor(params, point);


        case 2: //petals
            color = petalColor(params, point);
            normal = getNormal(params, point, fragCoord);
            intensity = dot(normal, lightDirection) * 0.5 + 0.5;
            return vec4(color*intensity, 1.0);
    }
    return vec4(params.color, 1.0);
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
    sdfs[0].radius = 0.5;
    sdfs[0].color = vec3(1.0, 1.0, 0.5);


    //seeds
    sdfs[1].sdfType = 1;
    sdfs[1].center = vec3(0,0,-0.3);
    sdfs[1].radius = 1.0;
    sdfs[1].color = vec3(0.0, 0.0, 1.0);


    //second rolw of petals
    sdfs[2].sdfType = 2;
    sdfs[2].center = vec3(0,0,-0.25);
    sdfs[2].radius = 1.0;
    sdfs[2].color = vec3(1.0, 1.0, 0.0);
    sdfs[2].extraVec3Val = vec3(0.5,0.1,0.005);
    sdfs[2].rotation = rotateZ(pi/4.0);

    //petals
    sdfs[3].sdfType = 2;
    sdfs[3].center = vec3(0,0,-0.2);
    sdfs[3].radius = 1.0;
    sdfs[3].color = vec3(1.0, 1.0, 0.0);
    sdfs[3].extraVec3Val = vec3(0.5,0.1,0.005);
    sdfs[3].rotation = rotateZ(0.0);

}



////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////// Lighting ////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////
void initLighting() {
    float timeScale = 0.02;
    sunPosition = 10.0 * vec3(-cos(iTime * sunSpeed *timeScale)/4.0,
                       sin(iTime * sunSpeed * timeScale),
                       -cos(iTime * sunSpeed * timeScale)/2.0);
}




void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    v2ScreenPos = pixelToScreenPos(fragCoord);
    initLighting();
    fragColor = backgroundColor();

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

    //gamma correction
    fragColor = vec4(pow(fragColor.rgb, vec3(1.0/2.2)), 1.0);

}

void main() {
    //need to convert to pixel dimesions
    vec2 fragCoord = screenToPixelPos(fs_Pos);
    v3Eye = u_Eye;
    mainImage(out_Col, fragCoord);
}

