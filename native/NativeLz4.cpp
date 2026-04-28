#include <hxcpp.h>
#include "NativeLz4.h"

#include <string>
#include <vector>

#include "lz4.h"

namespace {
static const char* toInput(Array<unsigned char> input, int inputLength) {
	if (inputLength <= 0) {
		return 0;
	}
	if (input.mPtr == 0 || inputLength > input->length) {
		hx::Throw(HX_CSTRING("Invalid LZ4 input buffer."));
		return 0;
	}
	return reinterpret_cast<const char*>(input->GetBase());
}

static Array<unsigned char> toBytes(const char* data, int length) {
	Array<unsigned char> out = Array_obj<unsigned char>::__new(length, length);
	for (int i = 0; i < length; ++i) {
		out[i] = static_cast<unsigned char>(data[i]);
	}
	return out;
}

static std::vector<char> toVector(Array<unsigned char> input, int inputLength) {
	std::vector<char> out;
	out.resize(inputLength);
	for (int i = 0; i < inputLength; ++i) {
		out[i] = static_cast<char>(input[i]);
	}
	return out;
}
}

bool crossbyte_lz4_available() {
	return true;
}

::String crossbyte_lz4_version() {
	return ::String(LZ4_versionString());
}

Array<unsigned char> crossbyte_lz4_compress(Array<unsigned char> input, int inputLength) {
	if (inputLength <= 0) {
		Array<unsigned char> out = Array_obj<unsigned char>::__new(1, 1);
		out[0] = 0;
		return out;
	}

	std::vector<char> source = toVector(input, inputLength);
	int bound = LZ4_compressBound(inputLength);
	if (bound <= 0) {
		hx::Throw(HX_CSTRING("LZ4 compression failed"));
	}

	std::vector<char> compressed;
	compressed.resize(bound);
	int written = LZ4_compress_default(source.data(), compressed.data(), inputLength, bound);
	if (written <= 0) {
		hx::Throw(HX_CSTRING("LZ4 compression failed"));
	}

	return toBytes(compressed.data(), written);
}

Array<unsigned char> crossbyte_lz4_decompress(Array<unsigned char> input, int inputLength) {
	if (inputLength <= 0) {
		return Array_obj<unsigned char>::__new(0, 0);
	}

	const char* source = toInput(input, inputLength);
	int capacity = inputLength < 64 ? 64 : inputLength * 4;
	const int maxCapacity = 256 * 1024 * 1024;

	while (capacity > 0 && capacity <= maxCapacity) {
		std::vector<char> output;
		output.resize(capacity);
		int decoded = LZ4_decompress_safe(source, output.data(), inputLength, capacity);
		if (decoded >= 0) {
			return toBytes(output.data(), decoded);
		}
		capacity *= 2;
	}

	hx::Throw(HX_CSTRING("LZ4 decompression failed"));
	return Array_obj<unsigned char>::__new(0, 0);
}
