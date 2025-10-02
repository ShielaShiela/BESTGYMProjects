//
//  pixelBufferRotation.metal
//  PoseA
//
//  Created by Ardhika Maulidani on 9/26/25.
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

vertex VSOut vs_fullscreen(const device float* verts [[buffer(0)]],
                           uint vid [[vertex_id]]) {
    VSOut out;
    out.position = float4(verts[vid * 4 + 0], verts[vid * 4 + 1], 0.0, 1.0);
    out.uv       = float2(verts[vid * 4 + 2], verts[vid * 4 + 3]);
    return out;
}

fragment float fs_rotate_depth(VSOut in [[stage_in]],
                               texture2d<float, access::sample> depthTex [[texture(0)]],
                               sampler s [[sampler(0)]]) {
    // Use the UVs provided by vertex data (already rotated)
    return depthTex.sample(s, in.uv).r;
}
