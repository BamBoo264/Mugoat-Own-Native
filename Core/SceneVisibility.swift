import Foundation
struct ScenePlane {
 let normal:Vec3
 let distance:Float
 func excludes(_ b:Bounds3)->Bool{
  let p=Vec3(x:normal.x>=0 ? b.max.x:b.min.x,y:normal.y>=0 ? b.max.y:b.min.y,z:normal.z>=0 ? b.max.z:b.min.z)
  return normal.dot(p)+distance < 0
 }
}
struct SceneVisibility {
 let planes:[ScenePlane]
 func contains(_ b:Bounds3)->Bool{!planes.contains{$0.excludes(b)}}
}
struct NativeWorldScene {
 let chunks:[StaticMesh]
 let report:String
 var bytes:Int{chunks.reduce(0){$0+$1.vertices.count*24+$1.indices.count*4}}
 func validate(budget:Int=96<<20)throws {
  guard !chunks.isEmpty,chunks.count<=64,bytes<=budget else{throw ArchiveFailure.unsupported("world scene budget")}
  for m in chunks{
   guard !m.vertices.isEmpty,!m.indices.isEmpty,m.indices.count%3==0,m.bounds.min.finite,m.bounds.max.finite,
    m.bounds.min.x<=m.bounds.max.x,m.bounds.min.y<=m.bounds.max.y,m.bounds.min.z<=m.bounds.max.z else{throw ArchiveFailure.invalid("scene bounds/count")}
   guard m.vertices.allSatisfy({$0.position.finite && $0.normal.finite}),m.indices.allSatisfy({UInt64($0)<UInt64(m.vertices.count)}) else{throw ArchiveFailure.invalid("scene vertices/indices")}
  }
 }
}
