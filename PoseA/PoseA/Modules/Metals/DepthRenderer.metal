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

fragment float4 fs_depth(VSOut in [[stage_in]],
                         texture2d<float, access::sample> depthTex [[texture(0)]],
                         sampler s [[sampler(0)]],
                         constant float &maxDepth [[buffer(0)]]) {
    float d = depthTex.sample(s, in.uv).r;
    float norm = clamp(d / maxDepth, 0.0, 1.0);

    // Jet-style colormap (blue -> cyan -> green -> yellow -> red)
    float4 color;
    if (norm < 0.25) {
        color = float4(0.0, norm * 4.0, 1.0, 1.0);   // blue to cyan
    } else if (norm < 0.5) {
        color = float4(0.0, 1.0, 1.0 - (norm - 0.25) * 4.0, 1.0); // cyan to green
    } else if (norm < 0.75) {
        color = float4((norm - 0.5) * 4.0, 1.0, 0.0, 1.0); // green to yellow
    } else {
        color = float4(1.0, 1.0 - (norm - 0.75) * 4.0, 0.0, 1.0); // yellow to red
    }

    return color;
}

