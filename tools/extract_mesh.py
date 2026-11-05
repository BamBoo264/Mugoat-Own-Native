"""Independent local static mesh extraction/validation. No original asset is modified or uploaded."""
from pathlib import Path
import argparse,struct,math,zlib,json,sys
sys.path.insert(0,str(Path(__file__).parents[1]/'build/audit-deps'))
from compression import zstd
from rpf7 import RPF7,RPFError

def segment(flags):
 base=512<<(flags&15)
 return sum(((flags>>bit)&mask)*weight for bit,mask,weight in [(27,1,1),(26,1,2),(25,1,4),(24,1,8),(17,127,16),(11,63,32),(7,15,64),(5,3,128),(4,1,256)])*base

def decode(raw,system,graphics,root_address=0x50000000):
 if len(raw)<16:raise ValueError('resource prefix')
 sy,gp=segment(system),segment(graphics)
 if not sy or sy+gp>64<<20:raise ValueError('resource budget')
 payload=raw[16:];decoder=zstd.ZstdDecompressor() if payload[:4]==bytes.fromhex('28b52ffd') else zlib.decompressobj(-15)
 data=decoder.decompress(payload,sy+gp+1)
 if not decoder.eof or decoder.unused_data:raise ValueError('compression boundaries')
 if len(data)!=sy+gp:raise ValueError('resource length')
 def span(address,n):
  if 0x50000000<=address<0x60000000:offset=address-0x50000000;size=sy;base=0
  elif 0x60000000<=address<0x70000000:offset=address-0x60000000;size=gp;base=sy
  else:raise ValueError('pointer tag')
  if n<0 or offset>size or n>size-offset:raise ValueError('pointer bounds')
  return data[base+offset:base+offset+n]
 def u16(b,p):return struct.unpack_from('<H',b,p)[0]
 def u32(b,p):return struct.unpack_from('<I',b,p)[0]
 def u64(b,p):return struct.unpack_from('<Q',b,p)[0]
 root=span(root_address,168);header=span(u64(root,80),16);count=u16(header,8)
 if count<1 or count>512 or count>u16(header,10):raise ValueError('model count')
 models=span(u64(header,0),count*8);vertices=[];indices=[]
 for i in range(count):
  model=span(u64(models,i*8),48);n=u16(model,16)
  if not 0<n<=1024 or n!=u16(model,18) or n!=u16(model,46):raise ValueError('geometry count')
  if u32(model,40)>>24:raise ValueError('skinned geometry needs animation')
  geoms=span(u64(model,8),n*8)
  for g in range(n):
   geo=span(u64(geoms,g*8),152);nv=u16(geo,96);ni=u32(geo,88);stride=u16(geo,112)
   if not 0<nv<=65535 or not 0<ni<=6000000 or ni%3 or not 12<=stride<=256 or u16(geo,98)!=3:raise ValueError('mesh counts')
   vb=span(u64(geo,24),128);ib=span(u64(geo,56),96)
   if u16(vb,8)!=stride or u32(vb,24)!=nv or u32(ib,8)!=ni:raise ValueError('buffer count mismatch')
   decl=span(u64(vb,48),16)
   if not u32(decl,0)&1 or u16(decl,4)!=stride or u64(decl,8)&15!=6:raise ValueError('Float3 position unsupported')
   vs=span(u64(vb,16) or u64(vb,32),nv*stride);ix=span(u64(ib,16),ni*2);base=len(vertices)
   for k in range(nv):
    v=struct.unpack_from('<3f',vs,k*stride)
    if not all(math.isfinite(x) and abs(x)<1000000 for x in v):raise ValueError('invalid vertex')
    vertices.append(v)
   values=struct.unpack('<'+'H'*ni,ix)
   if max(values)>=nv:raise ValueError('bad index')
   indices.extend(base+x for x in values)
 return vertices,indices

def extract(archive,entry,output,key=None):
 a=RPF7(archive,key=key);e=next(e for e in a.entries if e.path.lower()==entry.lower())
 vs,ix=decode(a.read(e.offset,e.stored),e.flags,e.graphics)
 if output.exists():raise ValueError('Output exists')
 with output.open('wb') as f:
  f.write(struct.pack('<4sII',b'MNM1',len(vs),len(ix)))
  for v in vs:f.write(struct.pack('<3f',*v))
  for x in ix:f.write(struct.pack('<I',x))
 return {'asset':entry,'vertices':len(vs),'triangles':len(ix)//3,'boundsMin':[min(v[c] for v in vs) for c in range(3)],'boundsMax':[max(v[c] for v in vs) for c in range(3)],'originalWritten':False}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('archive',type=Path);p.add_argument('entry');p.add_argument('output',type=Path);p.add_argument('--key',type=Path);a=p.parse_args();print(json.dumps(extract(a.archive,a.entry,a.output,a.key.read_bytes() if a.key else None),indent=2))
