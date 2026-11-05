import Foundation
actor NativeSceneLoader {
 private var root:URL?
 private var key:Data?
 private var districtIndex:[UInt32:(RPF7Archive,RPF7Entry,UInt64)]?
 private var archetypes:[UInt32:UInt32]=[:]
 func releaseCaches(){districtIndex=nil;archetypes.removeAll()}

 func open(root:URL)throws {self.root=root;self.key=try AssetKey.derive(root:root);releaseCaches()}
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
 func mapNames()throws->[String]{
  guard let root,let key else{throw ArchiveFailure.invalid("game root not selected")}
  let file=try checked(root,"data/x64/levels/gta5/_citye/downtown_01/downtown_01_metadata.rpf")
  return try RPF7Archive(file:file,tableKey:key).entries.filter{$0.path.hasSuffix(".ymap")}.map{$0.path}
 }
 /// Bounded static sector preview, not full world streaming. Unsupported references are counted.
 func sector(_ name:String)throws->(mesh:StaticMesh,report:String){
  guard let root,let key else{throw ArchiveFailure.invalid("game root not selected")}
  let prefix="x64/levels/gta5/_citye/downtown_01/"
  let metadata=try RPF7Archive(file:checked(root,"data/"+prefix+"downtown_01_metadata.rpf"),tableKey:key)
  guard let entry=metadata.entries.first(where:{$0.path==name}) else{throw ArchiveFailure.invalid("map absent")}
  let map=try MapMetadata(metadata.resource(entry)).placements()
  let data=try Data(contentsOf:checked(root,"data/manifest.json"))
  guard let json=try JSONSerialization.jsonObject(with:data) as? [String:Any],let files=json["files"] as? [[Any]] else{throw ArchiveFailure.invalid("manifest files")}
  var index=districtIndex ?? [:]
  if districtIndex==nil {
  for row in files {
   try Task.checkCancellation()
   guard let path=row.first as? String,path.hasPrefix(prefix),path.hasSuffix(".rpf") else{continue}
   let archive=try RPF7Archive(file:checked(root,"data/"+path),tableKey:key)
   for e in archive.entries where e.path.hasSuffix(".ydr"){
    let hash=MapMetadata.hash(URL(fileURLWithPath:e.path).deletingPathExtension().lastPathComponent)
    if index[hash]==nil{index[hash]=(archive,e,0x50000000)}
   }
  }
   var dictionaries=0
   for row in files{
    try Task.checkCancellation()
    guard let path=row.first as? String,path.hasPrefix(prefix),path.hasSuffix(".rpf") else{continue}
    let archive=try RPF7Archive(file:checked(root,"data/"+path),tableKey:key)
    for e in archive.entries where e.path.hasSuffix(".ydd"){
     dictionaries+=1
     guard dictionaries<=512 else{throw ArchiveFailure.unsupported("district dictionary budget")}
     let roots=try DrawableDictionary.roots(archive.resource(e))
     for (hash,pointer) in roots where index[hash]==nil{index[hash]=(archive,e,pointer)}
    }
   }
   for e in metadata.entries where e.path.hasSuffix(".ytyp"){
    let aliases=try MapMetadata(metadata.resource(e)).aliases()
    for (name,asset) in aliases{archetypes[name]=asset}
   }
   districtIndex=index
  }
  var vertices:[MeshVertex]=[],indices:[UInt32]=[],loaded=0,missing=0,unsupported=map.unsupported
  var cache:[UInt32:StaticMesh]=[:]
  for entity in map.entities {
   try Task.checkCancellation()
   guard let (archive,entry,pointer)=index[archetypes[entity.archetype] ?? entity.archetype] else{missing+=1;continue}
   let mesh:StaticMesh
   if let existing=cache[entity.archetype]{mesh=existing}else{
    do{mesh=try DrawableMesh.decode(archive.resource(entry),rootAddress:pointer);cache[entity.archetype]=mesh}catch{unsupported+=1;continue}
   }
   guard vertices.count+mesh.vertices.count<=1500000,indices.count+mesh.indices.count<=4500000 else{throw ArchiveFailure.unsupported("sector preview geometry budget")}
   let base=UInt32(vertices.count)
   vertices += mesh.vertices.map{v in
    let position=entity.point(v.position)
    let unscaled=Vec3(x:v.normal.x/(entity.scaleXY*entity.scaleXY),y:v.normal.y/(entity.scaleXY*entity.scaleXY),z:v.normal.z/(entity.scaleZ*entity.scaleZ))
    return MeshVertex(position:position,normal:(entity.point(unscaled)-entity.position).normalized)
   }
   indices += mesh.indices.map{$0+base};loaded+=1
  }
  guard let first=vertices.first else{throw ArchiveFailure.unsupported("No supported geometry in this sector; unresolved or unsupported assets are not substituted.")}
  var lo=first.position,hi=lo
  for v in vertices{lo=Vec3(x:min(lo.x,v.position.x),y:min(lo.y,v.position.y),z:min(lo.z,v.position.z));hi=Vec3(x:max(hi.x,v.position.x),y:max(hi.y,v.position.y),z:max(hi.z,v.position.z))}
  return (StaticMesh(vertices:vertices,indices:indices,bounds:Bounds3(min:lo,max:hi)),"\(loaded)/\(map.entities.count) objects | \(missing) unresolved | \(unsupported) unsupported")
 }
 /// Combined integration scenario; each map preserves actual world coordinates.
 func integrationScene()throws->NativeWorldScene{
  var chunks:[StaticMesh]=[],reports:[String]=[]
  for name in ["fwy_01_long_0.ymap","fwy_02_long_0.ymap","fwy_04_long_0.ymap"]{
   let result=try sector(name);chunks.append(result.mesh);reports.append(name+": "+result.report)
   try NativeWorldScene(chunks:chunks,report:"").validate()
  }
  return NativeWorldScene(chunks:chunks,report:reports.joined(separator:"\n"))
 }
 private func checked(_ root:URL,_ archive:String)throws->URL {
  guard !archive.hasPrefix("/"),!archive.contains(".."),!archive.contains("\\") else{throw ArchiveFailure.invalid("archive path")}
  let file=root.appendingPathComponent(archive).resolvingSymlinksInPath()
  guard file.path.hasPrefix(root.resolvingSymlinksInPath().path+"/") else{throw ArchiveFailure.invalid("archive escapes data folder")};return file
 }
}
