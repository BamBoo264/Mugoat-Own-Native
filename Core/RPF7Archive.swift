import Foundation

/// Original read-only archive layer. Reads tables/ranges, never maps an entire game archive.
enum ArchiveFailure:LocalizedError {
 case invalid(String),unsupported(String)
 var errorDescription:String?{switch self{case .invalid(let s):return "Invalid RPF7: "+s;case .unsupported(let s):return "Unsupported RPF7: "+s}}
}
struct RPF7Entry {
 let path:String
 let resource:Bool
 let offset:UInt64
 let stored:UInt64
 let size:UInt64
 let flags:UInt32
 let graphics:UInt32
}
final class RPF7Archive {
 private let tableKey:Data?
 private let file:URL
 private let base:UInt64
 private let length:UInt64
 let entries:[RPF7Entry]
 var identity:String{file.standardizedFileURL.path+"@"+String(base)+":"+String(length)}
 static func u32(_ b:Data,_ at:Int)->UInt32{(0..<4).reduce(UInt32(0)){$0 | UInt32(b[at+$1]) << (8*$1)}}
 static func span(_ offset:UInt64,_ count:UInt64,_ total:UInt64)->Bool{offset<=total && count<=total-offset}
 private static func read(_ file:URL,_ base:UInt64,_ length:UInt64,_ offset:UInt64,_ count:UInt64)throws->Data {
  guard span(offset,count,length),count<=64<<20 else{throw ArchiveFailure.invalid("read range/limit")}
  let h=try FileHandle(forReadingFrom:file);defer{try? h.close()}
  try h.seek(toOffset:base+offset);let bytes=try h.read(upToCount:Int(count)) ?? Data()
  guard bytes.count==Int(count) else{throw ArchiveFailure.invalid("short read")};return bytes
 }
 init(file:URL,base:UInt64=0,length:UInt64?=nil,tableKey:Data?=nil)throws {
  self.tableKey=tableKey
  if let tableKey,tableKey.count != 32{throw ArchiveFailure.invalid("AES key length")}
  self.file=file;self.base=base
  let size=UInt64(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)
  guard base<=size else{throw ArchiveFailure.invalid("base")}
  let total=length ?? size-base;self.length=total
  guard total>=16,Self.span(base,total,size) else{throw ArchiveFailure.invalid("archive range")}
  let header=try Self.read(file,base,total,0,16)
  guard Self.u32(header,0)==0x52504637 else{throw ArchiveFailure.invalid("magic")}
  let count=UInt64(Self.u32(header,4)),namesCount=UInt64(Self.u32(header,8)),key=Self.u32(header,12)
  guard key==0 || key==0x4e45504f || key==0x0ffffff9 else{throw ArchiveFailure.unsupported("archive encryption variant")}
  let tableEnd=16+count*16+namesCount
  guard count>0,count<=1_000_000,namesCount<=64<<20,tableEnd<=total else{throw ArchiveFailure.invalid("table bounds")}
  func tableBytes(_ offset:UInt64,_ length:UInt64)throws->Data {
   let input=try Self.read(file,base,total,offset,length)
   guard key==0x0ffffff9 else{return input}
   guard let tableKey,length%16==0 else{throw ArchiveFailure.unsupported("AES table needs private asset key")}
   var output=Data(count:input.count)
   let valid=output.withUnsafeMutableBytes{o in tableKey.withUnsafeBytes{k in input.withUnsafeBytes{i in rb_aes256_ecb(i.baseAddress,UInt32(input.count),k.baseAddress,o.baseAddress)}}}
   guard valid==1 else{throw ArchiveFailure.invalid("AES table decoding")};return output
  }
  let table=try tableBytes(16,count*16),names=try tableBytes(16+count*16,namesCount)
  struct Row {let name:String;let directory:Bool;let resource:Bool;let at:UInt64;let stored:UInt64;let size:UInt64;let flags:UInt32;let graphics:UInt32}
  var rows:[Row]=[];rows.reserveCapacity(Int(count))
  for index in 0..<Int(count) {
   let pos=index*16,a=Self.u32(table,pos),b=Self.u32(table,pos+4),c=Self.u32(table,pos+8),d=Self.u32(table,pos+12)
   let directory=b==0x7fffff00,resource=b&0x80000000 != 0,nameAt=Int(directory ? a:a&0xffff)
   guard nameAt<names.count,let end=names[nameAt...].firstIndex(of:0),end-nameAt<=255,let name=String(data:names[nameAt..<end],encoding:.utf8),!name.contains("/"),!name.contains("\\"),name != ".",name != ".." else{throw ArchiveFailure.invalid("name index/encoding")}
   if directory{rows.append(Row(name:name,directory:true,resource:false,at:UInt64(c),stored:UInt64(d),size:0,flags:0,graphics:0));continue}
   var stored=UInt64(a>>16 | (b&255)<<16)
   let offset=UInt64((b>>8)&(resource ? 0x7fffff:0xffffff))*512
   if resource && stored==0xffffff {
    let ext=try Self.read(file,base,total,offset,16)
    stored=UInt64(ext[7]) | UInt64(ext[14])<<8 | UInt64(ext[5])<<16 | UInt64(ext[2])<<24
   }
   let size=resource ? stored:UInt64(c),actual=stored==0 ? size:stored
   guard offset>=tableEnd,Self.span(offset,actual,total) else{throw ArchiveFailure.invalid("entry payload range")}
   rows.append(Row(name:name,directory:false,resource:resource,at:offset,stored:stored,size:size,flags:resource ? c:d,graphics:resource ? d:0))
  }
  guard rows[0].directory else{throw ArchiveFailure.invalid("root must be directory")}
  var visited=Set<Int>(),paths=Set<String>(),result:[RPF7Entry]=[]
  func walk(_ index:Int,_ parent:String,_ depth:Int)throws {
   guard depth<=64,visited.insert(index).inserted else{throw ArchiveFailure.invalid("cycle/repeated child")}
   let row=rows[index],path=index==0 ? "":parent.isEmpty ? row.name:parent+"/"+row.name
   guard paths.insert(path.lowercased()).inserted else{throw ArchiveFailure.invalid("duplicate path")}
   if row.directory {
    guard Self.span(row.at,row.stored,count) else{throw ArchiveFailure.invalid("directory range")}
    for child in row.at..<(row.at+row.stored){try walk(Int(child),path,depth+1)}
   }else{result.append(RPF7Entry(path:path,resource:row.resource,offset:row.at,stored:row.stored,size:row.size,flags:row.flags,graphics:row.graphics))}
  }
  try walk(0,"",0)
  guard visited.count==Int(count) else{throw ArchiveFailure.invalid("orphan entry")};entries=result
 }
 func binary(_ entry:RPF7Entry,limit:UInt64=64<<20)throws->Data {
  guard !entry.resource,entry.flags==0 else{throw ArchiveFailure.unsupported("encrypted/resource binary read")}
  guard entry.size<=limit,entry.size<=64<<20 else{throw ArchiveFailure.invalid("decompression cap")}
  let packed=try Self.read(file,base,length,entry.offset,entry.stored==0 ? entry.size:entry.stored)
  if entry.stored==0{return packed}
  var output=Data(count:Int(entry.size))
  let result=output.withUnsafeMutableBytes{o in packed.withUnsafeBytes{i in rb_inflate(i.baseAddress,UInt32(packed.count),o.baseAddress,UInt32(entry.size))}}
  guard result==1 else{throw ArchiveFailure.invalid("deflate length/trailing bytes")};return output
 }
 func resource(_ entry:RPF7Entry)throws->ResourceMemory {
  guard entry.resource,entry.stored>=16 else{throw ArchiveFailure.invalid("not a resource")}
  return try ResourceMemory.decode(Self.read(file,base,length,entry.offset,entry.stored),system:entry.flags,graphics:entry.graphics)
 }
 func nested(_ entry:RPF7Entry)throws->RPF7Archive {
  guard !entry.resource,entry.flags==0,entry.stored==0 else{throw ArchiveFailure.unsupported("nested archive is not plain storage")}
  return try RPF7Archive(file:file,base:base+entry.offset,length:entry.size,tableKey:tableKey)
 }
}
