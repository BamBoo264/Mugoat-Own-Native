"""Read-only local integration audit; never uploads assets or prints keys."""
import sys,json,struct,math,zlib,argparse
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'build/audit-deps'))
from compression import zstd
from rpf7 import RPF7
from extract_mesh import segment,decode

def hash_name(s):
 h=0
 for c in s.lower().encode():
  h=(h+c)&0xffffffff;h=(h+(h<<10))&0xffffffff;h^=h>>6
 h=(h+(h<<3))&0xffffffff;h^=h>>11;return (h+(h<<15))&0xffffffff

def resource(a,e):
 raw=a.read(e.offset,e.stored);sy,gp=segment(e.flags),segment(e.graphics)
 if not sy or sy+gp>64<<20:raise ValueError('resource cap')
 decoder=zstd.ZstdDecompressor() if raw[16:20]==bytes.fromhex('28b52ffd') else zlib.decompressobj(-15)
 d=decoder.decompress(raw[16:],sy+gp+1)
 if not decoder.eof or decoder.unused_data or len(d)!=sy+gp:raise ValueError('resource boundaries')
 def span(ptr,n):
  if 0x50000000<=ptr<0x60000000:o=ptr-0x50000000;size=sy;base=0
  elif 0x60000000<=ptr<0x70000000:o=ptr-0x60000000;size=gp;base=sy
  else:raise ValueError('pointer tag')
  if n<0 or o>size or n>size-o:raise ValueError('span')
  return d[base+o:base+o+n]
 return d,span

def audit(root,key):
 data=root/'data';manifest=json.loads((data/'manifest.json').read_text());prefix='x64/levels/gta5/_citye/downtown_01/'
 archives=[RPF7(data/r[0],key=key) for r in manifest['files'] if r[0].startswith(prefix) and r[0].endswith('.rpf')]
 index={};dictionary_count=0
 for a in archives:
  for e in a.entries:
   if e.path.endswith('.ydr'):index.setdefault(hash_name(Path(e.path).stem),(a,e,0x50000000))
 for a in archives:
  for e in a.entries:
   if not e.path.endswith('.ydd'):continue
   dictionary_count+=1;d,span=resource(a,e);h=span(0x50000000,64);n=struct.unpack_from('<H',h,40)[0]
   if not 0<n<=8192 or n!=struct.unpack_from('<H',h,56)[0] or n>struct.unpack_from('<H',h,42)[0] or n>struct.unpack_from('<H',h,58)[0]:raise ValueError('dictionary counts')
   hashes=span(struct.unpack_from('<Q',h,32)[0],n*4);refs=span(struct.unpack_from('<Q',h,48)[0],n*8)
   seen=set()
   for i in range(n):
    name=struct.unpack_from('<I',hashes,i*4)[0];ptr=struct.unpack_from('<Q',refs,i*8)[0];span(ptr,168)
    if name in seen:raise ValueError('duplicate hash')
    seen.add(name);index.setdefault(name,(a,e,ptr))
 meta=next(a for a in archives if a.path.name=='downtown_01_metadata.rpf');results=[]
 for name in ['fwy_01_long_0.ymap','fwy_02_long_0.ymap','fwy_04_long_0.ymap']:
  e=next(e for e in meta.entries if e.path==name);d,span=resource(meta,e);h=span(0x50000000,112);n=struct.unpack_from('<H',h,76)[0];table=span(struct.unpack_from('<Q',h,48)[0],n*16);blocks=[struct.unpack_from('<IIQ',table,i*16) for i in range(n)]
  root_block=blocks[struct.unpack_from('<I',h,28)[0]-1];r=span(root_block[2],root_block[1]);count=struct.unpack_from('<H',r,104)[0]
  def meta_span(ptr,n):
   kind,size,addr=blocks[(ptr&4095)-1];off=ptr>>12
   if off>size or n>size-off:raise ValueError('meta span')
   return kind,span(addr+off,n)
  _,refs=meta_span(struct.unpack_from('<Q',r,96)[0],count*8);loaded=missing=unsupported=nv=ni=0;errors=[];cache={}
  for i in range(count):
   ptr=struct.unpack_from('<Q',refs,i*8)[0];kind,entity=meta_span(ptr,128)
   if kind!=0xce501483:unsupported+=1;continue
   archetype=struct.unpack_from('<I',entity,8)[0]
   if archetype not in index:missing+=1;continue
   a,e,ptr=index[archetype]
   try:
    if archetype not in cache:cache[archetype]=decode(a.read(e.offset,e.stored),e.flags,e.graphics,ptr)
    v,ix=cache[archetype];nv+=len(v);ni+=len(ix);loaded+=1
   except Exception as error:unsupported+=1;errors.append(str(error))
  results.append({'map':name,'entities':count,'loaded':loaded,'missing':missing,'unsupported':unsupported,'vertices':nv,'indices':ni,'meshBytes':nv*24+ni*4,'errors':sorted(set(errors))})
 return {'archives':len(archives),'dictionaries':dictionary_count,'indexedAssets':len(index),'scenes':results,'aggregateBytes':sum(r['meshBytes'] for r in results),'gameDataModified':False}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('--key',required=True,type=Path);p.add_argument('--output',required=True,type=Path);args=p.parse_args()
 r=audit(args.root,args.key.read_bytes());args.output.write_text(json.dumps(r,indent=2));print(json.dumps(r))
