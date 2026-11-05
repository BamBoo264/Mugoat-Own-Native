import Foundation
struct MeshVertex {var position:Vec3;var normal:Vec3}
struct StaticMesh {
 let vertices:[MeshVertex];let indices:[UInt32];let bounds:Bounds3
 var triangleCount:Int{indices.count/3}
 func groundHeight(x:Float,y:Float,above:Float,reach:Float)->Float?{
  let origin=Vec3(x:x,y:y,z:above),direction=Vec3(x:0,y:0,z:-1)
  var nearest:Float?
  for i in stride(from:0,to:indices.count,by:3){
   let t=Triangle(a:vertices[Int(indices[i])].position,b:vertices[Int(indices[i+1])].position,c:vertices[Int(indices[i+2])].position)
   guard abs(t.normal.z)>0.6,let hit=t.ray(origin:origin,direction:direction,maxDistance:reach) else{continue}
   if nearest==nil||hit<nearest!{nearest=hit}
  }
  return nearest.map{above-$0}
 }
}
/// Original static drawable decoder. Binary field layout is format data, not copied parser code.
enum DrawableMesh {
 static func decode(_ resource:ResourceMemory,rootAddress:UInt64=0x50000000)throws->StaticMesh {
  func data(_ address:UInt64,_ count:Int)throws->Data{try resource.slice(address:address,count:count)}
  func u16(_ d:Data,_ p:Int)->UInt16{UInt16(d[p])|UInt16(d[p+1])<<8}
  func u32(_ d:Data,_ p:Int)->UInt32{RPF7Archive.u32(d,p)}
  func u64(_ d:Data,_ p:Int)->UInt64{UInt64(u32(d,p))|UInt64(u32(d,p+4))<<32}
  func float(_ d:Data,_ p:Int)->Float{Float(bitPattern:u32(d,p))}
  let root=try data(rootAddress,168)
  let high=u64(root,80);guard high != 0 else{throw ArchiveFailure.unsupported("drawable has no high LOD")}
  let list=try data(high,16),count=Int(u16(list,8)),capacity=Int(u16(list,10))
  guard count>0,count<=512,count<=capacity else{throw ArchiveFailure.invalid("model array count")}
  let pointers=try data(u64(list,0),count*8)
  var positions:[Vec3]=[],indices:[UInt32]=[]
  for modelIndex in 0..<count {
   let model=try data(u64(pointers,modelIndex*8),48),geometries=Int(u16(model,16))
   guard geometries>0,geometries<=1024,u16(model,18)==u16(model,16),u16(model,46)==u16(model,16) else{throw ArchiveFailure.invalid("geometry count")}
   // Skinned models need the animation subsystem. Do not render incorrectly deformed data.
   guard (u32(model,40)>>24)==0 else{throw ArchiveFailure.unsupported("skinned drawable")}
   let geometryPointers=try data(u64(model,8),geometries*8)
   for geometryIndex in 0..<geometries {
    let geometry=try data(u64(geometryPointers,geometryIndex*8),152)
    let vertexCount=Int(u16(geometry,96)),indexCount=Int(u32(geometry,88)),strideBytes=Int(u16(geometry,112))
    guard vertexCount>0,vertexCount<=65535,indexCount>0,indexCount<=6_000_000,indexCount%3==0,u16(geometry,98)==3,strideBytes>=12,strideBytes<=256 else{throw ArchiveFailure.invalid("mesh counts/stride")}
    guard positions.count+vertexCount<=1_000_000,indices.count+indexCount<=6_000_000 else{throw ArchiveFailure.unsupported("drawable budget")}
    let vb=try data(u64(geometry,24),128),ib=try data(u64(geometry,56),96)
    guard Int(u16(vb,8))==strideBytes,Int(u32(vb,24))==vertexCount,Int(u32(ib,8))==indexCount else{throw ArchiveFailure.invalid("buffer count mismatch")}
    let declaration=try data(u64(vb,48),16)
    guard u32(declaration,0)&1==1,u16(declaration,4)==UInt16(strideBytes),u64(declaration,8)&15==6 else{throw ArchiveFailure.unsupported("position is not Float3")}
    let address=u64(vb,16)==0 ? u64(vb,32):u64(vb,16)
    let vertexBytes=try data(address,vertexCount*strideBytes),indexBytes=try data(u64(ib,16),indexCount*2)
    let base=UInt32(positions.count)
    for i in 0..<vertexCount {
     let at=i*strideBytes,v=Vec3(x:float(vertexBytes,at),y:float(vertexBytes,at+4),z:float(vertexBytes,at+8))
     guard v.finite,abs(v.x)<1_000_000,abs(v.y)<1_000_000,abs(v.z)<1_000_000 else{throw ArchiveFailure.invalid("non-finite/extreme vertex")}
     positions.append(v)
    }
    for i in 0..<indexCount{let index=Int(u16(indexBytes,i*2));guard index<vertexCount else{throw ArchiveFailure.invalid("triangle index")};indices.append(base+UInt32(index))}
   }
  }
  guard let first=positions.first else{throw ArchiveFailure.invalid("empty drawable")}
  var lo=first,hi=first,normals=[Vec3](repeating:.zero,count:positions.count)
  for v in positions{lo=Vec3(x:min(lo.x,v.x),y:min(lo.y,v.y),z:min(lo.z,v.z));hi=Vec3(x:max(hi.x,v.x),y:max(hi.y,v.y),z:max(hi.z,v.z))}
  for i in stride(from:0,to:indices.count,by:3){let a=Int(indices[i]),b=Int(indices[i+1]),c=Int(indices[i+2]),n=(positions[b]-positions[a]).cross(positions[c]-positions[a]);normals[a]=normals[a]+n;normals[b]=normals[b]+n;normals[c]=normals[c]+n}
  return StaticMesh(vertices:positions.indices.map{MeshVertex(position:positions[$0],normal:normals[$0].normalized)},indices:indices,bounds:Bounds3(min:lo,max:hi))
 }
}
