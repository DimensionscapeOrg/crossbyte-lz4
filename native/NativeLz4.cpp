#include <hxcpp.h>
#include "NativeLz4.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lz4.h"

/*
 * Every codec call copies its input out of the collector's memory and then
 * runs in a GC-free zone, so a large block on one thread does not hold up the
 * collections every other thread is waiting on. Nothing inside a zone may
 * touch a Haxe object or throw: the codec work reports a status, and the Array
 * is made, or the error thrown, once the zone is left.
 */

namespace {

enum Status {
	STATUS_OK = 0,
	STATUS_INVALID,
	STATUS_LIMIT,
	STATUS_NO_MEMORY
};

// Copies input[0, length) into memory the collector does not own.
char* copyInput(Array<unsigned char> input, int length) {
	if (length < 0 || (length > 0 && (input.mPtr == 0 || length > input->length))) {
		hx::Throw(HX_CSTRING("Invalid LZ4 input buffer."));
	}
	char* copy = (char*)malloc(length > 0 ? (size_t)length : 1);
	if (copy == 0) {
		hx::Throw(HX_CSTRING("Out of memory copying the LZ4 input."));
	}
	if (length > 0) {
		memcpy(copy, input->GetBase(), (size_t)length);
	}
	return copy;
}

// What a block decodes to, read from its sequence headers without decoding
// it: -1 when those do not add up, -2 once they pass `limit`. A block has no
// length of its own, and this is what lets the decoder be handed exactly the
// room the block needs, so the format's end rules hold against the block's
// real end rather than a buffer's.
int64_t decodedSize(const unsigned char* source, int length, int64_t limit) {
	int64_t size = 0;
	int at = 0;
	for (;;) {
		if (at >= length) {
			return -1;
		}
		int token = source[at++];

		int64_t literals = token >> 4;
		if (literals == 15) {
			int more;
			do {
				if (at >= length) {
					return -1;
				}
				more = source[at++];
				literals += more;
			} while (more == 255);
		}
		if (literals > length - at) {
			return -1;
		}
		at += (int)literals;
		size += literals;
		if (size > limit) {
			return -2;
		}
		if (at == length) {
			// The last sequence is literals alone.
			return size;
		}

		if (length - at < 2) {
			return -1;
		}
		// The library decodes an offset of 0 from whatever the buffer held,
		// and the format calls it corrupt; one reaching before the block's
		// start it refuses anyway, but this is where it is cheapest to.
		int offset = source[at] | (source[at + 1] << 8);
		at += 2;
		if (offset == 0 || offset > size) {
			return -1;
		}
		int64_t match = token & 15;
		if (match == 15) {
			int more;
			do {
				if (at >= length) {
					return -1;
				}
				more = source[at++];
				match += more;
				// Every 255 is a byte of input; stop counting once it is
				// past the limit rather than at the end of the run.
				if (size + match > limit) {
					return -2;
				}
			} while (more == 255);
		}
		size += match + 4;
		if (size > limit) {
			return -2;
		}
	}
}

// Runs in a GC-free zone.
Status decode(const char* source, int length, int limit, char** out, int* produced) {
	int64_t size = decodedSize((const unsigned char*)source, length, limit);
	if (size == -2) {
		return STATUS_LIMIT;
	}
	if (size < 0) {
		return STATUS_INVALID;
	}
	char* buffer = (char*)malloc(size > 0 ? (size_t)size : 1);
	if (buffer == 0) {
		return STATUS_NO_MEMORY;
	}
	// Exactly the room the block needs, so a block that says one size and
	// holds another, a bad offset, a match into the last five bytes, is
	// refused by the library rather than decoded into slack.
	int decoded = LZ4_decompress_safe(source, buffer, length, (int)size);
	if (decoded != (int)size) {
		free(buffer);
		return STATUS_INVALID;
	}
	*out = buffer;
	*produced = decoded;
	return STATUS_OK;
}

} // namespace

bool crossbyte_lz4_available() {
	return true;
}

::String crossbyte_lz4_version() {
	return ::String(LZ4_versionString());
}

Array<unsigned char> crossbyte_lz4_compress(Array<unsigned char> input, int inputLength) {
	if (inputLength < 0 || (inputLength > 0 && (input.mPtr == 0 || inputLength > input->length))) {
		hx::Throw(HX_CSTRING("Invalid LZ4 input buffer."));
	}
	if (inputLength == 0) {
		// An empty block is still a token: one zero byte.
		Array<unsigned char> out = Array_obj<unsigned char>::__new(1, 1);
		out[0] = 0;
		return out;
	}

	int bound = LZ4_compressBound(inputLength);
	if (bound <= 0) {
		hx::Throw(HX_CSTRING("LZ4 input too large."));
	}
	char* source = copyInput(input, inputLength);
	char* output = (char*)malloc((size_t)bound);
	if (output == 0) {
		free(source);
		hx::Throw(HX_CSTRING("Out of memory for the LZ4 output."));
	}

	int written;
	{
		hx::AutoGCFreeZone zone;
		written = LZ4_compress_default(source, output, inputLength, bound);
	}
	free(source);
	if (written <= 0) {
		free(output);
		hx::Throw(HX_CSTRING("LZ4 compression failed."));
	}

	Array<unsigned char> result = Array_obj<unsigned char>::fromData((const unsigned char*)output, written);
	free(output);
	return result;
}

Array<unsigned char> crossbyte_lz4_decompress(Array<unsigned char> input, int inputLength, int maxOutputSize) {
	if (inputLength == 0) {
		hx::Throw(HX_CSTRING("no block"));
	}
	char* source = copyInput(input, inputLength);
	// The caller's limit, or failing one the most an Array can hold.
	int limit = maxOutputSize > 0 ? maxOutputSize : INT_MAX;

	char* output = 0;
	int produced = 0;
	Status status;
	{
		hx::AutoGCFreeZone zone;
		status = decode(source, inputLength, limit, &output, &produced);
	}
	free(source);

	switch (status) {
		case STATUS_LIMIT:
			// Null: the block decodes past the limit. The caller names it.
			return Array<unsigned char>();
		case STATUS_NO_MEMORY:
			hx::Throw(HX_CSTRING("out of memory"));
			break;
		case STATUS_INVALID:
			hx::Throw(HX_CSTRING("not a valid block"));
			break;
		default:
			break;
	}

	Array<unsigned char> result = Array_obj<unsigned char>::fromData((const unsigned char*)output, produced);
	free(output);
	return result;
}
