//
//  PointCloud.metal
//  DataCaptureTest
//
//  Created by Shiela Cabahug on 2024/8/1.
//
#include <metal_stdlib>
using namespace metal;

struct PointCloudPoint {
    float3 position;
    float3 color;
};

kernel void generatePointCloudKernel(texture2d<float, access::sample> depthTexture [[texture(0)]],
                                     texture2d<float, access::sample> colorYTexture [[texture(1)]],
                                     texture2d<float, access::sample> colorCbCrTexture [[texture(2)]],
                                     device PointCloudPoint *outputBuffer [[buffer(0)]],
                                     constant float3x3 &cameraIntrinsics [[buffer(1)]],
                                     uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= depthTexture.get_width() || gid.y >= depthTexture.get_height()) {
        return;
    }
    
    constexpr sampler textureSampler(coord::pixel, address::clamp_to_edge, filter::nearest);
    
    float depth = depthTexture.sample(textureSampler, float2(gid)).r;
    
    if (depth <= 0) {
        return;
    }
    
    float fx = cameraIntrinsics[0][0];
    float fy = cameraIntrinsics[1][1];
    float cx = cameraIntrinsics[2][0];
    float cy = cameraIntrinsics[2][1];
    
    float x = (float(gid.x) - cx) * depth / fx;
    float y = (float(gid.y) - cy) * depth / fy;
    
    float4 colorYCbCr = float4(colorYTexture.sample(textureSampler, float2(gid)).r,
                               colorCbCrTexture.sample(textureSampler, float2(gid)).rg,
                               1.0);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    float4 rgbaColor = ycbcrToRGBTransform * colorYCbCr;
    
    uint index = gid.y * depthTexture.get_width() + gid.x;
    outputBuffer[index] = PointCloudPoint{ float3(x, y, depth), rgbaColor.rgb };
}


