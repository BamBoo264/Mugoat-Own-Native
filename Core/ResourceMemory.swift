import Foundation
struct ResourceMemory {
 let bytes:Data
 let systemBytes:Int
 let graphicsBytes:Int
 /// Resource pointers are tagged virtual/physical offsets, never native pointers.
 func slice(address:UInt64,count:Int)throws->Data {
  guard count>=0 else{throw ArchiveFailure.invalid("negative resource span")}
  let offset:UInt64,limit:UInt64,base:Int
  if address>=0x50000000 && address<0x60000000{offset=address-0x50000000;limit=UInt64(systemBytes);base=0}
  else if address>=0x60000000 && address<0x70000000{offset=address-0x60000000;limit=UInt64(graphicsBytes);base=systemBytes}
  else{throw ArchiveFailure.invalid("resource pointer tag")}
  guard RPF7Archive.span(offset,UInt64(count),limit) else{throw ArchiveFailure.invalid("resource segment bounds")}
  let at=base+Int(offset);return bytes.subdata(in:at..<(at+count))
 }
 static func segmentBytes(_ flags:UInt32)->Int {
  let base=512 << Int(flags&15)
  let fields:[(UInt32,UInt32,Int)]=[(27,1,1),(26,1,2),(25,1,4),(24,1,8),(17,127,16),(11,63,32),(7,15,64),(5,3,128),(4,1,256)]
  return fields.reduce(0){$0+Int((flags >> $1.0)&$1.1)*$1.2}*base
 }
 static func decode(_ input:Data,system:UInt32,graphics:UInt32)throws->ResourceMemory {
  // In-archive RPF resources may use an opaque 16-byte prefix rather than standalone RSC7.
  guard input.count>=16 else{throw ArchiveFailure.invalid("resource prefix")}
  let systemSize=segmentBytes(system),graphicsSize=segmentBytes(graphics),total=systemSize+graphicsSize
  guard systemSize>0,total<=64<<20 else{throw ArchiveFailure.unsupported("resource memory cap")}
  let payload=input.subdata(in:16..<input.count)
  var output=Data(count:total)
  let zstd=payload.count>=4 && RPF7Archive.u32(payload,0)==0xfd2fb528
  let result=output.withUnsafeMutableBytes{o in payload.withUnsafeBytes{i in
   zstd ? rb_zstd(i.baseAddress,UInt32(payload.count),o.baseAddress,UInt32(total)):rb_inflate(i.baseAddress,UInt32(payload.count),o.baseAddress,UInt32(total))
  }}
  guard result==1 else{throw ArchiveFailure.invalid("resource decompression/size")}
  return ResourceMemory(bytes:output,systemBytes:systemSize,graphicsBytes:graphicsSize)
 }
}
