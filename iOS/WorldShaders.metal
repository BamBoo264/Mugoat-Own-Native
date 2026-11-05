#include <metal_stdlib>
using namespace metal;
struct VertexIn{float3 position [[attribute(0)]];float3 normal [[attribute(1)]];};
struct VertexOut{float4 position [[position]];float3 normal;};
vertex VertexOut worldVertex(VertexIn v [[stage_in]],constant float4x4 &viewProjection [[buffer(1)]]){
 VertexOut o;o.position=viewProjection*float4(v.position,1);o.normal=v.normal;return o;
}
fragment float4 worldFragment(VertexOut v [[stage_in]]){
 float3 light=normalize(float3(0.3,-0.5,0.9));float diffuse=0.25+0.75*max(dot(normalize(v.normal),light),0.0);
 return float4(float3(0.62,0.69,0.74)*diffuse,1);
}
