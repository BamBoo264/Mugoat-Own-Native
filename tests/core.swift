import Foundation
@main struct CoreTests {
 static func main()throws {
  let dir=URL(fileURLWithPath:CommandLine.arguments[1]),url=dir.appendingPathComponent("fixture.rpf")
  let key=Data((0..<32).map{UInt8($0)})
  let archive=try RPF7Archive(file:url,tableKey:key)
  assert(archive.entries.count==1&&archive.entries[0].path=="fixture.ydr")
  let mesh=try DrawableMesh.decode(archive.resource(archive.entries[0]))
  assert(mesh.vertices.count==3&&mesh.triangleCount==1)
  assert(abs(mesh.groundHeight(x:0,y:0,above:5,reach:10)!)<0.0001)
  assert(mesh.groundHeight(x:100,y:100,above:5,reach:10)==nil)
  do{_ = try RPF7Archive(file:url,tableKey:Data(repeating:0,count:32));fatalError("Wrong key accepted")}catch{}
  let triangle=Triangle(a:Vec3(x:-1,y:-1,z:0),b:Vec3(x:1,y:-1,z:0),c:Vec3(x:0,y:1,z:0))
  assert(triangle.ray(origin:Vec3(x:0,y:0,z:2),direction:Vec3(x:0,y:0,z:-1),maxDistance:3)==2)
  assert(triangle.ray(origin:Vec3(x:2,y:2,z:2),direction:Vec3(x:0,y:0,z:-1),maxDistance:3)==nil)
  var clock=FixedStepClock(),updates=0
  clock.advance(1){_ in updates+=1};assert(updates<=6&&clock.droppedTime>0.89)
  let bytes=try Data(contentsOf:dir.appendingPathComponent("resource.bin"))
  var corrupt=bytes;corrupt[0x700]=7
  do{_ = try DrawableMesh.decode(ResourceMemory(bytes:corrupt,systemBytes:16384,graphicsBytes:0));fatalError("Bad index accepted")}catch{}
  corrupt=bytes;corrupt.replaceSubrange(0x600..<0x604,with:[0,0,192,127])
  do{_ = try DrawableMesh.decode(ResourceMemory(bytes:corrupt,systemBytes:16384,graphicsBytes:0));fatalError("NaN accepted")}catch{}
  do{_ = try ResourceMemory(bytes:bytes,systemBytes:16384,graphicsBytes:0).slice(address:0x60000000,count:1);fatalError("Segment overflow accepted")}catch{}
  let fm=FileManager.default,search=dir.appendingPathComponent("folder-search"),game=search.appendingPathComponent("game")
  func gameRoot(_ root:URL)throws{
   for file in ["data/manifest.json","data/x64/levels/gta5/generic/procobj.rpf","asset-aes.key"]{
    let url=root.appendingPathComponent(file);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data([1]).write(to:url)
   }
  }
  try gameRoot(game)
  assert(GameRootLocator.find(in:search)?.standardizedFileURL.path==game.standardizedFileURL.path)
  assert(GameRootLocator.find(in:game)==game)
  assert(GameRootLocator.find(in:game.appendingPathComponent("data"))==nil)
  assert(GameRootLocator.find(in:search,maxDepth:0)==nil)
  let nested=dir.appendingPathComponent("nested/a/b/game");try gameRoot(nested)
  assert(GameRootLocator.find(in:dir.appendingPathComponent("nested"))?.standardizedFileURL.path==nested.standardizedFileURL.path)
  let onlyLink=dir.appendingPathComponent("only-symlink");try fm.createDirectory(at:onlyLink,withIntermediateDirectories:true)
  try fm.createSymbolicLink(at:onlyLink.appendingPathComponent("game"),withDestinationURL:game)
  assert(GameRootLocator.find(in:onlyLink)==nil)
  let empty=dir.appendingPathComponent("new-documents");GameRootLocator.prepareDocuments(empty)
  assert(fm.fileExists(atPath:empty.appendingPathComponent("HUONG-DAN-DATA.txt").path))
  assert(GameRootLocator.find(in:empty)==nil)
  // Synthetic PRD0: one translated entity, with pointers into three validated blocks.
  var meta=Data(repeating:0,count:1024)
  func put(_ offset:Int,_ value:UInt64,_ count:Int){for i in 0..<count{meta[offset+i]=UInt8(truncatingIfNeeded:value >> (8*i))}}
  put(16,0x50524430,4);put(20,0x79,2);put(28,1,4);put(48,0x50000070,8);put(76,3,2)
  put(112,0xd3593fa6,4);put(116,512,4);put(120,0x50000100,8)
  put(128,0xce501483,4);put(132,128,4);put(136,0x50000300,8)
  put(144,7,4);put(148,8,4);put(152,0x50000380,8)
  put(256+96,3,8);put(256+104,1,2);put(256+106,1,2);put(896,2,8)
  put(768+8,123,4);put(768+32,UInt64(Float(10).bitPattern),4)
  for at in [768+60,768+64,768+68]{put(at,UInt64(Float(1).bitPattern),4)}
  let document=try MapMetadata(ResourceMemory(bytes:meta,systemBytes:1024,graphicsBytes:0))
  let placements=try document.placements();assert(placements.entities.count==1)
  assert(placements.entities[0].point(Vec3(x:1,y:2,z:3))==Vec3(x:11,y:2,z:3))
  do{_ = try document.span(0xfffff002,128);fatalError("Metadata overflow accepted")}catch{}
  put(768+60,UInt64(Float.nan.bitPattern),4)
  do{_ = try MapMetadata(ResourceMemory(bytes:meta,systemBytes:1024,graphicsBytes:0)).placements();fatalError("Bad quaternion accepted")}catch{}
  assert(MapMetadata.hash("ADDER")==MapMetadata.hash("adder"))
  print("PASS: AES archive, opaque resource prefix, geometry, index/NaN rejection, ray collision, fixed timestep, Documents/nested folder discovery and symlink rejection")
 }
}
