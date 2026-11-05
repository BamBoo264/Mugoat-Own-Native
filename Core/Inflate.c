#include "RuntimeBridge.h"
#include <zlib.h>
int rb_inflate(const void *input,uint32_t n,void *output,uint32_t count){
 if(!input||!output||!n||!count)return 0;
 z_stream s={0};s.next_in=(Bytef*)input;s.avail_in=n;s.next_out=output;s.avail_out=count;
 if(inflateInit2(&s,-MAX_WBITS)!=Z_OK)return 0;
 int result=inflate(&s,Z_FINISH);
 int valid=result==Z_STREAM_END && s.total_in==n && s.total_out==count;
 inflateEnd(&s);return valid;
}

#include "../Vendor/zstd/lib/zstd.h"
int rb_zstd(const void *input,uint32_t n,void *output,uint32_t expected){
 if(!input||!output||!n||!expected)return 0;
 size_t frame=ZSTD_findFrameCompressedSize(input,n);
 if(ZSTD_isError(frame)||frame!=n)return 0;
 unsigned long long declared=ZSTD_getFrameContentSize(input,n);
 if(declared!=ZSTD_CONTENTSIZE_UNKNOWN && declared!=expected)return 0;
 size_t decoded=ZSTD_decompress(output,expected,input,n);
 return !ZSTD_isError(decoded)&&decoded==expected;
}

#ifdef __APPLE__
#include <CommonCrypto/CommonCryptor.h>
int rb_aes256_ecb(const void *input,uint32_t n,const void *key,void *output){
 if(!input||!key||!output||!n||(n%16))return 0;
 size_t done=0;CCCryptorStatus result=CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionECBMode,key,32,NULL,input,n,output,n,&done);
 return result==kCCSuccess&&done==n;
}
#else
int rb_aes256_ecb(const void *input,uint32_t n,const void *key,void *output){return 0;}
#endif

#ifdef __APPLE__
#include <CommonCrypto/CommonDigest.h>
#include <string.h>
int rb_find_asset_key(const void *input,uint32_t n,void *output){
 static const unsigned char fingerprint[20]={0xa0,0x79,0x61,0x28,0xa7,0x75,0x72,0x0a,0xc2,0x04,0xd9,0x81,0x9f,0x68,0xc1,0x72,0xe3,0x95,0x2c,0x6d};
 if(!input||!output||n<32)return 0;const unsigned char *bytes=input;unsigned char digest[20];
 for(uint32_t i=0;i<=n-32;i++){CC_SHA1(bytes+i,32,digest);if(!memcmp(digest,fingerprint,20)){memcpy(output,bytes+i,32);return 1;}}
 return 0;
}
#else
int rb_find_asset_key(const void *input,uint32_t n,void *output){return 0;}
#endif
