import Foundation
actor NativeSceneLoader {
 private var root:URL?
 private var key:Data?
 func open(root:URL)throws {self.root=root;self.key=try AssetKey.derive(root:root)}
 func assets(archive:String)throws->[String]{
  guard let root,let key else{throw ArchiveFailure.invalid("game root not selected")}
  let file=try checked(root,archive)
  return try RPF7Archive(file:file,tableKey:key).entries.filter{$0.path.hasSuffix(".ydr")}.map{$0.path}
 }
 func load(archive:String,asset:String)throws->StaticMesh{
  guard let root,let key else{throw ArchiveFailure.invalid("game root not selected")}
  let file=try checked(root,archive),rpf=try RPF7Archive(file:file,tableKey:key)
  guard let entry=rpf.entries.first(where:{$0.path==asset}) else{throw ArchiveFailure.invalid("model absent: "+asset)}
  return try DrawableMesh.decode(rpf.resource(entry))
 }
 private func checked(_ root:URL,_ archive:String)throws->URL {
  guard !archive.hasPrefix("/"),!archive.contains(".."),!archive.contains("\\") else{throw ArchiveFailure.invalid("archive path")}
  let file=root.appendingPathComponent(archive).resolvingSymlinksInPath()
  guard file.path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{throw ArchiveFailure.invalid("archive escapes data folder")};return file
 }
}
