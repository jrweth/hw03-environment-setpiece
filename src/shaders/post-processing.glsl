
const int  samples    = 15;  // must be odd
const int  samplesHalf = samples / 2;

float focalLength = 3.2;
float focalRange = 0.5;
float sigma = 1.0;


float Gaussian (float sigma, float x)
{
    return exp(-(x*x) / (2.0 * sigma*sigma));
}

vec3 BlurredPixel (in vec2 uv, float len) {

    //test to see if we are in the focal range
    vec4 color = texture(iChannel0, uv);
    if(abs(color.a -focalLength) < focalRange) {
        return color.rgb;
    }


    vec3 ret = vec3(0.0);
    float total = 0.0;
    for(int xi = -samplesHalf; xi <= samplesHalf; xi++) {
        float x = clamp(uv.x + float(xi)*len, 0.0, 1.0);
        float gx = Gaussian(sigma, x);
        for(int yi = -samplesHalf; yi <= samplesHalf; yi++) {
            float y = clamp(uv.y + float(yi)*len, 0.0, 1.0);
            float gy = Gaussian(sigma, y);
            ret += texture(iChannel0, vec2(x,y)).rgb * gx * gy;
            total += gx * gy;;
        }
    }
    //ret = texture(iChannel0, uv).rgb;
    return ret/total;
}

void setFocalLength() {
    float cycleLength = 140.0;
    float flower1 = 3.0;
    float flower2 = 4.6;
    float flower3 = 6.2;

    //first flower
    if(mod(iTime, cycleLength) < 20.0) {
        focalLength = flower1;
    }
    //first to second
    else if(mod(iTime, cycleLength) < 30.0) {
        focalLength = mix(flower1, flower2, (iTime - 20.0)/10.0);
    }
    //second flower
    else if(mod(iTime, cycleLength) < 40.0) {
        focalLength = flower2;
    }
    //second to third
    else if(mod(iTime, cycleLength) < 50.0) {
        focalLength = mix(flower2, flower3, (iTime - 40.0)/10.0);
    }
    //third
    else if(mod(iTime, cycleLength) < 80.0) {
        focalLength = flower3;
    }
    //third back to first
    else if(mod(iTime, cycleLength) < 100.0) {
        focalLength = mix(flower3, flower1, (iTime - 80.0)/20.0);
    }
    //fist again
    else {
        focalLength = flower1;
    }


}


void mainImage( out vec4 fragColor, in vec2 fragCoord )
{

    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord/iResolution.xy;
    vec3 color = texture(iChannel0, uv).rgb;

    setFocalLength();

    //distance and bloom are in "a" channel
    float distance = texture(iChannel0, uv).a;
    bool bloom = false;
    if(distance >= 1000.0) {
        bloom = true;
        distance -= 1000.0;
    }



    //fragColor = vec4(color, 1.0);
    if(bloom) {
        color = BlurredPixel(uv, 0.3/iResolution.x);
    }
    else if(abs(distance - focalLength) > focalRange) {
        float len = clamp(distance / 20.0, 0.0, 0.3)/iResolution.x;
        color = BlurredPixel(uv, len);
    }

    fragColor = vec4(color, 1.0);

}
