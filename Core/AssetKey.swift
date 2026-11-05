import Foundation
enum AssetKey {
 static func derive(root:URL)throws->Data {
  let direct=root.appendingPathComponent("asset-aes.key")
  if FileManager.default.fileExists(atPath:direct.path){let key=try Data(contentsOf:direct);guard key.count==32 else{throw ArchiveFailure.invalid("private asset key length")};return key}
  // Read only the data section to obtain a private asset key. No WASM code is executed.
  let input=root.appendingPathComponent("b/8b0b5899ed/game.wasm")
  let bytes=try Data(contentsOf:input,options:.mappedIfSafe)
  guard bytes.count<=256<<20,bytes.prefix(8)==Data([0,97,115,109,1,0,0,0]) else{throw ArchiveFailure.invalid("asset-key input")}
  func leb(_ at:Int)throws->(Int,Int){var value=0,shift=0,p=at;for _ in 0..<5{guard p<bytes.count else{throw ArchiveFailure.invalid("LEB span")};let b=Int(bytes[p]);p+=1;value|=(b&127)<<shift;if b&128==0{return(value,p)};shift+=7};throw ArchiveFailure.invalid("LEB overflow")}
  var position=8
  while position<bytes.count {
   let section=bytes[position],(length,begin)=try leb(position+1)
   guard length<=bytes.count-begin else{throw ArchiveFailure.invalid("runtime data section bounds")}
   if section==11 {
    var key=Data(count:32)
    let found=key.withUnsafeMutableBytes{o in bytes.withUnsafeBytes{input in rb_find_asset_key(input.baseAddress!.advanced(by:begin),UInt32(length),o.baseAddress)}}
    if found==1{return key}
   }
   position=begin+length
  }
  throw ArchiveFailure.unsupported("private asset key fingerprint not found")
 }
}
