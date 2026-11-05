import Foundation
/// Resource layout facts only; independently implemented bounded dictionary reader.
enum DrawableDictionary {
 static func roots(_ memory:ResourceMemory,address:UInt64=0x50000000)throws->[UInt32:UInt64]{
  let h=try memory.slice(address:address,count:64)
  let count=MapMetadata.u16(h,40)
  guard count>0,count<=8192,count==MapMetadata.u16(h,56),count<=MapMetadata.u16(h,42),count<=MapMetadata.u16(h,58) else{throw ArchiveFailure.invalid("drawable dictionary counts")}
  let hashes=try memory.slice(address:MapMetadata.u64(h,32),count:count*4)
  let pointers=try memory.slice(address:MapMetadata.u64(h,48),count:count*8)
  var result:[UInt32:UInt64]=[:]
  for i in 0..<count{
   let hash=RPF7Archive.u32(hashes,i*4),pointer=MapMetadata.u64(pointers,i*8)
   _ = try memory.slice(address:pointer,count:168)
   guard result[hash]==nil else{throw ArchiveFailure.invalid("duplicate drawable hash")}
   result[hash]=pointer
  }
  return result
 }
}
