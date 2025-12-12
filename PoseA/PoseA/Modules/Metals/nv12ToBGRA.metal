//
//  nv12ToBGRA.metal
//  PoseA
//
//  Created by Ardhika Maulidani on 8/21/25.
//

#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vs_nv12_to_bgra(VSIn in [[stage_in]]) {
    VSOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

// NV12 -> BGRA (actually returns RGBA; BGRA PixelBuffer swizzles in memory)
fragment float4 fs_nv12_to_bgra(VSOut in [[stage_in]],
                                texture2d<float, access::sample> yTex  [[texture(0)]],
                                texture2d<float, access::sample> uvTex [[texture(1)]],
                                sampler s [[sampler(0)]]) {

    float  y  = yTex.sample(s, in.uv).r;
    float2 uv = uvTex.sample(s, in.uv).rg;

    float u = uv.x - 0.5;
    float v = uv.y - 0.5;

    float r = y + 1.402    * v;
    float g = y - 0.344136 * u - 0.714136 * v;
    float b = y + 1.772    * u;

    return float4(clamp(r,0.0,1.0),
                  clamp(g,0.0,1.0),
                  clamp(b,0.0,1.0),
                  1.0);
}
