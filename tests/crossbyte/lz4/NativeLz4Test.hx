package crossbyte.lz4;

import crossbyte.errors.IOError;
import crossbyte.errors.RangeError;
import crossbyte.io.ByteArray;
import crossbyte.utils.CompressionAlgorithm;
import haxe.io.Bytes;
import utest.Assert;

#if cpp
// The process's peak resident set, for the tests that say a call did not take
// memory it had no need of.
@:cppFileCode('#ifdef HX_WINDOWS\n#ifndef NOMINMAX\n#define NOMINMAX\n#endif\n#include <windows.h>\n#include <psapi.h>\n#pragma comment(lib, "psapi.lib")\n#else\n#include <sys/resource.h>\n#endif\nstatic double crossbyte_test_peak_megabytes() {\n#ifdef HX_WINDOWS\n\tPROCESS_MEMORY_COUNTERS counters;\n\tif (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) return 0;\n\treturn (double)counters.PeakWorkingSetSize / 1048576.0;\n#else\n\tstruct rusage usage;\n\tif (getrusage(RUSAGE_SELF, &usage) != 0) return 0;\n#ifdef __APPLE__\n\treturn (double)usage.ru_maxrss / 1048576.0;\n#else\n\treturn (double)usage.ru_maxrss / 1024.0;\n#endif\n#endif\n}\n')
#end
class NativeLz4Test extends utest.Test {
	#if (cpp && crossbyte_lz4_native)
	/** What refusing the blocks in `setupClass` did: the errors, and the peak's growth in MB. **/
	private static var __refusals:Array<Dynamic> = [];
	private static var __refusalGrowth:Int = -1;

	/**
		Two blocks the decoder used to meet by allocating, refused here rather
		than in a test: the process's peak is what says whether the memory was
		taken, and the other tests here raise it past what this is looking for,
		in whatever order they run.
	**/
	public function setupClass():Void {
		var garbage = Bytes.alloc(100);
		garbage.set(0, 0x0F); // no literals, then a match...
		garbage.set(1, 0xFF); // ...65535 bytes back, before anything was written
		garbage.set(2, 0xFF);
		var bomb = __bomb(64 << 20);

		var before = __peakMegabytes();
		for (refuse in [() -> NativeLz4.decompress(garbage), () -> NativeLz4.decompress(bomb, 1 << 20)]) {
			try {
				refuse();
				__refusals.push(null);
			} catch (e:Dynamic) {
				__refusals.push(e);
			}
		}
		__refusalGrowth = __peakMegabytes() - before;
	}
	#end

	public function testAvailabilityMatchesBuildDefine():Void {
		#if (cpp && crossbyte_lz4_native)
		Assert.isTrue(NativeLz4.isAvailable());
		Assert.notEquals("unavailable", NativeLz4.version());
		#else
		Assert.isFalse(NativeLz4.isAvailable());
		Assert.equals("unavailable", NativeLz4.version());
		#end
	}

	#if (cpp && crossbyte_lz4_native)
	public function testNativeRoundTrip():Void {
		var input = Bytes.ofString("hello native lz4 hello native lz4");
		var compressed = NativeLz4.compress(input);
		var decompressed = NativeLz4.decompress(compressed);

		Assert.equals(input.toString(), decompressed.toString());

		var text = __text(300000);
		Assert.equals(0, NativeLz4.decompress(NativeLz4.compress(text)).compare(text));
	}

	public function testCoreAndNativeCanDecodeEachOther():Void {
		var input = Bytes.ofString("lz4 oracle parity payload");
		var coreEncoded:ByteArray = ByteArray.fromBytes(input);
		coreEncoded.compress(CompressionAlgorithm.LZ4);
		Assert.equals(input.toString(), NativeLz4.decompress(coreEncoded).toString());

		var nativeEncoded = NativeLz4.compress(input);
		var coreDecoded:ByteArray = ByteArray.fromBytes(nativeEncoded);
		coreDecoded.uncompress(CompressionAlgorithm.LZ4);
		Assert.equals(input.toString(), coreDecoded.toString());
	}

	public function testNativeRejectsInvalidPayload():Void {
		var encoded = NativeLz4.compress(Bytes.ofString("this payload will be truncated"));
		var truncated = encoded.sub(0, encoded.length - 1);
		Assert.raises(() -> NativeLz4.decompress(truncated), IOError);
		// Even an empty block is a token; nothing at all is not a block.
		Assert.raises(() -> NativeLz4.decompress(Bytes.alloc(0)), IOError);
	}

	public function testEmptyPayloadParity():Void {
		var empty = Bytes.alloc(0);
		var encoded = NativeLz4.compress(empty);
		Assert.equals(1, encoded.length);
		Assert.equals(0, encoded.get(0));
		Assert.equals(0, NativeLz4.decompress(encoded).length);
	}

	public function testByteArrayHandsTheLimitDown():Void {
		// CrossByte's ByteArray, on this backend, passes its limit down
		// rather than decoding the whole block here and measuring it
		// afterwards, which heard only that a block cut short past the
		// limit was cut short.
		var whole = NativeLz4.compress(__text(2 << 20));
		var cut:ByteArray = ByteArray.fromBytes(whole.sub(0, whole.length - 1));
		Assert.raises(() -> cut.uncompress(CompressionAlgorithm.LZ4, 1 << 20), RangeError);
	}

	public function testNativeLimitIsExact():Void {
		var input = __text(100000);
		var packed = NativeLz4.compress(input);

		Assert.equals(0, NativeLz4.decompress(packed, input.length).compare(input));
		Assert.raises(() -> NativeLz4.decompress(packed, input.length - 1), RangeError);
		Assert.equals(0, NativeLz4.decompress(packed, 0).compare(input));
	}

	public function testNativeRefusesWithoutTakingTheMemory():Void {
		// The decoder had no way to know what a block holds, so it guessed
		// four times the input and doubled on every failure, up to 256 MB: a
		// block that decodes to 64 MB was decoded seven times over before the
		// caller could measure it, and 100 bytes of garbage took the ladder
		// all the way up, 200 MB of it, to learn that it was garbage. Now the
		// block's sequence headers are read first, and neither gets past
		// them. (Both are refused in setupClass; see there.)
		Assert.isOfType(__refusals[0], IOError, "100 bytes of garbage: " + Std.string(__refusals[0]));
		Assert.isOfType(__refusals[1], RangeError, "a 64 MB block at 1 MB: " + Std.string(__refusals[1]));
		Assert.isTrue(__refusalGrowth >= 0 && __refusalGrowth < 32,
			'refusing 100 bytes of garbage and a 64 MB block at 1 MB raised the peak by $__refusalGrowth MB');
	}

	public function testNativeLimitComesBeforeWhereTheBlockEnds():Void {
		// 2 MB, one byte short. At a 1 MB limit the headers pass the limit
		// before they reach the missing byte, and the caller hears that, as
		// it does from the Haxe decoder.
		var whole = NativeLz4.compress(__text(2 << 20));
		var cut = whole.sub(0, whole.length - 1);

		Assert.raises(() -> NativeLz4.decompress(cut, 1 << 20), RangeError);
		Assert.raises(() -> NativeLz4.decompress(cut), IOError);
	}

	public function testNativeHoldsABlockToItsEndRules():Void {
		// Eight literals, a four-byte match, five literals: 17 bytes, whose
		// match starts eight in. No match may start within the last twelve
		// bytes of a block, which is what lets a decoder copy in wide steps,
		// and what gives away a block that was cut short. Handed a buffer
		// bigger than the block, the library measures that rule against the
		// buffer's end and lets this through; handed exactly the room the
		// block needs, it holds the block to it, as the Haxe decoder does.
		var block = Bytes.ofHex("806162636465666768" + "0400" + "50696a6b6c6d");
		Assert.raises(() -> NativeLz4.decompress(block), IOError);

		// A block that ends in a match, as one cut after a match does.
		Assert.raises(() -> NativeLz4.decompress(Bytes.ofHex("40616263640400")), IOError);

		// An offset of 0 is corrupt in the format, and the library decodes it
		// from whatever the buffer held.
		Assert.raises(() -> NativeLz4.decompress(Bytes.ofHex("8061626364656667680000" + "50696a6b6c6d")), IOError);
	}

	public function testCompressLeavesTheCollectorFree():Void {
		// A collection needs every thread at a safe point, and a thread in a
		// native call reaches none until it returns. Outside a GC-free zone a
		// large compress held every allocation on every other thread for the
		// whole call.
		var text = __text(48 << 20);
		var finished = new sys.thread.Deque<Float>();
		sys.thread.Thread.create(() -> {
			var t0 = haxe.Timer.stamp();
			NativeLz4.compress(text);
			finished.add(haxe.Timer.stamp() - t0);
		});

		var longest:Float = 0;
		var last:Float = haxe.Timer.stamp();
		var keep:Array<Array<Int>> = [];
		var took:Null<Float> = null;
		var iterations:Int = 0;
		while (took == null) {
			keep[iterations++ & 1023] = [for (i in 0...64) i];
			var now = haxe.Timer.stamp();
			if (now - last > longest) {
				longest = now - last;
			}
			last = now;
			took = finished.pop(false);
		}

		Assert.isTrue(longest < took / 2,
			'this thread stalled ${Math.round(longest * 1000)} ms of a ${Math.round(took * 1000)} ms compress on another');
	}

	/**
		A block of `size` zero bytes built by hand, a few hundred KB of it: one
		literal, then one match one byte back whose length is a run of 255s,
		then the five literals a block ends in.
	**/
	private static function __bomb(size:Int):Bytes {
		var matchLength = size - 1 - 5;
		var extra = matchLength - 4 - 15;
		var runs = Std.int(extra / 255);
		var out = Bytes.alloc(1 + 1 + 2 + runs + 1 + 1 + 5);
		var at = 0;
		out.set(at++, 0x1F); // one literal, a match of 19 or more
		out.set(at++, 0);
		out.set(at++, 1); // offset 1
		out.set(at++, 0);
		for (i in 0...runs) {
			out.set(at++, 255);
		}
		out.set(at++, extra - runs * 255);
		out.set(at++, 0x50); // five literals, and the end
		return out;
	}

	private static function __peakMegabytes():Int {
		var peak:Float = untyped __cpp__("crossbyte_test_peak_megabytes()");
		return Math.round(peak);
	}

	/** Deterministic text: words, so it compresses the way a page does. **/
	private static function __text(length:Int):Bytes {
		var words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "while", "native", "lz4", "decodes", "a", "block"];
		var out = Bytes.alloc(length);
		var seed = 0x2545F491;
		var at = 0;
		while (at < length) {
			seed ^= seed << 13;
			seed ^= seed >>> 17;
			seed ^= seed << 5;
			var word = words[(seed >>> 1) % words.length];
			for (i in 0...word.length) {
				if (at < length) {
					out.set(at++, StringTools.fastCodeAt(word, i));
				}
			}
			if (at < length) {
				out.set(at++, (seed & 15) == 0 ? ".".code : " ".code);
			}
		}
		return out;
	}
	#end
}
