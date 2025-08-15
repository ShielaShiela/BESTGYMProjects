//
//  File.metal
//  PoseA
//
//  Created by Ardhika Maulidani on 8/8/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vs_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

struct DepthUniforms {
    float nearPlane;
    float farPlane;
    uint  mode; // 0 = grayscale, 1 = heatmap
};

// Simple HSV -> RGB helper
float3 hsv_to_rgb(float h, float s, float v) {
    float c = v * s;
    float x = c * (1.0 - fabs(fmod(h * 6.0, 2.0) - 1.0));
    float m = v - c;
    float3 rgb;
    if (h < 1.0/6.0)      rgb = float3(c, x, 0);
    else if (h < 2.0/6.0) rgb = float3(x, c, 0);
    else if (h < 3.0/6.0) rgb = float3(0, c, x);
    else if (h < 4.0/6.0) rgb = float3(0, x, c);
    else if (h < 5.0/6.0) rgb = float3(x, 0, c);
    else                  rgb = float3(c, 0, x);
    return rgb + float3(m, m, m);
}

fragment float4 fs_main(VertexOut in [[stage_in]],
                        texture2d<float, access::sample> depthTexture [[texture(0)]],
                        constant DepthUniforms& uni [[buffer(0)]],
                        sampler s [[sampler(0)]]) {

    // Sample the R channel — depth is stored in red for r16Float
    float depth = depthTexture.sample(s, in.uv).r;

    // Normalize using provided near/far (clamp to 0..1)
    float normalized = (depth - uni.nearPlane) / (uni.farPlane - uni.nearPlane);
    normalized = clamp(normalized, 0.0, 1.0);

    // Flip mapping if you want nearer = white vs nearer = black, adjust here
    float mapped = 1.0 - normalized; // now nearer -> brighter

    if (uni.mode == 0) {
        // Grayscale
        return float4(mapped, mapped, mapped, 1.0);
    } else {
        // Heatmap: map mapped(0..1) -> hue (0.66 = blue .. 0.0 = red)
        float hue = mix(0.66, 0.0, mapped); // blue->red
        float3 rgb = hsv_to_rgb(hue, 1.0, 1.0);
        return float4(rgb, 1.0);
    }
}

