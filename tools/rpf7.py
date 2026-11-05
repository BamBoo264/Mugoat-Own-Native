"""Independent read-only RPF7 inspector. No decryption keys, source copying or writes to archives."""
from pathlib import Path
import struct,zlib
from dataclasses import dataclass
class RPFError(ValueError):pass
@dataclass(frozen=True)
class Entry:
 path:str;kind:str;offset:int;stored:int;size:int;flags:int;graphics:int
class RPF7:
 def __init__(self,path,base=0,length=None,key=None):
  self.key=key
  self.path=Path(path);self.base=base;self.length=self.path.stat().st_size-base if length is None else length
  if base<0 or self.length<16 or base+self.length>self.path.stat().st_size:raise RPFError('archive span')
  magic,count,names,key=struct.unpack('<4I',self.read(0,16))
  if magic!=0x52504637:raise RPFError('magic')
  if key not in (0,0x4e45504f,0x0ffffff9):raise RPFError('encryption variant unsupported')
  if count<1 or count>1000000 or names>64<<20 or 16+count*16+names>self.length:raise RPFError('table bounds')
  self.table_end=16+count*16+names
  rows=self.read(16,count*16);strings=self.read(16+count*16,names);decoded=[]
  if key==0x0ffffff9:
   if self.key is None or len(self.key)!=32:raise RPFError('private AES asset key required')
   from Crypto.Cipher import AES
   rows=AES.new(self.key,AES.MODE_ECB).decrypt(rows);strings=AES.new(self.key,AES.MODE_ECB).decrypt(strings)
  for i in range(count):
   a,b,c,d=struct.unpack_from('<4I',rows,i*16);resource=bool(b>>31);directory=b==0x7fffff00;name_at=a if directory else a&0xffff
   if name_at>=names:raise RPFError('name offset')
   stop=strings.find(b'\0',name_at)
   if stop<0 or stop-name_at>255:raise RPFError('name terminator')
   name=strings[name_at:stop].decode('utf-8',errors='strict')
   if '/' in name or '\\' in name or name in ('.','..'):raise RPFError('unsafe name')
   if directory:decoded.append((name,'directory',c,d,0,0,0));continue
   stored=((a>>16)|((b&255)<<16));offset=((b>>8)&(0x7fffff if resource else 0xffffff))*512
   if resource and stored==0xffffff:
    h=self.read(offset,16);stored=h[7]|h[14]<<8|h[5]<<16|h[2]<<24
   size=stored if resource else c
   actual=stored if stored else size
   if offset<self.table_end or offset>self.length or actual>self.length-offset:raise RPFError('entry bounds')
   decoded.append((name,'resource' if resource else 'binary',offset,stored,size,c if resource else d,d if resource else 0))
  if decoded[0][1]!='directory':raise RPFError('root')
  visited=set();paths=set();entries=[]
  def walk(i,parent,depth):
   if depth>64 or i in visited:raise RPFError('cycle/duplicate parent')
   visited.add(i);name,kind,at,stored,size,flags,gfx=decoded[i];path=parent+'/'+name if parent else name
   if i==0:path=''
   if path.lower() in paths:raise RPFError('duplicate path')
   paths.add(path.lower())
   if kind=='directory':
    if at>count or stored>count-at:raise RPFError('children bounds')
    for k in range(at,at+stored):walk(k,path,depth+1)
   else:entries.append(Entry(path,kind,at,stored,size,flags,gfx))
  walk(0,'',0)
  if len(visited)!=count:raise RPFError('orphan entries')
  self.entries=entries
 def read(self,offset,length):
  if offset<0 or length<0 or offset>self.length or length>self.length-offset:raise RPFError('read span')
  with self.path.open('rb') as f:f.seek(self.base+offset);data=f.read(length)
  if len(data)!=length:raise RPFError('short read')
  return data
 def binary(self,e,limit=64<<20):
  if e.kind!='binary' or e.flags:raise RPFError('encrypted/nonbinary entry')
  if e.size>limit:raise RPFError('output cap')
  data=self.read(e.offset,e.stored or e.size)
  if not e.stored:return data
  decoder=zlib.decompressobj(-15);out=decoder.decompress(data,e.size+1)
  if len(out)!=e.size or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:raise RPFError('invalid deflate')
  return out
 def nested(self,e):
  if e.kind!='binary' or e.stored or e.flags:raise RPFError('nested requires plain stored archive')
  return RPF7(self.path,self.base+e.offset,e.size,key=self.key)
