//
//  YCbCrToRGB.metal
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/7/9.
//
#include <metal_stdlib>
using namespace metal;

kernel void yCbCrToRGB(texture2d<float, access::read> inTexture [[texture(0)]],
                       texture2d<float, access::read> cbcrTexture [[texture(1)]],
                       texture2d<float, access::write> outTexture [[texture(2)]],
                       uint2 gid [[thread_position_in_grid]])
{
    float4 ycbcr = float4(inTexture.read(gid).r,
                          cbcrTexture.read(gid / 2).rg,
                          1.0);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    float4 rgb = ycbcrToRGBTransform * ycbcr;
    outTexture.write(rgb, gid);
}
