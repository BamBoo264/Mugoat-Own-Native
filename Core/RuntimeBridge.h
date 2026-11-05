#include <stdint.h>
int rb_inflate(const void *input,uint32_t inputBytes,void *output,uint32_t outputBytes);
int rb_zstd(const void *input,uint32_t inputBytes,void *output,uint32_t outputBytes);

int rb_aes256_ecb(const void *input,uint32_t n,const void *key,void *output);

int rb_find_asset_key(const void *input,uint32_t n,void *output);
