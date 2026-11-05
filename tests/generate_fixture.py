"""Synthetic geometry/AES fixture only; no game bytes or private key."""
from pathlib import Path
import struct,sys

def create(folder):
 folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
 b=bytearray(16384)
 def q(o,v):struct.pack_into('<Q',b,o,v)
 def h(o,v):struct.pack_into('<H',b,o,v)
 def i(o,v):struct.pack_into('<I',b,o,v)
 q(80,0x50000200);q(0x200,0x50000210);h(0x208,1);h(0x20a,1);q(0x210,0x50000220)
 q(0x228,0x50000260);h(0x230,1);h(0x232,1);h(0x24e,1);q(0x260,0x50000300)
 q(0x318,0x50000400);q(0x338,0x50000480);i(0x358,3);i(0x35c,1);h(0x360,3);h(0x362,3);h(0x370,12)
 h(0x408,12);q(0x410,0x50000600);i(0x418,3);q(0x430,0x50000500);i(0x488,3);q(0x490,0x50000700)
 i(0x500,1);h(0x504,12);b[0x507]=1;q(0x508,6)
 for n,v in enumerate([(-10,-10,0),(10,-10,0),(0,10,0)]):struct.pack_into('<3f',b,0x600+n*12,*v)
 struct.pack_into('<3H',b,0x700,0,1,2)
 payload=b'OWN_RESOURCE_V1!'+b'\x01'+struct.pack('<HH',len(b),65535-len(b))+b
 encrypted=bytes.fromhex('f93db0a06d089003c6e86e4df8c7a5b253ea544b6c4c569ab9b694257983c7b574886cccf404e2385396ebed4f5f2b2b')
 header=struct.pack('<4I',0x52504637,2,16,0x0ffffff9)
 (folder/'fixture.rpf').write_bytes((header+encrypted).ljust(512,b'\0')+payload)
 (folder/'resource.bin').write_bytes(b)
if __name__=='__main__':create(sys.argv[1])
