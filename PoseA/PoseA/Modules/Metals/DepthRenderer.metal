//
//  DepthRenderer.metal
//  PoseA
//
//  Created by Ardhika Maulidani on 9/26/25.
//

#include <metal_stdlib>
using namespace metal;

struct VSIn {
    float2 pos [[attribute(0)]];
    float2 uv  [[attribute(1)]];
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vs_depth(VSIn in [[stage_in]]) {
    VSOut out;
    out.position = float4(in.pos, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

// depth texture (r16Float/r32Float)
fragment float4 fs_depth(VSOut in [[stage_in]],
                         texture2d<float, access::sample> depthTex [[texture(0)]],
                         sampler s [[sampler(0)]],
                         constant float &maxDepth [[buffer(0)]]) {
    float d = depthTex.sample(s, in.uv).r;  // fetch depth value
    float norm = clamp(d / maxDepth, 0.0, 1.0); // normalize
    return float4(norm, norm, norm, 1.0);   // grayscale output
}

