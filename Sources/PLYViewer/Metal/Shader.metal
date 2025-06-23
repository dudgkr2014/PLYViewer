//
//  Shader.metal
//  PLYViewer
//
//  Created by 우영학 on 6/20/25.
//

#include <metal_stdlib>
using namespace metal;

struct PLYVertexIn {
  float3 position [[attribute(0)]];
  float3 color [[attribute(1)]];
};

struct PLYVertexOut {
  float4 position [[position]];
  float point_size [[point_size]];
  float3 color;
};

struct Uniforms {
  float3 center;
  float scale;
  float4x4 mvp;
};

vertex PLYVertexOut vertex_main(PLYVertexIn in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(1)]]) {
  PLYVertexOut out;
  
  float3 shifted = (in.position - uniforms.center) * uniforms.scale;
  
  out.position = uniforms.mvp * float4(shifted, 1.0);
  out.point_size = 3.0;
  out.color = in.color;
  return out;
}

fragment float4 fragment_main(PLYVertexOut in [[stage_in]]) {
  return float4(in.color, 1.0);
}
