package crossbyte.lz4;

import crossbyte.errors.IOError;
import crossbyte.errors.RangeError;
import crossbyte.lz4._internal.NativeLz4Bridge;
import haxe.io.Bytes;

/**
	The LZ4 library's raw block format, for hxcpp builds with
	`-D crossbyte_lz4_native`: what CrossByte's `CompressionAlgorithm.LZ4`
	writes, one block and nothing around it.

	Each call copies its input out of the collector's memory and runs the codec
	in a GC-free zone, so a large block on one thread does not hold up the
	collections every other thread is waiting on.
**/
class NativeLz4 {
	private static final __empty:Bytes = Bytes.alloc(0);

	public static inline function isAvailable():Bool {
		#if (cpp && crossbyte_lz4_native)
		return NativeLz4Bridge.isAvailable();
		#else
		return false;
		#end
	}

	public static inline function version():String {
		#if (cpp && crossbyte_lz4_native)
		return NativeLz4Bridge.version();
		#else
		return "unavailable";
		#end
	}

	public static function compress(bytes:Bytes):Bytes {
		#if (cpp && crossbyte_lz4_native)
		var input = bytes == null ? __empty : bytes;
		return Bytes.ofData(NativeLz4Bridge.compress(input.getData(), input.length));
		#else
		throw "Native LZ4 is only available on cpp targets with -D crossbyte_lz4_native.";
		#end
	}

	/**
		Decodes one block.

		@param maxOutputSize Bytes to produce before giving up, or `0` for no
		       limit. LZ4 ratios have no ceiling either, four bytes of window
		       replayed a million times is a valid block, so anything
		       decoding a block it did not author wants to name one. The block
		       is measured from its sequence headers before anything is
		       allocated for it, and one that decodes past this is refused
		       then.

		The decoder is handed exactly the room the block needs, which holds it
		to the format's end rules at its real end: a block cut short after a
		match, or one whose sizes do not add up, is refused.

		@throws IOError The data is not a valid block, or is empty.
		@throws RangeError It decodes past `maxOutputSize`.
	**/
	public static function decompress(bytes:Bytes, maxOutputSize:Int = 0):Bytes {
		#if (cpp && crossbyte_lz4_native)
		var input = bytes == null ? __empty : bytes;
		var data:haxe.io.BytesData;
		try {
			data = NativeLz4Bridge.decompress(input.getData(), input.length, maxOutputSize);
		} catch (e:String) {
			throw new IOError("Invalid LZ4 data: " + e);
		}
		if (data == null) {
			throw new RangeError("Decoded stream exceeded " + (maxOutputSize > 0 ? maxOutputSize : 0x7FFFFFFF) + " bytes");
		}
		return Bytes.ofData(data);
		#else
		throw "Native LZ4 is only available on cpp targets with -D crossbyte_lz4_native.";
		#end
	}
}
