import Foundation
import MetalKit
import simd
final class MetalWorldRenderer:NSObject,MTKViewDelegate {
 private let device:MTLDevice,queue:MTLCommandQueue,pipeline:MTLRenderPipelineState,depth:MTLDepthStencilState
 private var vertices:MTLBuffer?,indices:MTLBuffer?,indexCount=0
 private var center=SIMD3<Float>(0,0,0),radius:Float=1
 var yaw:Float=0.7,pitch:Float=0.25,zoom:Float=2.5
 private var last=ProcessInfo.processInfo.systemUptime,frames=0,windowStart=ProcessInfo.processInfo.systemUptime
 var metrics:((String)->Void)?
 init(view:MTKView)throws {
  guard let device=view.device,let queue=device.makeCommandQueue(),let library=device.makeDefaultLibrary() else{throw ArchiveFailure.unsupported("Metal device/library")}
  self.device=device;self.queue=queue
  let desc=MTLRenderPipelineDescriptor();desc.vertexFunction=library.makeFunction(name:"worldVertex");desc.fragmentFunction=library.makeFunction(name:"worldFragment");desc.colorAttachments[0].pixelFormat=view.colorPixelFormat;desc.depthAttachmentPixelFormat = .depth32Float
  let layout=MTLVertexDescriptor();layout.attributes[0].format = .float3;layout.attributes[0].offset=0;layout.attributes[0].bufferIndex=0;layout.attributes[1].format = .float3;layout.attributes[1].offset=12;layout.attributes[1].bufferIndex=0;layout.layouts[0].stride=24;desc.vertexDescriptor=layout
  pipeline=try device.makeRenderPipelineState(descriptor:desc)
  let state=MTLDepthStencilDescriptor();state.depthCompareFunction = .less;state.isDepthWriteEnabled=true
  guard let depth=device.makeDepthStencilState(descriptor:state) else{throw ArchiveFailure.unsupported("Metal depth state")};self.depth=depth
  super.init();view.depthStencilPixelFormat = .depth32Float;view.delegate=self;view.preferredFramesPerSecond=60;view.clearColor=MTLClearColor(red:0.07,green:0.12,blue:0.18,alpha:1)
 }
 func clearMesh(){vertices=nil;indices=nil;indexCount=0}
 func setMesh(_ mesh:StaticMesh)throws {
  var floats:[Float]=[];floats.reserveCapacity(mesh.vertices.count*6)
  for v in mesh.vertices{floats += [v.position.x,v.position.y,v.position.z,v.normal.x,v.normal.y,v.normal.z]}
  let vb=floats.withUnsafeBytes{device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
  let ib=mesh.indices.withUnsafeBytes{device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
  guard let vb,let ib else{throw ArchiveFailure.unsupported("GPU mesh allocation")}
  vertices=vb;indices=ib;indexCount=mesh.indices.count;let c=mesh.bounds.center;center=SIMD3(c.x,c.y,c.z);radius=max(mesh.bounds.radius,0.05)
 }
 func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize){}
 private func matrix(aspect:Float)->simd_float4x4 {
  let p=max(-1.4,min(1.4,pitch)),distance=radius*max(0.3,zoom),eye=center+SIMD3(cos(p)*sin(yaw),-cos(p)*cos(yaw),sin(p))*distance
  let f=simd_normalize(center-eye),r=simd_normalize(simd_cross(f,SIMD3<Float>(0,0,1))),u=simd_cross(r,f)
  let v=simd_float4x4(columns:(SIMD4(r.x,u.x,-f.x,0),SIMD4(r.y,u.y,-f.y,0),SIMD4(r.z,u.z,-f.z,0),SIMD4(-simd_dot(r,eye),-simd_dot(u,eye),simd_dot(f,eye),1)))
  let near=max(0.005,radius*0.001),far=max(100,radius*20),sy:Float=1/tan(Float.pi/6),sx=sy/max(0.1,aspect),z=far/(near-far)
  let projection=simd_float4x4(columns:(SIMD4(sx,0,0,0),SIMD4(0,sy,0,0),SIMD4(0,0,z,-1),SIMD4(0,0,near*z,0)))
  return projection*v
 }
 func draw(in view:MTKView){
  guard let pass=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass) else{return}
  encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth);encoder.setCullMode(.none)
  if let vertices,let indices,indexCount>0 {
   var transform=matrix(aspect:Float(view.drawableSize.width/max(1,view.drawableSize.height)))
   encoder.setVertexBuffer(vertices,offset:0,index:0);encoder.setVertexBytes(&transform,length:MemoryLayout<simd_float4x4>.size,index:1)
   encoder.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint32,indexBuffer:indices,indexBufferOffset:0)
  }
  encoder.endEncoding();command.present(drawable);command.commit()
  let now=ProcessInfo.processInfo.systemUptime;frames+=1
  if now-windowStart>=1{metrics?(String(format:"%.1f FPS · %d triangles · own Metal renderer",Double(frames)/(now-windowStart),indexCount/3));frames=0;windowStart=now};last=now
 }
}
