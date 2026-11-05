"""Local asset-key derivation by a public SHA1 fingerprint; never prints the key or uploads inputs."""
import argparse,hashlib,struct,json
from pathlib import Path
FINGERPRINT=bytes.fromhex('a0796128a775720ac204d9819f68c172e3952c6d')
def leb(data,pos):
 value=0;shift=0
 for _ in range(5):
  if pos>=len(data):raise ValueError('Truncated LEB')
  b=data[pos];pos+=1;value|=(b&127)<<shift
  if not b&128:return value,pos
  shift+=7
 raise ValueError('LEB overflow')
def derive(source,output):
 if output.exists():raise ValueError('Output exists; refusing overwrite')
 raw=source.read_bytes()
 if raw[:8]!=b'\0asm\x01\0\0\0':raise ValueError('Expected user-supplied wasm runtime input')
 pos=8;found=None;scanned=0
 while pos<len(raw):
  section=raw[pos];length,begin=leb(raw,pos+1);end=begin+length
  if end>len(raw):raise ValueError('Section bounds')
  if section==11:
   data=raw[begin:end]
   print('Scanning private data section:',len(data),'bytes',flush=True)
   for i in range(max(0,len(data)-31)):
    if hashlib.sha1(data[i:i+32]).digest()==FINGERPRINT:found=data[i:i+32];break
   scanned+=len(data)
  if found is not None:break
  pos=end
 if found is None:raise ValueError('Public fingerprint was not found; no key guessed')
 output.write_bytes(found)
 return {'derivedBytes':len(found),'scannedDataBytes':scanned,'keyPrinted':False,'destination':str(output)}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args();print(json.dumps(derive(a.source,a.output),indent=2))
