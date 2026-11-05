import Foundation
struct Vec3:Equatable {
 var x:Float;var y:Float;var z:Float
 static let zero=Vec3(x:0,y:0,z:0)
 static func +(a:Self,b:Self)->Self{Self(x:a.x+b.x,y:a.y+b.y,z:a.z+b.z)}
 static func -(a:Self,b:Self)->Self{Self(x:a.x-b.x,y:a.y-b.y,z:a.z-b.z)}
 static func *(a:Self,b:Float)->Self{Self(x:a.x*b,y:a.y*b,z:a.z*b)}
 func dot(_ b:Self)->Float{x*b.x+y*b.y+z*b.z}
 func cross(_ b:Self)->Self{Self(x:y*b.z-z*b.y,y:z*b.x-x*b.z,z:x*b.y-y*b.x)}
 var length:Float{sqrt(dot(self))}
 var normalized:Self{let n=length;return n>0.00001 ? self*(1/n):Self(x:0,y:0,z:1)}
 var finite:Bool{x.isFinite&&y.isFinite&&z.isFinite}
}
struct Bounds3 {
 var min:Vec3;var max:Vec3
 var center:Vec3{(min+max)*0.5}
 var radius:Float{(max-min).length*0.5}
 func overlaps(_ other:Self)->Bool{min.x<=other.max.x&&max.x>=other.min.x&&min.y<=other.max.y&&max.y>=other.min.y&&min.z<=other.max.z&&max.z>=other.min.z}
}
struct Triangle {
 let a:Vec3;let b:Vec3;let c:Vec3
 var normal:Vec3{(b-a).cross(c-a).normalized}
 func ray(origin:Vec3,direction:Vec3,maxDistance:Float)->Float?{
  let e1=b-a,e2=c-a,p=direction.cross(e2),det=e1.dot(p)
  guard abs(det)>0.000001 else{return nil}
  let inverse=1/det,t=origin-a,u=t.dot(p)*inverse
  guard u>=0,u<=1 else{return nil}
  let q=t.cross(e1),v=direction.dot(q)*inverse
  guard v>=0,u+v<=1 else{return nil}
  let distance=e2.dot(q)*inverse
  return distance>=0&&distance<=maxDistance ? distance:nil
 }
}
struct FixedStepClock {
 let step:Double=1.0/60.0
 private(set) var accumulator:Double=0
 private(set) var droppedTime:Double=0
 mutating func advance(_ elapsed:Double,update:(Float)->Void){
  guard elapsed.isFinite,elapsed>0 else{return}
  let bounded=min(elapsed,0.1);droppedTime+=max(0,elapsed-bounded);accumulator+=bounded
  var count=0
  while accumulator>=step&&count<6{update(Float(step));accumulator-=step;count+=1}
 }
}
