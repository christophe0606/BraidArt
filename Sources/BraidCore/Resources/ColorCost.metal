#include <metal_stdlib>
using namespace metal;
float linearize(float x) { return x<=0.04045f ? x/12.92f : pow((x+0.055f)/1.055f,2.4f); }
float labf(float x) { return x>216.0f/24389.0f ? pow(x,1.0f/3.0f) : (24389.0f/27.0f*x+16.0f)/116.0f; }
float3 lab(float3 c) {
    float r=linearize(c.r),g=linearize(c.g),b=linearize(c.b);
    float x=labf((0.4360747f*r+0.3850649f*g+0.1430804f*b)/0.96422f);
    float y=labf(0.2225045f*r+0.7168786f*g+0.0606169f*b);
    float z=labf((0.0139322f*r+0.0971045f*g+0.7141733f*b)/0.82521f);
    if(c.r==c.g && c.g==c.b) return float3(116*y-16,0,0);
    return float3(116*y-16,500*(x-y),200*(y-z));
}
float square(float x) { return x*x; }
float hue(float a,float b) { float h=atan2(b,a); return h<0 ? h+2*M_PI_F : h; }
float de2000(float3 p,float3 q) {
    float c1=length(p.yz),c2=length(q.yz),cm=(c1+c2)/2;
    float cm7=pow(cm,7.0f),k=6103515625.0f;
    float g=0.5f*(1-sqrt(cm7/(cm7+k)));
    float ap1=(1+g)*p.y,ap2=(1+g)*q.y;
    float cp1=length(float2(ap1,p.z)),cp2=length(float2(ap2,q.z));
    float h1=hue(ap1,p.z),h2=hue(ap2,q.z),dl=q.x-p.x,dc=cp2-cp1,dh=h2-h1;
    if (cp1*cp2==0) dh=0; else if (dh>M_PI_F) dh-=2*M_PI_F; else if(dh<-M_PI_F) dh+=2*M_PI_F;
    float dH=2*sqrt(cp1*cp2)*sin(dh/2),lm=(p.x+q.x)/2,cp=(cp1+cp2)/2;
    float hm=h1+h2;
    if(cp1*cp2!=0) { if(abs(h1-h2)<=M_PI_F) hm/=2; else hm=(hm+(hm<2*M_PI_F ? 2*M_PI_F : -2*M_PI_F))/2; }
    float rad=M_PI_F/180;
    float t=1-0.17f*cos(hm-30*rad)+0.24f*cos(2*hm)+0.32f*cos(3*hm+6*rad)-0.20f*cos(4*hm-63*rad);
    float sl=1+0.015f*square(lm-50)/sqrt(20+square(lm-50));
    float sc=1+0.045f*cp,sh=1+0.015f*cp*t;
    float cp7=pow(cp,7.0f);
    float rt=-2*sqrt(cp7/(cp7+k))*sin(60*rad*exp(-square((hm/rad-275)/25)));
    float x=dl/sl,y=dc/sc,z=dH/sh;
    return sqrt(max(0.0f,x*x+y*y+z*z+rt*y*z));
}
kernel void colorCosts(device const float4 *pixels [[buffer(0)]],device const float4 *tiles [[buffer(1)]],
                       device float *costs [[buffer(2)]],constant uint2 &counts [[buffer(3)]],uint i [[thread_position_in_grid]]) {
    if(i>=counts.x*counts.y) return;
    costs[i]=de2000(lab(pixels[i/counts.y].xyz),lab(tiles[i%counts.y].xyz));
}
