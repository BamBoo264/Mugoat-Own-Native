import Foundation
/// Bounded metadata-only search. Never traverses asset trees or copies game data.
enum GameRootLocator {
 static let archive="data/x64/levels/gta5/generic/procobj.rpf"
 private static func regular(_ file:URL,under root:URL)->Bool {
  let base=root.resolvingSymlinksInPath().standardizedFileURL.path
  guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base+"/") else{return false}
  guard let values=try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]),values.isRegularFile==true,values.isSymbolicLink != true else{return false}
  return FileManager.default.isReadableFile(atPath:file.path)
 }
 static func valid(_ root:URL)->Bool {
  regular(root.appendingPathComponent("data/manifest.json"),under:root) && regular(root.appendingPathComponent(archive),under:root) && (regular(root.appendingPathComponent("b/8b0b5899ed/game.wasm"),under:root) || regular(root.appendingPathComponent("asset-aes.key"),under:root))
 }
 static func find(in selection:URL,maxDepth:Int=4,maxDirectories:Int=128)->URL? {
  if valid(selection){return selection}
  let fm=FileManager.default
  if selection.lastPathComponent.lowercased()=="data",fm.fileExists(atPath:selection.appendingPathComponent("manifest.json").path){return nil}
  if selection.lastPathComponent.lowercased()=="b",fm.fileExists(atPath:selection.appendingPathComponent("8b0b5899ed").path){return nil}
  var queue:[(URL,Int)]=[(selection,0)],cursor=0,inspected=0
  let skip:Set<String>=["mods","logs",".git"]
  while cursor<queue.count,cursor<maxDirectories {
   let (folder,depth)=queue[cursor];cursor+=1
   guard depth<maxDepth,let children=try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:.skipsHiddenFiles) else{continue}
   // Deterministic preference for the documented game folder.
   let sorted=children.sorted{a,b in if a.lastPathComponent=="game"{return b.lastPathComponent != "game"};if b.lastPathComponent=="game"{return false};return a.lastPathComponent<b.lastPathComponent}
   for child in sorted {
    guard !skip.contains(child.lastPathComponent.lowercased()),let flags=try? child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),flags.isDirectory==true,flags.isSymbolicLink != true else{continue}
    inspected+=1;guard inspected<=maxDirectories else{return nil}
    let name=child.lastPathComponent.lowercased()
    if name=="data",fm.fileExists(atPath:child.appendingPathComponent("manifest.json").path){continue}
    if name=="b",fm.fileExists(atPath:child.appendingPathComponent("8b0b5899ed").path){continue}
    if valid(child){return child}
    if queue.count<maxDirectories{queue.append((child,depth+1))}
   }
  }
  return nil
 }
 static let instructions="""
 Chép nguyên thư mục game vào đây bằng ứng dụng Tệp:
 Trên iPhone → Mugoat Own Engine Lab → game

 Bên trong game cần có:
 data/manifest.json
 data/x64/levels/gta5/generic/procobj.rpf
 b/8b0b5899ed/game.wasm

 Không giải nén RPF. Không dùng bộ GTAV_IOS khác định dạng.
 Mở lại app hoặc nhấn Data → Tìm trong Documents.
 App đọc trực tiếp, không tạo thêm bản sao 20 GB.
 """
 static func prepareDocuments(_ documents:URL){
  try? FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
  let file=documents.appendingPathComponent("HUONG-DAN-DATA.txt")
  if !FileManager.default.fileExists(atPath:file.path){try? instructions.write(to:file,atomically:true,encoding:.utf8)}
 }
}
