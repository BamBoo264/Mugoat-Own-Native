import Foundation
import MetalKit
import simd
final class MetalWorldRenderer:NSObject,MTKViewDelegate {
 private let device:MTLDevice,queue:MTLCommandQueue,pipeline:MTLRenderPipelineState,depth:MTLDepthStencilState
 private struct Chunk {let vertices:MTLBuffer;let indices:MTLBuffer;let count:Int;let bounds:Bounds3}
 private var chunks:[Chunk]=[]
 private var center=SIMD3<Float>(0,0,0),radius:Float=1,eye=SIMD3<Float>(0,0,0)
 var yaw:Float=0.7,pitch:Float=0.25,zoom:Float=2.5
 private(set) var flying=false
 var movement=Vec3.zero
 var culling=true
 private var last=ProcessInfo.processInfo.systemUptime,windowStart=ProcessInfo.processInfo.systemUptime
 private var samples:[Double]=[]
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
 func clearMesh(){chunks=[];movement = .zero;samples=[];last=ProcessInfo.processInfo.systemUptime;windowStart=last}
 func setMesh(_ mesh:StaticMesh)throws{try setScene(NativeWorldScene(chunks:[mesh],report:""))}
 func setScene(_ scene:NativeWorldScene)throws {
  try scene.validate()
  var pending:[Chunk]=[]
  for mesh in scene.chunks{
   var floats:[Float]=[];floats.reserveCapacity(mesh.vertices.count*6)
   for v in mesh.vertices{floats += [v.position.x,v.position.y,v.position.z,v.normal.x,v.normal.y,v.normal.z]}
   let vb=floats.withUnsafeBytes{device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
   let ib=mesh.indices.withUnsafeBytes{device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
   guard let vb,let ib else{throw ArchiveFailure.unsupported("GPU scene allocation")}
   pending.append(Chunk(vertices:vb,indices:ib,count:mesh.indices.count,bounds:mesh.bounds))
  }
  // Commit only after all uploads succeed. Failed uploads cannot leave a half scene.
  chunks=pending
  var lo=scene.chunks[0].bounds.min,hi=scene.chunks[0].bounds.max
  for m in scene.chunks{lo=Vec3(x:min(lo.x,m.bounds.min.x),y:min(lo.y,m.bounds.min.y),z:min(lo.z,m.bounds.min.z));hi=Vec3(x:max(hi.x,m.bounds.max.x),y:max(hi.y,m.bounds.max.y),z:max(hi.z,m.bounds.max.z))}
  let bounds=Bounds3(min:lo,max:hi),c=bounds.center
  center=SIMD3(c.x,c.y,c.z);radius=max(bounds.radius,0.05);resetCamera()
 }
 func resetCamera(){flying=false;movement = .zero;yaw=0.7;pitch=0.25;zoom=2.5}
 func toggleFlight(){
  if !flying{eye=orbitEye();yaw += Float.pi;pitch = -pitch}
  else{yaw=0.7;pitch=0.25}
  flying.toggle();movement = .zero
 }
 private func direction()->SIMD3<Float>{let p=max(-1.4,min(1.4,pitch));return SIMD3(cos(p)*sin(yaw),-cos(p)*cos(yaw),sin(p))}
 private func orbitEye()->SIMD3<Float>{center+direction()*radius*max(0.3,zoom)}
 func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize){}
 private func matrix(aspect:Float,elapsed:Float)->simd_float4x4 {
  var f:SIMD3<Float>,camera:SIMD3<Float>
  if flying{
   f=direction();let right=simd_normalize(simd_cross(f,SIMD3<Float>(0,0,1)))
   let speed=max(1,min(100,radius*0.12))*max(0.1,min(10,zoom/2.5))
   let input=movement.length>1 ? movement.normalized:movement
   eye += (right*input.x+f*input.y+SIMD3<Float>(0,0,input.z))*speed*elapsed;camera=eye
  }else{camera=orbitEye();f=simd_normalize(center-camera)}
  let r=simd_normalize(simd_cross(f,SIMD3<Float>(0,0,1))),u=simd_cross(r,f)
  let v=simd_float4x4(columns:(SIMD4(r.x,u.x,-f.x,0),SIMD4(r.y,u.y,-f.y,0),SIMD4(r.z,u.z,-f.z,0),SIMD4(-simd_dot(r,camera),-simd_dot(u,camera),simd_dot(f,camera),1)))
  let near:Float=flying ? 0.05:max(0.005,radius*0.001),far=max(100,radius*20),sy:Float=1/tan(Float.pi/6),sx=sy/max(0.1,aspect),z=far/(near-far)
  let projection=simd_float4x4(columns:(SIMD4(sx,0,0,0),SIMD4(0,sy,0,0),SIMD4(0,0,z,-1),SIMD4(0,0,near*z,0)))
  return projection*v
 }
 private func visibility(_ m:simd_float4x4)->SceneVisibility{
  let rows=(0..<4).map{i in SIMD4<Float>(m[0][i],m[1][i],m[2][i],m[3][i])}
  // Metal clip space: -w<=x,y<=w, 0<=z<=w.
  return SceneVisibility(planes:[rows[3]+rows[0],rows[3]-rows[0],rows[3]+rows[1],rows[3]-rows[1],rows[2],rows[3]-rows[2]].map{ScenePlane(normal:Vec3(x:$0.x,y:$0.y,z:$0.z),distance:$0.w)})
 }
 func draw(in view:MTKView){
  let now=ProcessInfo.processInfo.systemUptime,elapsed=now-last;last=now
  guard let pass=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass) else{return}
  encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth);encoder.setCullMode(.none)
  var transform=matrix(aspect:Float(view.drawableSize.width/max(1,view.drawableSize.height)),elapsed:Float(max(0,min(0.05,elapsed))))
  let frustum=visibility(transform)
  encoder.setVertexBytes(&transform,length:MemoryLayout<simd_float4x4>.size,index:1)
  var draws=0,triangles=0
  for chunk in chunks where !culling || frustum.contains(chunk.bounds){
   encoder.setVertexBuffer(chunk.vertices,offset:0,index:0)
   encoder.drawIndexedPrimitives(type:.triangle,indexCount:chunk.count,indexType:.uint32,indexBuffer:chunk.indices,indexBufferOffset:0)
   draws+=1;triangles+=chunk.count/3
  }
  encoder.endEncoding();command.present(drawable);command.commit()
  if elapsed>0,elapsed<2{samples.append(elapsed)}
  if now-windowStart>=1{
   let sorted=samples.sorted(),p95=sorted.isEmpty ? 0:sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]*1000
   let bytes=chunks.reduce(0){$0+$1.vertices.length+$1.indices.length}
   metrics?(String(format:"%.1f FPS · p95 %.1f ms · %d/%d sectors · %d triangles · %.1f MB mesh",Double(samples.count)/(now-windowStart),p95,draws,chunks.count,triangles,Double(bytes)/1048576))
   samples=[];windowStart=now
  }
 }
}
