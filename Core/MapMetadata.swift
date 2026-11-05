import Foundation
/// Independently authored bounded PRD0 metadata reader. No native pointer dereferencing.
struct MapPlacement {
 let archetype:UInt32
 let position:Vec3
 let quaternion:(Float,Float,Float,Float)
 let scaleXY:Float,scaleZ:Float
 let lod:Int32
 func point(_ value:Vec3)->Vec3 {
  let v=Vec3(x:value.x*scaleXY,y:value.y*scaleXY,z:value.z*scaleZ)
  // CEntityDef stores the inverse orientation.
  let q=Vec3(x:-quaternion.0,y:-quaternion.1,z:-quaternion.2),t=q.cross(v)*2
  return v+t*quaternion.3+q.cross(t)+position
 }
}
struct MapMetadata {
 struct Block {let kind:UInt32;let bytes:Data}
 let blocks:[Block]
 let root:Int
 static func u64(_ d:Data,_ at:Int)->UInt64{(0..<8).reduce(UInt64(0)){$0|UInt64(d[at+$1]) << (8*$1)}}
 static func u16(_ d:Data,_ at:Int)->Int{Int(d[at])|Int(d[at+1])<<8}
 static func float(_ d:Data,_ at:Int)->Float{Float(bitPattern:RPF7Archive.u32(d,at))}
 init(_ memory:ResourceMemory)throws {
  let h=try memory.slice(address:0x50000000,count:112)
  guard RPF7Archive.u32(h,16)==0x50524430,Self.u16(h,20)==0x79 else{throw ArchiveFailure.unsupported("metadata version")}
  let count=Self.u16(h,76),rootIndex=Int(RPF7Archive.u32(h,28))
  guard count>0,count<=4096,rootIndex>0,rootIndex<=count else{throw ArchiveFailure.invalid("metadata block count/root")}
  let table=try memory.slice(address:Self.u64(h,48),count:count*16)
  var result:[Block]=[]
  for i in 0..<count {
   let at=i*16,n=Int(RPF7Archive.u32(table,at+4))
   guard n<=64<<20 else{throw ArchiveFailure.invalid("metadata block budget")}
   result.append(Block(kind:RPF7Archive.u32(table,at),bytes:try memory.slice(address:Self.u64(table,at+8),count:n)))
  }
  blocks=result;root=rootIndex-1
 }
 func span(_ pointer:UInt64,_ count:Int,kind:UInt32?=nil)throws->Data {
  let id=Int(pointer&0xfff),offset=pointer>>12
  guard id>0,id<=blocks.count,count>=0 else{throw ArchiveFailure.invalid("metadata pointer")}
  let b=blocks[id-1]
  guard kind==nil || kind==b.kind,RPF7Archive.span(offset,UInt64(count),UInt64(b.bytes.count)) else{throw ArchiveFailure.invalid("metadata pointer span/type")}
  return b.bytes.subdata(in:Int(offset)..<(Int(offset)+count))
 }
 func placements()throws->(entities:[MapPlacement],unsupported:Int) {
  let b=blocks[root]
  guard b.kind==0xd3593fa6,b.bytes.count>=512 else{throw ArchiveFailure.unsupported("not CMapData")}
  let n=Self.u16(b.bytes,104),capacity=Self.u16(b.bytes,106)
  guard n<=capacity,n<=8192 else{throw ArchiveFailure.invalid("entity count")}
  if n==0{return ([],0)}
  let pointers=try span(Self.u64(b.bytes,96),n*8)
  var result:[MapPlacement]=[],skipped=0
  for i in 0..<n {
   let ptr=Self.u64(pointers,i*8),id=Int(ptr&0xfff)
   guard id>0,id<=blocks.count else{throw ArchiveFailure.invalid("entity block")}
   guard blocks[id-1].kind==0xce501483 else{skipped+=1;continue}
   let e=try span(ptr,128,kind:0xce501483)
   let pos=Vec3(x:Self.float(e,32),y:Self.float(e,36),z:Self.float(e,40))
   let q=(Self.float(e,48),Self.float(e,52),Self.float(e,56),Self.float(e,60)),xy=Self.float(e,64),z=Self.float(e,68)
   let norm=q.0*q.0+q.1*q.1+q.2*q.2+q.3*q.3
   guard pos.finite,pos.length<1000000,norm.isFinite,abs(norm-1)<0.01,xy.isFinite,z.isFinite,xy>0,z>0,xy<=100,z<=100 else{throw ArchiveFailure.invalid("entity transform")}
   result.append(MapPlacement(archetype:RPF7Archive.u32(e,8),position:pos,quaternion:q,scaleXY:xy,scaleZ:z,lod:Int32(bitPattern:RPF7Archive.u32(e,84))))
  }
  return (result,skipped)
 }
 /// Only verified base/time archetypes; MLO and legacy layouts are not guessed.
 func aliases()throws->[UInt32:UInt32]{
  let b=blocks[root]
  guard b.kind==0xd98bb561,b.bytes.count>=80 else{throw ArchiveFailure.unsupported("not CMapTypes")}
  let n=Self.u16(b.bytes,32),capacity=Self.u16(b.bytes,34)
  guard n<=capacity,n<=16384 else{throw ArchiveFailure.invalid("archetype count")}
  if n==0{return [:]}
  let refs=try span(Self.u64(b.bytes,24),n*8)
  var result:[UInt32:UInt32]=[:]
  for i in 0..<n {
   let ptr=Self.u64(refs,i*8),id=Int(ptr&0xfff)
   guard id>0,id<=blocks.count else{throw ArchiveFailure.invalid("archetype block")}
   let kind=blocks[id-1].kind
   guard kind==0x82d6fc83 || kind==0x76b0c56c else{continue}
   let e=try span(ptr,kind==0x82d6fc83 ? 144:160)
   // assetType 3 is a drawable. Dictionary/interior types require separate loaders.
   guard RPF7Archive.u32(e,108)==3 else{continue}
   let name=RPF7Archive.u32(e,88),asset=RPF7Archive.u32(e,112)
   if name != 0,asset != 0{result[name]=asset}
  }
  return result
 }
 static func hash(_ name:String)->UInt32 {
  var h:UInt32=0
  for c in name.lowercased().utf8{h=h&+UInt32(c);h=h&+(h<<10);h ^= h>>6}
  h=h&+(h<<3);h ^= h>>11;return h&+(h<<15)
 }
}
