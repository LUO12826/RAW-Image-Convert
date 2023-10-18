//
//  DNGHelper.h
//  RAW Image Convert
//
//  Created by 骆荟州 on 2023/10/17.
//

#ifndef DNGHelper_h
#define DNGHelper_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int checkEndian(const char *data);

void extractJPEGpreviewFromDNG(const char *dng, uint64_t dng_len, char **jpeg_data, uint64_t *jpeg_len);

#ifdef __cplusplus
}
#endif




#endif /* DNGHelper_h */
