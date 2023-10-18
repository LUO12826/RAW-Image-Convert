//
//  DNGHelper.cpp
//  RAW Image Convert
//
//  Created by 骆荟州 on 2023/10/16.
//

#ifndef DNGHelper_hpp
#define DNGHelper_hpp

#include <stddef.h>
#include <string.h>
#include <stdlib.h>

#include "DNGHelper.h"

struct MemoryFileReader {
    size_t pos {0};
    size_t length;
    const char *data;
    
    MemoryFileReader(const char *data, size_t length): data(data), length(length) {}
    
    size_t read(void *dest, size_t byte_cnt) {
        if (pos >= length) return 0;
        
        if (pos + byte_cnt > length) {
            size_t byte_copied = length - pos;
            memcpy(dest, data + pos, byte_copied);
            pos = length;
            return byte_copied;
        }
        else {
            memcpy(dest, data + pos, byte_cnt);
            pos += byte_cnt;
            return byte_cnt;
        }
    }
    
    void seek(size_t index) {
        if (index > length) pos = length;
        else pos = index;
    }
};

extern "C" {

// return: 0 if little endian, 1 if big endian, -1 if error occurred
int checkEndian(const char *data) {
    if (data[0] != data[1]) return -1;
    if (data[0] == 'l') return 0;
    if (data[0] == 'M') return 1;
    return -1;
}

}




uint16_t swapEndian16(uint16_t value) {
    return (value >> 8) | (value << 8);
}

uint32_t swapEndian32(uint32_t value) {
    return ((value >> 24) & 0xFF) |
    ((value >> 8) & 0xFF00) |
    ((value << 8) & 0xFF0000) |
    ((value << 24) & 0xFF000000);
}

uint64_t swapEndian64(uint64_t value) {
    return ((value >> 56) & 0xFF) |
    ((value >> 48) & 0xFF00) |
    ((value >> 40) & 0xFF0000) |
    ((value >> 32) & 0xFF000000) |
    ((value << 32) & 0xFF00000000) |
    ((value << 40) & 0xFF0000000000) |
    ((value << 48) & 0xFF000000000000) |
    ((value << 56) & 0xFF00000000000000);
}

// DNG (TIFF) header
typedef struct {
    uint16_t byte_order;
    uint16_t version;
    uint32_t ifd_offset;
} DNGHeader;

// IFD Entry (aka DE)
typedef struct {
    uint16_t tag;
    uint16_t type;
    uint32_t count;
    uint32_t value;
} IFDEntry;

extern "C" {

void extractJPEGpreviewFromDNG(const char *dng, uint64_t dng_len, char **jpeg_data, uint64_t *jpeg_len) {

    static_assert(sizeof(DNGHeader) == 8, "Error DNGHeader struct size");
    static_assert(sizeof(IFDEntry) == 12, "Error IFDEntry struct size");

    MemoryFileReader reader(dng, dng_len);

    DNGHeader header;
    reader.read(&header, sizeof(DNGHeader));

    // First IFD
    reader.seek(swapEndian32(header.ifd_offset));

    uint16_t de_count;
    reader.read(&de_count, sizeof(de_count));
    de_count = swapEndian16(de_count);

    IFDEntry entry;
    // find StripOffsets(tag is 273) and StripByteCounts(tag is 279)
    uint32_t strip_offset;
    uint32_t strip_len;

    int field_found_cnt = 0;

    for (int i = 0; i < de_count; i++) {

        reader.read(&entry, sizeof(IFDEntry));
        uint16_t tag = swapEndian16(entry.tag);
        uint16_t type = swapEndian16(entry.type);
        uint32_t length = swapEndian32(entry.count);
        uint32_t value = entry.value;

        if (type == 4) {      // uint32
            value = swapEndian32(value);
        }
        else if (type == 3) { // uint16
            value &= 0xFFFF;
            value = swapEndian16(value);
        }
        else if (type == 2) { // byte
            value &= 0xFF;
        }

        if (tag == 273) {
            strip_offset = value;
            field_found_cnt += 1;
        }
        if (tag == 279) {
            strip_len = value;
            field_found_cnt += 1;
        }
    }

    if (field_found_cnt != 2) {
        *jpeg_data = nullptr;
        *jpeg_len = 0;
        return;
    }

    reader.seek(strip_offset);
    char *jpeg = (char *)malloc(strip_len);

    reader.read(jpeg, strip_len);

    *jpeg_data = jpeg;
    *jpeg_len = strip_len;
    return;
}

}



#endif /* DNGHelper_hpp */
