#ifndef CROSSBYTE_NATIVE_LZ4_H
#define CROSSBYTE_NATIVE_LZ4_H

#include <hx/CFFI.h>

bool crossbyte_lz4_available();
::String crossbyte_lz4_version();
Array<unsigned char> crossbyte_lz4_compress(Array<unsigned char> input, int inputLength);
Array<unsigned char> crossbyte_lz4_decompress(Array<unsigned char> input, int inputLength);

#endif
