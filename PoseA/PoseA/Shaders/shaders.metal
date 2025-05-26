/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders that render the app's camera views.
*/

#include <metal_stdlib>

using namespace metal;


typedef struct
{
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;



// Display a 2D texture.
vertex ColorInOut planeVertexShader(Vertex in [[stage_in]])
{
    ColorInOut out;
    out.position = float4(in.position, 0.0f, 1.0f);
    out.texCoord = in.texCoord;
    return out;
}

// Shade a 2D plane by passing through the texture inputs.
fragment float4 planeFragmentShader(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::linear);
    float4 sample = textureIn.sample(colorSampler, in.texCoord);
    return sample;
}

// Convert a color value to RGB using a Jet color scheme.
static half4 getJetColorsFromNormalizedVal(half val) {
    half4 res ;
    if(val <= 0.01h)
        return half4();
    res.r = 1.5h - fabs(4.0h * val - 3.0h);
    res.g = 1.5h - fabs(4.0h * val - 2.0h);
    res.b = 1.5h - fabs(4.0h * val - 1.0h);
    res.a = 1.0h;
    res = clamp(res,0.0h,1.0h);
    return res;
}

// Shade a texture with depth values using a Jet color scheme.
//- Tag: planeFragmentShaderDepth
fragment half4 planeFragmentShaderDepth(
                                        ColorInOut in [[stage_in]],
                                        texture2d<float, access::sample> textureDepth [[ texture(0) ]],
                                        constant float &minDepth [[buffer(0)]],
                                        constant float &maxDepth [[buffer(1)]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::nearest);
    float val = (textureDepth.sample(colorSampler, in.texCoord).r/* - minDepth*/)/(maxDepth-minDepth);
    half4 rgbaResult = getJetColorsFromNormalizedVal(half(val));
    
    if(val < minDepth || val > maxDepth)
    {
        rgbaResult = 0 ;
    }
    return rgbaResult;
}

fragment half4 planeFragmentShaderColor(ColorInOut in [[stage_in]],
                                        texture2d<half> colorYtexture [[ texture(0) ]],
                                        texture2d<half> colorCbCrtexture [[ texture(1) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    half y = colorYtexture.sample(textureSampler, in.texCoord).r;
    half2 uv = colorCbCrtexture.sample(textureSampler, in.texCoord).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);
    
    
    return rgbaResult;
}


////my add
//struct ColorInOut {
//    float4 position [[position]];
//    float2 texCoord;
//};
////my add

fragment half4 planeFragmentShaderColorThresholdDepth(ColorInOut in [[stage_in]],
                                                      texture2d<half> colorYTexture [[ texture(0) ]],
                                                      texture2d<half> colorCbCrTexture [[ texture(1) ]],
                                                      texture2d<float> depthTexture [[ texture(2) ]],
                                                      constant float &minDepth [[buffer(0)]],
                                                      constant float &maxDepth [[buffer(1)]],
                                                      constant float2 &tappedPoint [[buffer(3)]]
                                                      )
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    half y = colorYTexture.sample(textureSampler, in.texCoord).r;
    half2 uv = colorCbCrTexture.sample(textureSampler, in.texCoord).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);
    float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    if(depth < minDepth || depth > maxDepth)
    {
        rgbaResult = 0 ;
    }
    
    // Check if the fragment is near the tapped point
    float dist = distance(in.texCoord, tappedPoint);
    if (dist < 0.0001) { // Adjust the threshold for the point size
        rgbaResult = half4(0.2h, 0.0h, 0.0h, 0.2h); // Draw the point in red
    }
    return rgbaResult;
}

fragment half4 planeFragmentShaderColorZap(ColorInOut in [[stage_in]],
                                           texture2d<half> colorYTexture [[ texture(0) ]],
                                           texture2d<half> colorCbCrTexture [[ texture(1) ]],
                                           texture2d<float> depthTexture [[ texture(2) ]],
                                           constant float &minDepth [[buffer(0)]],
                                           constant float &maxDepth [[buffer(1)]],
                                           constant float &globalMaxDepth [[buffer(2)]]
                                           )
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    half y = colorYTexture.sample(textureSampler, in.texCoord).r;
    half2 uv = colorCbCrTexture.sample(textureSampler, in.texCoord).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);
    float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    if(depth > minDepth && depth < maxDepth)
    {
        half normDepth = (depth-minDepth)/(globalMaxDepth-minDepth);
        rgbaResult = rgbaResult * 0.5 + 0.5 * getJetColorsFromNormalizedVal(normDepth);
    }
    else if (depth>maxDepth && depth < maxDepth*1.1  )
    {
        rgbaResult = rgbaResult * 2 ;
        
    }
    return rgbaResult;
}


// Shade a texture with confidence levels low, medium, and high to red, green, and blue, respectively.
fragment half4 planeFragmentShaderConfidence(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::nearest);
    float4 s = textureIn.sample(colorSampler, in.texCoord);
    float res = round( 255.0f*(s.r) ) ;
    int resI = int(res);
    half4 color = half4(0.0h, 0.0h, 0.0h, 0.0h);
    if (resI == 0)
        color = half4(1.0h, 0.0h, 0.0h, 1.0h);
    else if (resI == 1)
        color = half4(0.0h, 1.0h, 0.0h, 1.0h);
    else if (resI == 2)
        color = half4(0.0h, 0.0h, 1.0h, 1.0h);
    return color;
}


// Declare a particle class that the `pointCloudVertexShader` inputs
// to `pointCloudFragmentShader`.
typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 coor;
    float pSize [[point_size]];
    float depth;
    half4 color;
} ParticleVertexInOut;


// Position vertices for the point cloud view. Filters out points with
// confidence below the selected confidence value and calculates the color of a
// particle using the color Y and CbCr per vertex. Use `viewMatrix` and
// `cameraIntrinsics` to calculate the world point location of each vertex in
// the depth map.
//- Tag: pointCloudVertexShader
vertex ParticleVertexInOut pointCloudVertexShader(
                                                  uint vertexID [[ vertex_id ]],
                                                  texture2d<float, access::read> depthTexture [[ texture(0) ]],
                                                  constant float4x4& viewMatrix [[ buffer(0) ]],
                                                  constant float3x3& cameraIntrinsics [[ buffer(1) ]],
                                                  texture2d<half> colorYtexture [[ texture(1) ]],
                                                  texture2d<half> colorCbCrtexture [[ texture(2) ]]
                                                  )
{ // ...
    ParticleVertexInOut out;
    uint2 pos;
    // Count the rows that are depth-texture-width wide to determine the y-value.
    pos.y = vertexID / depthTexture.get_width();
    
    // The x-position is the remainder of the y-value division.
    pos.x = vertexID % depthTexture.get_width();
    //get depth in [mm]
    float depth = (depthTexture.read(pos).x) * 1000.0f;
    
    
    // Calculate the vertex's world coordinates.
    float xrw = ((int)pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = ((int)pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    float4 xyzw = { xrw, yrw, depth, 1.f };
    
    // Project the coordinates to the view.
    float4 vecout = viewMatrix * xyzw;
    
    // Color the vertex.
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    out.coor = { pos.x / (depthTexture.get_width() - 1.0f), pos.y / (depthTexture.get_height() - 1.0f) };
    half y = colorYtexture.sample(textureSampler, out.coor).r;
    half2 uv = colorCbCrtexture.sample(textureSampler, out.coor).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);
    
    out.color = rgbaResult;
    out.clipSpacePosition = vecout;
    out.depth = depth;
    // Set the particle display size.
    out.pSize = 5.0f;
    
    return out;
}


// Position vertices for the point cloud view. Filters out points with
// confidence below the selected confidence value and calculates the color of a
// particle using the color Y and CbCr per vertex. Use `viewMatrix` and
// `cameraIntrinsics` to calculate the world point location of each vertex in
// the depth map.
//- Tag: pointCloudVertexShader
vertex ParticleVertexInOut pointCloudEffectVertexShader(
                                                        uint vertexID [[ vertex_id ]],
                                                        texture2d<float, access::read> depthTexture [[ texture(0) ]],
                                                        constant float4x4& viewMatrix [[ buffer(0) ]],
                                                        constant float3x3& cameraIntrinsics [[ buffer(1) ]],
                                                        constant uint& iTime [[ buffer(2) ]],
                                                        texture2d<half> colorYtexture [[ texture(1) ]],
                                                        texture2d<half> colorCbCrtexture [[ texture(2) ]]
                                                        )
{ // ...
    ParticleVertexInOut out;
    uint2 pos;
    // Count the rows that are depth-texture-width wide to determine the y-value.
    pos.y = vertexID / depthTexture.get_width();
    
    // The x-position is the remainder of the y-value division.
    pos.x = vertexID % depthTexture.get_width();
    //get depth in [mm]
    float depth = (depthTexture.read(pos).x) * 1000.0f;
    
    
    // Calculate the vertex's world coordinates.
    float xrw = ((int)pos.x - cameraIntrinsics[2][0]) * depth / cameraIntrinsics[0][0];
    float yrw = ((int)pos.y - cameraIntrinsics[2][1]) * depth / cameraIntrinsics[1][1];
    float3 xyz = { xrw, yrw, depth};
    
    // vertexID to linear random line
    float3 d = normalize(float3(sin(vertexID/2.),cos(vertexID/2.),sin(vertexID/2.)));
    //sin iTime
    float s = sin(iTime/100.0f);
    if(s <= 0)
    {
        s = 0;
    }
    float4 distXYZw = float4(xyz + 100*s* d,1.0f);
    
    // Project the coordinates to the view.
    float4 vecout = viewMatrix * distXYZw;
    
    // Color the vertex.
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    out.coor = { pos.x / (depthTexture.get_width() - 1.0f), pos.y / (depthTexture.get_height() - 1.0f) };
    half y = colorYtexture.sample(textureSampler, out.coor).r;
    half2 uv = colorCbCrtexture.sample(textureSampler, out.coor).rg - half2(0.5h, 0.5h);
    // Convert YUV to RGB inline.
    half4 rgbaResult = half4(y + 1.402h * uv.y, y - 0.7141h * uv.y - 0.3441h * uv.x, y + 1.772h * uv.x, 1.0h);
    
    out.color = rgbaResult;
    out.clipSpacePosition = vecout;
    out.depth = depth;
    // Set the particle display size.
    out.pSize = 5.0f;
    
    return out;
}

// Shade the point cloud points by using quad particles.
fragment half4 pointCloudFragmentShader(
                                        ParticleVertexInOut in [[stage_in]])
{
    // Avoid drawing particles that are too close, or filtered particles that
    // have zero depth.
    if (in.depth < 1.0f)
        discard_fragment();
    else
    {
        return in.color;
    }
    return half4();
}


// Convert the Y and CbCr textures into a single RGBA texture.
kernel void convertYCbCrToRGBA(texture2d<float, access::read> colorYtexture [[texture(0)]],
                               texture2d<float, access::read> colorCbCrtexture [[texture(1)]],
                               texture2d<float, access::write> colorRGBTexture [[texture(2)]],
                               uint2 gid [[thread_position_in_grid]])
{
    float y = colorYtexture.read(gid).r;
    float2 uv = colorCbCrtexture.read(gid / 2).rg;
    
    const float4x4 ycbcrToRGBTransform = float4x4(
                                                  float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                                  float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                                  float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                                  float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
                                                  );
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture
    // coordinate.
    float4 ycbcr = float4(y, uv.x, uv.y, 1.0f);
    
    // Return the converted RGB color.
    float4 colorSample = ycbcrToRGBTransform * ycbcr;
    colorRGBTexture.write(colorSample, uint2(gid.xy));
    
}

// Function to convert normalized depth to Jet color scheme
static float4 getJetColor(float normalizedDepth) {
    float4 color;
    color.r = clamp(1.5f - fabs(4.0f * normalizedDepth - 3.0f), 0.0f, 1.0f);
    color.g = clamp(1.5f - fabs(4.0f * normalizedDepth - 2.0f), 0.0f, 1.0f);
    color.b = clamp(1.5f - fabs(4.0f * normalizedDepth - 1.0f), 0.0f, 1.0f);
    color.a = 1.0f;
    return color;
}

// Sobel edge detection function for depth texture
float sobelEdgeDetect(texture2d<float, access::sample> texture, float2 uv, float2 texelSize) {
    float3 kernelX[3] = { float3(-1, 0, 1), float3(-2, 0, 2), float3(-1, 0, 1) };
    float3 kernelY[3] = { float3(1, 2, 1), float3(0, 0, 0), float3(-1, -2, -1) };
    
    float edgeX = 0.0;
    float edgeY = 0.0;

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float sample = texture.sample(sampler(address::clamp_to_edge), uv + float2(i, j) * texelSize).r;
            edgeX += sample * kernelX[i + 1][j + 1];
            edgeY += sample * kernelY[i + 1][j + 1];
        }
    }

    return length(float2(edgeX, edgeY));
}

// Fragment shader for fused depth and edge overlay using Jet colormap
fragment float4 fusedDepthEdgeFragmentShader(ColorInOut in [[stage_in]],
                                             texture2d<float> depthTexture [[ texture(0) ]],
                                             texture2d<half> colorTexture [[ texture(1) ]],
                                             constant float &minDepth [[buffer(0)]],
                                             constant float &maxDepth [[buffer(1)]],
                                             constant float2 &texelSize [[buffer(2)]])
{
    constexpr sampler textureSampler(address::clamp_to_edge, filter::linear);

    // Sample and normalize depth
    float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    float normalizedDepth = (depth - minDepth) / (maxDepth - minDepth);
    if (depth < minDepth || depth > maxDepth) {
        return float4(0.0);  // Return transparent if out of bounds
    }

    // Colorize depth using the Jet colormap
    float4 depthColor = getJetColor(normalizedDepth);

    // Detect edges in the depth map
    float depthEdge = sobelEdgeDetect(depthTexture, in.texCoord, texelSize);

    // Overlay edges as white lines
    float edgeIntensity = clamp(depthEdge * 2.0, 0.0, 1.0);
    float4 edgeColor = float4(edgeIntensity, edgeIntensity, edgeIntensity, 1.0);

    // Blend edge color with depth color
    float4 fusedResult = mix(depthColor, edgeColor, edgeIntensity);

    return fusedResult;
}


constant float gaussianKernel[5][5] = {
    {1.0 / 273.0, 4.0 / 273.0, 7.0 / 273.0, 4.0 / 273.0, 1.0 / 273.0},
    {4.0 / 273.0, 16.0 / 273.0, 26.0 / 273.0, 16.0 / 273.0, 4.0 / 273.0},
    {7.0 / 273.0, 26.0 / 273.0, 41.0 / 273.0, 26.0 / 273.0, 7.0 / 273.0},
    {4.0 / 273.0, 16.0 / 273.0, 26.0 / 273.0, 16.0 / 273.0, 4.0 / 273.0},
    {1.0 / 273.0, 4.0 / 273.0, 7.0 / 273.0, 4.0 / 273.0, 1.0 / 273.0}
};


float gaussianBlur(texture2d<float, access::sample> texture, float2 uv, float2 texelSize) {
    float sum = 0.0;
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            float sample = texture.sample(sampler(address::clamp_to_edge), uv + float2(i, j) * texelSize).r;
            sum += sample * gaussianKernel[i + 2][j + 2];
        }
    }
    return sum;
}

// 2. Gradient Calculation using Sobel
float2 calculateGradient(texture2d<float, access::sample> texture, float2 uv, float2 texelSize) {
    float3 kernelX[3] = { float3(-1, 0, 1), float3(-2, 0, 2), float3(-1, 0, 1) };
    float3 kernelY[3] = { float3(1, 2, 1), float3(0, 0, 0), float3(-1, -2, -1) };

    float edgeX = 0.0;
    float edgeY = 0.0;

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float sample = texture.sample(sampler(address::clamp_to_edge), uv + float2(i, j) * texelSize).r;
            edgeX += sample * kernelX[i + 1][j + 1];
            edgeY += sample * kernelY[i + 1][j + 1];
        }
    }
    return float2(edgeX, edgeY);
}

// 3. Non-maximum Suppression (simplified for shader use)
float nonMaximumSuppression(float gradientMagnitude, float gradientDirection, texture2d<float, access::sample> gradientTexture, float2 uv, float2 texelSize) {
    float2 direction = float2(cos(gradientDirection), sin(gradientDirection));
    float neighbor1 = gradientTexture.sample(sampler(address::clamp_to_edge), uv + direction * texelSize).r;
    float neighbor2 = gradientTexture.sample(sampler(address::clamp_to_edge), uv - direction * texelSize).r;

    return (gradientMagnitude >= neighbor1 && gradientMagnitude >= neighbor2) ? gradientMagnitude : 0.0;
}

// 4. Hysteresis Thresholding (simplified)
float hysteresisThreshold(float value, float highThreshold, float lowThreshold) {
    if (value >= highThreshold) return 1.0;
    else if (value >= lowThreshold) return 0.5; // Mark as weak edge
    else return 0.0; // Non-edge
}

// Main Canny Edge Detection function
float cannyEdgeDetect(texture2d<float, access::sample> texture, float2 uv, float2 texelSize) {
    // Step 1: Apply Gaussian Blur for smoothing
//    float blurred = gaussianBlur(texture, uv, texelSize); //unused variable

    // Step 2: Calculate gradient and its magnitude and direction
    float2 gradient = calculateGradient(texture, uv, texelSize);
    float gradientMagnitude = length(gradient);
    float gradientDirection = atan2(gradient.y, gradient.x);

    // Step 3: Non-maximum suppression to thin out edges
    float suppressed = nonMaximumSuppression(gradientMagnitude, gradientDirection, texture, uv, texelSize);

    // Step 4: Hysteresis thresholding to classify edges
    // Define high and low thresholds (these can be tuned)
    float highThreshold = 0.3;
    float lowThreshold = 0.1;
    float edgeValue = hysteresisThreshold(suppressed, highThreshold, lowThreshold);

    return edgeValue;
}


// Fragment shader for colorized depth with Canny Edge Detection
fragment float4 planeFragmentShaderCannyEdgeDetection(
    ColorInOut in [[stage_in]],
    texture2d<float> depthTexture [[ texture(0) ]],
    constant float &minDepth [[buffer(0)]],
    constant float &maxDepth [[buffer(1)]],
    constant float2 &texelSize [[buffer(2)]]
) {
    constexpr sampler textureSampler (address::clamp_to_edge, filter::linear);

    // Sample and normalize depth
    float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    float normalizedDepth = (depth - minDepth) / (maxDepth - minDepth);
    if (depth < minDepth || depth > maxDepth) {
        return float4(0.0); // Return black if depth is out of range
    }

    // Colorize depth using the Jet colormap
    float4 depthColor = getJetColor(normalizedDepth);

    // Apply Canny edge detection
    float edgeIntensity = cannyEdgeDetect(depthTexture, in.texCoord, texelSize);

    // Blend edge color with depth color
    float4 edgeColor = float4(edgeIntensity, edgeIntensity, edgeIntensity, 1.0);
    float4 fusedResult = mix(depthColor, edgeColor, edgeIntensity);

    return fusedResult;
}


struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

//vertex VertexOut planeVertexShader(uint vertexID [[vertex_id]],
//                                   const device VertexIn* vertexArray [[buffer(0)]]) {
//    VertexOut out;
//    out.position = vertexArray[vertexID].position;
//    out.texCoord = vertexArray[vertexID].texCoord;
//    return out;
//}

