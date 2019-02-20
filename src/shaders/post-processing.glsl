
const int  samples    = 15;  // must be odd
const int  samplesHalf = samples / 2;

float focalLength = 3.2;
float focalRange = 0.4;
float sigma = 3.0;


float Gaussian (float sigma, float x)
{
    return exp(-(x*x) / (2.0 * sigma*sigma));
}

vec3 BlurredPixel (in vec2 uv) {

    //test to see if we are in the focal range
    vec4 color = texture(iChannel0, uv);
    if(abs(color.a -focalLength) < focalRange) {
        return color.rgb;
    }

    float len = clamp(abs(color.a - focalLength)*0.15, 0.0, 1.5)/iResolution.x;
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




void mainImage( out vec4 fragColor, in vec2 fragCoord )
{

    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord/iResolution.xy;
    vec3 color = texture(iChannel0, uv).rgb;

    //focalLength = 4.4 + sin(iTime)* 1.8;
 	//uv = fragCoord.xy / iResolution.x;
	vec3 blurredColor = BlurredPixel(uv);

    //fragColor = vec4(color, 1.0);
    fragColor = vec4(blurredColor, 1.0);
}
